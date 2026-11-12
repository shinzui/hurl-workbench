module HurlWorkbench.Suite.ScenarioTest (tests) where

import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Selection
import HurlWorkbench.Suite.Scenario
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (createFileLink)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (setFileMode)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "scenario handoff"
    [ testCase "strict decoding never reveals malformed private input" $ do
        for_ ["{private-endpoint", "{\"version\":1,\"scenarios\":[],\"private-secret\":1}", "{\"version\":1,\"scenarios\":[{\"scenario\":\"private-fixture\"}]}"] $ \bytes ->
          decodeScenarioInputs bytes @?= Left ScenarioMalformedInput
        decodeScenarioInputs "{\"version\":2,\"scenarios\":[]}" @?= Left ScenarioUnsupportedVersion
        decodeScenarioInputs "{\"version\":1,\"scenarios\":[]}" @?= Right (ScenarioInputs []),
      testCase "file loader requires a private regular file and rejects symlinks" $
        withSystemTempDirectory "scenario-file" $ \directory -> do
          let path = directory </> "inputs.json"
          ByteString.writeFile path "{\"version\":1,\"scenarios\":[]}"
          setFileMode path 0o644
          loadScenarioInputs path >>= (@?= Left ScenarioFileNotPrivateRegular)
          setFileMode path 0o600
          loadScenarioInputs path >>= (@?= Right (ScenarioInputs []))
          createFileLink path (directory </> "link")
          loadScenarioInputs (directory </> "link") >>= (@?= Left ScenarioFileNotPrivateRegular)
          loadScenarioInputs directory >>= (@?= Left ScenarioFileNotPrivateRegular)
          loadScenarioInputs (directory </> "absent") >>= (@?= Left ScenarioFileUnreadable),
      testCase "whole assignments reject incomplete, duplicate, invalid, and conflicting inputs" $ do
        workspace <- loadValidated
        runs <- either (assertFailure . show) (pure . toList) (resolveSelection workspace (SelectMatrix (MatrixName "writes")))
        let first_ = assignment "writes/first" "private-fixture-a" "http://EXAMPLE.test"
            second_ = assignment "writes/second" "private-fixture-b" "http://other.test:81/"
            check expected common entries =
              verifyScenarioInputs workspace runs common (ScenarioInputs entries) >>= \case
                Left err -> err @?= expected
                Right _ -> assertFailure "invalid handoff verified"
        verified <- verifyScenarioInputs workspace runs emptyBindingInput (ScenarioInputs [second_, first_]) >>= either (assertFailure . show) pure
        assertBool "verified Show redacts runtime input" (not ("private" `Text.isInfixOf` Text.pack (show verified)))
        assertBool "raw Show redacts runtime input" (not ("private" `Text.isInfixOf` Text.pack (show (ScenarioInputs [first_]))))
        for_ runs $ \run -> do
          input <- maybe (assertFailure "missing assigned input") pure (scenarioBindingInput verified run)
          Map.keys (input ^. #plainOverrides) @?= [ParameterName "baseUrl"]
        check ScenarioAssignmentMismatch emptyBindingInput [first_]
        check ScenarioAssignmentMismatch emptyBindingInput [first_, first_]
        check ScenarioAssignmentMismatch emptyBindingInput [first_, second_ & #scenario .~ "writes/extra"]
        check ScenarioInvalidLabel emptyBindingInput [first_ & #scenario .~ "../private", second_]
        check ScenarioDuplicateFixture emptyBindingInput [first_, second_ & #fixtureId .~ "private-fixture-a"]
        check ScenarioInvalidFixture emptyBindingInput [first_ & #fixtureId .~ "private\nfixture", second_]
        for_ ["http://example.TEST:80/", "HTTP://EXAMPLE.TEST", "http://example.test:080/"] $ \endpoint ->
          check ScenarioDuplicateEndpoint emptyBindingInput [first_, second_ & #endpoint .~ endpoint]
        for_ ["ftp://private.test", "http://private.test/path", "http://user:private@host", "http://private.test/?secret", "http://private.test/#fragment", "http://private.test:99999", "http://private.test/ "] $ \endpoint ->
          check ScenarioInvalidEndpoint emptyBindingInput [first_ & #endpoint .~ endpoint, second_]
        check ScenarioDuplicateParameter emptyBindingInput [first_ & #bindings .~ [ScenarioBinding (ParameterName "baseUrl") "private-value"], second_]
        check ScenarioInvalidParameter emptyBindingInput [first_ & #endpointParameter .~ ParameterName "undeclared", second_]
        check ScenarioDuplicateParameter emptyBindingInput [first_ & #secretEnvironment .~ [ScenarioSecret (ParameterName "baseUrl") "PRIVATE_ENV"], second_]
        let literal = either (error . show) id (mkHurlValueLiteral "private-override")
        check ScenarioConflictingBinding (emptyBindingInput {plainOverrides = Map.singleton (ParameterName "baseUrl") literal}) [first_, second_]
        withSystemTempDirectory "scenario-conflict" $ \directory -> do
          let file = directory </> "variables"
          ByteString.writeFile file "baseUrl=private-file-value\n"
          check ScenarioConflictingBinding (emptyBindingInput {variableFiles = [file]}) [first_, second_]
          check ScenarioConflictingBinding (emptyBindingInput {secretFiles = [file]}) [first_, second_],
      testCase "handoff conflicts with committed layers and enforces workflow parameter kinds" $ do
        loaded <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/full/hurl-workbench.dhall")
        context <- either (assertFailure . show) pure loaded
        workspace <- validateWorkspace context >>= either (assertFailure . show) pure
        runs <- either (assertFailure . show) (pure . toList) (resolveSelection workspace (SelectMatrix (MatrixName "property-page-sizes")))
        let inputs binding =
              ScenarioInputs
                [ (assignment (run ^. #artifactStem) (Text.pack (show ordinal)) ("https://fixture" <> Text.pack (show ordinal) <> ".test"))
                    { endpointParameter = ParameterName "base_url",
                      bindings = [binding]
                    }
                | (ordinal, run) <- zip [1 :: Int ..] runs
                ]
            check expected raw =
              verifyScenarioInputs workspace runs emptyBindingInput raw >>= \case
                Left issue -> issue @?= expected
                Right _ -> assertFailure "invalid provider binding accepted"
        check ScenarioConflictingBinding (inputs (ScenarioBinding (ParameterName "top") "private-generated-value"))
        check ScenarioInvalidParameter (inputs (ScenarioBinding (ParameterName "client_secret") "private-plain-secret"))
        check ScenarioRuntimeInputFailed (inputs (ScenarioBinding (ParameterName "client_id") " private-invalid-literal "))
        let ScenarioInputs valid = inputs (ScenarioBinding (ParameterName "client_id") "private-generated-client")
        verifyScenarioInputs workspace runs emptyBindingInput (ScenarioInputs valid) >>= \case
          Left issue -> assertFailure (show issue)
          Right verified -> for_ runs $ \run -> do
            input <- maybe (assertFailure "missing assignment") pure (scenarioBindingInput verified run)
            assertBool "provider overrides declared endpoint fallback" (Map.member (ParameterName "base_url") (input ^. #plainOverrides))
    ]

assignment :: FilePath -> Text -> Text -> ScenarioAssignment
assignment scenario fixtureId endpoint = ScenarioAssignment scenario fixtureId endpoint (ParameterName "baseUrl") [] []

loadValidated :: IO ValidatedWorkspace
loadValidated = do
  loaded <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/isolation/hurl-workbench.dhall")
  context <- either (assertFailure . show) pure loaded
  validateWorkspace context >>= either (assertFailure . show) pure
