module HurlWorkbench.Parameter.ParameterTest (tests) where

import Control.Exception (bracket)
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import HurlWorkbench.Parameter.Properties
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, inOrderTestGroup, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests = testGroup "parameters" [propertiesTests, resolutionTests]

propertiesTests :: TestTree
propertiesTests =
  testGroup
    "properties files"
    [ testCase "ignores comments and preserves additional equals signs" $ do
        let input = "  # comment\n\nalpha=one=two\ntop=10\n"
        parseVariableProperties "values.env" input
          @?= Right
            ( Map.fromList
                [ (ParameterName "alpha", literal "one=two"),
                  (ParameterName "top", literal "10")
                ]
            ),
      testCase "rejects duplicate names in one file" $
        case parseVariableProperties "values.env" "top=1\ntop=2\n" of
          Left (DuplicatePropertyName VariableProperties "values.env" 2 (ParameterName "top")) -> pure ()
          other -> assertFailure ("expected duplicate property error, got " <> show other),
      testCase "secret errors never retain the secret text" $ do
        let secret = "do-not-print-me" :: Text
            result = parseSecretProperties "secrets.env" (Text.Encoding.encodeUtf8 ("token=" <> secret <> "\ntoken=again\n"))
        assertBool "redacts first secret" (not (secret `Text.isInfixOf` Text.pack (show result)))
    ]

resolutionTests :: TestTree
resolutionTests =
  inOrderTestGroup
    "resolution"
    [ testCase "applies explicit, later-file, environment, and default precedence" $
        withSystemTempDirectory "hurl-workbench-bindings" $ \dir ->
          withEnvironment
            [ ("EXAMPLE_CLIENT_ID", "environment-id"),
              ("EXAMPLE_CLIENT_SECRET", "environment-secret"),
              ("OVERRIDE_SECRET", "explicit-secret")
            ]
            $ do
              ByteString.writeFile (dir </> "first.env") "client_id=file-id\ntop=10\n"
              ByteString.writeFile (dir </> "second.env") "top=20\n"
              ByteString.writeFile (dir </> "secrets.env") "client_secret=file-secret\n"
              workspace <- fullWorkspace
              workflow <- requireWorkflow workspace (WorkflowName "list-properties")
              let input =
                    BindingInput
                      { plainOverrides = Map.singleton (ParameterName "client_id") (literal "explicit-id"),
                        secretEnvironmentOverrides = Map.singleton (ParameterName "client_secret") "OVERRIDE_SECRET",
                        variableFiles = [dir </> "first.env", dir </> "second.env"],
                        secretFiles = [dir </> "secrets.env"]
                      }
              resolveWorkflowBindings workspace workflow input >>= \case
                Left err -> assertFailure (Text.unpack (renderBindingError err))
                Right resolved -> do
                  fmap hurlValueLiteralText (resolved ^. #variables)
                    @?= Map.fromList
                      [ (ParameterName "auth_url", "https://auth.example.test"),
                        (ParameterName "base_url", "https://api.example.test"),
                        (ParameterName "client_id", "explicit-id"),
                        (ParameterName "top", "20")
                      ]
                  Map.keys (resolved ^. #secrets) @?= [ParameterName "client_secret"]
                  show resolved @?= "ResolvedBindings <redacted>",
      testCase "reports every missing workflow parameter in sorted order" $
        withUnsetEnvironment ["EXAMPLE_CLIENT_ID", "EXAMPLE_CLIENT_SECRET"] $ do
          workspace <- fullWorkspace
          workflow <- requireWorkflow workspace (WorkflowName "list-properties")
          workflow ^. #parameters
            @?= map ParameterName ["auth_url", "client_id", "client_secret", "base_url", "top"]
          lookupEnv "EXAMPLE_CLIENT_ID" >>= (@?= Nothing)
          lookupEnv "EXAMPLE_CLIENT_SECRET" >>= (@?= Nothing)
          resolveWorkflowBindings workspace workflow emptyBindingInput >>= \case
            Left (BindingIssues issues) ->
              mapMaybe missingName (toList issues)
                @?= [ParameterName "client_id", ParameterName "client_secret"]
            other -> assertFailure ("expected missing binding issues, got " <> show other),
      testCase "rejects unexpected and wrong-channel bindings" $ do
        workspace <- fullWorkspace
        let input =
              emptyBindingInput
                { plainOverrides =
                    Map.fromList
                      [ (ParameterName "client_secret", literal "not-secret-channel"),
                        (ParameterName "not_declared", literal "unused")
                      ]
                }
        resolveParameters workspace (Set.singleton (ParameterName "client_secret")) input >>= \case
          Left (BindingIssues issues) -> do
            assertBool "wrong channel" (any isKindMismatch issues)
            assertBool "unexpected" (any isUnexpected issues)
          other -> assertFailure ("expected binding issues, got " <> show other),
      testCase "a malformed secret environment value is redacted" $
        withEnvironment [("BAD_SECRET", " hidden ")] $ do
          workspace <- fullWorkspace
          let input = emptyBindingInput {secretEnvironmentOverrides = Map.singleton (ParameterName "client_secret") "BAD_SECRET"}
          resolveParameters workspace (Set.singleton (ParameterName "client_secret")) input >>= \case
            Left err -> assertBool "does not reveal value" (not ("hidden" `Text.isInfixOf` renderBindingError err))
            Right _ -> assertFailure "expected the secret to be rejected"
    ]

literal :: Text -> HurlValueLiteral
literal value = case mkHurlValueLiteral value of
  Left err -> error (show err)
  Right valid -> valid

fullWorkspace :: IO ValidatedWorkspace
fullWorkspace = do
  loaded <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/full/hurl-workbench.dhall")
  context <- either (assertFailure . Text.unpack . renderWorkspaceError) pure loaded
  validateWorkspace context >>= either (assertFailure . Text.unpack . Text.unlines . map renderValidationIssue . toList) pure

requireWorkflow :: ValidatedWorkspace -> WorkflowName -> IO Workflow
requireWorkflow workspace name = maybe (assertFailure "workflow fixture missing") pure (lookupWorkflow name workspace)

withEnvironment :: [(String, String)] -> IO a -> IO a
withEnvironment values action = bracket save restore (const applyAndRun)
  where
    save = traverse (\(name, _value) -> (name,) <$> lookupEnv name) values
    restore previous = for_ previous $ \(name, old) -> maybe (unsetEnv name) (setEnv name) old
    applyAndRun = traverse_ (uncurry setEnv) values >> action

withUnsetEnvironment :: [String] -> IO a -> IO a
withUnsetEnvironment names action = bracket save restore (const (traverse_ unsetEnv names >> action))
  where
    save = traverse (\name -> (name,) <$> lookupEnv name) names
    restore previous = for_ previous $ \(name, old) -> maybe (unsetEnv name) (setEnv name) old

isKindMismatch :: BindingIssue -> Bool
isKindMismatch BindingKindMismatch {} = True
isKindMismatch _ = False

isUnexpected :: BindingIssue -> Bool
isUnexpected UnexpectedBinding {} = True
isUnexpected _ = False

missingName :: BindingIssue -> Maybe ParameterName
missingName (MissingBinding name) = Just name
missingName (MissingBindingEnvironment name _environment _source) = Just name
missingName _ = Nothing
