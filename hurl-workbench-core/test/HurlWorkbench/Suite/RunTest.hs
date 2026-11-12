module HurlWorkbench.Suite.RunTest (tests) where

import Control.Concurrent.Async (AsyncCancelled (..), cancel, waitCatch, withAsync)
import Control.Concurrent.STM (TVar, atomically, modifyTVar', newEmptyTMVarIO, newTVarIO, putTMVar, readTVar, readTVarIO, takeTMVar)
import Control.Exception (bracket_, fromException)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Version (makeVersion)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.FileRoot
import HurlWorkbench.Suite.Isolation
import HurlWorkbench.Suite.LifecycleTest qualified as LifecycleTest
import HurlWorkbench.Suite.Resolve
import HurlWorkbench.Suite.Run
import HurlWorkbench.Suite.Scenario (ScenarioInputs (..))
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (createDirectoryIfMissing, createDirectoryLink, doesPathExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "integration suites"
    [ LifecycleTest.tests,
      testCase "explicit suite roots reach every request and protect refusal-summary inputs" $
        withSystemTempDirectory "suite-file-root" $ \directory -> do
          workspace <- loadValidated "test/fixtures/workspaces/isolation/hurl-workbench.dhall"
          root <- validateFileRoot directory (Just directory) >>= either (assertFailure . show) pure
          requests <- newTVarIO []
          let input = emptyBindingInput {plainOverrides = Map.singleton (ParameterName "baseUrl") (literal "http://fixture.test")}
              request = SuiteRequest (SuiteName "reads") (Just root) Nothing input defaultHurlOptions (SuiteOptions (positive 2) Nothing False False Set.empty Nothing False)
          _ <- runSuite (recordingRunner requests) trueCapabilities workspace request >>= requireSuite
          observed <- readTVarIO requests
          assertBool "all suite cases ran" (length observed > 1)
          for_ observed $ \run -> run ^. #fileRoot @?= root
          let forbidden _ _ = assertFailure "formatter ran before output preflight"
          result <- runSuiteWith forbidden (HurlRunner (const (assertFailure "Hurl ran"))) trueCapabilities workspace (request & #suiteOptions . #reportDirectory .~ Just directory & #suiteOptions . #overwriteReports .~ True)
          case result of
            Left err -> assertBool "root failure" (all (\case SuiteFileRootFailed _ -> True; _ -> False) (err ^. #issues))
            Right _ -> assertFailure "suite accepted overlapping report root"
          doesPathExist (directory </> "reads") >>= (@?= False),
      testCase "parallel unsafe suites are refused before syntax, binding IO, service, or Hurl" $ do
        workspace <- loadValidated "test/fixtures/workspaces/isolation/hurl-workbench.dhall"
        let request name allowed manage = SuiteRequest (SuiteName name) Nothing Nothing emptyBindingInput defaultHurlOptions (SuiteOptions (positive 2) Nothing allowed manage Set.empty Nothing False)
            forbidden _ _ = assertFailure "syntax validator called"
            runner = HurlRunner (const (assertFailure "Hurl started"))
        for_ [False, True] $ \allowed -> for_ [False, True] $ \manage -> do
          for_ ["mixed", "single-write"] $ \name -> do
            result <- runSuiteWith forbidden runner trueCapabilities workspace (request name allowed manage)
            case result of
              Left err -> do
                let unsafe = [scenario | SuiteIsolationFailed (SharedStateParallelUnsafe scenario _) <- toList (err ^. #issues)]
                unsafe @?= if name == "mixed" then ["dangerous-health", "writes/first", "writes/second", "health"] else ["dangerous-health"]
              Right _ -> assertFailure "unsafe suite started"
        for_ [1, 2] $ \jobs ->
          runSuiteWith forbidden runner trueCapabilities workspace (request "independent" True False & #suiteOptions . #jobs .~ positive jobs) >>= \case
            Left err -> toList (err ^. #issues) @?= [SuiteIsolationFailed IndependentStateHandoffRequired]
            Right _ -> assertFailure "bare independent declaration started"
        for_ [("reads", False, SuiteScenarioInputsUnexpected), ("independent", True, SuiteIndependentExternalRequired)] $ \(name, manage, issue) ->
          runSuiteWith forbidden runner trueCapabilities workspace (request name True manage & #scenarioInputs .~ Just (ScenarioInputs [])) >>= \case
            Left err -> toList (err ^. #issues) @?= [issue]
            Right _ -> assertFailure "invalid isolation mode accepted"
        for_ ["service-started", "readiness-started"] $ \marker ->
          doesPathExist ("test/fixtures/workspaces/isolation" </> marker) >>= (@?= False),
      testCase "parallel reads and serial authorized mutations remain supported" $ do
        workspace <- loadValidated "test/fixtures/workspaces/isolation/hurl-workbench.dhall"
        requests <- newTVarIO []
        let request name jobs allowed = SuiteRequest (SuiteName name) Nothing Nothing (emptyBindingInput {plainOverrides = Map.singleton (ParameterName "baseUrl") (literal "http://fixture.test")}) defaultHurlOptions (SuiteOptions (positive jobs) Nothing allowed False Set.empty Nothing False)
        readResult <- runSuite (recordingRunner requests) trueCapabilities workspace (request "reads" 2 False) >>= requireSuite
        readResult ^. #selectedExitCode @?= ExitSuccess
        length <$> readTVarIO requests >>= (@?= 3)
        write <- runSuite (recordingRunner requests) trueCapabilities workspace (request "single-write" 1 True) >>= requireSuite
        write ^. #selectedExitCode @?= ExitSuccess
        runSuite (recordingRunner requests) trueCapabilities workspace (request "single-write" 1 False) >>= \case
          Left err -> assertBool "serial still requires opt-in" (any isUnsafe (err ^. #issues))
          Right _ -> assertFailure "unauthorized mutation started",
      testCase "refusal and setup summaries contain logical cases and stable codes only" $
        withSystemTempDirectory "suite-preflight-summary" $ \directory -> do
          workspace <- loadValidated "test/fixtures/workspaces/isolation/hurl-workbench.dhall"
          let runner = HurlRunner (const (assertFailure "preflight started Hurl"))
              request name root = SuiteRequest (SuiteName name) Nothing Nothing emptyBindingInput defaultHurlOptions (SuiteOptions (positive 2) Nothing True False Set.empty (Just root) False)
          for_ [("mixed", "refused"), ("reads", "setup-failed")] $ \(name, status) -> do
            let root = directory </> name
            runSuiteWith (\_ _ -> pure (Right ())) runner trueCapabilities workspace (request (Text.pack name) root) >>= \case
              Left _ -> pure ()
              Right _ -> assertFailure "preflight unexpectedly succeeded"
            summary <- readJson (root </> name </> "summary.json")
            field "status" summary @?= Aeson.String status
            field "isolation" summary @?= Aeson.String "shared-state"
            let cases = arrayValues (field "cases" summary)
            assertBool "logical cases present" (not (null cases))
            for_ cases $ \logical -> do
              field "status" logical @?= Aeson.String "not-started"
              field "reports" logical @?= Aeson.toJSON ([] :: [Text])
              field "exitCode" logical @?= Aeson.Null
              assertBool "scenario is explicit" (field "scenario" logical /= Aeson.Null),
      testCase "unsafe report destinations and unknown suites preserve existing trees" $
        withSystemTempDirectory "suite-refusal-destination" $ \directory -> do
          workspace <- loadValidated "test/fixtures/workspaces/isolation/hurl-workbench.dhall"
          let outsideDirectory = directory </> "outside"
              link = directory </> "link"
              request name root = SuiteRequest (SuiteName name) Nothing Nothing emptyBindingInput defaultHurlOptions (SuiteOptions (positive 2) Nothing True False Set.empty (Just root) True)
              runner = HurlRunner (const (assertFailure "unexpected execution"))
          createDirectoryIfMissing True outsideDirectory
          ByteString.writeFile (outsideDirectory </> "sentinel") "preserve"
          createDirectoryLink outsideDirectory link
          result <- runSuiteWith (\_ _ -> assertFailure "unexpected format") runner trueCapabilities workspace (request "mixed" (link </> "nested"))
          case result of
            Left err -> assertBool "symlink ancestor rejected" (any (\case SuiteReportPathIsSymbolicLink _ -> True; _ -> False) (err ^. #issues))
            Right _ -> assertFailure "unsafe destination accepted"
          doesPathExist (outsideDirectory </> "nested") >>= (@?= False)
          _ <- runSuite runner trueCapabilities workspace (request "unknown" outsideDirectory)
          ByteString.readFile (outsideDirectory </> "sentinel") >>= (@?= "preserve")
          doesPathExist (outsideDirectory </> "unknown") >>= (@?= False),
      testCase "cancellation retains completed outcomes, joins workers, and propagates even if summary writing fails" $
        for_ [False, True] $ \breakSummary -> withSystemTempDirectory "suite-cancel-summary" $ \directory -> do
          workspace <- loadValidated "test/fixtures/workspaces/isolation/hurl-workbench.dhall"
          started <- newEmptyTMVarIO
          blocked <- newEmptyTMVarIO
          starts <- newTVarIO (0 :: Int)
          active <- newTVarIO (0 :: Int)
          let summaryPath = directory </> "reads" </> "summary.json"
              literal_ = literal "private-plain-sentinel"
              request = SuiteRequest (SuiteName "reads") Nothing Nothing (emptyBindingInput {plainOverrides = Map.singleton (ParameterName "baseUrl") literal_}) defaultHurlOptions (SuiteOptions (positive 1) Nothing False False Set.empty (Just directory) False)
              runner = HurlRunner $ \_ -> do
                ordinal <- atomically $ do
                  modifyTVar' starts (+ 1)
                  count <- readTVar starts
                  pure count
                if ordinal == 1
                  then pure (Right (RunResult ExitSuccess 0.01 (Just (CapturedRunOutput "private-captured-sentinel" "private-secret-sentinel"))))
                  else bracket_
                    (atomically (modifyTVar' active (+ 1)))
                    (atomically (modifyTVar' active (subtract 1)))
                    $ do
                      when breakSummary (createDirectoryIfMissing True summaryPath)
                      atomically (putTMVar started ())
                      _ <- atomically (takeTMVar blocked)
                      assertFailure "cancelled run resumed"
          withAsync (runSuiteWith (\_ _ -> pure (Right ())) runner trueCapabilities workspace request) $ \worker -> do
            atomically (takeTMVar started)
            cancel worker
            waitCatch worker >>= \case
              Left err -> (fromException err :: Maybe AsyncCancelled) @?= Just AsyncCancelled
              Right _ -> assertFailure "cancellation returned a SuiteResult"
          readTVarIO active >>= (@?= 0)
          readTVarIO starts >>= (@?= 2)
          unless breakSummary $ do
            raw <- ByteString.readFile summaryPath
            for_ ["private-plain-sentinel", "private-captured-sentinel", "private-secret-sentinel"] $ \sentinel -> assertBool "summary redacted" (not (sentinel `ByteString.isInfixOf` raw))
            summary <- readJson summaryPath
            field "status" summary @?= Aeson.String "cancelled"
            let cases = arrayValues (field "cases" summary)
            map (field "scenario") cases @?= map Aeson.String ["health-cases/first", "health-cases/second", "health-cases/third"]
            map (field "status") cases @?= map Aeson.String ["passed", "cancelled", "cancelled"],
      testCase "summary failure preserves a managed-service failure status" $
        withSystemTempDirectory "suite-service-summary-failure" $ \directory -> do
          original <- failureWorkspace
          let summaryPath = directory </> "failure" </> "summary.json"
              context = validatedContext original
              sabotage service = service & #command . #executable .~ "python3" & #command . #arguments .~ ["-c", "import os, sys; os.mkdir(sys.argv[1]); raise SystemExit(9)", Text.pack summaryPath]
          workspace <- validateWorkspace (context & #workspace . #services %~ map sabotage) >>= either (assertFailure . show) pure
          requests <- newTVarIO []
          let request = SuiteRequest (SuiteName "failure") Nothing Nothing emptyBindingInput defaultHurlOptions (SuiteOptions (positive 1) Nothing False True Set.empty (Just directory) False)
          result <- runSuite (recordingRunner requests) trueCapabilities workspace request >>= requireSuite
          result ^. #selectedExitCode @?= ExitFailure 4
          assertBool "summary failure retained" (isJust (result ^. #summaryError))
          readTVarIO requests >>= (@?= []),
      testCase "missing managed environment skips Hurl; external service bypasses policy" $ do
        original <- failureWorkspace
        let context = validatedContext original
            services = map (\service -> service & #command . #environmentPolicy .~ Clean ["HURL_WORKBENCH_TEST_ABSENT_972638"]) (validatedWorkspace original ^. #services)
        workspace <- validateWorkspace (context & #workspace . #services .~ services) >>= either (assertFailure . show) pure
        requests <- newTVarIO []
        let request = SuiteRequest (SuiteName "failure") Nothing Nothing emptyBindingInput defaultHurlOptions (SuiteOptions (positive 1) Nothing False True Set.empty Nothing False)
        result <- runSuite (recordingRunner requests) trueCapabilities workspace request
        case result of
          Left err -> assertBool "missing environment rejected in preflight" (any (\case SuiteServiceResolutionFailed _ -> True; _ -> False) (err ^. #issues))
          Right _ -> assertFailure "missing managed environment accepted"
        readTVarIO requests >>= (@?= [])
        external <- runSuite (recordingRunner requests) trueCapabilities workspace (request & #suiteOptions . #manageService .~ False) >>= requireSuite
        external ^. #selectedExitCode @?= ExitSuccess
        length <$> readTVarIO requests >>= (@?= 1),
      testCase "blocks unclassified runs before the managed service or Hurl starts" $
        withSystemTempDirectory "hurl-workbench-suite-gate" $ \directory -> do
          ByteString.writeFile (directory </> "secrets.env") "client_secret=suite-secret\n"
          workspace <- fullWorkspace
          requests <- newTVarIO []
          result <- runSuite (recordingRunner requests) trueCapabilities workspace (fullSuiteRequest directory False True Set.empty Nothing False)
          case result of
            Left err ->
              assertBool
                "preflight identifies the unclassified workflow"
                (any isUnsafe (toList (err ^. #issues)))
            Right _ -> assertFailure "expected the suite safety gate to fail"
          readTVarIO requests >>= (@?= []),
      testCase "flattens runs, isolates reports, and writes a redacted atomic summary" $
        withSystemTempDirectory "hurl-workbench-suite-reports" $ \directory -> do
          ByteString.writeFile (directory </> "secrets.env") "client_secret=suite-secret\n"
          workspace <- fullWorkspace
          requests <- newTVarIO []
          let reportRoot = directory </> "reports"
              request = fullSuiteRequest directory True False (Set.fromList [JUnit, Json]) (Just reportRoot) False
          result <- runSuite (recordingRunner requests) trueCapabilities workspace request >>= requireSuite
          map (view #name) (NonEmpty.toList (result ^. #cases))
            @?= ["list-members", "top-properties", "property-page-sizes/small", "property-page-sizes/large"]
          result ^. #serviceOutcome @?= Nothing
          result ^. #selectedExitCode @?= ExitSuccess
          summary <- maybe (assertFailure "missing summary path") pure (result ^. #summaryPath)
          rawSummary <- ByteString.readFile summary
          assertBool "summary omits secret values" (not ("suite-secret" `ByteString.isInfixOf` rawSummary))
          assertBool "summary omits plain runtime values" (not ("suite-client" `ByteString.isInfixOf` rawSummary))
          assertBool "summary names relative report targets" ("property-page-sizes/small/junit.xml" `ByteString.isInfixOf` rawSummary)
          observed <- readTVarIO requests
          length observed @?= 4
          traverse_ assertTestRequest observed
          traverse_ (traverse_ assertReportExists . requestReportPaths) observed
          runSuite (recordingRunner requests) trueCapabilities workspace request >>= \case
            Left err -> assertBool "existing suite report root is rejected" (any isExistingReport (toList (err ^. #issues)))
            Right _ -> assertFailure "expected an existing report error"
          overwritten <- runSuite (recordingRunner requests) trueCapabilities workspace (request & #suiteOptions . #overwriteReports .~ True) >>= requireSuite
          overwritten ^. #selectedExitCode @?= ExitSuccess,
      testCase "turns managed-service failure into exit 4 and prerequisite skips" $ do
        workspace <- failureWorkspace
        requests <- newTVarIO []
        let request =
              SuiteRequest
                { suiteName = SuiteName "failure",
                  fileRoot = Nothing,
                  scenarioInputs = Nothing,
                  bindingInput = emptyBindingInput,
                  hurlOptions = defaultHurlOptions,
                  suiteOptions = SuiteOptions (positive 1) Nothing False True Set.empty Nothing False
                }
        result <- runSuite (recordingRunner requests) trueCapabilities workspace request >>= requireSuite
        result ^. #selectedExitCode @?= ExitFailure 4
        map (view #outcome) (NonEmpty.toList (result ^. #cases)) @?= [CaseSkipped BatchPrerequisiteFailed]
        case result ^. #serviceOutcome of
          Just (ServiceFailed _) -> pure ()
          other -> assertFailure ("expected managed-service failure, got " <> show other)
        readTVarIO requests >>= (@?= [])
    ]

fullSuiteRequest :: FilePath -> Bool -> Bool -> Set ReportFormat -> Maybe FilePath -> Bool -> SuiteRequest
fullSuiteRequest directory allowMutating manageService reportFormats reportDirectory overwriteReports =
  SuiteRequest
    { suiteName = SuiteName "smoke",
      fileRoot = Nothing,
      scenarioInputs = Nothing,
      bindingInput =
        emptyBindingInput
          { plainOverrides = Map.singleton (ParameterName "client_id") (literal "suite-client"),
            secretFiles = [directory </> "secrets.env"]
          },
      hurlOptions = defaultHurlOptions,
      suiteOptions =
        SuiteOptions
          { jobs = positive 1,
            failFastOverride = Nothing,
            allowMutating,
            manageService,
            reportFormats,
            reportDirectory,
            overwriteReports
          }
    }

recordingRunner :: TVar [RunRequest] -> HurlRunner
recordingRunner requests = HurlRunner $ \request -> do
  materializeReports request
  atomically (modifyTVar' requests (request :))
  pure (Right (RunResult ExitSuccess 0.01 (Just (CapturedRunOutput "" ""))))

materializeReports :: RunRequest -> IO ()
materializeReports request = traverse_ create (request ^. #reportTargets)
  where
    create = \case
      JUnitReport path -> ByteString.writeFile path "<testsuites/>"
      TapReport path -> ByteString.writeFile path "1..0\n"
      HtmlReport path -> createDirectoryIfMissing True path >> ByteString.writeFile (path </> "index.html") ""
      JsonReport path -> createDirectoryIfMissing True path >> ByteString.writeFile (path </> "report.json") "{}"

requestReportPaths :: RunRequest -> [FilePath]
requestReportPaths request = map path (request ^. #reportTargets)
  where
    path = \case
      JUnitReport value -> value
      TapReport value -> value
      HtmlReport value -> value
      JsonReport value -> value

assertTestRequest :: RunRequest -> IO ()
assertTestRequest request = do
  request ^. #mode @?= TestMode
  length (request ^. #reportTargets) @?= 2

assertReportExists :: FilePath -> IO ()
assertReportExists path = doesPathExist path >>= assertBool ("fake report target was not created: " <> path)

requireSuite :: Either SuitePreflightError SuiteResult -> IO SuiteResult
requireSuite = either (assertFailure . Text.unpack . renderSuitePreflightError) pure

isUnsafe :: SuitePreflightIssue -> Bool
isUnsafe SuiteUnsafeRun {} = True
isUnsafe _ = False

isExistingReport :: SuitePreflightIssue -> Bool
isExistingReport SuiteReportPathExists {} = True
isExistingReport _ = False

literal :: Text -> HurlValueLiteral
literal value = either (error . show) id (mkHurlValueLiteral value)

positive :: Int -> PositiveInt
positive value = either (error . show) id (mkPositiveInt value)

trueCapabilities :: HurlfmtCapabilities
trueCapabilities = HurlfmtCapabilities (HurlfmtExecutable "true") (makeVersion [8, 0, 1])

fullWorkspace :: IO ValidatedWorkspace
fullWorkspace = loadValidated "test/fixtures/workspaces/full/hurl-workbench.dhall"

failureWorkspace :: IO ValidatedWorkspace
failureWorkspace = loadValidated "test/fixtures/workspaces/suite-failure/hurl-workbench.dhall"

loadValidated :: FilePath -> IO ValidatedWorkspace
loadValidated path = do
  loaded <- loadWorkspaceContext (ExplicitWorkspace path)
  context <- either (assertFailure . Text.unpack . renderWorkspaceError) pure loaded
  validateWorkspace context >>= either (assertFailure . Text.unpack . Text.unlines . map renderValidationIssue . toList) pure

readJson :: FilePath -> IO Aeson.Value
readJson path = ByteString.readFile path >>= either assertFailure pure . Aeson.eitherDecodeStrict

field :: Aeson.Key -> Aeson.Value -> Aeson.Value
field key (Aeson.Object object) = fromMaybe Aeson.Null (KeyMap.lookup key object)
field _ _ = Aeson.Null

arrayValues :: Aeson.Value -> [Aeson.Value]
arrayValues (Aeson.Array values) = toList values
arrayValues _ = []
