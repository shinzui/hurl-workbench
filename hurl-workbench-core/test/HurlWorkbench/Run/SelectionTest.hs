module HurlWorkbench.Run.SelectionTest (tests) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (atomically, modifyTVar', newTVarIO, readTVar, readTVarIO, writeTVar)
import Control.Exception (bracket)
import Data.Bits ((.&.))
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
import HurlWorkbench.Run.Artifact
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files
  ( accessModes,
    fileMode,
    getFileStatus,
    ownerExecuteMode,
    ownerReadMode,
    ownerWriteMode,
    unionFileModes,
  )
import System.Posix.Types qualified
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
        withSystemTempDirectory "hurl-workbench-layered-bindings" $ \directory -> do
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
              batchCase ^. #request . #mode @?= TestMode,
      testCase "bounds concurrency and returns results in declaration order" $ do
        cases <- syntheticCases ["slow", "fast", "middle"]
        active <- newTVarIO (0 :: Int)
        maximumActive <- newTVarIO (0 :: Int)
        let runner = HurlRunner $ \request -> do
              atomically $ do
                modifyTVar' active (+ 1)
                current <- readTVar active
                observed <- readTVar maximumActive
                writeTVar maximumActive (max current observed)
              threadDelay (if requestPath request == Just "slow" then 150000 else 20000)
              atomically (modifyTVar' active (subtract 1))
              pure (Right (RunResult ExitSuccess 0 (Just (CapturedRunOutput "" ""))))
        result <- runBatch runner (BatchOptions (positive 2) False) cases
        readTVarIO maximumActive >>= (@?= 2)
        map (view #name) (toList (result ^. #cases)) @?= ["slow", "fast", "middle"]
        map (view #outcome) (toList (result ^. #cases)) @?= replicate 3 CasePassed
        result ^. #selectedExitCode @?= ExitSuccess,
      testCase "fail-fast stops queue scheduling and marks untouched cases skipped" $ do
        cases <- syntheticCases ["first", "active", "third", "fourth", "fifth"]
        starts <- newTVarIO (0 :: Int)
        let runner = HurlRunner $ \request -> do
              atomically (modifyTVar' starts (+ 1))
              if requestPath request == Just "first"
                then threadDelay 20000 >> pure (Right (RunResult (ExitFailure 7) 0 Nothing))
                else threadDelay 120000 >> pure (Right (RunResult ExitSuccess 0 Nothing))
        result <- runBatch runner (BatchOptions (positive 2) True) cases
        readTVarIO starts >>= (@?= 2)
        map (view #outcome) (toList (result ^. #cases))
          @?= [ CaseFailed (ExitFailure 7),
                CasePassed,
                CaseSkipped FailFastTriggered,
                CaseSkipped FailFastTriggered,
                CaseSkipped FailFastTriggered
              ]
        result ^. #selectedExitCode @?= ExitFailure 7,
      testCase "rejects non-positive worker counts" $ do
        mkPositiveInt 0 @?= Left (NonPositiveJobs 0)
        positiveIntValue (positive 1) @?= 1,
      testCase "prepares collision-checked owner-only response artifacts" $
        withSystemTempDirectory "hurl-workbench-artifacts" $ \directory -> do
          prepared <- preparedMatrix
          let outputDirectory = directory </> "responses"
              smallPath = outputDirectory </> "property-page-sizes" </> "small.response"
              expected = smallPath :| [outputDirectory </> "property-page-sizes" </> "large.response"]
          prepareResponseArtifacts outputDirectory False prepared >>= \case
            Left errors -> assertFailure (Text.unpack (Text.unlines (map renderArtifactError (toList errors))))
            Right paths -> do
              paths @?= expected
              traverse filePermissions expected >>= (@?= (ownerFileMode :| [ownerFileMode]))
              directoryPermissions outputDirectory >>= (@?= ownerDirectoryMode)
              directoryPermissions (outputDirectory </> "property-page-sizes") >>= (@?= ownerDirectoryMode)
          ByteString.writeFile smallPath "keep-me"
          prepareResponseArtifacts outputDirectory False prepared >>= \case
            Left errors -> map renderArtifactError (toList errors) @?= map (renderArtifactError . ArtifactAlreadyExists) (toList expected)
            Right _ -> assertFailure "expected existing artifacts to be rejected"
          ByteString.readFile smallPath >>= (@?= "keep-me")
          prepareResponseArtifacts outputDirectory True prepared >>= \case
            Left errors -> assertFailure (Text.unpack (Text.unlines (map renderArtifactError (toList errors))))
            Right _ -> ByteString.readFile smallPath >>= (@?= "")
    ]

trueCapabilities :: HurlfmtCapabilities
trueCapabilities = HurlfmtCapabilities (HurlfmtExecutable "/usr/bin/true") (makeVersion [8, 0, 1])

literal :: Text -> HurlValueLiteral
literal value = either (error . show) id (mkHurlValueLiteral value)

requireBindings :: Either BindingError ResolvedBindings -> IO ResolvedBindings
requireBindings = either (assertFailure . Text.unpack . renderBindingError) pure

positive :: Int -> PositiveInt
positive value = either (error . show) id (mkPositiveInt value)

syntheticCases :: [Text] -> IO (NonEmpty BatchCase)
syntheticCases names = do
  prepared <- preparedMatrix
  let base = NonEmpty.head prepared
      makeCase name =
        let original = buildBatchCase ClientMode (ResponseFile (Text.unpack name)) [] base
         in BatchCase
              { name,
                artifactStem = original ^. #artifactStem,
                request = original ^. #request
              }
  maybe (assertFailure "synthetic case list must be non-empty") pure (nonEmpty (map makeCase names))

preparedMatrix :: IO (NonEmpty PreparedRun)
preparedMatrix =
  withSystemTempDirectory "hurl-workbench-batch-bindings" $ \directory -> do
    let secretsPath = directory </> "secrets.env"
    ByteString.writeFile secretsPath "client_secret=fixture-secret\n"
    workspace <- fullWorkspace
    let input =
          emptyBindingInput
            { plainOverrides = Map.singleton (ParameterName "client_id") (literal "fixture-id"),
              secretFiles = [secretsPath]
            }
    prepareSelection trueCapabilities workspace input defaultHurlOptions (SelectMatrix (MatrixName "property-page-sizes")) >>= \case
      Left errors -> assertFailure (Text.unpack (Text.unlines (map renderPreparationError (toList errors))))
      Right prepared -> pure prepared

requestPath :: RunRequest -> Maybe FilePath
requestPath request = case request ^. #outputPolicy of
  ResponseFile path -> Just path
  _ -> Nothing

filePermissions :: FilePath -> IO System.Posix.Types.FileMode
filePermissions path = (.&. accessModes) . fileMode <$> getFileStatus path

directoryPermissions :: FilePath -> IO System.Posix.Types.FileMode
directoryPermissions = filePermissions

ownerFileMode :: System.Posix.Types.FileMode
ownerFileMode = ownerReadMode `unionFileModes` ownerWriteMode

ownerDirectoryMode :: System.Posix.Types.FileMode
ownerDirectoryMode = ownerFileMode `unionFileModes` ownerExecuteMode

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
