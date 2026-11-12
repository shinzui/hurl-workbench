-- | Execute a fully preflighted suite, optionally inside one managed-service
--   lifecycle, and emit a redacted atomic summary.
module HurlWorkbench.Suite.Run
  ( ServiceOutcome (..),
    SuiteResult (..),
    runSuite,
    runSuiteWith,
    finalizeSuitePreflight,
  )
where

import Control.Concurrent.STM (atomically, modifyTVar', newTVarIO, readTVarIO)
import Control.Exception (IOException, SomeAsyncException, SomeException, catch, mask, onException, throwIO, try)
import Data.Aeson qualified as Aeson
import Data.Bits ((.&.))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Time.Clock (NominalDiffTime)
import HurlWorkbench.Hurl.Format (HurlfmtCapabilities, HurlfmtError, validateRenderedWorkflow)
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Service.Run
import HurlWorkbench.Suite.Resolve
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)
import HurlWorkbench.Workspace.Types (IsolationPolicy (..), SuiteName (..))
import System.Directory (removeFile, renameFile)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
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
runSuite = runSuiteWith validateRenderedWorkflow

runSuiteWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlRunner -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError SuiteResult)
runSuiteWith validateRendered runner capabilities validated request =
  prepareSuiteWith validateRendered capabilities validated request >>= \case
    Left err -> Left <$> finalizeSuitePreflight validated request err
    Right prepared -> Right <$> executePreparedSuite runner prepared

executePreparedSuite :: HurlRunner -> PreparedSuite -> IO SuiteResult
executePreparedSuite runner prepared = mask $ \restore -> do
  observed <- newTVarIO Map.empty
  restore (executeAndSummarize observed) `catch` \(cancelled :: SomeAsyncException) -> do
    -- The batch and managed-service brackets have joined their children before
    -- this handler runs. Retain completed results and rethrow the first signal.
    completed <- readTVarIO observed
    let unfinished batchCase = (prerequisiteFailed batchCase) {outcome = CaseSkipped BatchCancelled}
        results = NonEmpty.fromList [Map.findWithDefault (unfinished batchCase) caseIndex completed | (caseIndex, batchCase) <- zip [0 ..] (toList (prepared ^. #cases))]
        result = SuiteResult results Nothing Nothing Nothing (ExitFailure 130)
    case prepared ^. #metadata . #summaryPath of
      Nothing -> pure ()
      Just path -> do
        _ <- try @SomeException (writeSummary path (summaryValueWithStatus "cancelled" (prepared ^. #metadata) result))
        pure ()
    throwIO cancelled
  where
    executeAndSummarize observed = do
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
      summary <- case prepared ^. #metadata . #summaryPath of
        Nothing -> pure (Right Nothing)
        Just path -> writeSummary path (summaryValue (prepared ^. #metadata) provisional) <&> fmap (const (Just path))
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

writeSummary :: FilePath -> Aeson.Value -> IO (Either Text ())
writeSummary path value = do
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
        LazyByteString.hPut handle (Aeson.encode value)
        hClose handle
        renameFile temporaryPath path
        setFileMode path secureFileMode
        verifyMode path
      )
      `onException` cleanup
  pure $ case written of
    Left _ -> Left "could not write suite summary"
    Right () -> Right ()

summaryValue :: SuiteMetadata -> SuiteResult -> Aeson.Value
summaryValue metadata result = summaryValueWithStatus (exitStatus (result ^. #selectedExitCode)) metadata result

summaryValueWithStatus :: Text -> SuiteMetadata -> SuiteResult -> Aeson.Value
summaryValueWithStatus status metadata result =
  Aeson.object
    [ "suite" Aeson..= unSuiteName (metadata ^. #name),
      "isolation" Aeson..= isolationLabel (metadata ^. #isolation),
      "status" Aeson..= status,
      "service" Aeson..= serviceStatus (result ^. #serviceOutcome),
      "cases" Aeson..= zipWith caseValue (toList (metadata ^. #scenarios)) (toList (result ^. #cases))
    ]
  where
    caseValue logical caseResult =
      Aeson.object
        [ "name" Aeson..= (logical ^. #name),
          "scenario" Aeson..= (logical ^. #scenario),
          "status" Aeson..= caseStatus (caseResult ^. #outcome),
          "elapsedSeconds" Aeson..= fmap (realToFrac @NominalDiffTime @Double) (caseResult ^. #elapsed),
          "reports" Aeson..= case (caseResult ^. #outcome) of
            CaseSkipped _ -> []
            CaseStartFailed _ -> []
            _ -> logical ^. #reports
        ]

isolationLabel :: IsolationPolicy -> Text
isolationLabel SharedState = "shared-state"
isolationLabel IndependentState = "independent-state"

-- | Report a refusal only when validated logical names and the ordinary safe
-- report reservation rules make a destination available. No runner is involved.
finalizeSuitePreflight :: ValidatedWorkspace -> SuiteRequest -> SuitePreflightError -> IO SuitePreflightError
finalizeSuitePreflight workspace request original
  | any isReportFailure (original ^. #issues) = pure original
  | otherwise = case suiteMetadata workspace request of
      Left _ -> pure original
      Right metadata -> case metadata ^. #summaryPath of
        Nothing -> pure original
        Just path ->
          reserveSuiteSummary request metadata >>= \case
            Left issue -> pure (append issue)
            Right () ->
              writeSummary path (preflightSummary metadata) <&> \case
                Left _ -> append (SuiteReportIoError path "summary-write-failed")
                Right () -> original
  where
    append issue = original & #issues %~ (<> (issue :| []))
    isReportFailure = \case
      SuiteReportPathExists _ -> True
      SuiteReportPathIsSymbolicLink _ -> True
      SuiteReportPathIsNotDirectory _ -> True
      SuiteInvalidReportDirectory _ -> True
      SuiteReportIoError _ _ -> True
      _ -> False
    preflightSummary metadata =
      Aeson.object
        [ "suite" Aeson..= unSuiteName (metadata ^. #name),
          "isolation" Aeson..= isolationLabel (metadata ^. #isolation),
          "status" Aeson..= (if any suitePreflightSetupFailure (original ^. #issues) then "setup-failed" else "refused" :: Text),
          "reasonCodes" Aeson..= map suitePreflightReasonCode (toList (original ^. #issues)),
          "cases"
            Aeson..= map
              ( \logical ->
                  Aeson.object
                    [ "name" Aeson..= (logical ^. #name),
                      "scenario" Aeson..= (logical ^. #scenario),
                      "status" Aeson..= ("not-started" :: Text),
                      "reports" Aeson..= ([] :: [FilePath])
                    ]
              )
              (toList (metadata ^. #scenarios))
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
  CaseSkipped BatchCancelled -> "cancelled"

exitStatus :: ExitCode -> Text
exitStatus = \case
  ExitSuccess -> "passed"
  ExitFailure _ -> "failed"

verifyMode :: FilePath -> IO ()
verifyMode path = do
  actual <- (.&. accessModes) . fileMode <$> getFileStatus path
  unless (actual == secureFileMode) (ioError (userError ("insecure permissions on " <> path)))

secureFileMode :: FileMode
secureFileMode = ownerReadMode `unionFileModes` ownerWriteMode
