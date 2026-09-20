-- | Hurlfmt capability detection and syntax validation. Hurlfmt remains the
--   parser oracle; this module does not interpret Hurl grammar.
module HurlWorkbench.Hurl.Format
  ( HurlfmtExecutable (..),
    HurlfmtCapabilities (..),
    DependencyError (..),
    HurlfmtError (..),
    WorkflowSyntaxError (..),
    detectHurlfmtCapabilities,
    parseHurlfmtVersion,
    validateRenderedWorkflow,
    validateWorkspaceSyntax,
    renderDependencyError,
    renderHurlfmtError,
    renderWorkflowSyntaxError,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isDigit)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Version (Version, makeVersion)
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workflow.Resolve
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process.Typed (proc, readProcess)
import Text.Read (readMaybe)

newtype HurlfmtExecutable = HurlfmtExecutable {unHurlfmtExecutable :: FilePath}
  deriving stock (Generic, Eq, Ord, Show)

data HurlfmtCapabilities = HurlfmtCapabilities
  { executable :: !HurlfmtExecutable,
    version :: !Version
  }
  deriving stock (Generic, Eq, Show)

data DependencyError
  = DependencyNotFound !Text !FilePath
  | DependencyProbeFailed !Text !ExitCode !Text
  | DependencyVersionUnrecognized !Text !Text
  deriving stock (Generic, Eq, Show)

data HurlfmtError
  = HurlfmtNotFound !FilePath
  | InvalidHurl !WorkflowName !(Maybe RenderedFragmentSpan) !Text
  | HurlfmtFailed !ExitCode !Text
  deriving stock (Generic, Eq, Show)

data WorkflowSyntaxError
  = SyntaxResolutionFailed !WorkflowError
  | SyntaxRenderFailed !WorkflowName !RenderError
  | SyntaxFormatFailed !HurlfmtError
  deriving stock (Generic, Eq, Show)

detectHurlfmtCapabilities :: IO (Either DependencyError HurlfmtCapabilities)
detectHurlfmtCapabilities = do
  located <- findExecutable "hurlfmt"
  case located of
    Nothing -> pure (Left (DependencyNotFound "hurlfmt" "hurlfmt"))
    Just path -> do
      probe <- try (readProcess (proc path ["--version"]))
      pure $ case probe of
        Left (err :: IOException) -> Left (DependencyNotFound "hurlfmt" (path <> ": " <> displayException err))
        Right (exitCode, stdout, stderr)
          | exitCode /= ExitSuccess ->
              Left (DependencyProbeFailed "hurlfmt" exitCode (decodeOutput stderr))
          | otherwise -> case parseHurlfmtVersion (decodeOutput stdout) of
              Nothing -> Left (DependencyVersionUnrecognized "hurlfmt" (decodeOutput stdout))
              Just detected ->
                Right
                  HurlfmtCapabilities
                    { executable = HurlfmtExecutable path,
                      version = detected
                    }

parseHurlfmtVersion :: Text -> Maybe Version
parseHurlfmtVersion output =
  makeVersion <$> firstJust (map parseCandidate (Text.words output))
  where
    parseCandidate token =
      let candidate = Text.takeWhile (\c -> isDigit c || c == '.') (Text.dropWhile (not . isDigit) token)
          components = Text.splitOn "." candidate
       in if null components || any Text.null components
            then Nothing
            else traverse (readMaybe . Text.unpack) components

    firstJust = \case
      [] -> Nothing
      Nothing : remaining -> firstJust remaining
      Just value : _ -> Just value

validateRenderedWorkflow :: HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())
validateRenderedWorkflow capabilities rendered =
  withSystemTempDirectory "hurl-workbench-hurlfmt" $ \directory -> do
    let temporaryFile = directory </> "workflow.hurl"
        HurlfmtExecutable executablePath = capabilities ^. #executable
    writeResult <- try (ByteString.writeFile temporaryFile (Text.Encoding.encodeUtf8 (rendered ^. #contents)))
    case writeResult of
      Left (err :: IOException) ->
        pure (Left (HurlfmtFailed (ExitFailure 1) (Text.pack (displayException err))))
      Right () -> do
        processResult <-
          try
            ( readProcess
                (proc executablePath ["--no-color", "--out", "json", temporaryFile])
            )
        pure $ case processResult of
          Left (_err :: IOException) -> Left (HurlfmtNotFound executablePath)
          Right (ExitSuccess, _stdout, _stderr) -> Right ()
          Right (exitCode, _stdout, stderr) ->
            let diagnostics = decodeOutput stderr
             in case diagnosticLine diagnostics of
                  Just line ->
                    Left
                      ( InvalidHurl
                          (rendered ^. #workflowName)
                          (spanForLine line (rendered ^. #fragmentSpans))
                          diagnostics
                      )
                  Nothing -> Left (HurlfmtFailed exitCode diagnostics)

validateWorkspaceSyntax ::
  HurlfmtCapabilities ->
  ValidatedWorkspace ->
  IO (Either DependencyError [WorkflowSyntaxError])
validateWorkspaceSyntax capabilities validated =
  go [] (Map.keys (validatedWorkflows validated))
  where
    HurlfmtExecutable executablePath = capabilities ^. #executable

    go issues [] = pure (Right (reverse issues))
    go issues (name : remaining) =
      case resolveWorkflow validated name of
        Left err -> go (SyntaxResolutionFailed err : issues) remaining
        Right resolved ->
          renderWorkflow resolved >>= \case
            Left err -> go (SyntaxRenderFailed name err : issues) remaining
            Right rendered ->
              validateRenderedWorkflow capabilities rendered >>= \case
                Left (HurlfmtNotFound _) -> pure (Left (DependencyNotFound "hurlfmt" executablePath))
                Left err -> go (SyntaxFormatFailed err : issues) remaining
                Right () -> go issues remaining

spanForLine :: Int -> NonEmpty RenderedFragmentSpan -> Maybe RenderedFragmentSpan
spanForLine line =
  findFirst
    (\span_ -> line >= span_ ^. #firstLine && line <= span_ ^. #lastLine)
    . NonEmpty.toList
  where
    findFirst _ [] = Nothing
    findFirst predicate (value : remaining)
      | predicate value = Just value
      | otherwise = findFirst predicate remaining

diagnosticLine :: Text -> Maybe Int
diagnosticLine diagnostics =
  firstJust (map parseLocation (Text.lines diagnostics))
  where
    parseLocation raw = do
      location <- Text.stripPrefix "--> " (Text.strip raw)
      let (throughLine, columnText) = Text.breakOnEnd ":" location
          withoutColumn = Text.dropEnd 1 throughLine
          (throughPath, lineText) = Text.breakOnEnd ":" withoutColumn
      if Text.null throughPath || Text.null columnText
        then Nothing
        else readMaybe (Text.unpack lineText)

    firstJust = \case
      [] -> Nothing
      Nothing : remaining -> firstJust remaining
      Just value : _ -> Just value

decodeOutput :: LazyByteString.ByteString -> Text
decodeOutput = Text.Encoding.decodeUtf8With lenientDecode . LazyByteString.toStrict

renderDependencyError :: DependencyError -> Text
renderDependencyError = \case
  DependencyNotFound name path ->
    "required dependency " <> quote name <> " was not found or could not be started at " <> Text.pack path
  DependencyProbeFailed name exitCode message ->
    "dependency " <> quote name <> " failed its version probe with " <> Text.pack (show exitCode) <> detail message
  DependencyVersionUnrecognized name output ->
    "could not parse the version reported by dependency " <> quote name <> detail output

renderHurlfmtError :: HurlfmtError -> Text
renderHurlfmtError = \case
  HurlfmtNotFound path -> "hurlfmt could not be started at " <> Text.pack path
  InvalidHurl name sourceSpan diagnostics ->
    "workflow "
      <> quote (unWorkflowName name)
      <> maybe "" renderSpan sourceSpan
      <> " is not valid Hurl:\n"
      <> Text.stripEnd diagnostics
  HurlfmtFailed exitCode diagnostics ->
    "hurlfmt failed with " <> Text.pack (show exitCode) <> detail diagnostics
  where
    renderSpan span_ =
      " (fragment "
        <> quote (unFragmentName (span_ ^. #fragmentName))
        <> " at "
        <> Text.pack (span_ ^. #fragmentPath)
        <> ")"

renderWorkflowSyntaxError :: WorkflowSyntaxError -> Text
renderWorkflowSyntaxError = \case
  SyntaxResolutionFailed err -> renderWorkflowError err
  SyntaxRenderFailed name err ->
    "workflow " <> quote (unWorkflowName name) <> ": " <> renderRenderError err
  SyntaxFormatFailed err -> renderHurlfmtError err

detail :: Text -> Text
detail value
  | Text.null (Text.strip value) = ""
  | otherwise = ": " <> Text.strip value

quote :: Text -> Text
quote value = "\"" <> value <> "\""
