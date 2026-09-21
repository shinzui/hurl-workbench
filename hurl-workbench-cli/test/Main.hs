module Main (main) where

import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Version (makeVersion)
import FixtureServer qualified
import HurlWorkbench.Cli (runCommandWithDependencies, runCommandWithHurlfmt)
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workflow.Render (RenderedWorkflow, renderRenderError, renderWorkflow)
import HurlWorkbench.Workflow.Resolve (renderWorkflowError, resolveWorkflow)
import HurlWorkbench.Workspace.Context (lookupWorkflow)
import HurlWorkbench.Workspace.Types (MatrixName (..), ParameterName (..), RecipeName (..), WorkflowName (..), mkHurlValueLiteral)
import Network.Wai.Handler.Warp (testWithApplication)
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure, renderFailure)
import System.Directory (canonicalizePath, getPermissions, setOwnerExecutable, setPermissions)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

main :: IO ()
main = defaultMain (testGroup "hurl-workbench-cli" [parserTests, commandTests, executionTests])

fixtureDir :: FilePath -> FilePath
fixtureDir name = "../hurl-workbench-core/test/fixtures/workspaces" </> name

fixtureManifest :: FilePath -> FilePath
fixtureManifest name = fixtureDir name </> "hurl-workbench.dhall"

parse :: [String] -> ParserResult Options
parse = execParserPure defaultPrefs parserInfo

parserTests :: TestTree
parserTests =
  testGroup
    "parser"
    [ testCase "validate with an explicit workspace" $
        successOf (parse ["--workspace", "ws.dhall", "validate"])
          >>= (@?= Options (GlobalOptions (Just "ws.dhall")) ValidateCommand),
      testCase "list defaults to all categories" $
        successOf (parse ["list"]) >>= (@?= Options (GlobalOptions Nothing) (ListCommand AllCategories)),
      testCase "list accepts every category name" $
        for_ allListCategories $ \category ->
          successOf (parse ["list", Text.unpack (listCategoryName category)])
            >>= (@?= Options (GlobalOptions Nothing) (ListCommand category)),
      testCase "list rejects an unknown category" $
        case parse ["list", "widgets"] of
          Failure _ -> pure ()
          _ -> assertFailure "expected a parse failure",
      testCase "render parses a workflow and optional output" $
        successOf (parse ["render", "workflow", "oauth-property", "--output", "rendered.hurl"])
          >>= (@?= Options (GlobalOptions Nothing) (RenderCommand (RenderOptions (SelectWorkflow (WorkflowName "oauth-property")) (Just "rendered.hurl") False))),
      testCase "run parses grouped binding and Hurl options" $ do
        options <-
          successOf
            ( parse
                [ "run",
                  "workflow",
                  "health",
                  "--variable",
                  "baseUrl=http://127.0.0.1",
                  "--retry",
                  "2",
                  "--include",
                  "--hurl-arg=--compressed"
                ]
            )
        case options ^. #cmd of
          RunCommand execute -> do
            execute ^. #selection @?= SelectWorkflow (WorkflowName "health")
            execute ^. #bindings . #variables @?= ["baseUrl=http://127.0.0.1"]
            execute ^. #hurl . #retryCount @?= Just 2
            execute ^. #hurl . #includeHeaders @?= True
            execute ^. #hurl . #additionalArguments @?= ["--compressed"]
          other -> assertFailure ("expected run command, got " <> show other),
      testCase "run help groups options by intent" $ do
        helpText <- case parse ["run", "workflow", "health", "--help"] of
          Failure failure -> pure (fst (renderFailure failure "hurl-workbench"))
          _ -> assertFailure "expected --help to produce help text"
        for_ ["Bindings", "HTTP and retry", "Output and diagnostics", "Advanced Hurl arguments"] $ \heading ->
          assertBool ("mentions " <> heading) (heading `isIn` helpText),
      testCase "recipe and matrix selectors parse with grouped batch controls" $ do
        rendered <- successOf (parse ["render", "recipe", "properties", "--explain"])
        rendered
          @?= Options
            (GlobalOptions Nothing)
            (RenderCommand (RenderOptions (SelectRecipe (RecipeName "properties")) Nothing True))
        selected <-
          successOf
            ( parse
                [ "matrix",
                  "property-by-mls",
                  "--mode",
                  "run",
                  "--jobs",
                  "2",
                  "--fail-fast",
                  "--allow-mutating",
                  "--output-dir",
                  "responses"
                ]
            )
        case selected ^. #cmd of
          MatrixCommand options -> do
            options ^. #matrix @?= MatrixName "property-by-mls"
            options ^. #mode @?= ClientMode
            positiveIntValue (options ^. #jobs) @?= 2
            options ^. #failFastOverride @?= Just True
            options ^. #allowMutating @?= True
            options ^. #outputDirectory @?= Just "responses"
          other -> assertFailure ("expected matrix command, got " <> show other)
        helpText <- case parse ["matrix", "property-by-mls", "--help"] of
          Failure failure -> pure (fst (renderFailure failure "hurl-workbench"))
          _ -> assertFailure "expected matrix --help to produce help text"
        for_ ["Batch control", "Bindings", "HTTP and retry", "Output", "Advanced Hurl arguments"] $ \heading ->
          assertBool ("mentions " <> heading) (heading `isIn` helpText),
      testCase "help lists every top-level command and no longer mentions hello" $ do
        helpText <- case parse ["--help"] of
          Failure failure -> pure (fst (renderFailure failure "hurl-workbench"))
          _ -> assertFailure "expected --help to produce help text"
        assertBool "mentions validate" ("validate" `isIn` helpText)
        assertBool "mentions list" ("list" `isIn` helpText)
        assertBool "mentions render" ("render" `isIn` helpText)
        assertBool "mentions run" ("run" `isIn` helpText)
        assertBool "mentions test" ("test" `isIn` helpText)
        assertBool "mentions matrix" ("matrix" `isIn` helpText)
        assertBool "mentions doctor" ("doctor" `isIn` helpText)
        assertBool "mentions --workspace" ("--workspace" `isIn` helpText)
        assertBool "does not mention hello" (not ("hello" `isIn` helpText))
    ]
  where
    isIn needle haystack = Text.pack needle `Text.isInfixOf` Text.pack haystack

successOf :: ParserResult a -> IO a
successOf = \case
  Success a -> pure a
  _ -> assertFailure "expected the arguments to parse"

commandTests :: TestTree
commandTests =
  testGroup
    "commands"
    [ testCase "validate discovers a parent workspace and reports counts" $ do
        result <- runTestCommand (GlobalOptions Nothing) (fixtureDir "full" </> "hurl") ValidateCommand
        manifest <- canonicalizePath (fixtureManifest "full")
        result
          @?= CommandResult
            { stdoutLines =
                [ "Valid workspace: " <> Text.pack manifest,
                  "5 parameters, 3 fragments, 2 workflows, 1 recipe, 1 matrix, 1 service, 1 suite"
                ],
              stderrLines = [],
              exitCode = ExitSuccess
            },
      testCase "validate reports every invalid reference and exits non-zero" $ do
        result <- runTestCommand (GlobalOptions (Just (fixtureManifest "missing-reference"))) "." ValidateCommand
        result ^. #exitCode @?= ExitFailure 1
        result ^. #stdoutLines @?= []
        let err = result ^. #stderrLines
        take 1 err @?= take 1 (filter ("Invalid workspace: " `Text.isPrefixOf`) err)
        for_ ["missing-fragment", "missing_parameter", "missing-workflow", "missing-recipe", "missing-matrix", "missing-service"] $ \name ->
          assertBool ("reports " <> Text.unpack name) (any (Text.isInfixOf name) err)
        drop (length err - 1) err @?= ["8 issues found"],
      testCase "a missing explicit workspace is a workbench error" $ do
        result <- runTestCommand (GlobalOptions (Just "does-not-exist.dhall")) "." ValidateCommand
        result ^. #exitCode @?= ExitFailure 1
        assertBool "names the missing manifest" (any (Text.isInfixOf "workspace manifest not found") (result ^. #stderrLines)),
      testCase "list all groups every category and shows relationships" $ do
        result <- runTestCommand (GlobalOptions (Just (fixtureManifest "full"))) "." (ListCommand AllCategories)
        result ^. #exitCode @?= ExitSuccess
        let out = result ^. #stdoutLines
        for_ ["Parameters:", "Fragments:", "Workflows:", "Recipes:", "Matrices:", "Services:", "Suites:"] $ \title ->
          assertBool ("has heading " <> Text.unpack title) (title `elem` out)
        assertBool "workflow shares the oauth fragment" (any (Text.isInfixOf "list-properties  oauth, properties") out)
        assertBool "suite lists its runs" (any (Text.isInfixOf "workflow:list-members, recipe:top-properties, matrix:property-page-sizes") out),
      testCase "list parameters names environment variables but never reads them" $ do
        result <- runTestCommand (GlobalOptions (Just (fixtureManifest "full"))) "." (ListCommand ParametersCategory)
        result ^. #stdoutLines
          @?= [ "NAME           KIND    DEFAULT                    ENVIRONMENT            DESCRIPTION",
                "auth_url       plain   https://auth.example.test  -                      -",
                "base_url       plain   https://api.example.test   -                      -",
                "client_id      plain   -                          EXAMPLE_CLIENT_ID      -",
                "client_secret  secret  -                          EXAMPLE_CLIENT_SECRET  OAuth client secret",
                "top            plain   5                          -                      -"
              ],
      testCase "list of an empty category says so" $ do
        result <- runTestCommand (GlobalOptions (Just (fixtureManifest "minimal"))) "." (ListCommand SuitesCategory)
        result ^. #stdoutLines @?= ["(none)"],
      testCase "render writes only composed Hurl source to stdout" $ do
        result <-
          runTestCommand
            (GlobalOptions (Just (fixtureManifest "full")))
            "."
            (RenderCommand (RenderOptions (SelectWorkflow (WorkflowName "list-properties")) Nothing False))
        oauth <- Text.IO.readFile (fixtureDir "full" </> "hurl/oauth.hurl")
        properties <- Text.IO.readFile (fixtureDir "full" </> "hurl/properties.hurl")
        result ^. #exitCode @?= ExitSuccess
        result ^. #stderrLines @?= []
        Text.unlines (result ^. #stdoutLines) @?= oauth <> "\n" <> properties,
      testCase "render reports an unknown workflow on stderr" $ do
        result <-
          runTestCommand
            (GlobalOptions (Just (fixtureManifest "full")))
            "."
            (RenderCommand (RenderOptions (SelectWorkflow (WorkflowName "missing")) Nothing False))
        result ^. #exitCode @?= ExitFailure 1
        result ^. #stdoutLines @?= []
        assertBool "names the unknown workflow" (any (Text.isInfixOf "unknown workflow \"missing\"") (result ^. #stderrLines)),
      testCase "render recipe explains binding sources without values" $ do
        result <-
          runTestCommand
            (GlobalOptions (Just (fixtureManifest "full")))
            "."
            (RenderCommand (RenderOptions (SelectRecipe (RecipeName "top-properties")) Nothing True))
        result ^. #exitCode @?= ExitSuccess
        result ^. #stderrLines
          @?= ["Binding sources (values redacted):", "  recipe \"top-properties\" (1 plain bindings)"]
        assertBool "does not explain the bound value" (not (any (Text.isInfixOf "10") (result ^. #stderrLines))),
      testCase "render atomically replaces an output file and reports its path" $
        withSystemTempDirectory "hurl-workbench-cli" $ \dir -> do
          manifest <- canonicalizePath (fixtureManifest "full")
          let output = dir </> "rendered.hurl"
          Text.IO.writeFile output "old contents"
          result <-
            runTestCommand
              (GlobalOptions (Just manifest))
              dir
              (RenderCommand (RenderOptions (SelectWorkflow (WorkflowName "list-properties")) (Just "rendered.hurl") False))
          canonicalOutput <- canonicalizePath output
          result ^. #exitCode @?= ExitSuccess
          result ^. #stdoutLines @?= []
          result ^. #stderrLines @?= [Text.pack canonicalOutput]
          rendered <- Text.IO.readFile output
          assertBool "replaced the old file" ("POST {{auth_url}}/oauth/token" `Text.isInfixOf` rendered),
      testCase "render refuses to overwrite an input fragment" $ do
        manifest <- canonicalizePath (fixtureManifest "full")
        source <- canonicalizePath (fixtureDir "full" </> "hurl/oauth.hurl")
        before <- Text.IO.readFile source
        result <-
          runTestCommand
            (GlobalOptions (Just manifest))
            "."
            (RenderCommand (RenderOptions (SelectWorkflow (WorkflowName "list-properties")) (Just source) False))
        result ^. #exitCode @?= ExitFailure 1
        after <- Text.IO.readFile source
        after @?= before
        assertBool "explains the refusal" (any (Text.isInfixOf "refusing to overwrite source fragment") (result ^. #stderrLines)),
      testCase "run propagates the exact Hurl exit status after spawn" $
        withSystemTempDirectory "hurl-workbench-cli-run" $ \dir -> do
          executable <- writeExitHurl dir 17
          result <-
            runExecutionCommand
              (Right (testCapabilities executable))
              ( RunCommand
                  ExecuteOptions
                    { selection = SelectWorkflow (WorkflowName "health"),
                      bindings = BindingOptions ["baseUrl=http://127.0.0.1"] [] [] [],
                      hurl = defaultCliHurlOptions,
                      allowMutating = False
                    }
              )
          result ^. #exitCode @?= ExitFailure 17,
      testCase "run uses exit 2 for binding errors and exit 3 for dependency errors" $
        withSystemTempDirectory "hurl-workbench-cli-exits" $ \dir -> do
          executable <- writeExitHurl dir 0
          let command = RunCommand (ExecuteOptions (SelectWorkflow (WorkflowName "health")) emptyBindingOptions defaultCliHurlOptions False)
          bindingFailure <- runExecutionCommand (Right (testCapabilities executable)) command
          bindingFailure ^. #exitCode @?= ExitFailure 2
          dependencyFailure <- runExecutionCommand (Left (DependencyNotFound "hurl" "hurl")) command
          dependencyFailure ^. #exitCode @?= ExitFailure 3,
      testCase "mutating recipes require an explicit invocation gate" $
        withSystemTempDirectory "hurl-workbench-cli-mutation" $ \dir -> do
          executable <- writeExitHurl dir 0
          let recipeCommand allowed =
                RunCommand
                  ExecuteOptions
                    { selection = SelectRecipe (RecipeName "dangerous-health"),
                      bindings = BindingOptions ["baseUrl=http://127.0.0.1"] [] [] [],
                      hurl = defaultCliHurlOptions,
                      allowMutating = allowed
                    }
          denied <- runExecutionCommand (Right (testCapabilities executable)) (recipeCommand False)
          denied ^. #exitCode @?= ExitFailure 2
          assertBool "explains the safety gate" (any (Text.isInfixOf "requires --allow-mutating") (denied ^. #stderrLines))
          allowed <- runExecutionCommand (Right (testCapabilities executable)) (recipeCommand True)
          allowed ^. #exitCode @?= ExitSuccess,
      testCase "parallel client matrices require and populate isolated artifacts" $
        withSystemTempDirectory "hurl-workbench-cli-matrix" $ \dir -> do
          executable <- writeExitHurl dir 0
          let options outputDirectory =
                MatrixOptions
                  { matrix = MatrixName "health-cases",
                    mode = ClientMode,
                    jobs = positiveJobs 2,
                    failFastOverride = Nothing,
                    allowMutating = False,
                    outputDirectory,
                    overwrite = False,
                    bindings = BindingOptions ["baseUrl=http://127.0.0.1"] [] [] [],
                    hurl = defaultCliHurlOptions
                  }
          rejected <- runExecutionCommand (Right (testCapabilities executable)) (MatrixCommand (options Nothing))
          rejected ^. #exitCode @?= ExitFailure 2
          assertBool "requires output isolation" (any (Text.isInfixOf "require --output-dir") (rejected ^. #stderrLines))
          let output = dir </> "responses"
          result <- runExecutionCommand (Right (testCapabilities executable)) (MatrixCommand (options (Just output)))
          result ^. #exitCode @?= ExitSuccess
          length (filter (Text.isPrefixOf "PASS") (result ^. #stderrLines)) @?= 3
          for_ ["first", "second", "third"] $ \caseName ->
            ByteString.readFile (output </> "health-cases" </> caseName <> ".response") >>= (@?= ""),
      testCase "doctor reports both executable paths and versions without a workspace" $ do
        let capabilities = testCapabilities "/tools/hurl"
        result <- runExecutionCommand (Right capabilities) DoctorCommand
        result ^. #exitCode @?= ExitSuccess
        assertBool "reports Hurl" (any (Text.isInfixOf "/tools/hurl (8.0.1, supported)") (result ^. #stdoutLines))
        assertBool "reports Hurlfmt" (any (Text.isInfixOf "/tools/hurlfmt (8.0.1, supported)") (result ^. #stdoutLines))
    ]

runTestCommand :: GlobalOptions -> FilePath -> Command -> IO CommandResult
runTestCommand =
  runCommandWithHurlfmt
    (pure (Right (HurlfmtCapabilities (HurlfmtExecutable "unused-in-tests") (makeVersion [8, 0, 1]))))
    (\_capabilities _rendered -> pure (Right ()))
    (\_capabilities _validated -> pure (Right []))

runExecutionCommand :: Either DependencyError HurlCapabilities -> Command -> IO CommandResult
runExecutionCommand detected =
  runCommandWithDependencies
    (pure (Right (HurlfmtCapabilities (HurlfmtExecutable "/tools/hurlfmt") (makeVersion [8, 0, 1]))))
    (pure detected)
    (\_capabilities _rendered -> pure (Right ()))
    (\_capabilities _validated -> pure (Right []))
    (GlobalOptions (Just (fixtureManifest "execution")))
    "."

testCapabilities :: FilePath -> HurlCapabilities
testCapabilities executable =
  HurlCapabilities
    executable
    (makeVersion [8, 0, 1])
    (HurlfmtCapabilities (HurlfmtExecutable "/tools/hurlfmt") (makeVersion [8, 0, 1]))

writeExitHurl :: FilePath -> Int -> IO FilePath
writeExitHurl directory status = do
  let executable = directory </> "fake-hurl"
  Text.IO.writeFile executable ("#!/bin/sh\nexit " <> Text.pack (show status) <> "\n")
  permissions <- getPermissions executable
  setPermissions executable (setOwnerExecutable True permissions)
  pure executable

executionTests :: TestTree
executionTests =
  testGroup
    "live Hurl execution"
    [ testCase "client and test modes execute against the shared fixture service" $ do
        detected <- detectHurlCapabilities
        case detected of
          Left DependencyNotFound {} -> putStrLn "SKIP: Hurl 8.x or Hurlfmt is not installed"
          Left err -> assertFailure (Text.unpack (renderDependencyError err))
          Right capabilities ->
            testWithApplication (pure FixtureServer.application) $ \port -> do
              validated <-
                loadValidatedWorkspace
                  (GlobalOptions (Just (fixtureManifest "execution")))
                  "."
                  >>= either (assertFailure . Text.unpack . Text.unlines) pure
              workflow <- maybe (assertFailure "health workflow missing") pure (lookupWorkflow (WorkflowName "health") validated)
              resolved <- either (assertFailure . Text.unpack . renderWorkflowError) pure (resolveWorkflow validated (WorkflowName "health"))
              rendered <- renderWorkflow resolved >>= either (assertFailure . Text.unpack . renderRenderError) pure
              validateRenderedWorkflow (capabilities ^. #hurlfmt) rendered
                >>= either (assertFailure . Text.unpack . renderHurlfmtError) pure
              baseUrl <-
                either
                  (assertFailure . show)
                  pure
                  (mkHurlValueLiteral ("http://127.0.0.1:" <> Text.pack (show port)))
              bindings <-
                resolveWorkflowBindings
                  validated
                  workflow
                  emptyBindingInput {plainOverrides = Map.singleton (ParameterName "baseUrl") baseUrl}
                  >>= either (assertFailure . Text.unpack . renderBindingError) pure
              client <- runLive capabilities rendered bindings ClientMode
              test <- runLive capabilities rendered bindings TestMode
              client ^. #exitCode @?= ExitSuccess
              test ^. #exitCode @?= ExitSuccess
              assertBool "client prints fixture response" (maybe False (ByteString.isInfixOf "ok" . view #stdout) (client ^. #capturedOutput))
              assertBool
                "test mode prints a Hurl result"
                ( maybe
                    False
                    (\captured -> not (ByteString.null (captured ^. #stdout) && ByteString.null (captured ^. #stderr)))
                    (test ^. #capturedOutput)
                ),
      testCase "a real Hurl matrix runs with bounded captured output" $ do
        detected <- detectHurlCapabilities
        case detected of
          Left DependencyNotFound {} -> putStrLn "SKIP: Hurl 8.x or Hurlfmt is not installed"
          Left err -> assertFailure (Text.unpack (renderDependencyError err))
          Right capabilities ->
            testWithApplication (pure FixtureServer.application) $ \port -> do
              validated <-
                loadValidatedWorkspace
                  (GlobalOptions (Just (fixtureManifest "execution")))
                  "."
                  >>= either (assertFailure . Text.unpack . Text.unlines) pure
              baseUrl <-
                either
                  (assertFailure . show)
                  pure
                  (mkHurlValueLiteral ("http://127.0.0.1:" <> Text.pack (show port)))
              prepared <-
                prepareSelection
                  (capabilities ^. #hurlfmt)
                  validated
                  emptyBindingInput {plainOverrides = Map.singleton (ParameterName "baseUrl") baseUrl}
                  defaultHurlOptions
                  (SelectMatrix (MatrixName "health-cases"))
                  >>= either (assertFailure . Text.unpack . Text.unlines . map renderPreparationError . toList) pure
              let cases = fmap (buildBatchCase TestMode CaptureRunOutput []) prepared
              result <- runBatch (mkHurlRunner capabilities) (BatchOptions (positiveJobs 2) False) cases
              result ^. #selectedExitCode @?= ExitSuccess
              map (view #outcome) (toList (result ^. #cases)) @?= replicate 3 CasePassed
              assertBool "all cases retain captured Hurl diagnostics" (all (isJust . view #capturedOutput) (result ^. #cases))
    ]

positiveJobs :: Int -> PositiveInt
positiveJobs value = either (error . show) id (mkPositiveInt value)

runLive :: HurlCapabilities -> RenderedWorkflow -> ResolvedBindings -> HurlRunMode -> IO RunResult
runLive capabilities rendered bindings mode =
  runHurl
    (mkHurlRunner capabilities)
    RunRequest
      { renderedWorkflow = rendered,
        mode,
        bindings,
        options = defaultHurlOptions,
        outputPolicy = CaptureRunOutput,
        reportTargets = []
      }
    >>= either (assertFailure . Text.unpack . renderRunStartError) pure
