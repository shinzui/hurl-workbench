module HurlWorkbench.Run.SelectionTest (tests) where

import Control.Exception (bracket)
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
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "run selection and preparation"
    [ testCase "expands matrix cases in declaration order with case-over-recipe layers" $ do
        workspace <- fullWorkspace
        case resolveSelection workspace (SelectMatrix (MatrixName "property-page-sizes")) of
          Left err -> assertFailure (Text.unpack (renderSelectionError err))
          Right expanded -> do
            let runs = NonEmpty.toList expanded
            map (view #displayName) runs @?= ["property-page-sizes/small", "property-page-sizes/large"]
            map (view #artifactStem) runs @?= ["property-page-sizes" </> "small", "property-page-sizes" </> "large"]
            map (view #safety) runs @?= [Classified ReadOnly, Classified ReadOnly]
            map (map (view #source) . view #bindingLayers) runs
              @?= [ [CommittedBinding "matrix \"property-page-sizes\" case \"small\"", CommittedBinding "recipe \"top-properties\""],
                    [CommittedBinding "matrix \"property-page-sizes\" case \"large\"", CommittedBinding "recipe \"top-properties\""]
                  ],
      testCase "applies runtime, file, matrix, recipe, environment, and default precedence" $
        withSystemTempDirectory "hurl-workbench-layered-bindings" $ \directory ->
          withEnvironment [("EXAMPLE_CLIENT_ID", "environment-id")] $ do
            workspace <- fullWorkspace
            expanded <- case resolveSelection workspace (SelectMatrix (MatrixName "property-page-sizes")) of
              Left err -> assertFailure (Text.unpack (renderSelectionError err))
              Right value -> pure (NonEmpty.head value)
            let layers = expanded ^. #bindingLayers
                top = ParameterName "top"
                clientId = ParameterName "client_id"
                recipeOnly = drop 1 layers
                topValue result = hurlValueLiteralText <$> Map.lookup top (result ^. #variables)
            resolveParametersWithLayers workspace (Set.singleton top) [] emptyBindingInput >>= requireBindings >>= ((@?= Just "5") . topValue)
            resolveParametersWithLayers workspace (Set.singleton top) recipeOnly emptyBindingInput >>= requireBindings >>= ((@?= Just "10") . topValue)
            resolveParametersWithLayers workspace (Set.singleton top) layers emptyBindingInput >>= requireBindings >>= ((@?= Just "1") . topValue)
            ByteString.writeFile (directory </> "values.env") "top=20\n"
            let fileInput = emptyBindingInput {variableFiles = [directory </> "values.env"]}
            resolveParametersWithLayers workspace (Set.singleton top) layers fileInput >>= requireBindings >>= ((@?= Just "20") . topValue)
            let explicitInput = fileInput {plainOverrides = Map.singleton top (literal "30")}
            resolveParametersWithLayers workspace (Set.singleton top) layers explicitInput >>= requireBindings >>= ((@?= Just "30") . topValue)
            let committedClient = BindingLayer (CommittedBinding "recipe test") (Map.singleton clientId (literal "committed-id"))
            resolveParametersWithLayers workspace (Set.singleton clientId) [committedClient] emptyBindingInput >>= requireBindings >>= \resolved ->
              (hurlValueLiteralText <$> Map.lookup clientId (resolved ^. #variables)) @?= Just "committed-id",
      testCase "prepares every matrix case before building the shared request shape" $
        withEnvironment [("PREPARE_SELECTION_SECRET", "fixture-secret")] $ do
          workspace <- fullWorkspace
          let input =
                emptyBindingInput
                  { plainOverrides = Map.singleton (ParameterName "client_id") (literal "fixture-id"),
                    secretEnvironmentOverrides = Map.singleton (ParameterName "client_secret") "PREPARE_SELECTION_SECRET"
                  }
          prepared <-
            prepareSelection
              trueCapabilities
              workspace
              input
              defaultHurlOptions
              (SelectMatrix (MatrixName "property-page-sizes"))
          case prepared of
            Left errors -> assertFailure (Text.unpack (Text.unlines (map renderPreparationError (toList errors))))
            Right runs -> do
              map (view #displayName) (NonEmpty.toList runs) @?= ["property-page-sizes/small", "property-page-sizes/large"]
              map (fmap hurlValueLiteralText . Map.lookup (ParameterName "top") . view #variables . view #bindings) (NonEmpty.toList runs)
                @?= [Just "1", Just "100"]
              let batchCase = buildBatchCase TestMode CaptureRunOutput [] (NonEmpty.head runs)
              batchCase ^. #name @?= "property-page-sizes/small"
              batchCase ^. #request . #mode @?= TestMode
    ]

trueCapabilities :: HurlfmtCapabilities
trueCapabilities = HurlfmtCapabilities (HurlfmtExecutable "/usr/bin/true") (makeVersion [8, 0, 1])

literal :: Text -> HurlValueLiteral
literal value = either (error . show) id (mkHurlValueLiteral value)

requireBindings :: Either BindingError ResolvedBindings -> IO ResolvedBindings
requireBindings = either (assertFailure . Text.unpack . renderBindingError) pure

fullWorkspace :: IO ValidatedWorkspace
fullWorkspace = do
  loaded <- loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/full/hurl-workbench.dhall")
  context <- either (assertFailure . Text.unpack . renderWorkspaceError) pure loaded
  validateWorkspace context >>= either (assertFailure . Text.unpack . Text.unlines . map renderValidationIssue . toList) pure

withEnvironment :: [(String, String)] -> IO a -> IO a
withEnvironment values action = bracket save restore (const applyAndRun)
  where
    save = traverse (\(name, _value) -> (name,) <$> lookupEnv name) values
    restore previous = for_ previous $ \(name, old) -> maybe (unsetEnv name) (setEnv name) old
    applyAndRun = traverse_ (uncurry setEnv) values >> action
