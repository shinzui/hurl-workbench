-- | Complete suite preflight. Every run, safety decision, report target, and
--   optional managed service is resolved before execution can start.
module HurlWorkbench.Suite.Resolve
  ( ReportFormat (..),
    SuiteOptions (..),
    SuiteRequest (..),
    SuitePreflightIssue (..),
    SuitePreflightError (..),
    PreparedSuite (..),
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
import HurlWorkbench.Hurl.Format (HurlfmtCapabilities, HurlfmtError, validateRenderedWorkflow)
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import System.Directory
  ( createDirectory,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesPathExist,
    pathIsSymbolicLink,
    removePathForcibly,
  )
import System.FilePath (splitDirectories, (</>))
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
    bindingInput :: !BindingInput,
    hurlOptions :: !HurlOptions,
    suiteOptions :: !SuiteOptions
  }
  deriving stock (Generic, Eq, Show)

data SuitePreflightIssue
  = SuiteNotFound !SuiteName
  | SuiteRunPreparationFailed !PreparationError
  | SuiteUnsafeRun !Text !SafetyDisposition
  | SuiteDuplicateArtifactStem !FilePath
  | SuiteSharedCurlExport !FilePath
  | SuiteReportDirectoryRequired
  | SuiteInvalidReportDirectory !FilePath
  | SuiteReportPathExists !FilePath
  | SuiteReportPathIsSymbolicLink !FilePath
  | SuiteReportPathIsNotDirectory !FilePath
  | SuiteReportIoError !FilePath !Text
  | SuiteServiceNotFound !ServiceName
  | SuiteServiceBindingFailed !BindingError
  | SuiteServiceResolutionFailed !ServiceError
  deriving stock (Generic, Eq, Show)

newtype SuitePreflightError = SuitePreflightError
  { issues :: NonEmpty SuitePreflightIssue
  }
  deriving stock (Generic, Eq, Show)

data PreparedSuite = PreparedSuite
  { name :: !SuiteName,
    cases :: !(NonEmpty BatchCase),
    batchOptions :: !BatchOptions,
    managedService :: !(Maybe ResolvedService),
    summaryPath :: !(Maybe FilePath)
  }
  deriving stock (Generic, Show)

prepareSuite :: HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError PreparedSuite)
prepareSuite = prepareSuiteWith validateRenderedWorkflow

prepareSuiteWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> SuiteRequest -> IO (Either SuitePreflightError PreparedSuite)
prepareSuiteWith validateRendered capabilities validated request =
  case lookupSuite (request ^. #suiteName) validated of
    Nothing -> pure (Left (SuitePreflightError (SuiteNotFound (request ^. #suiteName) :| [])))
    Just suite -> do
      selections <- traverse prepareReference (suite ^. #runs)
      serviceResult <- prepareManagedService suite
      let preparationIssues =
            concat
              [ map SuiteRunPreparationFailed (NonEmpty.toList errors)
              | Left errors <- selections
              ]
          preparedRuns = concat [NonEmpty.toList runs | Right runs <- selections]
          safetyIssues =
            [ SuiteUnsafeRun (prepared ^. #displayName) (prepared ^. #safety)
            | prepared <- preparedRuns,
              not (request ^. #suiteOptions . #allowMutating),
              requiresAuthorization (prepared ^. #safety)
            ]
          duplicateIssues = map SuiteDuplicateArtifactStem (duplicates (map (view #artifactStem) preparedRuns))
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
          (Just runs, Right service) ->
            prepareReports suite runs >>= \case
              Left problem -> pure (Left (SuitePreflightError (problem :| [])))
              Right (batchCases, summary) ->
                pure
                  ( Right
                      PreparedSuite
                        { name = suite ^. #name,
                          cases = batchCases,
                          batchOptions =
                            BatchOptions
                              (request ^. #suiteOptions . #jobs)
                              (fromMaybe (suite ^. #failFast) (request ^. #suiteOptions . #failFastOverride)),
                          managedService = service,
                          summaryPath = summary
                        }
                  )
          _ -> error "prepareSuite: validated suite produced no prepared runs"
  where
    prepareReference reference =
      prepareSelectionForSuiteWith
        validateRendered
        capabilities
        validated
        (request ^. #bindingInput)
        (request ^. #hurlOptions)
        (runSelection reference)

    prepareManagedService suite
      | not (request ^. #suiteOptions . #manageService) = pure (Right Nothing)
      | otherwise = case suite ^. #service of
          Nothing -> pure (Right Nothing)
          Just serviceName -> case lookupService serviceName validated of
            Nothing -> pure (Left (SuiteServiceNotFound serviceName))
            Just service -> case requiredServiceParameters service of
              Left err -> pure (Left (SuiteServiceResolutionFailed err))
              Right required ->
                resolveParameterSubset validated required (request ^. #bindingInput) <&> \case
                  Left err -> Left (SuiteServiceBindingFailed err)
                  Right bindings -> case resolveService validated bindings service of
                    Left err -> Left (SuiteServiceResolutionFailed err)
                    Right resolved -> Right (Just resolved)

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
        prepared <- prepareReportLayout reportRoot suiteRoot runRoots (request ^. #suiteOptions . #overwriteReports)
        pure ((,Just summary) batchCases <$ prepared)

runSelection :: RunReference -> RunSelection
runSelection = \case
  WorkflowRun name -> SelectWorkflow name
  RecipeRun name -> SelectRecipe name
  MatrixRun name -> SelectMatrix name

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
  | null reportRoot || reportRoot == "." || reportRoot == ".." = pure (Left (SuiteInvalidReportDirectory reportRoot))
  | otherwise = do
      inspectedRoot <- inspectDirectory reportRoot
      inspectedSuite <- inspectDirectory suiteRoot
      case inspectedRoot <> inspectedSuite of
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
  exists <- doesPathExist path
  if not exists
    then pure []
    else do
      symbolic <- pathIsSymbolicLink path
      directory <- if symbolic then pure False else doesDirectoryExist path
      pure $ [SuiteReportPathIsSymbolicLink path | symbolic] <> [SuiteReportPathIsNotDirectory path | not symbolic && not directory]

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
