module HurlWorkbench.Suite.LifecycleTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Concurrent.MVar (newMVar, withMVar)
import Control.Concurrent.STM
import Control.Exception (IOException, bracket_, try)
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
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
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Signals (nullSignal, signalProcess)
import System.Timeout qualified as Timeout
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "ordered multi-service lifecycle"
    [ testCase "jobs=2 batches drain around restart and cleanup follows new acquisition order" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws -> ws & #suites %~ map (\suite -> suite & #runs .~ [RecipeRun (RecipeName "r1"), RecipeRun (RecipeName "r2"), ServiceRun (Restart (ServiceName "s1")), RecipeRun (RecipeName "r3"), RecipeRun (RecipeName "r4")])
          eventLock <- newMVar ()
          active <- newTVarIO (0 :: Int)
          peak <- newTVarIO (0 :: Int)
          calls <- newTVarIO (0 :: Int)
          let runner = HurlRunner $ \_ -> bracket_
                (atomically (modifyTVar' active (+ 1) >> readTVar active >>= \n -> modifyTVar' peak (max n)))
                (atomically (modifyTVar' active (subtract 1)))
                $ do
                  ordinal <- atomically (modifyTVar' calls (+ 1) >> readTVar calls)
                  withMVar eventLock $ \_ -> appendFile (directory </> "events") ("hurl-start-" <> show ordinal <> "\n")
                  threadDelay 80000
                  withMVar eventLock $ \_ -> appendFile (directory </> "events") ("hurl-end-" <> show ordinal <> "\n")
                  pure (Right success)
          result <- run directory workspace 2 runner
          result ^. #selectedExitCode @?= ExitSuccess
          readTVarIO peak >>= (@?= 2)
          events <- lines <$> readFile (directory </> "events")
          take 7 events @?= ["setup", "s1-start", "s1-ready", "s2-start", "s2-ready", "s3-start", "s3-ready"]
          take 3 (drop 11 events) @?= ["s1-stop", "s1-start", "s1-ready"]
          drop (length events - 4) events @?= ["s1-stop", "s3-stop", "s2-stop", "teardown"]
          [event ^. #action | LifecycleStep event <- result ^. #steps] @?= ["restart"]
          map (view #outcome) (toList (result ^. #cases)) @?= replicate 4 CasePassed
          raw <- ByteString.readFile (directory </> "reports" </> "failure" </> "summary.json")
          assertBool "private output not serialized" (not ("private-phaseSpec-sentinel" `ByteString.isInfixOf` raw))
          ByteString.readFile (directory </> "reports" </> "failure" </> "phases" </> "setup" </> "0" </> "stdout") >>= (@?= "private-phaseSpec-sentinel\n")
          assertStopped directory,
      testCase "Stop and Start are barriers and intentional monitor retirement succeeds" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws -> ws & #suites %~ map (\suite -> suite & #runs .~ [ServiceRun (Stop (ServiceName "s2")), RecipeRun (RecipeName "r1"), ServiceRun (Start (ServiceName "s2")), RecipeRun (RecipeName "r2")])
          result <- run directory workspace 1 passingRunner
          result ^. #selectedExitCode @?= ExitSuccess
          [event ^. #action | LifecycleStep event <- result ^. #steps] @?= ["stop", "start"]
          assertStopped directory,
      testCase "second and third readiness failures clean the failing group first" $
        for_ ["s2", "s3"] $ \failed -> fixture $ \directory original -> do
          workspace <- changed original $ \ws -> ws & #services %~ map (\definition -> if definition ^. #name == ServiceName failed then definition & #readiness .~ CommandReadinessCheck (CommandReadiness (pythonSpec "raise SystemExit(1)") 10 1) else definition)
          result <- run directory workspace 1 forbidden
          result ^. #selectedExitCode @?= ExitFailure 4
          events <- lines <$> readFile (directory </> "events")
          let count = if failed == "s2" then 2 else 3
          drop (1 + 2 * count) events @?= (reverse (take count ["s1-stop", "s2-stop", "s3-stop"]) <> ["teardown"])
          assertStopped directory,
      testCase "setup failure skips later setup and services, attempts every teardown" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws ->
            ws
              & #suites
              %~ map
                ( \suite ->
                    suite
                      & #setup
                      .~ [phaseSpec directory "setup-failed" 9, phaseSpec directory "unreachable" 0]
                      & #teardown
                      .~ [phaseSpec directory "teardown-failed" 7, phaseSpec directory "teardown-last" 0]
                )
          result <- run directory workspace 1 forbidden
          result ^. #selectedExitCode @?= ExitFailure 4
          result ^. #primaryFailure @?= Just "setup-failed"
          map (view #status) (result ^. #phases) @?= [CommandFailed, CommandSkipped, CommandFailed, CommandPassed]
          lines <$> readFile (directory </> "events") >>= (@?= ["setup-failed", "teardown-failed", "teardown-last"]),
      testCase "Hurl primary failure survives failing teardown and fail-fast skips barriers" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws ->
            ws
              & #suites
              %~ map
                ( \suite ->
                    suite
                      & #failFast
                      .~ True
                      & #runs
                      .~ [RecipeRun (RecipeName "r1"), ServiceRun (Restart (ServiceName "s1")), RecipeRun (RecipeName "r2")]
                      & #teardown
                      .~ [phaseSpec directory "teardown" 8]
                )
          result <- run directory workspace 1 (HurlRunner (const (pure (Right (success & #exitCode .~ ExitFailure 5)))))
          result ^. #selectedExitCode @?= ExitFailure 4
          result ^. #primaryFailure @?= Just "hurl-failed"
          [event ^. #status | LifecycleStep event <- result ^. #steps] @?= ["skipped"]
          map (view #outcome) (toList (result ^. #cases)) @?= [CaseFailed (ExitFailure 5), CaseSkipped FailFastTriggered]
          assertStopped directory,
      testCase "keep-going reaches later batches after ordinary Hurl failures" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws -> ws & #suites %~ map (\suite -> suite & #runs .~ [RecipeRun (RecipeName "r1"), ServiceRun (Restart (ServiceName "s1")), RecipeRun (RecipeName "r2")])
          result <- run directory workspace 1 (HurlRunner (const (pure (Right (success & #exitCode .~ ExitFailure 5)))))
          result ^. #selectedExitCode @?= ExitFailure 5
          [event ^. #status | LifecycleStep event <- result ^. #steps] @?= ["passed"]
          map (view #outcome) (toList (result ^. #cases)) @?= replicate 2 (CaseFailed (ExitFailure 5)),
      testCase "unexpected leader death cancels active children and preserves completed cases" $
        fixture $ \directory original -> do
          calls <- newTVarIO (0 :: Int)
          active <- newTVarIO (0 :: Int)
          blocked <- newEmptyTMVarIO
          let runner = HurlRunner $ \_ -> do
                ordinal <- atomically (modifyTVar' calls (+ 1) >> readTVar calls)
                if ordinal == 1
                  then pure (Right success)
                  else bracket_
                    (atomically (modifyTVar' active (+ 1)))
                    (atomically (modifyTVar' active (subtract 1)))
                    $ do
                      writeFile (directory </> "s1-die") "die"
                      _ <- atomically (takeTMVar blocked)
                      pure (Right success)
          result <- bounded (run directory original 1 runner)
          result ^. #selectedExitCode @?= ExitFailure 4
          readTVarIO active >>= (@?= 0)
          map (view #outcome) (take 1 (toList (result ^. #cases))) @?= [CasePassed]
          assertStopped directory,
      testCase "cancellation reaps all services before teardown and writes partial summary" $
        fixture $ \directory original -> do
          started <- newEmptyTMVarIO
          blocked <- newEmptyTMVarIO
          let runner = HurlRunner $ \_ -> do
                atomically (putTMVar started ())
                _ <- atomically (takeTMVar blocked)
                pure (Right success)
          withAsync (run directory original 1 runner) $ \worker -> do
            bounded (atomically (takeTMVar started))
            bounded (cancel worker)
            waitCatch worker >>= \case Left _ -> pure (); Right _ -> assertFailure "cancellation was swallowed"
          events <- lines <$> readFile (directory </> "events")
          drop (length events - 4) events @?= ["s3-stop", "s2-stop", "s1-stop", "teardown"]
          summary <- ByteString.readFile (directory </> "reports" </> "failure" </> "summary.json")
          assertBool "cancelled summary retained" ("cancelled" `ByteString.isInfixOf` summary)
          assertStopped directory,
      testCase "teardown collectively expires and records remaining skips" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws ->
            ws
              & #suites
              %~ map
                ( \suite ->
                    suite
                      & #cleanupTimeoutSeconds
                      .~ 1
                      & #teardown
                      .~ [pythonSpec "import time; time.sleep(30)", phaseSpec directory "unreachable-teardown" 0]
                )
          result <- bounded (run directory workspace 1 passingRunner)
          result ^. #selectedExitCode @?= ExitFailure 4
          map (view #status) (filter ((== "teardown") . view #phase) (result ^. #phases)) @?= [CommandTimedOut, CommandSkipped]
          assertStopped directory,
      testCase "service restarts and teardown retain the preflight environment snapshot" $
        fixture $ \directory original -> do
          previous <- lookupEnv "HURL_WORKBENCH_SNAPSHOT_TEST"
          let restore = maybe (unsetEnv "HURL_WORKBENCH_SNAPSHOT_TEST") (setEnv "HURL_WORKBENCH_SNAPSHOT_TEST") previous
          bracket_ (setEnv "HURL_WORKBENCH_SNAPSHOT_TEST" "initial") restore $ do
            workspace <- changed original $ \ws ->
              ws
                & #services
                %~ map
                  ( \definition ->
                      definition
                        & #command
                        . #arguments
                        %~ ( \args -> case args of
                               [flag, code] -> [flag, "import os; assert os.environ['HURL_WORKBENCH_SNAPSHOT_TEST'] == 'initial'; " <> code]
                               _ -> args
                           )
                  )
                & #suites
                %~ map
                  ( \suite ->
                      suite
                        & #runs
                        .~ [RecipeRun (RecipeName "r1"), ServiceRun (Restart (ServiceName "s1")), RecipeRun (RecipeName "r2")]
                        & #teardown
                        .~ [pythonSpec "import os; assert os.environ['HURL_WORKBENCH_SNAPSHOT_TEST'] == 'initial'"]
                  )
            let runner = HurlRunner (\_ -> setEnv "HURL_WORKBENCH_SNAPSHOT_TEST" "changed" >> pure (Right success))
            result <- run directory workspace 1 runner
            result ^. #selectedExitCode @?= ExitSuccess,
      testCase "all late phase environments are preflighted before setup" $
        fixture $ \directory original -> do
          workspace <- changed original $ \ws -> ws & #suites %~ map (\suite -> suite & #teardown .~ [pythonSpec "pass" & #environmentPolicy .~ Clean ["HURL_WORKBENCH_MISSING_PHASE_918273"]])
          result <- runSuiteWith validate forbidden capabilities workspace (suiteRequest directory 1)
          case result of Left _ -> pure (); Right _ -> assertFailure "bad late pythonSpec accepted"
          doesFileExist (directory </> "events") >>= (@?= False),
      testCase "external mode rejects lifecycle steps and bypasses all phases otherwise" $
        fixture $ \directory original -> do
          let req = suiteRequest directory 1 & #suiteOptions . #manageService .~ False
          result <- runSuiteWith validate passingRunner capabilities original req >>= requireResult
          result ^. #services @?= []
          result ^. #phases @?= []
          doesFileExist (directory </> "events") >>= (@?= False)
          workspace <- changed original $ \ws -> ws & #suites %~ map (\suite -> suite & #runs %~ (ServiceRun (Restart (ServiceName "s1")) :))
          rejected <- runSuiteWith validate forbidden capabilities workspace (req & #suiteOptions . #overwriteReports .~ True)
          case rejected of Left err -> assertBool "external lifecycle refusal" (SuiteExternalLifecycle `elem` toList (err ^. #issues)); Right _ -> assertFailure "external restart accepted",
      testCase "invalid transitions, duplicate services, ambiguous sugar, and zero budgets are rejected" $
        fixture $ \_ original -> for_
          [ \suite -> suite & #runs %~ (ServiceRun (Start (ServiceName "s1")) :),
            \suite -> suite & #runs %~ (ServiceRun (Stop (ServiceName "unknown")) :),
            \suite -> suite & #services .~ [ServiceName "s1", ServiceName "s1"],
            \suite -> suite & #service .~ Just (ServiceName "s1"),
            \suite -> suite & #commandTimeoutSeconds .~ 0,
            \suite -> suite & #cleanupTimeoutSeconds .~ 0
          ]
          $ \change -> do
            result <- validateWorkspace (validatedContext original & #workspace . #suites %~ map change)
            case result of Left _ -> pure (); Right _ -> assertFailure "invalid lifecycle accepted"
    ]

fixture :: (FilePath -> ValidatedWorkspace -> IO a) -> IO a
fixture action = withSystemTempDirectory "multi-service" $ \directory -> do
  context <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/suite-failure/hurl-workbench.dhall") >>= either (assertFailure . show) pure
  original <- validateWorkspace context >>= either (assertFailure . show) pure
  workspace <- changed original $ \ws ->
    ws
      & #services
      .~ map (serviceSpec directory) ["s1", "s2", "s3"]
      & #recipes
      .~ [recipe & #name .~ RecipeName name | recipe <- ws ^. #recipes, name <- ["r1", "r2", "r3", "r4"]]
      & #suites
      %~ map
        ( \suite ->
            suite
              & #service
              .~ Nothing
              & #services
              .~ map ServiceName ["s1", "s2", "s3"]
              & #runs
              .~ map (RecipeRun . RecipeName) ["r1", "r2", "r3", "r4"]
              & #setup
              .~ [phaseSpec directory "setup" 0]
              & #teardown
              .~ [phaseSpec directory "teardown" 0]
        )
  action directory workspace

changed :: ValidatedWorkspace -> (Workspace -> Workspace) -> IO ValidatedWorkspace
changed original change = validateWorkspace (validatedContext original & #workspace %~ change) >>= either (assertFailure . show) pure

pythonSpec :: Text -> CommandSpec
pythonSpec code = CommandSpec "python3" ["-c", code] Nothing Inherit []

phaseSpec :: FilePath -> String -> Int -> CommandSpec
phaseSpec directory label exitCode = pythonSpec (Text.pack ("open(" <> show (directory </> "events") <> ", 'a').write(" <> show (label <> "\n") <> "); print('private-phaseSpec-sentinel'); raise SystemExit(" <> show exitCode <> ")"))

serviceSpec :: FilePath -> Text -> Service
serviceSpec directory name =
  Service
    (ServiceName name)
    (pythonSpec script)
    (CommandReadinessCheck (CommandReadiness (pythonSpec probe) 10 2))
    1
    Nothing
  where
    prefix = directory </> Text.unpack name
    probe = Text.pack ("import os; raise SystemExit(0 if os.path.exists(" <> show (prefix <> "-ready") <> ") else 1)")
    script =
      Text.unlines
        [ "import os, signal, time",
          "prefix = " <> Text.pack (show prefix),
          "events = " <> Text.pack (show (directory </> "events")),
          "def event(value):",
          "    with open(events, 'a') as out: out.write(value + '\\n')",
          "def stop(*args):",
          "    event('" <> name <> "-stop')",
          "    if os.path.exists(prefix + '-ready'): os.unlink(prefix + '-ready')",
          "    raise SystemExit(0)",
          "signal.signal(signal.SIGTERM, stop)",
          "open(prefix + '-pid', 'a').write(str(os.getpid()) + '\\n')",
          "event('" <> name <> "-start')",
          "time.sleep(0.03)",
          "open(prefix + '-ready', 'w').write('ready')",
          "event('" <> name <> "-ready')",
          "while not os.path.exists(prefix + '-die'): time.sleep(0.01)",
          "raise SystemExit(9)"
        ]

suiteRequest :: FilePath -> Int -> SuiteRequest
suiteRequest directory jobs =
  SuiteRequest
    (SuiteName "failure")
    Nothing
    emptyBindingInput
    defaultHurlOptions
    (SuiteOptions (either (error . show) id (mkPositiveInt jobs)) Nothing False True Set.empty (Just (directory </> "reports")) False)

capabilities :: HurlfmtCapabilities
capabilities = HurlfmtCapabilities (HurlfmtExecutable "true") (makeVersion [8, 0, 1])

validate :: HurlfmtCapabilities -> a -> IO (Either HurlfmtError ())
validate _ _ = pure (Right ())

run :: FilePath -> ValidatedWorkspace -> Int -> HurlRunner -> IO SuiteResult
run directory workspace jobs runner = runSuiteWith validate runner capabilities workspace (suiteRequest directory jobs) >>= requireResult

requireResult :: Either SuitePreflightError SuiteResult -> IO SuiteResult
requireResult = either (assertFailure . show) pure

success :: RunResult
success = RunResult ExitSuccess 0.01 Nothing

passingRunner :: HurlRunner
passingRunner = HurlRunner (const (pure (Right success)))

forbidden :: HurlRunner
forbidden = HurlRunner (const (assertFailure "Hurl must not start"))

bounded :: IO a -> IO a
bounded action = Timeout.timeout 12000000 action >>= maybe (assertFailure "lifecycle did not finish within 12 seconds") pure

assertStopped :: FilePath -> IO ()
assertStopped directory = for_ ["s1", "s2", "s3"] $ \name -> do
  let path = directory </> name <> "-pid"
  exists <- doesFileExist path
  when exists $ do
    pids <- map read . lines <$> readFile path
    for_ pids $ \pid -> do
      alive <- try @IOException (signalProcess nullSignal pid)
      assertBool ("owned child survived: " <> show pid) (either (const True) (const False) alive)
