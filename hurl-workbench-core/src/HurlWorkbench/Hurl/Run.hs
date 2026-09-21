-- | Secure execution of one rendered workflow through Hurl. This is the only
--   production module which constructs Hurl argv.
module HurlWorkbench.Hurl.Run
  ( HurlRunMode (..),
    RunOutputPolicy (..),
    HurlReportTarget (..),
    HurlVerbosity (..),
    AllowedHurlArgument,
    HurlOptionError (..),
    HurlOptions (..),
    defaultHurlOptions,
    mkAllowedHurlArgument,
    RunRequest (..),
    RunStartError (..),
    CapturedRunOutput (..),
    RunResult (..),
    HurlRunner (..),
    mkHurlRunner,
    renderRunStartError,
  )
where

import Control.Concurrent.STM (atomically)
import Control.Exception (IOException, displayException, finally, onException, try)
import Data.Bits ((.&.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Generics.Labels ()
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock (NominalDiffTime, diffUTCTime, getCurrentTime)
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Parameter.Resolve (ResolvedBindings (..))
import HurlWorkbench.Parameter.Resolve.Internal (secretValueText)
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workspace.Types
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode)
import System.FilePath (takeDirectory)
import System.IO (hClose, hFlush)
import System.IO.Temp (openBinaryTempFile, withSystemTempDirectory)
import System.Posix.Files
  ( accessModes,
    fileMode,
    getFileStatus,
    ownerExecuteMode,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
    unionFileModes,
  )
import System.Posix.IO (OpenFileFlags (..), OpenMode (WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Posix.Types (FileMode)
import System.Process.Typed
  ( byteStringOutput,
    closed,
    getStderr,
    getStdout,
    proc,
    setEnv,
    setStderr,
    setStdin,
    setStdout,
    startProcess,
    stopProcess,
    waitExitCode,
  )

data HurlRunMode = ClientMode | TestMode
  deriving stock (Generic, Eq, Show)

data RunOutputPolicy
  = InheritRunOutput
  | CaptureRunOutput
  | ResponseFile !FilePath
  deriving stock (Generic, Eq, Show)

data HurlReportTarget
  = JUnitReport !FilePath
  | HtmlReport !FilePath
  | JsonReport !FilePath
  | TapReport !FilePath
  deriving stock (Generic, Eq, Show)

data HurlVerbosity = Verbose | VeryVerbose
  deriving stock (Generic, Eq, Show)

newtype AllowedHurlArgument = AllowedHurlArgument Text
  deriving stock (Generic, Eq, Ord, Show)

data HurlOptionError
  = NegativeOption !Text !Int
  | UnsupportedHurlArgument !Text
  | DuplicateReportFormat !Text
  deriving stock (Generic, Eq, Show)

data HurlOptions = HurlOptions
  { connectTimeoutSeconds :: !(Maybe Int),
    maxTimeSeconds :: !(Maybe Int),
    retryCount :: !(Maybe Int),
    retryIntervalMilliseconds :: !(Maybe Int),
    insecureTls :: !Bool,
    includeHeaders :: !Bool,
    jsonOutput :: !Bool,
    verbosity :: !(Maybe HurlVerbosity),
    curlExportPath :: !(Maybe FilePath),
    additionalArguments :: ![AllowedHurlArgument]
  }
  deriving stock (Generic, Eq, Show)

defaultHurlOptions :: HurlOptions
defaultHurlOptions =
  HurlOptions
    { connectTimeoutSeconds = Nothing,
      maxTimeSeconds = Nothing,
      retryCount = Nothing,
      retryIntervalMilliseconds = Nothing,
      insecureTls = False,
      includeHeaders = False,
      jsonOutput = False,
      verbosity = Nothing,
      curlExportPath = Nothing,
      additionalArguments = []
    }

mkAllowedHurlArgument :: Text -> Either HurlOptionError AllowedHurlArgument
mkAllowedHurlArgument rawArgument
  | rawArgument `elem` allowedArguments = Right (AllowedHurlArgument rawArgument)
  | otherwise = Left (UnsupportedHurlArgument rawArgument)
  where
    allowedArguments = ["--compressed", "--location", "--location-trusted", "--no-color", "--path-as-is"]

data RunRequest = RunRequest
  { renderedWorkflow :: !RenderedWorkflow,
    mode :: !HurlRunMode,
    bindings :: !ResolvedBindings,
    options :: !HurlOptions,
    outputPolicy :: !RunOutputPolicy,
    reportTargets :: ![HurlReportTarget]
  }
  deriving stock (Generic, Eq)

instance Show RunRequest where
  show request =
    "RunRequest {workflow="
      <> show (request ^. #renderedWorkflow . #workflowName)
      <> ", mode="
      <> show (request ^. #mode)
      <> ", bindings=<redacted>}"

data RunStartError
  = InvalidRunOptions !(NonEmpty HurlOptionError)
  | SecureRunFileError !FilePath !Text
  | HurlSpawnFailed !FilePath !Text
  deriving stock (Generic, Eq, Show)

data CapturedRunOutput = CapturedRunOutput
  { stdout :: !ByteString.ByteString,
    stderr :: !ByteString.ByteString
  }
  deriving stock (Generic, Eq, Show)

data RunResult = RunResult
  { exitCode :: !ExitCode,
    elapsed :: !NominalDiffTime,
    capturedOutput :: !(Maybe CapturedRunOutput)
  }
  deriving stock (Generic, Eq, Show)

newtype HurlRunner = HurlRunner
  { runHurl :: RunRequest -> IO (Either RunStartError RunResult)
  }

mkHurlRunner :: HurlCapabilities -> HurlRunner
mkHurlRunner capabilities = HurlRunner (runRequest capabilities)

runRequest :: HurlCapabilities -> RunRequest -> IO (Either RunStartError RunResult)
runRequest capabilities request = case validateRequest request of
  Just issues -> pure (Left (InvalidRunOptions issues))
  Nothing -> do
    attempted <- try @IOException (withSystemTempDirectory "hurl-workbench-run" (prepareAndRun capabilities request))
    pure $ case attempted of
      Left err -> Left (SecureRunFileError "temporary execution directory" (Text.pack (displayException err)))
      Right result -> result

prepareAndRun :: HurlCapabilities -> RunRequest -> FilePath -> IO (Either RunStartError RunResult)
prepareAndRun capabilities request directory = do
  renderedPath <- writeSecureTemporary directory "workflow.hurl" (Text.Encoding.encodeUtf8 (request ^. #renderedWorkflow . #contents))
  variablesPath <- writeBindings directory "variables.env" renderVariable (request ^. #bindings . #variables)
  secretsPath <- writeBindings directory "secrets.env" renderSecret (request ^. #bindings . #secrets)
  traverse_ prepareReportTarget (request ^. #reportTargets)
  traverse_ prepareResponseTarget (responseTarget (request ^. #outputPolicy))
  traverse_ prepareSecureFile (request ^. #options . #curlExportPath)
  environment <- filter (not . Text.isPrefixOf "HURL_" . Text.pack . fst) <$> getEnvironment
  let arguments = buildArguments request renderedPath variablesPath secretsPath
  spawn capabilities request environment arguments
  where
    renderVariable name value = unParameterName name <> "=" <> hurlValueLiteralText value
    renderSecret name value = unParameterName name <> "=" <> secretValueText value

writeBindings :: FilePath -> FilePath -> (ParameterName -> value -> Text) -> Map ParameterName value -> IO (Maybe FilePath)
writeBindings _directory _template _render values | Map.null values = pure Nothing
writeBindings directory template render values =
  Just <$> writeSecureTemporary directory template (Text.Encoding.encodeUtf8 (Text.unlines [render name value | (name, value) <- Map.toAscList values]))

writeSecureTemporary :: FilePath -> FilePath -> ByteString.ByteString -> IO FilePath
writeSecureTemporary directory template bytes = do
  (path, handle) <- openBinaryTempFile directory template
  let cleanup = do
        _ <- try @IOException (hClose handle)
        _ <- try @IOException (removeFile path)
        pure ()
  ( do
      verifyMode secureFileMode path
      ByteString.hPut handle bytes
      hFlush handle
      hClose handle
      pure path
    )
    `onException` cleanup

prepareResponseTarget :: FilePath -> IO ()
prepareResponseTarget = prepareSecureFile

prepareReportTarget :: HurlReportTarget -> IO ()
prepareReportTarget = \case
  JUnitReport path -> prepareSecureFileWith path "<?xml version=\"1.0\"?>\n<testsuites/>\n"
  TapReport path -> prepareSecureFileWith path "TAP version 13\n1..0\n"
  HtmlReport path -> prepareSecureDirectory path
  JsonReport path -> prepareSecureDirectory path

prepareSecureFile :: FilePath -> IO ()
prepareSecureFile path = prepareSecureFileWith path ""

-- Hurl 8 appends to JUnit and TAP files by parsing any existing target. Seed
-- those owner-only files with valid empty documents rather than zero bytes;
-- File.create then preserves the secure mode when Hurl replaces the content.
prepareSecureFileWith :: FilePath -> ByteString.ByteString -> IO ()
prepareSecureFileWith path initialContent = do
  createDirectoryIfMissing True (takeDirectory path)
  handle <- fdToHandle =<< openFd path WriteOnly defaultFileFlags {creat = Just secureFileMode, trunc = True, nofollow = True}
  ByteString.hPut handle initialContent
  hClose handle
  setFileMode path secureFileMode
  verifyMode secureFileMode path

prepareSecureDirectory :: FilePath -> IO ()
prepareSecureDirectory path = do
  exists <- doesDirectoryExist path
  unless exists (createDirectoryIfMissing True path)
  setFileMode path secureDirectoryMode
  verifyMode secureDirectoryMode path

verifyMode :: FileMode -> FilePath -> IO ()
verifyMode expected path = do
  actual <- (.&. accessModes) . fileMode <$> getFileStatus path
  unless (actual == expected) (ioError (userError ("insecure permissions on " <> path)))

secureFileMode :: FileMode
secureFileMode = ownerReadMode `unionFileModes` ownerWriteMode

secureDirectoryMode :: FileMode
secureDirectoryMode = secureFileMode `unionFileModes` ownerExecuteMode

spawn :: HurlCapabilities -> RunRequest -> [(String, String)] -> [String] -> IO (Either RunStartError RunResult)
spawn capabilities request environment arguments = case request ^. #outputPolicy of
  InheritRunOutput -> do
    let config = setEnv environment (proc (capabilities ^. #hurlExecutable) arguments)
    started <- try @IOException (startProcess config)
    case started of
      Left err -> pure (Left (HurlSpawnFailed (capabilities ^. #hurlExecutable) (Text.pack (displayException err))))
      Right process -> do
        began <- getCurrentTime
        exit <- waitExitCode process `finally` stopProcess process
        ended <- getCurrentTime
        pure (Right (RunResult exit (diffUTCTime ended began) Nothing))
  CaptureRunOutput -> spawnCaptured
  ResponseFile _path -> spawnCaptured
  where
    spawnCaptured = do
      let config =
            setStdin closed
              . setStdout byteStringOutput
              . setStderr byteStringOutput
              . setEnv environment
              $ proc (capabilities ^. #hurlExecutable) arguments
      started <- try @IOException (startProcess config)
      case started of
        Left err -> pure (Left (HurlSpawnFailed (capabilities ^. #hurlExecutable) (Text.pack (displayException err))))
        Right process -> do
          began <- getCurrentTime
          (exit, stdout, stderr) <-
            ( do
                exit <- waitExitCode process
                stdout <- atomically (getStdout process)
                stderr <- atomically (getStderr process)
                pure (exit, stdout, stderr)
            )
              `finally` stopProcess process
          ended <- getCurrentTime
          pure
            ( Right
                ( RunResult
                    exit
                    (diffUTCTime ended began)
                    (Just (CapturedRunOutput (LazyByteString.toStrict stdout) (LazyByteString.toStrict stderr)))
                )
            )

buildArguments :: RunRequest -> FilePath -> Maybe FilePath -> Maybe FilePath -> [String]
buildArguments request renderedPath variablesPath secretsPath =
  ["--file-root", root]
    <> maybe [] (\path -> ["--variables-file", path]) variablesPath
    <> maybe [] (\path -> ["--secrets-file", path]) secretsPath
    <> ["--test" | request ^. #mode == TestMode]
    <> renderOptions (request ^. #options)
    <> concatMap renderReportTarget (request ^. #reportTargets)
    <> maybe [] (\path -> ["--output", path]) (responseTarget (request ^. #outputPolicy))
    <> [renderedPath]
  where
    WorkspaceRoot root = request ^. #renderedWorkflow . #workspaceRoot

renderOptions :: HurlOptions -> [String]
renderOptions options =
  valued "--connect-timeout" (options ^. #connectTimeoutSeconds)
    <> valued "--max-time" (options ^. #maxTimeSeconds)
    <> valued "--retry" (options ^. #retryCount)
    <> valued "--retry-interval" (options ^. #retryIntervalMilliseconds)
    <> ["--insecure" | options ^. #insecureTls]
    <> ["--include" | options ^. #includeHeaders]
    <> ["--json" | options ^. #jsonOutput]
    <> case options ^. #verbosity of
      Just Verbose -> ["--verbose"]
      Just VeryVerbose -> ["--very-verbose"]
      Nothing -> []
    <> maybe [] (\path -> ["--curl", path]) (options ^. #curlExportPath)
    <> map (Text.unpack . allowedArgumentText) (options ^. #additionalArguments)
  where
    valued flag = maybe [] (\value -> [flag, show value])

allowedArgumentText :: AllowedHurlArgument -> Text
allowedArgumentText (AllowedHurlArgument value) = value

renderReportTarget :: HurlReportTarget -> [String]
renderReportTarget = \case
  JUnitReport path -> ["--report-junit", path]
  HtmlReport path -> ["--report-html", path]
  JsonReport path -> ["--report-json", path]
  TapReport path -> ["--report-tap", path]

responseTarget :: RunOutputPolicy -> Maybe FilePath
responseTarget = \case
  ResponseFile path -> Just path
  _ -> Nothing

validateRequest :: RunRequest -> Maybe (NonEmpty HurlOptionError)
validateRequest request = nonEmpty (numericIssues <> reportIssues)
  where
    options = request ^. #options
    numericIssues =
      concat
        [ nonNegative "connect timeout" (options ^. #connectTimeoutSeconds),
          nonNegative "max time" (options ^. #maxTimeSeconds),
          nonNegative "retry count" (options ^. #retryCount),
          nonNegative "retry interval" (options ^. #retryIntervalMilliseconds)
        ]
    formats = map reportFormat (request ^. #reportTargets)
    reportIssues = [DuplicateReportFormat format | format <- nub formats, length (filter (== format) formats) > 1]
    nonNegative name = maybe [] (\value -> [NegativeOption name value | value < 0])

reportFormat :: HurlReportTarget -> Text
reportFormat = \case
  JUnitReport _ -> "JUnit"
  HtmlReport _ -> "HTML"
  JsonReport _ -> "JSON"
  TapReport _ -> "TAP"

renderRunStartError :: RunStartError -> Text
renderRunStartError = \case
  InvalidRunOptions issues -> Text.intercalate "\n" (map renderOptionError (toList issues))
  SecureRunFileError path message -> "could not prepare secure run file " <> Text.pack path <> ": " <> message
  HurlSpawnFailed path message -> "Hurl could not be started at " <> Text.pack path <> ": " <> message
  where
    renderOptionError = \case
      NegativeOption name value -> name <> " must not be negative, got " <> Text.pack (show value)
      UnsupportedHurlArgument rawArgument -> "unsupported --hurl-arg " <> rawArgument
      DuplicateReportFormat format -> "at most one " <> format <> " report target is allowed"
