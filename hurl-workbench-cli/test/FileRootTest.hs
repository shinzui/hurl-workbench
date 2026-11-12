module FileRootTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (cancel, concurrently, waitCatch, withAsync)
import Control.Exception (bracket_)
import Data.ByteString qualified as Bytes
import Data.ByteString.Lazy (fromStrict)
import Data.Generics.Labels ()
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Text.IO qualified as Text.IO
import HurlWorkbench.Cli (runCommandWithDependencies)
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import Network.HTTP.Types (status201)
import Network.Wai (pathInfo, responseLBS, strictRequestBody)
import Network.Wai.Handler.Warp (testWithApplication)
import Options.Applicative (CompletionResult (..), ParserResult (..), defaultPrefs, execParserPure, renderFailure)
import System.Directory (canonicalizePath, copyFile, createDirectory, createDirectoryLink, listDirectory, removeDirectoryRecursive)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (fileMode, getFileStatus, setFileMode)
import System.Posix.User (getEffectiveUserID)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

parsed :: [String] -> IO Command
parsed args = case execParserPure defaultPrefs parserInfo args of
  Success options -> pure (options ^. #cmd)
  _ -> assertFailure ("parse failed: " <> show args)

invoke :: FilePath -> FilePath -> IO (Either DependencyError HurlCapabilities) -> [String] -> IO CommandResult
invoke manifest cwd detect args = do
  command <- parsed args
  runCommandWithDependencies (fmap (fmap (view #hurlfmt)) detect) detect validateRenderedWorkflow (\_ _ -> pure (Right [])) (GlobalOptions (Just manifest)) cwd command

createWorkspace :: FilePath -> IO FilePath
createWorkspace directory = do
  schema <- canonicalizePath "schema/package.dhall"
  source <- Text.IO.readFile "examples/file-body/hurl-workbench.dhall"
  let manifest = directory </> "hurl-workbench.dhall"
  Text.IO.writeFile manifest (Text.replace "../../schema/package.dhall" (Text.pack schema) source)
  copyFile "examples/file-body/request.hurl" (directory </> "request.hurl")
  pure manifest

tests :: TestTree
tests =
  testGroup
    "caller-owned file roots"
    [ testCase "option is execution-only, rejects duplicates, and appears in help/completion" $ do
        for_ [["run", "workflow", "send-body"], ["test", "recipe", "send-body"], ["matrix", "bodies"], ["test", "suite", "bodies"]] $ \prefix -> do
          void (parsed (prefix <> ["--file-root", "private"]))
          case execParserPure defaultPrefs parserInfo (prefix <> ["--help"]) of
            Failure failure -> assertBool "help describes file root" ("--file-root" `Text.isInfixOf` Text.pack (fst (renderFailure failure "workbench")))
            _ -> assertFailure "missing execution help"
          case execParserPure defaultPrefs parserInfo (["--bash-completion-index", show (length prefix + 1), "--bash-completion-word", "hurl-workbench"] <> concatMap (\word -> ["--bash-completion-word", word]) prefix <> ["--bash-completion-word", "--file-"]) of
            CompletionInvoked (CompletionResult complete) -> complete "hurl-workbench" >>= assertBool "offers file-root completion" . Text.isInfixOf "--file-root" . Text.pack
            _ -> assertFailure "file-root completion protocol unavailable"
          case execParserPure defaultPrefs parserInfo (prefix <> ["--file-root", "one", "--file-root", "two"]) of
            Failure _ -> pure ()
            _ -> assertFailure "duplicate file root accepted"
        for_ [["render", "workflow", "send-body"], ["validate"]] $ \prefix ->
          case execParserPure defaultPrefs parserInfo (prefix <> ["--file-root", "private"]) of
            Failure _ -> pure ()
            _ -> assertFailure "inspection accepted execution option",
      testCase "invalid roots and overlaps refuse before injected dependency or formatter work" $
        withSystemTempDirectory "file-root-preflight" $ \directory -> do
          manifest <- createWorkspace directory
          let body = directory </> "body"
              failProbe = assertFailure "dependency detection ran before file-root validation"
              selections = [["run", "workflow", "send-body"], ["test", "workflow", "send-body"], ["run", "recipe", "send-body"], ["test", "recipe", "send-body"], ["matrix", "bodies"], ["test", "suite", "bodies"]]
          writeFile (directory </> "regular") "payload"
          createDirectory body
          for_ ["missing", "regular", ""] $ \bad -> for_ selections $ \prefix -> do
            result <- invoke manifest directory failProbe (prefix <> ["--file-root", if null bad then "" else directory </> bad])
            result ^. #exitCode @?= ExitFailure 2
          uid <- getEffectiveUserID
          when (uid /= 0) $ for_ [0o300, 0o600] $ \mode -> bracket_ (setFileMode body mode) (setFileMode body 0o700) $
            for_ selections $
              \prefix -> invoke manifest directory failProbe (prefix <> ["--file-root", body]) >>= (\result -> result ^. #exitCode @?= ExitFailure 2)
          for_ [["matrix", "bodies", "--output-dir", body </> "output", "--overwrite"], ["test", "suite", "bodies", "--report-dir", directory, "--overwrite"], ["test", "workflow", "send-body", "--curl", body </> "curl"]] $ \args -> do
            result <- invoke manifest directory failProbe (args <> ["--file-root", body])
            result ^. #exitCode @?= ExitFailure 2,
      testCase "static parameter validation rejects unknown, Secret, and Generated references even with CLI override" $
        withSystemTempDirectory "file-root-static" $ \directory -> do
          manifest <- createWorkspace directory
          source <- Text.IO.readFile manifest
          for_ [Text.replace "Some \"payloadRoot\"" "Some \"unknown\"" source, Text.replace "name = \"payloadRoot\"" "name = \"payloadRoot\", kind = S.ParameterKind.Secret" source, Text.replace "name = \"payloadRoot\"" "name = \"payloadRoot\", kind = S.ParameterKind.Generated S.Generator.Uuid4" source] $ \bad -> do
            Text.IO.writeFile manifest bad
            result <- invoke manifest directory (assertFailure "invalid manifest started a probe") ["test", "suite", "parameter", "--file-root", directory]
            result ^. #exitCode @?= ExitFailure 2,
      testCase "real Hurl delivers exact bytes across execution paths, concurrent roots, failure, and cancellation" $ do
        capabilities <- detectHurlCapabilities >>= either (assertFailure . Text.unpack . renderDependencyError) pure
        received <- newIORef Map.empty
        slowStarted <- newIORef False
        let app request respond = do
              bytes <- strictRequestBody request
              atomicModifyIORef' received (\values -> (Map.insert (pathInfo request) bytes values, ()))
              when ("slow" `elem` pathInfo request) $ writeIORef slowStarted True >> threadDelay 10000000
              respond (responseLBS status201 [] bytes)
        testWithApplication (pure app) $ \port -> withSystemTempDirectory "file-root-live" $ \directory -> do
          let ws = directory </> "workspace"
              first = directory </> "root 雪 sentinel"
              second = directory </> "second root"
              nested = ws </> "nested"
              one = "{\"payload-sentinel\":\"雪\"}\r\n"
              two = "{\"payload-sentinel\":\"別\"}"
              url label = "baseUrl=http://127.0.0.1:" <> show port <> "/" <> label
              run args = invoke (ws </> "hurl-workbench.dhall") nested (pure (Right capabilities)) args
              successful args = run args >>= \result -> assertBool (show (result ^. #stderrLines)) (result ^. #exitCode == ExitSuccess)
              capture label expected = readIORef received >>= \values -> Map.lookup [Text.pack label, "mutating"] values @?= Just expected
              snapshot root = do
                names <- listDirectory root
                files <- for names $ \name -> (name,,) <$> Bytes.readFile (root </> name) <*> (fileMode <$> getFileStatus (root </> name))
                mode <- fileMode <$> getFileStatus root
                pure (mode, files)
          traverse_ createDirectory [ws, first, second]
          createDirectory nested
          _ <- createWorkspace ws
          Bytes.writeFile (first </> "request.json") (Encoding.encodeUtf8 one)
          Bytes.writeFile (second </> "request.json") (Encoding.encodeUtf8 two)
          Bytes.writeFile (ws </> "request.json") "workspace fallback\n"
          createDirectoryLink first (directory </> "alias")
          beforeSecond <- snapshot second
          sourceBytes <- traverse (Bytes.readFile . (ws </>)) ["request.hurl", "hurl-workbench.dhall", "request.json"]
          before <- snapshot first
          rendered <- run ["render", "workflow", "send-body"]
          rendered ^. #exitCode @?= ExitSuccess
          original <- Text.IO.readFile (ws </> "request.hurl")
          Text.unlines (rendered ^. #stdoutLines) @?= original
          inspected <- run ["validate"]
          inspected ^. #exitCode @?= ExitSuccess
          let firstRoot = ["--file-root", "../../alias"]
          for_ [["run", "workflow", "send-body"], ["test", "workflow", "send-body"], ["run", "recipe", "send-body", "--allow-mutating"], ["test", "recipe", "send-body", "--allow-mutating"], ["matrix", "bodies", "--allow-mutating", "--output-dir", directory </> "matrix"], ["test", "suite", "bodies", "--allow-mutating", "--report-dir", directory </> "reports"]] $ \prefix -> do
            successful (prefix <> firstRoot <> ["--variable", url "one"])
            capture "one" (fromStrict (Encoding.encodeUtf8 one))
          let command root label = ["matrix", "bodies", "--allow-mutating", "--file-root", root, "--output-dir", directory </> label, "--variable", url label]
          void (concurrently (successful (command first "a")) (successful (command second "b")))
          capture "a" (fromStrict (Encoding.encodeUtf8 one))
          capture "b" (fromStrict (Encoding.encodeUtf8 two))
          successful ["test", "workflow", "send-body", "--variable", url "fallback"]
          capture "fallback" "workspace fallback\n"
          successful ["test", "suite", "parameter", "--allow-mutating", "--variable", "payloadRoot=../root 雪 sentinel", "--variable", url "parameter"]
          capture "parameter" (fromStrict (Encoding.encodeUtf8 one))
          successful (["test", "suite", "parameter", "--allow-mutating", "--variable", "payloadRoot=missing", "--variable", url "precedence"] <> firstRoot)
          capture "precedence" (fromStrict (Encoding.encodeUtf8 one))
          -- A missing shadowed value must not be required.
          successful (["test", "suite", "parameter", "--allow-mutating", "--variable", url "shadowed"] <> firstRoot)
          summary <- Bytes.readFile (directory </> "reports/bodies/summary.json")
          for_ ["sentinel", "payload-sentinel", Encoding.encodeUtf8 (Text.pack first)] $ \sentinel -> assertBool "summary omits root and payload" (not (sentinel `Bytes.isInfixOf` summary))
          source <- Text.IO.readFile (ws </> "request.hurl")
          Text.IO.writeFile (ws </> "request.hurl") (Text.replace "HTTP 201" "HTTP 200" source)
          failed <- run (["test", "workflow", "send-body", "--variable", url "failure"] <> firstRoot)
          assertBool "Hurl assertion failed" (failed ^. #exitCode /= ExitSuccess)
          Text.IO.writeFile (ws </> "request.hurl") source
          withAsync (run (["test", "workflow", "send-body", "--variable", url "slow"] <> firstRoot)) $ \worker -> do
            let awaitSlow remaining = readIORef slowStarted >>= \ready -> unless ready (if remaining == (0 :: Int) then assertFailure "slow request never arrived" else threadDelay 10000 >> awaitSlow (remaining - 1))
            awaitSlow 1000
            cancel worker
            waitCatch worker >>= \case Left _ -> pure (); Right _ -> assertFailure "cancelled execution returned normally"
          snapshot first >>= (@?= before)
          snapshot second >>= (@?= beforeSecond)
          traverse (Bytes.readFile . (ws </>)) ["request.hurl", "hurl-workbench.dhall", "request.json"] >>= (@?= sourceBytes)
          -- Disappearance after validation is a normal Hurl failure; never recreate.
          let gone = directory </> "gone"
          createDirectory gone
          Bytes.writeFile (gone </> "request.json") "gone"
          cmd <- parsed ["test", "workflow", "send-body", "--file-root", gone, "--variable", url "gone"]
          result <- runCommandWithDependencies (assertFailure "format probe") (removeDirectoryRecursive gone >> pure (Right capabilities)) validateRenderedWorkflow (\_ _ -> pure (Right [])) (GlobalOptions (Just (ws </> "hurl-workbench.dhall"))) nested cmd
          assertBool "missing runtime root fails" (result ^. #exitCode /= ExitSuccess)
    ]
