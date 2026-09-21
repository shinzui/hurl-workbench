module HurlWorkbench.Suite.RunTest (tests) where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
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
import HurlWorkbench.Suite.Resolve
import HurlWorkbench.Suite.Run
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (createDirectoryIfMissing, doesPathExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "integration suites"
    [ testCase "blocks unclassified runs before the managed service or Hurl starts" $
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
      bindingInput =
        emptyBindingInput
          { plainOverrides = Map.singleton (ParameterName "client_id") (literal "suite-client"),
            secretFiles = [directory </> "secrets.env"]
          },
      hurlOptions = defaultHurlOptions,
      suiteOptions =
        SuiteOptions
          { jobs = positive 2,
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
