-- | Complete suite preflight. Every run, safety decision, report target, and
--   optional managed service is resolved before execution can start.
module HurlWorkbench.Suite.Resolve
  ( ReportFormat (..),
    SuiteOptions (..),
    SuiteRequest (..),
    SuitePreflightIssue (..),
    SuitePreflightError (..),
    PreparedSuite (..),
    PreparedStep (..),
    SuiteMetadata (..),
    ScenarioMetadata (..),
    suiteMetadata,
    reserveSuiteSummary,
    suitePreflightReasonCode,
    suitePreflightSetupFailure,
    preflightScenarioInputs,
    prepareSuite,
    prepareSuiteWith,
    renderSuitePreflightIssue,
    renderSuitePreflightError,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.Bits ((.&.))
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime)
import HurlWorkbench.Hurl.Format (HurlfmtCapabilities, HurlfmtError, validateRenderedWorkflow)
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Service.Run (freezeService, prepareCommand)
import HurlWorkbench.Suite.Isolation
import HurlWorkbench.Suite.Scenario
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import System.Directory
  ( canonicalizePath,
    createDirectory,
    createDirectoryIfMissing,
    doesPathExist,
    removePathForcibly,
  )
import System.Environment (getEnvironment)
import System.FilePath (normalise, splitDirectories, (</>))
import System.IO.Error (isDoesNotExistError)
import System.Info (os)
import System.Posix.Files
  ( accessModes,
    fileMode,
    getFileStatus,
    getSymbolicLinkStatus,
    isDirectory,
    isSymbolicLink,
    ownerExecuteMode,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
    unionFileModes,
  )
import System.Posix.Types (FileMode)

data ReportFormat = JUnit | Html | Json | Tap
  deriving stock (Generic, Eq, Ord, Show)

data SuiteOptions = SuiteOptions
  { jobs :: !PositiveInt,
    failFastOverride :: !(Maybe Bool),
    allowMutating :: !Bool,
    manageService :: !Bool,
    reportFormats :: !(Set ReportFormat),
    reportDirectory :: !(Maybe FilePath),
    overwriteReports :: !Bool
  }
  deriving stock (Generic, Eq, Show)

data SuiteRequest = SuiteRequest
  { suiteName :: !SuiteName,
    scenarioInputs :: !(Maybe ScenarioInputs),
    bindingInput :: !BindingInput,
    hurlOptions :: !HurlOptions,
    suiteOptions :: !SuiteOptions
  }
  deriving stock (Generic, Eq, Show)

data SuitePreflightIssue
  = SuiteNotFound !SuiteName
  | SuiteRunPreparationFailed !PreparationError
  | SuiteDependencyUnavailable
  | SuiteScenarioFailed !ScenarioIssue
  | SuiteScenarioInputsUnexpected
  | SuiteIndependentExternalRequired
  | SuiteIsolationFailed !IsolationIssue
  | SuiteUnsafeRun !Text !SafetyDisposition
  | SuiteDuplicateArtifactStem !FilePath
  | SuiteSharedCurlExport !FilePath
  | SuiteReportDirectoryRequired
  | SuiteInvalidReportDirectory !FilePath
  | SuiteReportPathExists !FilePath
  | SuiteReportPathIsSymbolicLink !FilePath
  | SuiteReportPathIsNotDirectory !FilePath
  | SuiteReportIoError !FilePath !Text
  | SuiteExternalLifecycle
  | SuiteServiceNotFound !ServiceName
  | SuiteServiceBindingFailed !BindingError
  | SuiteServiceResolutionFailed !ServiceError
  deriving stock (Generic, Eq, Show)

newtype SuitePreflightError = SuitePreflightError
  { issues :: NonEmpty SuitePreflightIssue
  }
  deriving stock (Generic, Eq, Show)

-- | Safe report data has no executable requests or provider/runtime values.
data ScenarioMetadata = ScenarioMetadata
  { name :: !Text,
    scenario :: !FilePath,
    reports :: ![FilePath]
  }
  deriving stock (Generic, Eq, Show)

data SuiteMetadata = SuiteMetadata
  { name :: !SuiteName,
    isolation :: !IsolationPolicy,
    scenarios :: !(NonEmpty ScenarioMetadata),
    summaryPath :: !(Maybe FilePath)
  }
  deriving stock (Generic, Eq, Show)

data PreparedStep = HurlBatch !Int !(NonEmpty BatchCase) | ServiceBarrier !ServiceStep
  deriving stock (Generic, Show)

data PreparedSuite = PreparedSuite
  { metadata :: !SuiteMetadata,
    cases :: !(NonEmpty BatchCase),
    batchOptions :: !BatchOptions,
    managedServices :: ![ResolvedService],
    steps :: ![PreparedStep],
    setupCommands :: ![ResolvedCommand],
    teardownCommands :: ![ResolvedCommand],
    commandTimeout :: !NominalDiffTime,
    cleanupTimeout :: !NominalDiffTime
  }
  deriving stock (Generic, Show)

suiteMetadata :: ValidatedWorkspace -> SuiteRequest -> Either SuitePreflightError SuiteMetadata
suiteMetadata workspace request = do
  suite <- maybe (Left (SuitePreflightError (SuiteNotFound (request ^. #suiteName) :| []))) Right (lookupSuite (request ^. #suiteName) workspace)
  expanded <- either (Left . SuitePreflightError . (:| []) . SuiteRunPreparationFailed . SelectionPreparationFailed) Right (traverse (resolveSelection workspace . runSelection) (hurlReferences suite))
  runs <- maybe (Left (SuitePreflightError (SuiteNotFound (request ^. #suiteName) :| []))) Right (nonEmpty (concatMap toList expanded))
  pure
    SuiteMetadata
      { name = suite ^. #name,
        isolation = suite ^. #isolation,
        scenarios = fmap (\run -> ScenarioMetadata (run ^. #displayName) (run ^. #artifactStem) (map reportPath (suiteReportTargets (request ^. #suiteOptions . #reportFormats) (run ^. #artifactStem)))) runs,
        summaryPath = fmap (\root -> root </> Text.unpack (unSuiteName (suite ^. #name)) </> "summary.json") (request ^. #suiteOptions . #reportDirectory)
      }
  where
    reportPath = \case
      JUnitReport path -> path
      HtmlReport path -> path
      JsonReport path -> path
      TapReport path -> path

-- | A refusal reserves only the suite directory, never fictitious Hurl reports.
reserveSuiteSummary :: SuiteRequest -> SuiteMetadata -> IO (Either SuitePreflightIssue ())
reserveSuiteSummary request metadata = case request ^. #suiteOptions . #reportDirectory of
  Nothing -> pure (Right ())
  Just root -> prepareReportLayout root (root </> Text.unpack (unSuiteName (metadata ^. #name))) [] (request ^. #suiteOptions . #overwriteReports)

prepareSuite :: HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError PreparedSuite)
prepareSuite = prepareSuiteWith validateRenderedWorkflow

prepareSuiteWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError PreparedSuite)
prepareSuiteWith validateRendered capabilities validated request = do
  preflight <- preflightScenarioInputs validated request
  case preflight of
    Left err -> pure (Left err)
    Right verified -> prepareVerifiedSuiteWith verified validateRendered capabilities validated request

prepareVerifiedSuiteWith :: Maybe VerifiedScenarioInputs -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError PreparedSuite)
prepareVerifiedSuiteWith verified validateRendered capabilities validated request =
  case lookupSuite (request ^. #suiteName) validated of
    Nothing -> pure (Left (SuitePreflightError (SuiteNotFound (request ^. #suiteName) :| [])))
    Just _
      | Just problems <- nonEmpty (checkSuiteIsolationWith verified validated (request ^. #suiteName) (request ^. #suiteOptions . #jobs)) ->
          pure (Left (SuitePreflightError (fmap SuiteIsolationFailed problems)))
    Just suite -> do
      ambient <- getEnvironment
      selections <- case verified of
        Nothing -> traverse prepareReference (hurlReferences suite)
        Just inputs -> case traverse (resolveSelection validated . runSelection) (hurlReferences suite) of
          Left err -> pure [Left (SelectionPreparationFailed err :| [])]
          Right expanded -> case nonEmpty (concatMap toList expanded) of
            Nothing -> error "validated suite has no runs"
            Just runs -> case traverse (\run -> (run,) <$> scenarioBindingInput inputs run) runs of
              Nothing -> error "verified scenario assignment incomplete"
              Just assigned -> pure <$> prepareExpandedForSuiteWith validateRendered capabilities validated (request ^. #hurlOptions) assigned
      serviceResult <- prepareManagedServices ambient suite
      let preparationIssues =
            concat
              [ map preparationIssue (NonEmpty.toList errors)
              | Left errors <- selections
              ]
          preparedRuns = concat [NonEmpty.toList runs | Right runs <- selections]
          safetyIssues =
            [ SuiteUnsafeRun (prepared ^. #displayName) (prepared ^. #safety)
            | prepared <- preparedRuns,
              not (request ^. #suiteOptions . #allowMutating),
              requiresAuthorization (prepared ^. #safety)
            ]
          duplicateIssues =
            map SuiteDuplicateArtifactStem (duplicates (map (view #artifactStem) preparedRuns))
              <> [SuiteDuplicateArtifactStem "phases" | not (null (suite ^. #setup) && null (suite ^. #teardown)), any (\run -> take 1 (splitDirectories (run ^. #artifactStem)) == ["phases"]) preparedRuns]
          curlIssues =
            [ SuiteSharedCurlExport path
            | length preparedRuns > 1,
              Just path <- [request ^. #hurlOptions . #curlExportPath]
            ]
          reportIssues =
            [SuiteReportDirectoryRequired | not (Set.null (request ^. #suiteOptions . #reportFormats)) && isNothing (request ^. #suiteOptions . #reportDirectory)]
          serviceIssues = either pure (const []) serviceResult
          issues = preparationIssues <> safetyIssues <> duplicateIssues <> curlIssues <> reportIssues <> serviceIssues
      case nonEmpty issues of
        Just problems -> pure (Left (SuitePreflightError problems))
        Nothing -> case (nonEmpty preparedRuns, serviceResult) of
          (Just runs, Right (services, setup, teardown)) ->
            prepareReports suite runs >>= \case
              Left problem -> pure (Left (SuitePreflightError (problem :| [])))
              Right (batchCases, _summary) ->
                pure
                  ( Right
                      PreparedSuite
                        { metadata = either (error "validated suite metadata failed") id (suiteMetadata validated request),
                          cases = batchCases,
                          batchOptions =
                            BatchOptions
                              (request ^. #suiteOptions . #jobs)
                              (fromMaybe (suite ^. #failFast) (request ^. #suiteOptions . #failFastOverride)),
                          managedServices = services,
                          steps = orderedSteps validated suite batchCases,
                          setupCommands = setup,
                          teardownCommands = teardown,
                          commandTimeout = fromIntegral (suite ^. #commandTimeoutSeconds),
                          cleanupTimeout = fromIntegral (suite ^. #cleanupTimeoutSeconds)
                        }
                  )
          _ -> error "prepareSuite: validated suite produced no prepared runs"
  where
    preparationIssue RunBindingFailed {} | isJust verified = SuiteScenarioFailed ScenarioRuntimeInputFailed
    preparationIssue err = SuiteRunPreparationFailed err

    prepareReference reference =
      prepareSelectionForSuiteWith
        validateRendered
        capabilities
        validated
        (request ^. #bindingInput)
        (request ^. #hurlOptions)
        (runSelection reference)

    prepareManagedServices ambient suite
      | not (request ^. #suiteOptions . #manageService) =
          pure $ if any isLifecycle (suite ^. #runs) then Left SuiteExternalLifecycle else Right ([], [], [])
      | otherwise = do
          services <- traverse (prepareService ambient) (suiteServices suite)
          setup <- traverse (preparePhase ambient "setup") (suite ^. #setup)
          teardown <- traverse (preparePhase ambient "teardown") (suite ^. #teardown)
          pure ((,,) <$> sequence services <*> sequence setup <*> sequence teardown)

    prepareService ambient serviceName = case lookupService serviceName validated of
      Nothing -> pure (Left (SuiteServiceNotFound serviceName))
      Just service -> case requiredServiceParameters service of
        Left err -> pure (Left (SuiteServiceResolutionFailed err))
        Right required ->
          resolveParameterSubsetInEnvironment ambient validated required (request ^. #bindingInput) >>= \case
            Left err -> pure (Left (SuiteServiceBindingFailed err))
            Right bindings -> case resolveService validated bindings service of
              Left err -> pure (Left (SuiteServiceResolutionFailed err))
              Right resolved -> fmap (either (Left . SuiteServiceResolutionFailed) Right) (freezeService ambient resolved)

    preparePhase ambient phase command =
      resolveParameterSubsetInEnvironment ambient validated (Set.fromList (map (view #parameter) (command ^. #environment))) (request ^. #bindingInput) <&> \case
        Left err -> Left (SuiteServiceBindingFailed err)
        Right bindings ->
          either
            (Left . SuiteServiceResolutionFailed)
            Right
            (resolveCommand validated bindings command >>= prepareCommand ambient (request ^. #suiteName & unSuiteName & ServiceName) phase)

    prepareReports suite runs = case request ^. #suiteOptions . #reportDirectory of
      Nothing ->
        pure
          ( Right
              ( fmap (buildBatchCase TestMode CaptureRunOutput []) runs,
                Nothing
              )
          )
      Just reportRoot -> do
        let suiteRoot = reportRoot </> Text.unpack (unSuiteName (suite ^. #name))
            runList = NonEmpty.toList runs
            runRoots = map ((suiteRoot </>) . view #artifactStem) runList
            formats = request ^. #suiteOptions . #reportFormats
            batchCases =
              NonEmpty.fromList
                [ buildBatchCase TestMode CaptureRunOutput (suiteReportTargets formats runRoot) prepared
                | (prepared, runRoot) <- zip runList runRoots
                ]
            summary = suiteRoot </> "summary.json"
        prepared <- prepareReportLayout reportRoot suiteRoot (runRoots <> [suiteRoot </> "phases" </> phase </> show ordinal | (phase, commands) <- [("setup", suite ^. #setup), ("teardown", suite ^. #teardown)], ordinal <- [0 .. length commands - 1]]) (request ^. #suiteOptions . #overwriteReports)
        pure ((,Just summary) batchCases <$ prepared)

-- | Public early boundary for core runners and CLI capability detection. Raw
-- assignments are checked in full before any syntax probe or binding preparation.
preflightScenarioInputs :: ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError (Maybe VerifiedScenarioInputs))
preflightScenarioInputs workspace request = case lookupSuite (request ^. #suiteName) workspace of
  Nothing -> pure (failure (SuiteNotFound (request ^. #suiteName)))
  Just suite -> case (suite ^. #isolation, request ^. #scenarioInputs) of
    (SharedState, Just _) -> pure (failure SuiteScenarioInputsUnexpected)
    (SharedState, Nothing) -> pure $ case nonEmpty (checkSuiteIsolation workspace (request ^. #suiteName) (request ^. #suiteOptions . #jobs)) of
      Nothing -> Right Nothing
      Just issues -> Left (SuitePreflightError (fmap SuiteIsolationFailed issues))
    (IndependentState, Nothing) -> pure (failure (SuiteIsolationFailed IndependentStateHandoffRequired))
    (IndependentState, Just inputs)
      | request ^. #suiteOptions . #manageService -> pure (failure SuiteIndependentExternalRequired)
      | otherwise -> case traverse (resolveSelection workspace . runSelection) (hurlReferences suite) of
          Left err -> pure (failure (SuiteRunPreparationFailed (SelectionPreparationFailed err)))
          Right expanded -> verifyScenarioInputs workspace (concatMap toList expanded) (request ^. #bindingInput) inputs <&> either (failure . SuiteScenarioFailed) (Right . Just)
  where
    failure issue = Left (SuitePreflightError (issue :| []))

hurlReferences :: Suite -> [RunReference]
hurlReferences suite = filter (not . isLifecycle) (suite ^. #runs)

isLifecycle :: RunReference -> Bool
isLifecycle (ServiceRun _) = True
isLifecycle _ = False

-- | Partition adjacent Hurl references without losing global case indices.
orderedSteps :: ValidatedWorkspace -> Suite -> NonEmpty BatchCase -> [PreparedStep]
orderedSteps workspace suite cases = go 0 [] 0 (toList cases) (suite ^. #runs)
  where
    flush _ [] = []
    flush offset accumulated = [HurlBatch offset (NonEmpty.fromList accumulated)]
    go offset accumulated count _remaining [] = flush (offset - count) accumulated
    go offset accumulated count remaining (ServiceRun step : rest) =
      flush (offset - count) accumulated <> [ServiceBarrier step] <> go offset [] 0 remaining rest
    go offset accumulated count remaining (reference : rest) =
      let size = either (const 0) length (resolveSelection workspace (runSelection reference))
          (batch, later) = splitAt size remaining
       in go (offset + size) (accumulated <> batch) (count + size) later rest

runSelection :: RunReference -> RunSelection
runSelection = \case
  WorkflowRun name -> SelectWorkflow name
  RecipeRun name -> SelectRecipe name
  MatrixRun name -> SelectMatrix name
  ServiceRun _ -> error "lifecycle step is not a Hurl selection"

requiresAuthorization :: SafetyDisposition -> Bool
requiresAuthorization = \case
  Classified ReadOnly -> False
  Classified Mutating -> True
  UnclassifiedWorkflow -> True

suiteReportTargets :: Set ReportFormat -> FilePath -> [HurlReportTarget]
suiteReportTargets formats runRoot = map target (Set.toAscList formats)
  where
    target = \case
      JUnit -> JUnitReport (runRoot </> "junit.xml")
      Html -> HtmlReport (runRoot </> "html")
      Json -> JsonReport (runRoot </> "json")
      Tap -> TapReport (runRoot </> "report.tap")

prepareReportLayout :: FilePath -> FilePath -> [FilePath] -> Bool -> IO (Either SuitePreflightIssue ())
prepareReportLayout reportRoot suiteRoot runRoots overwrite
  | null reportRoot || reportRoot == "." || reportRoot == ".." || normalise reportRoot == "/" = pure (Left (SuiteInvalidReportDirectory reportRoot))
  | otherwise = do
      inspected <- concat <$> traverse inspectDirectory (filter (\path -> path /= "/" && path /= "") (drop 1 (scanl (</>) "" (splitDirectories (normalise suiteRoot)))))
      case inspected of
        problem : _ -> pure (Left problem)
        [] -> do
          suiteExists <- doesPathExist suiteRoot
          if suiteExists && not overwrite
            then pure (Left (SuiteReportPathExists suiteRoot))
            else do
              attempted <- try @IOException $ do
                when suiteExists (removePathForcibly suiteRoot)
                ensureOwnerDirectory reportRoot
                createDirectory suiteRoot
                secureDirectory suiteRoot
                traverse_ createRunRoot runRoots
              pure $ case attempted of
                Left err -> Left (SuiteReportIoError suiteRoot (Text.pack (displayException err)))
                Right () -> Right ()
  where
    createRunRoot path = do
      createDirectoryIfMissing True path
      secureTree suiteRoot path

inspectDirectory :: FilePath -> IO [SuitePreflightIssue]
inspectDirectory path = do
  inspected <- try @IOException (getSymbolicLinkStatus path)
  case inspected of
    Left err | isDoesNotExistError err -> pure []
    Left _ -> pure [SuiteReportIoError path "could not inspect report path"]
    Right status
      | isSymbolicLink status -> do
          -- macOS exposes these fixed OS-owned aliases for ordinary temporary
          -- directories. User-controlled symlink ancestors remain forbidden.
          canonical <- try @IOException (canonicalizePath path)
          pure [SuiteReportPathIsSymbolicLink path | not (os == "darwin" && path `elem` ["/tmp", "/var"] && either (const False) (== ("/private" <> path)) canonical)]
      | not (isDirectory status) -> pure [SuiteReportPathIsNotDirectory path]
      | otherwise -> pure []

ensureOwnerDirectory :: FilePath -> IO ()
ensureOwnerDirectory path = createDirectoryIfMissing True path >> secureDirectory path

secureTree :: FilePath -> FilePath -> IO ()
secureTree root target = go root relativeParts
  where
    rootParts = splitDirectories root
    targetParts = splitDirectories target
    relativeParts = drop (length rootParts) targetParts
    go _ [] = pure ()
    go parent (component : remaining) = do
      let path = parent </> component
      secureDirectory path
      go path remaining

secureDirectory :: FilePath -> IO ()
secureDirectory path = do
  setFileMode path secureDirectoryMode
  actual <- (.&. accessModes) . fileMode <$> getFileStatus path
  unless (actual == secureDirectoryMode) (ioError (userError ("insecure permissions on " <> path)))

secureDirectoryMode :: FileMode
secureDirectoryMode = ownerReadMode `unionFileModes` ownerWriteMode `unionFileModes` ownerExecuteMode

duplicates :: (Ord value) => [value] -> [value]
duplicates values =
  [ value
  | (value, count) <- Map.toAscList (Map.fromListWith (+) [(value, 1 :: Int) | value <- values]),
    count > 1
  ]

renderSuitePreflightError :: SuitePreflightError -> Text
renderSuitePreflightError = Text.intercalate "\n" . map renderSuitePreflightIssue . toList . view #issues

renderSuitePreflightIssue :: SuitePreflightIssue -> Text
renderSuitePreflightIssue = \case
  SuiteDependencyUnavailable -> "suite-dependency-unavailable"
  SuiteScenarioFailed issue -> renderScenarioIssue issue
  SuiteScenarioInputsUnexpected -> "scenario-inputs-unexpected: shared-state suites reject scenario inputs"
  SuiteIndependentExternalRequired -> "independent-state-external-required: use --external-service"
  SuiteIsolationFailed issue -> renderIsolationIssue issue
  SuiteExternalLifecycle -> "external-service-lifecycle: lifecycle steps require managed services"
  SuiteNotFound name -> "unknown suite " <> quote (unSuiteName name)
  SuiteRunPreparationFailed err -> renderPreparationError err
  SuiteUnsafeRun name disposition ->
    "run " <> quote name <> " requires --allow-mutating (" <> safetyLabel disposition <> ")"
  SuiteDuplicateArtifactStem stem -> "suite produces duplicate report path for " <> quote (Text.pack stem)
  SuiteSharedCurlExport path -> "--curl has one path and cannot be shared by multiple suite runs: " <> quote (Text.pack path)
  SuiteReportDirectoryRequired -> "--report-dir is required when a report format is selected"
  SuiteInvalidReportDirectory path -> "invalid report directory " <> quote (Text.pack path)
  SuiteReportPathExists path -> "report suite directory already exists; use --overwrite to replace " <> quote (Text.pack path)
  SuiteReportPathIsSymbolicLink path -> "report path must not be a symbolic link: " <> quote (Text.pack path)
  SuiteReportPathIsNotDirectory path -> "report path is not a directory: " <> quote (Text.pack path)
  SuiteReportIoError path message -> "could not prepare reports under " <> quote (Text.pack path) <> ": " <> message
  SuiteServiceNotFound name -> "suite refers to unknown service " <> quote (unServiceName name)
  SuiteServiceBindingFailed err -> "managed service: " <> renderBindingError err
  SuiteServiceResolutionFailed err -> "managed service: " <> renderServiceError err
  where
    safetyLabel = \case
      Classified Mutating -> "mutating recipe"
      Classified ReadOnly -> "read-only recipe"
      UnclassifiedWorkflow -> "unclassified workflow"
    quote value = "\"" <> value <> "\""

-- | Stable codes are the only diagnostic content serialized into summaries.
suitePreflightReasonCode :: SuitePreflightIssue -> Text
suitePreflightReasonCode = \case
  SuiteIsolationFailed (SharedStateParallelUnsafe _ _) -> "shared-state-parallel-unsafe"
  SuiteIsolationFailed IndependentStateHandoffRequired -> "independent-state-handoff-required"
  SuiteScenarioFailed issue -> renderScenarioIssue issue
  SuiteScenarioInputsUnexpected -> "scenario-inputs-unexpected"
  SuiteIndependentExternalRequired -> "independent-state-external-required"
  SuiteDependencyUnavailable -> "suite-dependency-unavailable"
  SuiteExternalLifecycle -> "external-service-lifecycle"
  SuiteNotFound _ -> "suite-not-found"
  SuiteRunPreparationFailed RunBindingFailed {} -> "suite-binding-failed"
  SuiteRunPreparationFailed _ -> "suite-preparation-failed"
  SuiteUnsafeRun _ _ -> "mutation-authorization-required"
  SuiteDuplicateArtifactStem _ -> "suite-duplicate-scenario"
  SuiteSharedCurlExport _ -> "suite-shared-curl-export"
  SuiteReportDirectoryRequired -> "suite-report-directory-required"
  SuiteInvalidReportDirectory _ -> "suite-invalid-report-directory"
  SuiteReportPathExists _ -> "suite-report-path-exists"
  SuiteReportPathIsSymbolicLink _ -> "suite-report-path-symlink"
  SuiteReportPathIsNotDirectory _ -> "suite-report-path-not-directory"
  SuiteReportIoError _ _ -> "suite-report-io-error"
  SuiteServiceNotFound _ -> "suite-service-not-found"
  SuiteServiceBindingFailed _ -> "suite-service-binding-failed"
  SuiteServiceResolutionFailed _ -> "suite-service-resolution-failed"

suitePreflightSetupFailure :: SuitePreflightIssue -> Bool
suitePreflightSetupFailure = \case
  SuiteDependencyUnavailable -> True
  SuiteScenarioFailed ScenarioFileUnreadable -> True
  SuiteScenarioFailed ScenarioRuntimeInputFailed -> True
  SuiteRunPreparationFailed RunBindingFailed {} -> True
  SuiteServiceBindingFailed _ -> True
  _ -> False
