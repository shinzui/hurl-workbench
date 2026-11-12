module CheckTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, waitCatch, withAsync)
import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import HurlWorkbench.Cli (runCommandWithDependencies)
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import Network.HTTP.Types (status200)
import Network.Wai (Application, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (testWithApplication)
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure)
import System.Directory (canonicalizePath, doesFileExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (setFileMode)
import System.Timeout qualified as Timeout
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "public executable checks"
    [ testCase "jobs=2 drains both sides, lists checks and uses private artifacts" $
        fixture $ \root manifest -> do
          result <- invoke root manifest "ordered" []
          result ^. #exitCode @?= ExitSuccess
          events <- Text.lines <$> Text.IO.readFile (root </> "events")
          let before = ["before1-end", "before2-end"]
              after = ["after1-start", "after2-start"]
              position label = length (takeWhile (/= label) events)
          assertBool "barrier after both earlier ends" (all ((< position "check") . position) before)
          assertBool "barrier before both later starts" (all ((> position "check") . position) after)
          summary <- Text.IO.readFile (root </> "reports" </> "ordered" </> "summary.json")
          for_ ["\"kind\":\"check\"", "\"name\":\"parity\"", "checks/parity/stdout"] $ \part -> assertBool "named summary" (part `Text.isInfixOf` summary)
          let ordinary = Text.unlines (result ^. #stderrLines) <> summary
          assertBool "sensitive output absent" (not ("secret-sentinel" `Text.isInfixOf` ordinary))
          Text.IO.readFile (root </> "reports" </> "ordered" </> "checks" </> "parity" </> "stdout") >>= (\captured -> assertBool "private output retained" ("secret-sentinel" `Text.isInfixOf` captured))
          listed <- command root manifest ["list", "checks"]
          listed ^. #exitCode @?= ExitSuccess
          assertBool "check category" ("parity" `Text.isInfixOf` Text.unlines (listed ^. #stdoutLines))
          repeated <- invoke root manifest "ordered" []
          repeated ^. #exitCode @?= ExitFailure 2,
      testCase "status mismatch keeps going, fail-fast skips later Hurl and named checks" $
        fixture $ \root manifest -> do
          mismatch <- invoke root manifest "mismatch" []
          mismatch ^. #exitCode @?= ExitFailure 7
          Text.lines <$> Text.IO.readFile (root </> "events") >>= (\events -> assertBool "keep-going" ("after1-end" `elem` events))
          writeFile (root </> "events") ""
          stopped <- invoke root manifest "mismatch" ["--fail-fast", "--overwrite"]
          stopped ^. #exitCode @?= ExitFailure 7
          events <- Text.lines <$> Text.IO.readFile (root </> "events")
          assertBool "later Hurl skipped" (not ("after1-start" `elem` events))
          summary <- Text.IO.readFile (root </> "reports" </> "mismatch" </> "summary.json")
          assertBool "explicit later check skip" ("skipped-fail-fast" `Text.isInfixOf` summary)
          assertBool "named mismatch" ("\"actualStatus\":7" `Text.isInfixOf` summary),
      testCase "checks-only supports expected nonzero and missing reports refuse before execution" $
        fixture $ \root manifest -> do
          missing <- command root manifest ["test", "suite", "only", "--secrets-file", root </> "secrets"]
          missing ^. #exitCode @?= ExitFailure 2
          doesFileExist (root </> "events") >>= (@?= False)
          result <- invoke root manifest "only" []
          result ^. #exitCode @?= ExitSuccess,
      testCase "late missing environment rejects whole suite before setup or Hurl" $
        fixture $ \root manifest -> do
          result <- invoke root manifest "late" []
          result ^. #exitCode @?= ExitFailure 3
          doesFileExist (root </> "events") >>= (@?= False),
      testCase "a check failure still tears down services before teardown" $
        fixture $ \root manifest -> do
          result <- invoke root manifest "managed-failure" []
          result ^. #exitCode @?= ExitFailure 7
          events <- Text.lines <$> Text.IO.readFile (root </> "events")
          drop (length events - 2) events @?= ["service-stop", "teardown"],
      testCase "service death cancels a check, preserves both failures and tears down" $
        fixture $ \root manifest -> do
          result <- bounded (invoke root manifest "service-death" [])
          result ^. #exitCode @?= ExitFailure 4
          events <- Text.lines <$> Text.IO.readFile (root </> "events")
          last events @?= "teardown"
          summary <- Text.IO.readFile (root </> "reports" </> "service-death" </> "summary.json")
          assertBool "check interruption retained" ("\"status\":\"cancelled\"" `Text.isInfixOf` summary)
          assertBool "service failure retained" ("\"service\":\"failed\"" `Text.isInfixOf` summary),
      testCase "timeout cleans the check before later Hurl; cancellation writes partial summary" $
        fixture $ \root manifest -> do
          result <- bounded (invoke root manifest "timeout" [])
          result ^. #exitCode @?= ExitFailure 124
          events <- Text.lines <$> Text.IO.readFile (root </> "events")
          assertBool "keep-going after timeout" ("after1-end" `elem` events)
          withAsync (invoke root manifest "cancel" []) $ \worker -> do
            bounded (waitFor (root </> "cancel-started"))
            bounded (cancel worker)
            waitCatch worker >>= \case Left _ -> pure (); Right _ -> assertFailure "cancel swallowed"
          summary <- Text.IO.readFile (root </> "reports" </> "cancel" </> "summary.json")
          assertBool "cancelled summary" ("\"status\":\"cancelled\"" `Text.isInfixOf` summary)
    ]

command :: FilePath -> FilePath -> [String] -> IO CommandResult
command root manifest args = case execParserPure defaultPrefs parserInfo args of
  Success options -> runCommandWithDependencies detectHurlfmtCapabilities detectHurlCapabilities validateRenderedWorkflow (\_ _ -> pure (Right [])) (GlobalOptions (Just manifest)) root (options ^. #cmd)
  _ -> assertFailure ("parse failed: " <> show args)

invoke :: FilePath -> FilePath -> String -> [String] -> IO CommandResult
invoke root manifest suite extra = command root manifest (["test", "suite", suite, "--jobs", "2", "--report-dir", root </> "reports", "--secrets-file", root </> "secrets"] <> extra)

fixture :: (FilePath -> FilePath -> IO a) -> IO a
fixture action = withSystemTempDirectory "check-cli" $ \directory -> do
  root <- canonicalizePath directory
  schema <- canonicalizePath "schema/package.dhall"
  Text.IO.writeFile (root </> "check.py") checkScript
  Text.IO.writeFile (root </> "service.py") serviceScript
  setFileMode (root </> "check.py") 0o700
  writeFile (root </> "secrets") "token=secret-sentinel\n"
  setFileMode (root </> "secrets") 0o600
  lock <- newMVar ()
  testWithApplication (pure (application lock root)) $ \port -> do
    for_ ["before1", "before2", "after1", "after2"] $ \name ->
      Text.IO.writeFile (root </> name <> ".hurl") ("GET http://127.0.0.1:" <> Text.pack (show port) <> "/" <> Text.pack name <> "\nHTTP 200\n")
    let manifest = root </> "hurl-workbench.dhall"
    Text.IO.writeFile manifest (source (Text.pack schema))
    action root manifest

application :: MVar () -> FilePath -> Application
application lock root request respond = do
  let label = Text.unpack (Text.intercalate "/" (pathInfo request))
  withMVar lock $ \_ -> appendFile (root </> "events") (label <> "-start\n")
  threadDelay 60000
  withMVar lock $ \_ -> appendFile (root </> "events") (label <> "-end\n")
  respond (responseLBS status200 [] "ok")

source :: Text -> Text
source schema =
  Text.unlines
    [ "let S = " <> schema,
      "let check = \\(name : Text) -> \\(mode : Text) -> S.Check::{name = name, command = S.CommandSpec::{executable = \"check.py\", arguments = [mode, \"{{value}}\"], environmentPolicy = S.EnvironmentPolicy.Clean [\"PATH\"], environment = [ {variable = \"TOKEN\", parameter = \"token\"} ] }}",
      "let phase = S.CommandSpec::{executable = \"python3\", arguments = [\"-c\", \"open('events','a').write('teardown\\\\n')\"]}",
      "let managed = \\(name : Text) -> \\(run : S.RunReference) -> S.Suite::{name = name, services = [\"server\"], teardown = [phase], runs = [run]}",
      "in S.Workspace::{schemaVersion = 1,",
      " parameters = [ S.Parameter::{name = \"value\", defaultValue = Some \"one argument\"}, S.Parameter::{name = \"token\", kind = S.ParameterKind.Secret} ],",
      " fragments = [" <> Text.intercalate "," ["S.Fragment::{name = \"" <> n <> "\", path = \"" <> n <> ".hurl\"}" | n <- names] <> "],",
      " workflows = [" <> Text.intercalate "," ["S.Workflow::{name = \"" <> n <> "\", fragments = [\"" <> n <> "\"]}" | n <- names] <> "],",
      " recipes = [" <> Text.intercalate "," ["S.Recipe::{name = \"" <> n <> "\", workflow = \"" <> n <> "\", safety = S.Safety.ReadOnly}" | n <- names] <> "],",
      " checks = [check \"parity\" \"0\", check \"mismatch\" \"7\", check \"expected\" \"7\" // {expectedStatus = 7}, check \"later\" \"0\", check \"death\" \"death\", check \"timeout\" \"timeout\" // {timeoutSeconds = Some 1}, check \"cancel\" \"cancel\", (check \"bad\" \"0\") with command.environmentPolicy = S.EnvironmentPolicy.Clean [\"HURL_WORKBENCH_ABSENT_CHECK_65182\"] ],",
      " services = [ S.Service::{name = \"server\", command = S.CommandSpec::{executable = \"python3\", arguments = [\"service.py\"]}, readiness = S.Readiness.Command S.CommandReadiness::{command = S.CommandSpec::{executable = \"python3\", arguments = [\"-c\", \"import os; raise SystemExit(0 if os.path.exists('ready') else 1)\"]}}, shutdownTimeoutSeconds = 1} ],",
      " suites = [ S.Suite::{name = \"ordered\", runs = [S.RunReference.Recipe \"before1\", S.RunReference.Recipe \"before2\", S.RunReference.Check \"parity\", S.RunReference.Recipe \"after1\", S.RunReference.Recipe \"after2\"]},",
      " S.Suite::{name = \"mismatch\", runs = [S.RunReference.Recipe \"before1\", S.RunReference.Check \"mismatch\", S.RunReference.Recipe \"after1\", S.RunReference.Check \"later\"]},",
      " S.Suite::{name = \"only\", runs = [S.RunReference.Check \"expected\"]},",
      " S.Suite::{name = \"late\", runs = [S.RunReference.Recipe \"before1\", S.RunReference.Check \"bad\"]},",
      " managed \"managed-failure\" (S.RunReference.Check \"mismatch\"), managed \"service-death\" (S.RunReference.Check \"death\"),",
      " S.Suite::{name = \"timeout\", runs = [S.RunReference.Check \"timeout\", S.RunReference.Recipe \"after1\"]}, S.Suite::{name = \"cancel\", runs = [S.RunReference.Check \"cancel\"]} ] }"
    ]
  where
    names = ["before1", "before2", "after1", "after2"]

checkScript :: Text
checkScript =
  Text.unlines
    [ "#!/usr/bin/env python3",
      "import os, sys, time",
      "assert len(sys.argv) == 3 and sys.argv[2] == 'one argument'",
      "assert not any(key.startswith(('REI_', 'MORI_', 'PG')) for key in os.environ)",
      "assert os.environ['TOKEN'] == 'secret-sentinel'",
      "print(os.environ['TOKEN'], flush=True)",
      "with open('events','a') as f: f.write('check\\n')",
      "if sys.argv[1] == 'death': open('die','w').close()",
      "if sys.argv[1] == 'cancel': open('cancel-started','w').close()",
      "if sys.argv[1] in ('death','cancel','timeout'): time.sleep(30)",
      "raise SystemExit(int(sys.argv[1]))"
    ]

serviceScript :: Text
serviceScript =
  Text.unlines
    [ "import signal, os, time",
      "def stop(*args):",
      "    with open('events','a') as f: f.write('service-stop\\n')",
      "    raise SystemExit(0)",
      "signal.signal(signal.SIGTERM, stop)",
      "open('ready','w').close()",
      "while not os.path.exists('die'): time.sleep(0.01)",
      "raise SystemExit(9)"
    ]

bounded :: IO a -> IO a
bounded action = Timeout.timeout 15000000 action >>= maybe (assertFailure "suite exceeded time bound") pure

waitFor :: FilePath -> IO ()
waitFor path = doesFileExist path >>= \exists -> unless exists (threadDelay 5000 >> waitFor path)
