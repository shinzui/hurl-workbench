module HurlWorkbench.Check.RunTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Exception (IOException, try)
import Data.Bits ((.&.))
import Data.ByteString qualified as Bytes
import Data.Generics.Labels ()
import Data.IORef
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Data.Version (makeVersion)
import HurlWorkbench.Check.Resolve
import HurlWorkbench.Check.Run
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Service.Resolve (ServiceError (..))
import HurlWorkbench.Suite.Resolve
import HurlWorkbench.Suite.Run
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (canonicalizePath, createDirectoryIfMissing, createFileLink, doesFileExist, removeFile)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (fileMode, getFileStatus, setFileMode)
import System.Posix.Signals (nullSignal, signalProcess)
import System.Timeout qualified as Timeout
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "executable checks"
    [ testCase "normal zero/nonzero matches, mismatch, private separate captures and redacted Show" $
        fixture $ \root workspace -> for_ [(0, 0, CheckPassed), (7, 7, CheckPassed), (0, 7, CheckMismatch), (7, 0, CheckMismatch)] $ \(expected, actual, outcome) -> do
          let directory = root </> show expected <> "-" <> show actual
          createDirectoryIfMissing True (directory </> "checks" </> "parity")
          check <- resolved workspace (definition [Text.pack (show actual)])
          result <- runCheck directory (check & #expectedStatus .~ expected)
          result ^. #outcome @?= outcome
          result ^. #actualStatus @?= Just actual
          result ^. #cleanupDiagnostics @?= []
          for_ ["stdout", "stderr"] $ \stream -> do
            let path = directory </> "checks" </> "parity" </> stream
            mode <- fileMode <$> getFileStatus path
            mode .&. 0o777 @?= 0o600
            content <- Bytes.readFile path
            assertBool "separate stream" ((if stream == "stdout" then "private-output" else "private-error") `Bytes.isInfixOf` content)
          assertBool "resolved command redacted" (not ("sensitive-argument" `Text.isInfixOf` Text.pack (show check))),
      testCase "timeout includes descendant cleanup and allows no live survivor" $
        fixture $ \root workspace -> do
          check <- resolved workspace (definition ["timeout"])
          began <- getCurrentTime
          result <- bounded (runCheck root (check & #timeout .~ 0.2))
          ended <- getCurrentTime
          result ^. #outcome @?= CheckTimedOut
          assertBool "bounded" (diffUTCTime ended began < 12)
          assertStopped root,
      testCase "normal leader exit still kills a TERM-ignoring descendant" $
        fixture $ \root workspace -> do
          check <- resolved workspace (definition ["orphan"])
          result <- bounded (runCheck root check)
          result ^. #outcome @?= CheckMismatch
          result ^. #actualStatus @?= Just 9
          assertStopped root,
      testCase "cancellation retains an observed cancelled outcome after cleanup" $
        fixture $ \root workspace -> do
          check <- resolved workspace (definition ["timeout"])
          observed <- newIORef Nothing
          withAsync (runCheckObserved root check (writeIORef observed . Just)) $ \worker -> do
            bounded (waitFor (root </> "child.pid"))
            bounded (cancel worker)
            waitCatch worker >>= \case Left _ -> pure (); Right _ -> assertFailure "cancel swallowed"
          result <- readIORef observed >>= maybe (assertFailure "no partial result") pure
          result ^. #outcome @?= CheckCancelled
          assertStopped root,
      testCase "spawn race and capture collision are distinct start failures" $
        fixture $ \root workspace -> do
          check <- resolved workspace (definition ["0"])
          removeFile (root </> "check.py")
          runCheck root check >>= (\result -> result ^. #outcome @?= CheckStartFailed)
          runCheck root check >>= (\result -> result ^. #outcome @?= CheckStartFailed),
      testCase "cleanup diagnostics do not replace a primary mismatch" $
        fixture $ \root workspace -> do
          check <- resolved workspace (definition ["7"])
          result <- runCheckObservedWith (const (pure (Left (ServicePhaseFailed "injected")))) root check (const (pure ()))
          result ^. #outcome @?= CheckMismatch
          result ^. #actualStatus @?= Just 7
          result ^. #cleanupDiagnostics @?= ["process-group-cleanup-failed"]
          checkExitCode result @?= ExitFailure 7,
      testCase "path, channel, name, status and timeout refusals are located and deterministic" $
        fixture $ \root workspace -> do
          createFileLink (root </> "check.py") (root </> "inside")
          withSystemTempDirectory "check-outside" $ \outside -> do
            writeFile (outside </> "outside") "outside"
            createFileLink (outside </> "outside") (root </> "escape")
            for_ ["", "/bin/sh", "../check.py", "checks", "missing", "escape"] $ \path -> reject workspace (definition [] & #command . #executable .~ path) "/command/executable"
            validateChanged workspace [definition [] & #command . #executable .~ "inside"] >>= either (assertFailure . show) (const (pure ()))
          setFileMode (root </> "check.py") 0o600
          reject workspace (definition []) "/command/executable"
          setFileMode (root </> "check.py") 0o700
          for_ ["{{secret}}", "{{generated}}", "{{unknown}}", "{{ plain }}", "{{plain", "{{}}", "x}}y{{plain}}"] $ \value -> reject workspace (definition [value]) "/command/arguments/0"
          reject workspace (definition [] & #expectedStatus .~ 256) "/expectedStatus"
          reject workspace (definition [] & #timeoutSeconds .~ Just 0) "/timeoutSeconds"
          reject workspace (definition [] & #timeoutSeconds .~ Just (10 ^ (30 :: Int))) "/timeoutSeconds"
          validateChanged workspace [definition [], definition []] >>= \case Left _ -> pure (); Right _ -> assertFailure "duplicate accepted",
      testCase "resolution preserves argv elements and suite-wide defaults without recipe bindings" $
        fixture $ \_ workspace -> do
          check <- resolved workspace (definition ["prefix={{plain}}", "sensitive-argument"])
          check ^. #processConfig . #arguments @?= ["prefix=one argument", "sensitive-argument"]
          assertBool "secret absent from argv" (not ("secret-sentinel" `Text.isInfixOf` Text.pack (show (check ^. #processConfig . #arguments)))),
      testCase "checks-only suites, late preflight, report requirement and duplicate occurrence refusal" $
        fixture $ \root workspace -> do
          let req = suiteRequest root
          result <- runSuiteWith validate forbidden capabilities workspace req >>= either (assertFailure . show) pure
          result ^. #cases @?= []
          result ^. #selectedExitCode @?= ExitSuccess
          [checkStatus check | CheckStep check <- result ^. #steps] @?= ["passed"]
          for_
            [ req & #suiteOptions . #reportDirectory .~ Nothing,
              req & #suiteOptions . #overwriteReports .~ False
            ]
            $ \bad ->
              prepareSuiteWith validate capabilities workspace bad >>= \case Left _ -> pure (); Right _ -> assertFailure "report refusal missing"
          let ctx = validatedContext workspace
          late <- validateWorkspace (ctx & #workspace . #checks %~ map (\check -> check & #command . #environmentPolicy .~ Clean ["HURL_WORKBENCH_NO_CHECK_ENV_8765"])) >>= either (assertFailure . show) pure
          prepareSuiteWith validate capabilities late (req & #suiteOptions . #overwriteReports .~ True) >>= \case Left _ -> pure (); Right _ -> assertFailure "late environment accepted"
          duplicate <- validateWorkspace (ctx & #workspace . #suites %~ map (\suite -> suite & #runs .~ [CheckRun (CheckName "parity"), CheckRun (CheckName "parity")])) >>= either (assertFailure . show) pure
          prepareSuiteWith validate capabilities duplicate req >>= \case Left _ -> pure (); Right _ -> assertFailure "duplicate occurrence accepted"
    ]

fixture :: (FilePath -> ValidatedWorkspace -> IO a) -> IO a
fixture action = withSystemTempDirectory "executable-check" $ \directory -> do
  root <- canonicalizePath directory
  schema <- canonicalizePath "schema/package.dhall"
  Text.IO.writeFile (root </> "hurl-workbench.dhall") ("let S = " <> Text.pack schema <> " in S.Workspace::{ schemaVersion = 1, parameters = [ S.Parameter::{name = \"plain\", defaultValue = Some \"one argument\"}, S.Parameter::{name = \"secret\", kind = S.ParameterKind.Secret}, S.Parameter::{name = \"generated\", kind = S.ParameterKind.Generated S.Generator.Uuid4} ], checks = [ S.Check::{name = \"parity\", command = S.CommandSpec::{executable = \"check.py\", arguments = [\"0\"]}} ], suites = [S.Suite::{name = \"only\", runs = [S.RunReference.Check \"parity\"]}] }")
  Text.IO.writeFile (root </> "check.py") script
  setFileMode (root </> "check.py") 0o700
  createDirectoryIfMissing True (root </> "checks" </> "parity")
  ctx <- loadWorkspaceContext (ExplicitWorkspace (root </> "hurl-workbench.dhall")) >>= either (assertFailure . show) pure
  workspace <- validateWorkspace ctx >>= either (assertFailure . show) pure
  action root workspace

script :: Text
script =
  Text.unlines
    [ "#!/usr/bin/env python3",
      "import os, sys, time, signal",
      "mode = sys.argv[1] if len(sys.argv) > 1 else '0'",
      "print('private-output', flush=True); print('private-error', file=sys.stderr, flush=True)",
      "if mode in ('timeout', 'orphan'):",
      "    pid = os.fork()",
      "    if pid == 0:",
      "        signal.signal(signal.SIGTERM, signal.SIG_IGN)",
      "        open('child.pid','w').write(str(os.getpid()))",
      "        while True: time.sleep(0.01)",
      "    while not os.path.exists('child.pid'): time.sleep(0.005)",
      "    if mode == 'orphan': raise SystemExit(9)",
      "    while True: time.sleep(0.01)",
      "raise SystemExit(int(mode) if mode.isdigit() else 0)"
    ]

definition :: [Text] -> Check
definition arguments = Check (CheckName "parity") (CommandSpec "check.py" arguments Nothing Inherit []) 0 Nothing Nothing

resolved :: ValidatedWorkspace -> Check -> IO ResolvedCheck
resolved workspace check = do
  changed <- validateChanged workspace [check] >>= either (assertFailure . show) pure
  prepareCheck [] changed emptyBindingInput (CheckName "parity") >>= either (assertFailure . show) pure

validateChanged :: ValidatedWorkspace -> [Check] -> IO (Either (NonEmpty ValidationIssue) ValidatedWorkspace)
validateChanged workspace checks = validateWorkspace (validatedContext workspace & #workspace . #checks .~ checks)

reject :: ValidatedWorkspace -> Check -> Text -> IO ()
reject workspace check suffix = do
  first <- validateChanged workspace [check]
  second <- validateChanged workspace [check]
  first @?= second
  case first of
    Left issues -> assertBool "located refusal" (any (Text.isSuffixOf suffix . view #location) issues)
    Right _ -> assertFailure "invalid check accepted"

bounded :: IO a -> IO a
bounded action = Timeout.timeout 15000000 action >>= maybe (assertFailure "check exceeded bound") pure

waitFor :: FilePath -> IO ()
waitFor path = doesFileExist path >>= \exists -> unless exists (threadDelay 5000 >> waitFor path)

assertStopped :: FilePath -> IO ()
assertStopped root = do
  pid <- read <$> readFile (root </> "child.pid")
  -- Linux orphan zombies cannot execute; PID 1 is responsible for reaping them.
  let stopped = do
        present <- try @IOException (signalProcess nullSignal pid)
        case present of
          Left _ -> pure ()
          Right () -> do
            status <- try @IOException (readFile ("/proc/" <> show pid <> "/stat"))
            case status of
              Right value | ") Z" `Text.isInfixOf` Text.pack value -> pure ()
              _ -> threadDelay 10000 >> stopped
  bounded stopped

suiteRequest :: FilePath -> SuiteRequest
suiteRequest root = SuiteRequest (SuiteName "only") Nothing Nothing emptyBindingInput defaultHurlOptions (SuiteOptions (either (error . show) id (mkPositiveInt 2)) Nothing False True mempty (Just (root </> "reports")) False)

capabilities :: HurlfmtCapabilities
capabilities = HurlfmtCapabilities (HurlfmtExecutable "true") (makeVersion [8, 0, 1])

validate :: HurlfmtCapabilities -> a -> IO (Either HurlfmtError ())
validate _ _ = pure (Right ())

forbidden :: HurlRunner
forbidden = HurlRunner (const (assertFailure "checks-only suite started Hurl"))
