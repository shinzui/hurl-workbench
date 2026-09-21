module HurlWorkbench.Cli.Command.Matrix
  ( runMatrix,
    runMatrixWith,
    replayCaptured,
    renderCaseSummary,
  )
where

import Data.Generics.Labels ()
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Text.IO qualified as Text.IO
import HurlWorkbench.Cli.Command.Run (buildExecutionInputs)
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve (BindingInput)
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Artifact
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.Prepare
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context (lookupMatrix)
import HurlWorkbench.Workspace.Types (MatrixName (..), Safety (..))
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, (</>))
import System.IO qualified as IO

runMatrix :: GlobalOptions -> FilePath -> MatrixOptions -> IO CommandResult
runMatrix = runMatrixWith detectHurlCapabilities validateRenderedWorkflow

runMatrixWith ::
  IO (Either DependencyError HurlCapabilities) ->
  (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) ->
  GlobalOptions ->
  FilePath ->
  MatrixOptions ->
  IO CommandResult
runMatrixWith detectCapabilities validateRendered global currentDirectory matrixOptions =
  loadValidatedWorkspace global currentDirectory >>= \case
    Left errors -> pure (workbenchFailure 2 errors)
    Right validated -> case lookupMatrix (matrixOptions ^. #matrix) validated of
      Nothing -> pure (workbenchFailure 2 ["error: unknown matrix \"" <> unMatrixName (matrixOptions ^. #matrix) <> "\""])
      Just matrixDefinition -> case validateMatrixOptions matrixOptions of
        Just problem -> pure (workbenchFailure 2 ["error: " <> problem])
        Nothing -> case buildInputs matrixOptions of
          Left errors -> pure (workbenchFailure 2 (map ("error: " <>) errors))
          Right (bindingInput, hurlOptions) ->
            detectCapabilities >>= \case
              Left err -> pure (workbenchFailure 3 ["error: " <> renderDependencyError err])
              Right capabilities ->
                prepareSelectionWith
                  validateRendered
                  (capabilities ^. #hurlfmt)
                  validated
                  bindingInput
                  hurlOptions
                  (SelectMatrix (matrixOptions ^. #matrix))
                  >>= \case
                    Left errors ->
                      pure
                        ( workbenchFailure
                            (preparationExitCode errors)
                            (map (("error: " <>) . renderPreparationError) (toList errors))
                        )
                    Right prepared
                      | any (mutatingDenied (matrixOptions ^. #allowMutating) . view #safety) prepared ->
                          pure (workbenchFailure 2 ["error: mutating matrix requires --allow-mutating"])
                      | isJust (matrixOptions ^. #hurl . #curlExportPath) && length prepared > 1 ->
                          pure (workbenchFailure 2 ["error: --curl has one path and cannot be shared by multiple matrix cases"])
                      | otherwise -> do
                          built <- buildCases currentDirectory matrixOptions prepared
                          case built of
                            Left errors -> pure (workbenchFailure 2 (map (("error: " <>) . renderArtifactError) (toList errors)))
                            Right batchCases -> do
                              let failFast = fromMaybe (matrixDefinition ^. #failFast) (matrixOptions ^. #failFastOverride)
                                  batchOptions = BatchOptions (matrixOptions ^. #jobs) failFast
                                  runner = mkHurlRunner capabilities
                              selectedRunner <-
                                if usesInheritedOutput matrixOptions
                                  then labelSequentialRunner (map (view #name) (toList batchCases)) runner
                                  else pure runner
                              result <- runBatch selectedRunner batchOptions batchCases
                              pure
                                CommandResult
                                  { stdoutLines = [],
                                    stderrLines =
                                      hurlCapabilityWarnings capabilities
                                        <> replayCaptured (result ^. #cases)
                                        <> map renderCaseSummary (toList (result ^. #cases)),
                                    exitCode = result ^. #selectedExitCode
                                  }

buildInputs :: MatrixOptions -> Either [Text] (BindingInput, HurlOptions)
buildInputs matrixOptions =
  buildExecutionInputs
    ExecuteOptions
      { selection = SelectMatrix (matrixOptions ^. #matrix),
        bindings = matrixOptions ^. #bindings,
        hurl = matrixOptions ^. #hurl,
        allowMutating = matrixOptions ^. #allowMutating
      }

validateMatrixOptions :: MatrixOptions -> Maybe Text
validateMatrixOptions options
  | options ^. #overwrite && isNothing (options ^. #outputDirectory) = Just "--overwrite requires --output-dir"
  | options ^. #mode == ClientMode && positiveIntValue (options ^. #jobs) > 1 && isNothing (options ^. #outputDirectory) =
      Just "client matrices with --jobs greater than 1 require --output-dir"
  | options ^. #mode == TestMode && isJust (options ^. #outputDirectory) = Just "--output-dir is available only with --mode run"
  | otherwise = Nothing

buildCases :: FilePath -> MatrixOptions -> NonEmpty PreparedRun -> IO (Either (NonEmpty ArtifactError) (NonEmpty BatchCase))
buildCases currentDirectory options prepared = case (options ^. #mode, options ^. #outputDirectory) of
  (ClientMode, Just requestedDirectory) -> do
    let outputDirectory = if isAbsolute requestedDirectory then requestedDirectory else currentDirectory </> requestedDirectory
    prepareResponseArtifacts outputDirectory (options ^. #overwrite) prepared <&> \case
      Left errors -> Left errors
      Right paths -> Right (NonEmpty.zipWith (\ready path -> buildBatchCase ClientMode (ResponseFile path) [] ready) prepared paths)
  (ClientMode, Nothing) -> pure (Right (fmap (buildBatchCase ClientMode InheritRunOutput []) prepared))
  (TestMode, Nothing) -> pure (Right (fmap (buildBatchCase TestMode CaptureRunOutput []) prepared))
  (TestMode, Just _) -> error "buildCases: output directory rejected by validation"

usesInheritedOutput :: MatrixOptions -> Bool
usesInheritedOutput options = options ^. #mode == ClientMode && isNothing (options ^. #outputDirectory)

labelSequentialRunner :: [Text] -> HurlRunner -> IO HurlRunner
labelSequentialRunner names runner = do
  remaining <- newIORef names
  pure $ HurlRunner $ \request -> do
    caseName <- atomicModifyIORef' remaining $ \case
      [] -> ([], "unknown")
      name : rest -> (rest, name)
    Text.IO.hPutStrLn IO.stderr ("==> " <> caseName)
    result <- runHurl runner request
    Text.IO.hPutStrLn IO.stderr ("<== " <> caseName <> " (" <> resultLabel result <> ")")
    pure result
  where
    resultLabel = \case
      Left _ -> "start failed"
      Right result -> case result ^. #exitCode of
        ExitSuccess -> "passed"
        ExitFailure status -> "Hurl exit " <> Text.pack (show status)

replayCaptured :: NonEmpty CaseResult -> [Text]
replayCaptured = concatMap replayOne . toList
  where
    replayOne result = case result ^. #capturedOutput of
      Nothing -> []
      Just captured ->
        let stdoutText = decode (captured ^. #stdout)
            stderrText = decode (captured ^. #stderr)
            lines_ = Text.lines stdoutText <> Text.lines stderrText
         in ["--- " <> result ^. #name <> " diagnostics ---" | not (null lines_)] <> lines_
    decode = Text.Encoding.decodeUtf8With lenientDecode

renderCaseSummary :: CaseResult -> Text
renderCaseSummary result =
  summary <> maybe "" ((" -> " <>) . Text.pack) (result ^. #outputPath)
  where
    summary = case result ^. #outcome of
      CasePassed -> "PASS  " <> result ^. #name
      CaseFailed (ExitFailure status) -> "FAIL  " <> result ^. #name <> " (Hurl exit " <> Text.pack (show status) <> ")"
      CaseFailed ExitSuccess -> "FAIL  " <> result ^. #name <> " (invalid successful failure status)"
      CaseStartFailed err -> "ERROR " <> result ^. #name <> " (" <> renderRunStartError err <> ")"
      CaseSkipped reason -> "SKIP  " <> result ^. #name <> " (" <> skipReason reason <> ")"
    skipReason FailFastTriggered = "fail-fast"
    skipReason BatchPrerequisiteFailed = "batch prerequisite failed"

preparationExitCode :: NonEmpty PreparationError -> Int
preparationExitCode errors = maximum (map one (toList errors))
  where
    one = \case
      RunFormatFailed _ InvalidHurl {} -> 2
      RunFormatFailed {} -> 3
      _ -> 2

mutatingDenied :: Bool -> SafetyDisposition -> Bool
mutatingDenied allowed = \case
  Classified Mutating -> not allowed
  _ -> False

workbenchFailure :: Int -> [Text] -> CommandResult
workbenchFailure status errors =
  CommandResult
    { stdoutLines = [],
      stderrLines = errors,
      exitCode = ExitFailure status
    }
