-- | Execute a fully preflighted suite, optionally inside one managed-service
--   lifecycle, and emit a redacted atomic summary.
module HurlWorkbench.Suite.Run
  ( ServiceOutcome (..),
    SuiteResult (..),
    StepOutcome (..),
    PhaseOutcome (..),
    CommandOutcome (..),
    LifecycleOutcome (..),
    runSuite,
    runSuiteWith,
    finalizeSuitePreflight,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent.STM (atomically, modifyTVar', newTVarIO, readTVarIO)
import Control.Exception (IOException, SomeAsyncException, SomeException, fromException, mask, onException, throwIO, try)
import Data.Aeson qualified as Aeson
import Data.Bits ((.&.))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime, addUTCTime, diffUTCTime, getCurrentTime)
import HurlWorkbench.Hurl.Format (HurlfmtCapabilities, HurlfmtError, validateRenderedWorkflow)
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Prelude
import HurlWorkbench.Process.Run
import HurlWorkbench.Run.Batch
import HurlWorkbench.Service.Group
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Suite.Resolve
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)
import HurlWorkbench.Workspace.Types (IsolationPolicy (..), ServiceName (..), ServiceStep (..), SuiteName (..))
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO (Handle, IOMode (WriteMode), hClose, withBinaryFile)
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
import System.Posix.Types (FileMode)
import System.Timeout qualified as Timeout

data ServiceOutcome
  = ServiceStopped
  | ServiceFailed !ServiceError
  deriving stock (Generic, Eq, Show)

data StepOutcome = HurlStep !CaseResult | LifecycleStep !LifecycleOutcome
  deriving stock (Generic, Eq, Show)

data PhaseOutcome = PhaseOutcome
  { phase :: !Text,
    ordinal :: !Int,
    status :: !CommandOutcome,
    elapsed :: !(Maybe NominalDiffTime),
    artifacts :: ![FilePath],
    cleanupFailure :: !(Maybe ServiceError)
  }
  deriving stock (Generic, Eq, Show)

data SuiteResult = SuiteResult
  { cases :: !(NonEmpty CaseResult),
    serviceOutcome :: !(Maybe ServiceOutcome),
    summaryPath :: !(Maybe FilePath),
    summaryError :: !(Maybe Text),
    selectedExitCode :: !ExitCode,
    steps :: ![StepOutcome],
    services :: ![LifecycleOutcome],
    phases :: ![PhaseOutcome],
    primaryFailure :: !(Maybe Text),
    cleanupDiagnostics :: ![ServiceError]
  }
  deriving stock (Generic, Eq, Show)

runSuite :: HurlRunner -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError SuiteResult)
runSuite = runSuiteWith validateRenderedWorkflow

runSuiteWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlRunner -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError SuiteResult)
runSuiteWith validateRendered runner capabilities validated request =
  prepareSuiteWith validateRendered capabilities validated request >>= \case
    Left err -> Left <$> finalizeSuitePreflight validated request err
    Right prepared -> Right <$> executePreparedSuite runner prepared

-- | One ownership boundary covers setup, every acquisition and barrier, active
-- batches, reverse service cleanup, and finally teardown. Observations survive
-- cancellation; only safe logical outcomes reach the summary.
executePreparedSuite :: HurlRunner -> PreparedSuite -> IO SuiteResult
executePreparedSuite runner prepared = withPhaseRoot $ \phaseRoot -> mask $ \restore -> do
  observed <- newTVarIO Map.empty
  lifecycle <- newTVarIO Map.empty
  startups <- newTVarIO []
  phases <- newTVarIO Map.empty
  primary <- newTVarIO Nothing
  group <- newServiceGroup
  let remember reason = atomically (modifyTVar' primary (\current -> current <|> Just reason))
      phaseCommand phase ordinal budget command = do
        let relative = "phases" </> Text.unpack phase </> show ordinal
            directory = phaseRoot </> relative
            artifacts = if isJust (prepared ^. #metadata . #summaryPath) then [relative </> "stdout", relative </> "stderr"] else []
            pending = PhaseOutcome phase ordinal CommandCancelled Nothing artifacts Nothing
        atomically (modifyTVar' phases (Map.insert (phase, ordinal) pending))
        began <- getCurrentTime
        attempted <- try @IOException $ do
          createDirectoryIfMissing True directory
          traverse_ (`setFileMode` secureDirectoryMode) [takeDirectory (takeDirectory directory), takeDirectory directory, directory]
          withCapture (directory </> "stdout") $ \stdout ->
            withCapture (directory </> "stderr") $ \stderr ->
              runCommand (ServiceName phase) budget command stdout stderr
        let (outcome, cleanup) = either (const (CommandStartFailed, Nothing)) id attempted
        ended <- getCurrentTime
        atomically (modifyTVar' phases (Map.insert (phase, ordinal) (pending & #status .~ outcome & #elapsed .~ Just (diffUTCTime ended began) & #cleanupFailure .~ cleanup)))
        pure (outcome == CommandPassed && isNothing cleanup)
      setup = runSetup 0 (prepared ^. #setupCommands)
      runSetup _ [] = pure (Right ())
      runSetup ordinal (command : rest) = do
        passed <- phaseCommand "setup" ordinal (prepared ^. #commandTimeout) command
        if passed
          then runSetup (ordinal + 1) rest
          else do
            remember "setup-failed"
            pure (Left (ServicePhaseFailed "setup"))
      recordService event = atomically (modifyTVar' startups (<> [event]))
      startAll [] = pure (Right ())
      startAll (service : rest) = do
        result <- startNamedObserved group service recordService
        case result of
          Left err -> pure (Left err)
          Right () -> startAll rest
      executeSteps _ [] = pure (Right ())
      executeSteps ordinal (step : rest) = case step of
        HurlBatch offset cases -> do
          batch <-
            watchServices group $
              Right
                <$> runBatchObserved
                  runner
                  (prepared ^. #batchOptions)
                  cases
                  ( \caseIndex result -> do
                      atomically (modifyTVar' observed (Map.insert (offset + caseIndex) result))
                      when (result ^. #outcome /= CasePassed) (remember "hurl-failed")
                  )
          case batch of
            Left err -> pure (Left err)
            Right result
              | prepared ^. #batchOptions . #failFast, result ^. #selectedExitCode /= ExitSuccess -> pure (Right ())
              | otherwise -> executeSteps (ordinal + 1) rest
        ServiceBarrier operation -> do
          let (name, action) = stepLabel operation
              pending = LifecycleOutcome name action "cancelled" 0 Nothing
          atomically (modifyTVar' lifecycle (Map.insert ordinal pending))
          began <- getCurrentTime
          result <- applyServiceStepObserved group (prepared ^. #managedServices) operation recordService
          ended <- getCurrentTime
          atomically (modifyTVar' lifecycle (Map.insert ordinal (pending & #status .~ either (const "failed") (const "passed") result & #elapsed .~ diffUTCTime ended began & #failure .~ either Just (const Nothing) result)))
          case result of
            Left err -> pure (Left err)
            Right () -> executeSteps (ordinal + 1) rest
      execute =
        setup >>= \case
          Left err -> pure (Left err)
          Right () ->
            startAll (prepared ^. #managedServices) >>= \case
              Left err -> pure (Left err)
              Right () -> executeSteps 0 (prepared ^. #steps)
      teardown = do
        began <- getCurrentTime
        let deadline = addUTCTime (prepared ^. #cleanupTimeout) began
            go _ [] = pure ()
            go ordinal (command : rest) = do
              now <- getCurrentTime
              if now >= deadline
                then pure ()
                else do
                  _passed <- phaseCommand "teardown" ordinal (min (prepared ^. #commandTimeout) (diffUTCTime deadline now)) command
                  outcomes <- readTVarIO phases
                  let timedOut = maybe False ((== CommandTimedOut) . view #status) (Map.lookup ("teardown", ordinal) outcomes)
                  unless (timedOut && diffUTCTime deadline now <= prepared ^. #commandTimeout) (go (ordinal + 1) rest)
        go 0 (prepared ^. #teardownCommands)
  execution <- try @SomeException (restore execute)
  case execution of
    Right (Left _) -> remember "service-failed"
    _ -> pure ()
  cleanup <- cleanupServices group
  teardown
  completed <- readTVarIO observed
  barrierResults <- readTVarIO lifecycle
  serviceStarts <- readTVarIO startups
  phaseResults <- readTVarIO phases
  primaryFailure <- readTVarIO primary
  let cancelled = case execution of Left err -> isJust (fromException err :: Maybe SomeAsyncException); _ -> False
      serviceError = case execution of Right (Left err) -> Just err; _ -> Nothing
      missingReason
        | cancelled = BatchCancelled
        | isJust serviceError = BatchPrerequisiteFailed
        | otherwise = FailFastTriggered
      caseResults = NonEmpty.fromList [Map.findWithDefault ((prerequisiteFailed batchCase) {outcome = CaseSkipped missingReason}) caseIndex completed | (caseIndex, batchCase) <- zip [0 ..] (toList (prepared ^. #cases))]
      phaseOutcomes = [Map.findWithDefault (PhaseOutcome phase ordinal CommandSkipped Nothing [] Nothing) (phase, ordinal) phaseResults | (phase, commands) <- [("setup", prepared ^. #setupCommands), ("teardown", prepared ^. #teardownCommands)], ordinal <- [0 .. length commands - 1]]
      cleanupErrors =
        mapMaybe (view #failure) cleanup
          <> mapMaybe (view #cleanupFailure) phaseOutcomes
          <> [ServicePhaseFailed "teardown" | phase <- phaseOutcomes, phase ^. #phase == "teardown", phase ^. #status /= CommandPassed]
      allServiceErrors = maybe [] pure serviceError <> cleanupErrors
      serviceOutcome
        | err : _ <- allServiceErrors = Just (ServiceFailed err)
        | null (prepared ^. #managedServices) = Nothing
        | otherwise = Just ServiceStopped
      exitCode
        | cancelled = ExitFailure 130
        | not (null allServiceErrors) = ExitFailure 4
        | otherwise = selectCaseExit caseResults
      stepResults =
        concat
          [ case step of
              HurlBatch offset cases -> map HurlStep (take (length cases) (drop offset (toList caseResults)))
              ServiceBarrier operation -> let (name, action) = stepLabel operation in [LifecycleStep (Map.findWithDefault (LifecycleOutcome name action "skipped" 0 Nothing) ordinal barrierResults)]
          | (ordinal, step) <- zip [0 :: Int ..] (prepared ^. #steps)
          ]
      provisional =
        SuiteResult
          caseResults
          serviceOutcome
          Nothing
          Nothing
          exitCode
          stepResults
          (serviceStarts <> [event | LifecycleStep event <- stepResults] <> cleanup)
          phaseOutcomes
          (primaryFailure <|> if null cleanupErrors then Nothing else Just "cleanup-failed")
          cleanupErrors
  summary <- case prepared ^. #metadata . #summaryPath of
    Nothing -> pure (Right Nothing)
    Just path -> do
      let write = writeSummary path (summaryValueWithStatus (if cancelled then "cancelled" else exitStatus exitCode) (prepared ^. #metadata) provisional)
      written <-
        if cancelled
          then fromMaybe (Left "suite summary write timed out") <$> Timeout.timeout 1000000 write
          else write
      pure (Just path <$ written)
  let finished = case summary of
        Right path -> provisional & #summaryPath .~ path
        Left message -> provisional & #summaryError .~ Just message & #selectedExitCode .~ (if exitCode == ExitFailure 4 then exitCode else ExitFailure 3)
  case execution of
    Left err -> throwIO err
    Right _ -> pure finished
  where
    withPhaseRoot action = case prepared ^. #metadata . #summaryPath of
      Just path -> action (takeDirectory path)
      Nothing -> withSystemTempDirectory "hurl-workbench-phases" action

stepLabel :: ServiceStep -> (ServiceName, Text)
stepLabel = \case Stop name -> (name, "stop"); Start name -> (name, "start"); Restart name -> (name, "restart")

withCapture :: FilePath -> (Handle -> IO a) -> IO a
withCapture path action = withBinaryFile path WriteMode $ \handle -> do
  setFileMode path secureFileMode
  action handle

secureDirectoryMode :: FileMode
secureDirectoryMode = secureFileMode `unionFileModes` ownerExecuteMode

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

summaryValueWithStatus :: Text -> SuiteMetadata -> SuiteResult -> Aeson.Value
summaryValueWithStatus status metadata result =
  Aeson.object
    [ "suite" Aeson..= unSuiteName (metadata ^. #name),
      "isolation" Aeson..= isolationLabel (metadata ^. #isolation),
      "status" Aeson..= status,
      "service" Aeson..= serviceStatus (result ^. #serviceOutcome),
      "primaryFailure" Aeson..= (result ^. #primaryFailure),
      "cleanupDiagnostics" Aeson..= map (const ("cleanup-failed" :: Text)) (result ^. #cleanupDiagnostics),
      "services" Aeson..= map lifecycleValue (result ^. #services),
      "phases" Aeson..= map phaseValue (result ^. #phases),
      "steps" Aeson..= map stepValue (result ^. #steps),
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

lifecycleValue :: LifecycleOutcome -> Aeson.Value
lifecycleValue event =
  Aeson.object
    [ "kind" Aeson..= ("service" :: Text),
      "name" Aeson..= unServiceName (event ^. #name),
      "action" Aeson..= (event ^. #action),
      "status" Aeson..= (event ^. #status),
      "artifacts" Aeson..= ([] :: [FilePath]),
      "elapsedSeconds" Aeson..= realToFrac @NominalDiffTime @Double (event ^. #elapsed)
    ]

phaseValue :: PhaseOutcome -> Aeson.Value
phaseValue event =
  Aeson.object
    [ "phase" Aeson..= (event ^. #phase),
      "index" Aeson..= (event ^. #ordinal),
      "status" Aeson..= commandStatus (event ^. #status),
      "elapsedSeconds" Aeson..= fmap (realToFrac @NominalDiffTime @Double) (event ^. #elapsed),
      "artifacts" Aeson..= (event ^. #artifacts)
    ]

commandStatus :: CommandOutcome -> Text
commandStatus = \case
  CommandPassed -> "passed"
  CommandFailed -> "failed"
  CommandTimedOut -> "timed-out"
  CommandStartFailed -> "start-failed"
  CommandSkipped -> "skipped"
  CommandCancelled -> "cancelled"

stepValue :: StepOutcome -> Aeson.Value
stepValue (LifecycleStep event) = lifecycleValue event
stepValue (HurlStep result) =
  Aeson.object
    ["kind" Aeson..= ("hurl" :: Text), "name" Aeson..= (result ^. #name), "status" Aeson..= caseStatus (result ^. #outcome)]

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
