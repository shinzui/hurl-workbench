module HurlWorkbench.Hurl.RunTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, replicateConcurrently_, waitCatch, withAsync)
import Control.Exception (IOException, bracket, try)
import Control.Monad (replicateM_)
import Data.Bits ((.&.))
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Version (Version, makeVersion)
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Generate
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.FileRoot
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workflow.Resolve
import HurlWorkbench.Workspace.Context (WorkspaceContext (..))
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate (renderValidationIssue, validateWorkspace)
import System.Directory
  ( canonicalizePath,
    doesDirectoryExist,
    doesFileExist,
    getPermissions,
    setOwnerExecutable,
    setPermissions,
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (accessModes, fileMode, getFileStatus)
import System.Posix.Signals (nullSignal, signalProcess)
import System.Posix.Types (FileMode)
import System.Timeout qualified as Timeout
import Test.Tasty (TestTree, inOrderTestGroup, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests = testGroup "Hurl execution" [capabilityTests, inOrderTestGroup "runner" runnerTests]

capabilityTests :: TestTree
capabilityTests =
  testGroup
    "capabilities"
    [ testCase "parses Hurl 8 version output" $ do
        parseHurlVersion "hurl 8.0.1 libcurl/8.7.1" @?= Just (makeVersion [8, 0, 1])
        parseHurlVersion "not a version" @?= Nothing,
      testCase "warns for a later major without rejecting it" $
        assertBool "later-major warning" (not (null (hurlCapabilityWarnings (capabilities "hurl" (makeVersion [9, 0, 0])))))
    ]

runnerTests :: [TestTree]
runnerTests =
  [ testCase "argv uses the explicit canonical body root independently of source root" $
      withSystemTempDirectory "hurl-file-root-source" $ \directory ->
        withSystemTempDirectory "hurl-file-root-body" $ \body -> do
          executable <- writeFakeHurl directory
          rendered <- renderedFixture directory
          root <- validateFileRoot body (Just body) >>= either (assertFailure . show) pure
          let logPath = directory </> "explicit"
          withEnvironment [("FAKE_HURL_LOG", logPath), ("FAKE_EXIT_CODE", "0")] $
            runHurl (mkHurlRunner (capabilities executable (makeVersion [8, 0, 1]))) (baseRequest root rendered) >>= either (assertFailure . show) (const (pure ()))
          arguments <- Text.lines <$> Text.IO.readFile (logPath <> ".args")
          assertBool "canonical body root reaches argv" (hasPair "--file-root" (Text.pack (fileRootPath root)) arguments),
    testCase "short-lived parallel children retain their real exit statuses" $
      withSystemTempDirectory "hurl-fast-exit" $ \dir -> do
        let executable = dir </> "instant-hurl"
        writeFile executable "#!/bin/sh\nexit 7\n"
        permissions <- getPermissions executable
        setPermissions executable (setOwnerExecutable True permissions)
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        replicateConcurrently_ 4 $
          replicateM_ 12 $
            runHurl (mkHurlRunner (capabilities executable (makeVersion [8, 0, 1]))) (baseRequest root rendered) >>= \case
              Right result -> result ^. #exitCode @?= ExitFailure 7
              Left err -> assertFailure (Text.unpack (renderRunStartError err)),
    testCase "cancellation of a live captured Hurl process is bounded and reaps its group" $
      withSystemTempDirectory "hurl-cancel-capture" $ \dir -> do
        let executable = dir </> "blocked-hurl"
            marker = dir </> "running"
        writeFile executable ("#!/usr/bin/env python3\nimport os, sys, time\nsys.stdout.write('private stdout\\n'); sys.stdout.flush()\nsys.stderr.write('private stderr\\n'); sys.stderr.flush()\nopen(" <> show marker <> ", 'w').write(str(os.getpid()))\ntime.sleep(60)\n")
        permissions <- getPermissions executable
        setPermissions executable (setOwnerExecutable True permissions)
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        let waitStarted = doesFileExist marker >>= \ready -> unless ready (threadDelay 10000 >> waitStarted)
        withAsync (runHurl (mkHurlRunner (capabilities executable (makeVersion [8, 0, 1]))) (baseRequest root rendered)) $ \worker -> do
          Timeout.timeout 3000000 waitStarted >>= maybe (assertFailure "Hurl did not start") pure
          Timeout.timeout 4000000 (cancel worker) >>= maybe (assertFailure "capture cleanup blocked on a live pipe") pure
          waitCatch worker >>= \case Left _ -> pure (); Right _ -> assertFailure "cancelled Hurl returned normally"
        pid <- read <$> readFile marker
        alive <- try @IOException (signalProcess nullSignal pid)
        assertBool "Hurl was reaped" (either (const True) (const False) alive),
    testCase "constructs secure argv, filters HURL environment, captures output, and cleans temporary files" $
      withSystemTempDirectory "hurl-workbench-run-test" $ \dir -> do
        executable <- writeFakeHurl dir
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        secret <- requireSecret "super-secret-fixture"
        generated <- generateValue defaultGeneratorEnvironment (TypeId (TypeIdOptions "rcp")) >>= either (assertFailure . Text.unpack) pure
        let runLog = dir </> "fake"
            request =
              (baseRequest root rendered)
                { bindings =
                    ResolvedBindings
                      { variables = Map.fromList [(ParameterName "base_url", literal "http://127.0.0.1"), (ParameterName "recipientId", generated)],
                        secrets = Map.singleton (ParameterName "token") secret
                      },
                  mode = TestMode
                }
        withEnvironment
          [ ("FAKE_HURL_LOG", runLog),
            ("FAKE_EXIT_CODE", "23"),
            ("HURL_TEST", "1"),
            ("HURL_OUTPUT", dir </> "hostile-output"),
            ("HURL_SECRET_TOKEN", "ambient-secret")
          ]
          $ runHurl (mkHurlRunner (capabilities executable (makeVersion [8, 0, 1]))) request
            >>= \case
              Left err -> assertFailure (Text.unpack (renderRunStartError err))
              Right result -> do
                result ^. #exitCode @?= ExitFailure 23
                result ^. #capturedOutput
                  @?= Just (CapturedRunOutput "fake stdout\n" "fake stderr\n")
        arguments <- Text.lines <$> Text.IO.readFile (runLog <> ".args")
        assertBool "test mode" ("--test" `elem` arguments)
        assertBool "file root" (hasPair "--file-root" (Text.pack dir) arguments)
        assertBool "variables file" ("--variables-file" `elem` arguments)
        assertBool "secrets file" ("--secrets-file" `elem` arguments)
        assertBool "secret absent from argv" (not (any (Text.isInfixOf "super-secret-fixture") arguments))
        delivered <- Text.IO.readFile (runLog <> ".variables")
        assertBool "generated literal delivered unchanged" (("recipientId=" <> hurlValueLiteralText generated) `Text.isInfixOf` delivered)
        hurlEnvironment <- Text.IO.readFile (runLog <> ".hurl-env")
        hurlEnvironment @?= ""
        modes <- Text.lines <$> Text.IO.readFile (runLog <> ".modes")
        assertBool "all generated files were 0600" (not (null modes) && all (Text.isSuffixOf " 600") modes)
        let generatedPaths = map (Text.unpack . fst . Text.breakOn " ") modes
        remains <- traverse doesFileExist generatedPaths
        assertBool "temporary files removed" (not (or remains)),
    testCase "prepares response and report targets with owner-only permissions" $
      withSystemTempDirectory "hurl-workbench-target-test" $ \dir -> do
        executable <- writeFakeHurl dir
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        let runLog = dir </> "fake"
            response = dir </> "response.txt"
            junit = dir </> "junit.xml"
            html = dir </> "html-report"
            json = dir </> "json-report"
            tap = dir </> "report.tap"
            curl = dir </> "requests.sh"
            request =
              (baseRequest root rendered)
                { outputPolicy = ResponseFile response,
                  reportTargets = [JUnitReport junit, HtmlReport html, JsonReport json, TapReport tap],
                  options = defaultHurlOptions {curlExportPath = Just curl}
                }
        withEnvironment [("FAKE_HURL_LOG", runLog), ("FAKE_EXIT_CODE", "0")] $
          runHurl (mkHurlRunner (capabilities executable (makeVersion [8, 0, 1]))) request
            >>= either (assertFailure . Text.unpack . renderRunStartError) (const (pure ()))
        ByteString.Char8.readFile response >>= (@?= "fake response\n")
        filePermissions response >>= (@?= 0o600)
        filePermissions junit >>= (@?= 0o600)
        filePermissions tap >>= (@?= 0o600)
        filePermissions curl >>= (@?= 0o600)
        directoryPermissions html >>= (@?= 0o700)
        directoryPermissions json >>= (@?= 0o700)
        ByteString.Char8.readFile junit >>= (@?= "<?xml version=\"1.0\"?>\n<testsuites/>\n")
        ByteString.Char8.readFile tap >>= (@?= "TAP version 13\n1..0\n")
        arguments <- Text.lines <$> Text.IO.readFile (runLog <> ".args")
        assertBool "client mode omits --test" ("--test" `notElem` arguments)
        assertBool "output flag" (hasPair "--output" (Text.pack response) arguments)
        assertBool "JUnit flag" (hasPair "--report-junit" (Text.pack junit) arguments)
        assertBool "HTML flag" (hasPair "--report-html" (Text.pack html) arguments)
        assertBool "JSON flag" (hasPair "--report-json" (Text.pack json) arguments)
        assertBool "TAP flag" (hasPair "--report-tap" (Text.pack tap) arguments)
        assertBool "curl flag" (hasPair "--curl" (Text.pack curl) arguments),
    testCase "inherits streams only for the interactive policy" $
      withSystemTempDirectory "hurl-workbench-inherit-test" $ \dir -> do
        executable <- writeFakeHurl dir
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        let runLog = dir </> "fake"
            request = (baseRequest root rendered) {outputPolicy = InheritRunOutput}
        withEnvironment [("FAKE_HURL_LOG", runLog), ("FAKE_EXIT_CODE", "7"), ("FAKE_QUIET", "1")] $
          runHurl (mkHurlRunner (capabilities executable (makeVersion [8, 0, 1]))) request
            >>= \case
              Left err -> assertFailure (Text.unpack (renderRunStartError err))
              Right result -> do
                result ^. #exitCode @?= ExitFailure 7
                result ^. #capturedOutput @?= Nothing,
    testCase "represents a spawn failure separately from a child exit" $
      withSystemTempDirectory "hurl-workbench-spawn-test" $ \dir -> do
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        runHurl (mkHurlRunner (capabilities (dir </> "missing-hurl") (makeVersion [8, 0, 1]))) (baseRequest root rendered)
          >>= \case
            Left HurlSpawnFailed {} -> pure ()
            other -> assertFailure ("expected HurlSpawnFailed, got " <> show other),
    testCase "rejects dangerous passthrough arguments and duplicate report formats before spawn" $
      withSystemTempDirectory "hurl-workbench-options-test" $ \dir -> do
        mkAllowedHurlArgument "--secret=value" @?= Left (UnsupportedHurlArgument "--secret=value")
        mkAllowedHurlArgument "--test" @?= Left (UnsupportedHurlArgument "--test")
        rendered <- renderedFixture dir
        root <- validateFileRoot dir Nothing >>= either (assertFailure . show) pure
        let request = (baseRequest root rendered) {reportTargets = [JUnitReport "one.xml", JUnitReport "two.xml"]}
        runHurl (mkHurlRunner (capabilities (dir </> "must-not-start") (makeVersion [8, 0, 1]))) request
          >>= \case
            Left (InvalidRunOptions issues) ->
              assertBool "duplicate format" (DuplicateReportFormat "JUnit" `elem` toList issues)
            other -> assertFailure ("expected option rejection, got " <> show other)
  ]

baseRequest :: FileRoot -> RenderedWorkflow -> RunRequest
baseRequest root rendered =
  RunRequest
    { renderedWorkflow = rendered,
      fileRoot = root,
      mode = ClientMode,
      bindings = ResolvedBindings Map.empty Map.empty,
      options = defaultHurlOptions,
      outputPolicy = CaptureRunOutput,
      reportTargets = []
    }

capabilities :: FilePath -> Version -> HurlCapabilities
capabilities executable version =
  HurlCapabilities
    executable
    version
    (HurlfmtCapabilities (HurlfmtExecutable "unused-hurlfmt") (makeVersion [8, 0, 1]))

renderedFixture :: FilePath -> IO RenderedWorkflow
renderedFixture directory = do
  canonicalRoot <- canonicalizePath directory
  let fragmentPath = canonicalRoot </> "request.hurl"
      fragment = Fragment (FragmentName "request") "request.hurl" Nothing
      workflow = Workflow (WorkflowName "request") [FragmentName "request"] [] Nothing
      workspace = Workspace supportedSchemaVersion [] [fragment] [workflow] [] [] [] []
      context = WorkspaceContext (canonicalRoot </> "hurl-workbench.dhall") (WorkspaceRoot canonicalRoot) workspace
  Text.IO.writeFile fragmentPath "GET http://127.0.0.1/health\n"
  validated <-
    validateWorkspace context
      >>= either (assertFailure . Text.unpack . Text.unlines . map renderValidationIssue . toList) pure
  resolved <- either (assertFailure . Text.unpack . renderWorkflowError) pure (resolveWorkflow validated (WorkflowName "request"))
  renderWorkflow resolved >>= either (assertFailure . Text.unpack . renderRenderError) pure

writeFakeHurl :: FilePath -> IO FilePath
writeFakeHurl directory = do
  let executable = directory </> "fake-hurl"
  Text.IO.writeFile
    executable
    ( Text.unlines
        [ "#!/bin/sh",
          "log=$FAKE_HURL_LOG",
          "printf '%s\\n' \"$@\" > \"$log.args\"",
          "env | grep '^HURL_' > \"$log.hurl-env\" || true",
          ": > \"$log.modes\"",
          "mode_of() { if stat -f '%Lp' \"$1\" >/dev/null 2>&1; then stat -f '%Lp' \"$1\"; else stat -c '%a' \"$1\"; fi; }",
          "for arg in \"$@\"; do",
          "  case \"$arg\" in *.hurl|*.env) printf '%s %s\\n' \"$arg\" \"$(mode_of \"$arg\")\" >> \"$log.modes\" ;; esac",
          "done",
          "previous=''",
          "for arg in \"$@\"; do",
          "  if [ \"$previous\" = '--output' ]; then printf 'fake response\\n' > \"$arg\"; fi",
          "  if [ \"$previous\" = '--variables-file' ]; then cat \"$arg\" > \"$log.variables\"; fi",
          "  previous=$arg",
          "done",
          "if [ \"${FAKE_QUIET:-0}\" != '1' ]; then printf 'fake stdout\\n'; printf 'fake stderr\\n' >&2; fi",
          "exit \"${FAKE_EXIT_CODE:-0}\""
        ]
    )
  permissions <- getPermissions executable
  setPermissions executable (setOwnerExecutable True permissions)
  pure executable

literal :: Text -> HurlValueLiteral
literal value = either (error . show) id (mkHurlValueLiteral value)

requireSecret :: Text -> IO SecretValue
requireSecret value = either (assertFailure . show) pure (mkSecretValue value)

hasPair :: Text -> Text -> [Text] -> Bool
hasPair first second values = any (== [first, second]) (zipWith (\a b -> [a, b]) values (drop 1 values))

filePermissions :: FilePath -> IO FileMode
filePermissions path = (.&. accessModes) . fileMode <$> getFileStatus path

directoryPermissions :: FilePath -> IO FileMode
directoryPermissions path = do
  exists <- doesDirectoryExist path
  unless exists (assertFailure ("missing directory " <> path))
  filePermissions path

withEnvironment :: [(String, String)] -> IO a -> IO a
withEnvironment values action = bracket save restore (const applyAndRun)
  where
    save = traverse (\(name, _value) -> (name,) <$> lookupEnv name) values
    restore previous = for_ previous $ \(name, old) -> maybe (unsetEnv name) (setEnv name) old
    applyAndRun = traverse_ (uncurry setEnv) values >> action
