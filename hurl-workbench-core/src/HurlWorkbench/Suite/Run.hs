-- | Execute a fully preflighted suite, optionally inside one managed-service
--   lifecycle, and emit a redacted atomic summary.
module HurlWorkbench.Suite.Run
  ( ServiceOutcome (..),
    SuiteResult (..),
    runSuite,
  )
where

import Control.Concurrent.STM (atomically, modifyTVar', newTVarIO, readTVarIO)
import Control.Exception (IOException, displayException, onException, try)
import Data.Aeson qualified as Aeson
import Data.Bits ((.&.))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime)
import HurlWorkbench.Hurl.Format (HurlfmtCapabilities)
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Service.Run
import HurlWorkbench.Suite.Resolve
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)
import HurlWorkbench.Workspace.Types (SuiteName (..))
import System.Directory (removeFile, renameFile)
import System.Exit (ExitCode (..))
import System.FilePath (makeRelative, takeDirectory)
import System.IO (hClose)
import System.IO.Temp (openBinaryTempFile)
import System.Posix.Files
  ( accessModes,
    fileMode,
    getFileStatus,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
    unionFileModes,
  )
import System.Posix.Types (FileMode)

data ServiceOutcome
  = ServiceStopped
  | ServiceFailed !ServiceError
  deriving stock (Generic, Eq, Show)

data SuiteResult = SuiteResult
  { cases :: !(NonEmpty CaseResult),
    serviceOutcome :: !(Maybe ServiceOutcome),
    summaryPath :: !(Maybe FilePath),
    summaryError :: !(Maybe Text),
    selectedExitCode :: !ExitCode
  }
  deriving stock (Generic, Eq, Show)

runSuite :: HurlRunner -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError SuiteResult)
runSuite runner capabilities validated request =
  prepareSuite capabilities validated request >>= \case
    Left err -> pure (Left err)
    Right prepared -> Right <$> executePreparedSuite runner prepared

executePreparedSuite :: HurlRunner -> PreparedSuite -> IO SuiteResult
executePreparedSuite runner prepared = do
  observed <- newTVarIO Map.empty
  let execute =
        runBatchObserved
          runner
          (prepared ^. #batchOptions)
          (prepared ^. #cases)
          (\caseIndex result -> atomically (modifyTVar' observed (Map.insert caseIndex result)))
  (caseResults, serviceOutcome) <- case prepared ^. #managedService of
    Nothing -> (,Nothing) . view #cases <$> execute
    Just service ->
      withService service (const execute) >>= \case
        Right batch -> pure (batch ^. #cases, Just ServiceStopped)
        Left err -> do
          completed <- readTVarIO observed
          pure (resultsAfterPrerequisiteFailure completed (prepared ^. #cases), Just (ServiceFailed err))
  let executionExit = case serviceOutcome of
        Just (ServiceFailed _) -> ExitFailure 4
        _ -> selectCaseExit caseResults
      provisional =
        finished Nothing Nothing executionExit
      finished writtenSummary writeError exitCode =
        SuiteResult
          { cases = caseResults,
            serviceOutcome,
            summaryPath = writtenSummary,
            summaryError = writeError,
            selectedExitCode = exitCode
          }
  summary <- case prepared ^. #summaryPath of
    Nothing -> pure (Right Nothing)
    Just path -> writeSummary path prepared provisional <&> fmap (const (Just path))
  pure $ case summary of
    Right path -> finished path Nothing executionExit
    Left message ->
      finished
        Nothing
        (Just message)
        ( case serviceOutcome of
            Just (ServiceFailed _) -> ExitFailure 4
            _ -> ExitFailure 3
        )

resultsAfterPrerequisiteFailure :: Map Int CaseResult -> NonEmpty BatchCase -> NonEmpty CaseResult
resultsAfterPrerequisiteFailure completed batchCases =
  NonEmpty.fromList
    [ Map.findWithDefault (prerequisiteFailed batchCase) caseIndex completed
    | (caseIndex, batchCase) <- zip [0 ..] (NonEmpty.toList batchCases)
    ]

prerequisiteFailed :: BatchCase -> CaseResult
prerequisiteFailed batchCase =
  CaseResult
    { name = batchCase ^. #name,
      outcome = CaseSkipped BatchPrerequisiteFailed,
      elapsed = Nothing,
      outputPath = Nothing,
      capturedOutput = Nothing
    }

selectCaseExit :: NonEmpty CaseResult -> ExitCode
selectCaseExit results = fromMaybe fallback (firstFailure (NonEmpty.toList results))
  where
    fallback
      | all ((== CasePassed) . view #outcome) results = ExitSuccess
      | otherwise = ExitFailure 3
    firstFailure = \case
      [] -> Nothing
      result : remaining -> case result ^. #outcome of
        CaseFailed exitCode -> Just exitCode
        CaseStartFailed _ -> Just (ExitFailure 3)
        CasePassed -> firstFailure remaining
        CaseSkipped _ -> firstFailure remaining

writeSummary :: FilePath -> PreparedSuite -> SuiteResult -> IO (Either Text ())
writeSummary path prepared result = do
  written <- try @IOException $ do
    let directory = takeDirectory path
    (temporaryPath, handle) <- openBinaryTempFile directory ".summary.json.tmp"
    let cleanup = do
          _ <- try @IOException (hClose handle)
          _ <- try @IOException (removeFile temporaryPath)
          pure ()
    ( do
        setFileMode temporaryPath secureFileMode
        verifyMode temporaryPath
        LazyByteString.hPut handle (Aeson.encode (summaryValue path prepared result))
        hClose handle
        renameFile temporaryPath path
        setFileMode path secureFileMode
        verifyMode path
      )
      `onException` cleanup
  pure $ case written of
    Left err -> Left ("could not write suite summary " <> Text.pack path <> ": " <> Text.pack (displayException err))
    Right () -> Right ()

summaryValue :: FilePath -> PreparedSuite -> SuiteResult -> Aeson.Value
summaryValue summary prepared result =
  Aeson.object
    [ "suite" Aeson..= unSuiteName (prepared ^. #name),
      "status" Aeson..= exitStatus (result ^. #selectedExitCode),
      "service" Aeson..= serviceStatus (result ^. #serviceOutcome),
      "cases" Aeson..= zipWith caseValue (NonEmpty.toList (prepared ^. #cases)) (NonEmpty.toList (result ^. #cases))
    ]
  where
    suiteRoot = takeDirectory summary
    caseValue batchCase caseResult =
      Aeson.object
        [ "name" Aeson..= (caseResult ^. #name),
          "status" Aeson..= caseStatus (caseResult ^. #outcome),
          "elapsedSeconds" Aeson..= fmap (realToFrac @NominalDiffTime @Double) (caseResult ^. #elapsed),
          "reports" Aeson..= map (makeRelative suiteRoot) (requestReportPaths (batchCase ^. #request))
        ]

serviceStatus :: Maybe ServiceOutcome -> Text
serviceStatus = \case
  Nothing -> "external-or-not-configured"
  Just ServiceStopped -> "stopped"
  Just (ServiceFailed _) -> "failed"

caseStatus :: CaseOutcome -> Text
caseStatus = \case
  CasePassed -> "passed"
  CaseFailed _ -> "failed"
  CaseStartFailed _ -> "start-failed"
  CaseSkipped FailFastTriggered -> "skipped-fail-fast"
  CaseSkipped BatchPrerequisiteFailed -> "skipped-prerequisite-failed"

exitStatus :: ExitCode -> Text
exitStatus = \case
  ExitSuccess -> "passed"
  ExitFailure _ -> "failed"

requestReportPaths :: RunRequest -> [FilePath]
requestReportPaths request = map reportPath (request ^. #reportTargets)
  where
    reportPath = \case
      JUnitReport path -> path
      HtmlReport path -> path
      JsonReport path -> path
      TapReport path -> path

verifyMode :: FilePath -> IO ()
verifyMode path = do
  actual <- (.&. accessModes) . fileMode <$> getFileStatus path
  unless (actual == secureFileMode) (ioError (userError ("insecure permissions on " <> path)))

secureFileMode :: FileMode
secureFileMode = ownerReadMode `unionFileModes` ownerWriteMode
