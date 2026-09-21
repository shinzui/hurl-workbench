module HurlWorkbench.Service.RunTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, withAsync)
import Control.Exception (IOException, try)
import Data.ByteString.Lazy.Char8 qualified as LazyByteString
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Service.Run
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Signals (nullSignal, signalProcess)
import System.Posix.Types (ProcessID)
import System.Process.Typed (proc, readProcessStdout_)
import System.Timeout qualified as Timeout
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "managed services"
    [ testCase "resolves suite bindings while rejecting secret URL placeholders" $ do
        workspace <- fullWorkspace
        secret <- either (assertFailure . show) pure (mkSecretValue "never-print-this")
        let bindings =
              ResolvedBindings
                (Map.singleton (ParameterName "top") (literal "43123"))
                (Map.singleton (ParameterName "client_secret") secret)
            processSpec =
              CommandSpec
                "python3"
                ["-c", "import time; time.sleep(60)"]
                Nothing
                [EnvironmentBinding "SERVICE_TOKEN" (ParameterName "client_secret")]
            httpReadiness url = HttpReadinessCheck (HttpReadiness url 200 20 2)
            service = Service (ServiceName "fixture") processSpec (httpReadiness "http://127.0.0.1:{{top}}/health") 1 Nothing
        case resolveService workspace bindings service of
          Left err -> assertFailure (Text.unpack (renderServiceError err))
          Right resolved -> do
            resolved ^. #readiness @?= ResolvedHttpReadiness "http://127.0.0.1:43123/health" 200 20000 2
            assertBool "resolved command show output redacts environment values" (not ("never-print-this" `Text.isInfixOf` Text.pack (show resolved)))
        let secretReadiness :: Service
            secretReadiness =
              Service
                (ServiceName "fixture")
                processSpec
                (httpReadiness "http://127.0.0.1/{{client_secret}}")
                1
                Nothing
        resolveService workspace bindings secretReadiness
          @?= Left (ServiceReadinessSecretPlaceholder (ParameterName "client_secret")),
      testCase "polls HTTP status and terminates the process group after the callback" $
        withSystemTempDirectory "hurl-workbench-http-service" $ \directory -> do
          port <- unusedPort
          let readyPath = directory </> "ready"
              countPath = directory </> "requests"
              service =
                directService
                  (pythonCommand [httpFixture, show port, readyPath, countPath])
                  (ResolvedHttpReadiness (healthUrl port) 200 20000 3)
          outcome <- withService service $ \handle -> do
            alive <- processAlive (serviceProcessId handle)
            assertBool "service is alive while callback runs" alive
            readCount countPath
          case outcome of
            Left err -> assertFailure (Text.unpack (renderServiceError err))
            Right requestCount -> assertBool "readiness retried a non-200 response" (requestCount >= 2)
          pid <- readFixturePid readyPath
          assertProcessStopped pid,
      testCase "supports command readiness probes" $
        withSystemTempDirectory "hurl-workbench-command-service" $ \directory -> do
          let readyPath = directory </> "ready"
              pidPath = directory </> "pid"
              service =
                directService
                  (pythonCommand [delayedMarkerFixture, readyPath, pidPath])
                  ( ResolvedCommandReadiness
                      (pythonCommand [fileProbe, readyPath])
                      20000
                      3
                  )
          outcome <- withService service (pure . serviceProcessId)
          case outcome of
            Left err -> assertFailure (Text.unpack (renderServiceError err))
            Right pid -> assertProcessStopped pid,
      testCase "bounds a hanging readiness command and cleans up the service" $
        withSystemTempDirectory "hurl-workbench-readiness-timeout" $ \directory -> do
          let pidPath = directory </> "pid"
              service =
                ( directService
                    (pythonCommand [pidSleepFixture, pidPath])
                    (ResolvedCommandReadiness (pythonCommand [hangingProbe]) 10000 0.15)
                )
                  { shutdownTimeout = 0.2
                  }
          withService service (const (pure ())) >>= (@?= Left (ServiceReadinessTimedOut (ServiceName "fixture")))
          readFixturePid pidPath >>= assertProcessStopped,
      testCase "reports a service that exits before readiness" $ do
        let service =
              directService
                (pythonCommand ["import sys; sys.exit(7)"])
                (ResolvedCommandReadiness (pythonCommand ["import sys; sys.exit(1)"]) 10000 1)
        withService service (const (pure ())) >>= \case
          Left (ServiceExitedBeforeReady (ServiceName "fixture") _) -> pure ()
          other -> assertFailure ("expected an early-exit error, got " <> show other),
      testCase "escalates from TERM to KILL when the service ignores TERM" $
        withSystemTempDirectory "hurl-workbench-service-kill" $ \directory -> do
          let pidPath = directory </> "pid"
              service =
                ( directService
                    (pythonCommand [ignoreTermFixture, pidPath])
                    (ResolvedCommandReadiness (pythonCommand ["import sys; sys.exit(0)"]) 10000 1)
                )
                  { shutdownTimeout = 0.1
                  }
          outcome <- withService service (pure . serviceProcessId)
          case outcome of
            Left err -> assertFailure (Text.unpack (renderServiceError err))
            Right pid -> assertProcessStopped pid,
      testCase "async cancellation waits for managed-service cleanup" $
        withSystemTempDirectory "hurl-workbench-service-cancel" $ \directory -> do
          let pidPath = directory </> "pid"
              callbackPath = directory </> "callback"
              service =
                directService
                  (pythonCommand [pidSleepFixture, pidPath])
                  (ResolvedCommandReadiness (pythonCommand ["import sys; sys.exit(0)"]) 10000 1)
          withAsync
            ( withService service $ \_handle -> do
                writeFile callbackPath "running"
                threadDelay 10000000
            )
            $ \worker -> do
              waitForFile callbackPath
              pid <- readFixturePid pidPath
              cancel worker
              assertProcessStopped pid
    ]

directService :: ResolvedCommand -> ResolvedReadiness -> ResolvedService
directService processConfig readiness =
  ResolvedService
    { name = ServiceName "fixture",
      processConfig,
      readiness,
      shutdownTimeout = 1
    }

pythonCommand :: [String] -> ResolvedCommand
pythonCommand arguments =
  ResolvedCommand
    { executable = "python3",
      arguments = "-c" : arguments,
      workingDirectory = ".",
      environment = []
    }

healthUrl :: Int -> Text
healthUrl port = "http://127.0.0.1:" <> Text.pack (show port) <> "/health"

unusedPort :: IO Int
unusedPort = do
  output <-
    readProcessStdout_
      ( proc
          "python3"
          [ "-c",
            "import socket; s=socket.socket(); s.bind(('127.0.0.1', 0)); print(s.getsockname()[1]); s.close()"
          ]
      )
  case reads (LazyByteString.unpack output) of
    [(port, _)] -> pure port
    _ -> assertFailure "python failed to return an unused TCP port"

processAlive :: ProcessID -> IO Bool
processAlive pid = either (const False) (const True) <$> try @IOException (signalProcess nullSignal pid)

assertProcessStopped :: ProcessID -> IO ()
assertProcessStopped pid = do
  alive <- processAlive pid
  assertBool ("process " <> show pid <> " is still alive") (not alive)

waitForFile :: FilePath -> IO ()
waitForFile path = do
  result <- Timeout.timeout 2000000 loop
  case result of
    Nothing -> assertFailure ("timed out waiting for fixture file " <> path)
    Just () -> pure ()
  where
    loop = do
      exists <- doesFileExist path
      if exists then pure () else threadDelay 10000 >> loop

readFixturePid :: FilePath -> IO ProcessID
readFixturePid path = do
  waitForFile path
  read <$> readFile path

readCount :: FilePath -> IO Int
readCount path = do
  waitForFile path
  read <$> readFile path

literal :: Text -> HurlValueLiteral
literal value = either (error . show) id (mkHurlValueLiteral value)

fullWorkspace :: IO ValidatedWorkspace
fullWorkspace = do
  loaded <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/full/hurl-workbench.dhall")
  context <- either (assertFailure . Text.unpack . renderWorkspaceError) pure loaded
  validateWorkspace context >>= either (assertFailure . Text.unpack . Text.unlines . map renderValidationIssue . toList) pure

httpFixture :: String
httpFixture =
  unlines
    [ "import http.server, os, sys, threading",
      "port, ready, count = int(sys.argv[1]), sys.argv[2], sys.argv[3]",
      "open(ready, 'w').write(str(os.getpid()))",
      "threading.Timer(0.25, lambda: open(ready + '.status', 'w').close()).start()",
      "class Handler(http.server.BaseHTTPRequestHandler):",
      "  def do_GET(self):",
      "    n = int(open(count).read()) if os.path.exists(count) else 0",
      "    open(count, 'w').write(str(n + 1))",
      "    self.send_response(200 if os.path.exists(ready + '.status') else 503)",
      "    self.end_headers()",
      "  def log_message(self, format, *args): pass",
      "http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()"
    ]

delayedMarkerFixture :: String
delayedMarkerFixture =
  unlines
    [ "import os, sys, threading, time",
      "ready, pid = sys.argv[1], sys.argv[2]",
      "open(pid, 'w').write(str(os.getpid()))",
      "threading.Timer(0.2, lambda: open(ready, 'w').close()).start()",
      "time.sleep(60)"
    ]

pidSleepFixture :: String
pidSleepFixture = "import os, sys, time; open(sys.argv[1], 'w').write(str(os.getpid())); time.sleep(60)"

fileProbe :: String
fileProbe = "import os, sys; sys.exit(0 if os.path.exists(sys.argv[1]) else 1)"

hangingProbe :: String
hangingProbe = "import time; time.sleep(60)"

ignoreTermFixture :: String
ignoreTermFixture =
  "import os, signal, sys, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); open(sys.argv[1], 'w').write(str(os.getpid())); time.sleep(60)"
