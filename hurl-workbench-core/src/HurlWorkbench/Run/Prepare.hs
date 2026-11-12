-- | Convert pure selections into fully rendered, syntax-checked, bound runs
--   before any Hurl process starts.
module HurlWorkbench.Run.Prepare
  ( PreparedRun (..),
    PreparationError (..),
    prepareSelection,
    prepareSelectionForSuite,
    prepareSelectionForSuiteWith,
    prepareSelectionWith,
    prepareSelectionWithGenerator,
    prepareExpandedForSuiteWith,
    prepareSelectionAtFileRootWith,
    prepareSelectionForSuiteAtFileRootWith,
    prepareExpandedForSuiteAtFileRootWith,
    buildBatchCase,
    renderPreparationError,
  )
where

import Control.Monad (foldM)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Generate (GeneratorEnvironment)
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.FileRoot
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workspace.Context (ValidatedWorkspace, validatedRoot)
import HurlWorkbench.Workspace.Types (Workflow, WorkspaceRoot (..))

data PreparedRun = PreparedRun
  { displayName :: !Text,
    artifactStem :: !FilePath,
    safety :: !SafetyDisposition,
    renderedWorkflow :: !RenderedWorkflow,
    bindings :: !ResolvedBindings,
    fileRoot :: !FileRoot,
    options :: !HurlOptions
  }
  deriving stock (Generic, Eq, Show)

data PreparationError
  = RunFileRootFailed !FileRootError
  | SelectionPreparationFailed !SelectionError
  | RunRenderFailed !Text !RenderError
  | RunFormatFailed !Text !HurlfmtError
  | RunBindingFailed !Text !BindingError
  deriving stock (Generic, Eq, Show)

data CachedWorkflow
  = CachedRenderFailure !RenderError
  | CachedFormatFailure !HurlfmtError
  | CachedRendered !RenderedWorkflow

prepareSelection :: HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelection = prepareSelectionWith validateRenderedWorkflow

-- | Prepare one selection from suite-wide runtime input. Bindings intended
--   for other selections in the same suite are ignored.
prepareSelectionForSuite :: HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionForSuite = prepareSelectionUsing resolveWorkflowBindingSubsetWithLayers validateRenderedWorkflow

prepareSelectionForSuiteWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionForSuiteWith = prepareSelectionUsing resolveWorkflowBindingSubsetWithLayers

prepareSelectionWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionWith = prepareSelectionUsing resolveWorkflowBindingsWithLayers

-- | Deterministic preflight with an injected clock and entropy provider.
prepareSelectionWithGenerator :: GeneratorEnvironment -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionWithGenerator env = prepareSelectionUsing (\validated workflow -> resolveParametersWithLayersAndGenerator env validated (Set.fromList (workflow ^. #parameters)))

prepareSelectionUsing :: (ValidatedWorkspace -> Workflow -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)) -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionUsing resolveBindings validateRendered capabilities validated input hurlOptions selection =
  case resolveSelection validated selection of
    Left err -> pure (Left (SelectionPreparationFailed err :| []))
    Right expanded -> withDefaultRoot validated $ \root -> prepareExpandedUsing resolveBindings root validateRendered capabilities validated hurlOptions (fmap (,input) expanded)

prepareExpandedForSuiteWith :: (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> HurlOptions -> NonEmpty (ExpandedRun, BindingInput) -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareExpandedForSuiteWith validateRendered capabilities validated options runs =
  withDefaultRoot validated $ \root -> prepareExpandedForSuiteAtFileRootWith root validateRendered capabilities validated options runs

withDefaultRoot :: ValidatedWorkspace -> (FileRoot -> IO (Either (NonEmpty PreparationError) a)) -> IO (Either (NonEmpty PreparationError) a)
withDefaultRoot validated action = validateFileRoot (unWorkspaceRoot (validatedRoot validated)) Nothing >>= either (pure . Left . (:| []) . RunFileRootFailed) action

prepareSelectionAtFileRootWith :: FileRoot -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionAtFileRootWith = prepareSelectionAtFileRootUsing resolveWorkflowBindingsWithLayers

prepareSelectionForSuiteAtFileRootWith :: FileRoot -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionForSuiteAtFileRootWith = prepareSelectionAtFileRootUsing resolveWorkflowBindingSubsetWithLayers

prepareSelectionAtFileRootUsing :: (ValidatedWorkspace -> Workflow -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)) -> FileRoot -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelectionAtFileRootUsing resolveBindings root validateRendered capabilities validated input options selection =
  case resolveSelection validated selection of
    Left err -> pure (Left (SelectionPreparationFailed err :| []))
    Right expanded -> prepareExpandedUsing resolveBindings root validateRendered capabilities validated options (fmap (,input) expanded)

prepareExpandedForSuiteAtFileRootWith :: FileRoot -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> HurlOptions -> NonEmpty (ExpandedRun, BindingInput) -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareExpandedForSuiteAtFileRootWith = prepareExpandedUsing resolveWorkflowBindingSubsetWithLayers

prepareExpandedUsing :: (ValidatedWorkspace -> Workflow -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)) -> FileRoot -> (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) -> HurlfmtCapabilities -> ValidatedWorkspace -> HurlOptions -> NonEmpty (ExpandedRun, BindingInput) -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareExpandedUsing resolveBindings root validateRendered capabilities validated hurlOptions assignedRuns = do
  (_cache, errors, prepared) <- foldM prepareOne (Map.empty, [], []) (NonEmpty.toList assignedRuns)
  pure $ case (nonEmpty (reverse errors), nonEmpty (reverse prepared)) of
    (Just problems, _) -> Left problems
    (Nothing, Just ready) -> Right ready
    (Nothing, Nothing) -> error "prepareExpandedUsing: impossible empty expanded selection"
  where
    prepareOne (cache, errors, prepared) (expanded, input) = do
      (nextCache, cached) <- cachedWorkflow cache expanded
      case cached of
        CachedRenderFailure err -> pure (nextCache, RunRenderFailed (expanded ^. #displayName) err : errors, prepared)
        CachedFormatFailure err -> pure (nextCache, RunFormatFailed (expanded ^. #displayName) err : errors, prepared)
        CachedRendered rendered -> do
          resolved <-
            resolveBindings
              validated
              (expanded ^. #workflow . #workflow)
              (expanded ^. #bindingLayers)
              input
          pure $ case resolved of
            Left err -> (nextCache, RunBindingFailed (expanded ^. #displayName) err : errors, prepared)
            Right bindings ->
              ( nextCache,
                errors,
                PreparedRun
                  { displayName = expanded ^. #displayName,
                    artifactStem = expanded ^. #artifactStem,
                    safety = expanded ^. #safety,
                    renderedWorkflow = rendered,
                    bindings,
                    fileRoot = root,
                    options = hurlOptions
                  }
                  : prepared
              )

    cachedWorkflow cache expanded =
      let workflowName = expanded ^. #workflow . #workflow . #name
       in case Map.lookup workflowName cache of
            Just cached -> pure (cache, cached)
            Nothing -> do
              cached <- renderAndValidate expanded
              pure (Map.insert workflowName cached cache, cached)

    renderAndValidate expanded =
      renderWorkflow (expanded ^. #workflow) >>= \case
        Left err -> pure (CachedRenderFailure err)
        Right rendered ->
          validateRendered capabilities rendered <&> \case
            Left err -> CachedFormatFailure err
            Right () -> CachedRendered rendered

buildBatchCase :: HurlRunMode -> RunOutputPolicy -> [HurlReportTarget] -> PreparedRun -> BatchCase
buildBatchCase runMode output reports prepared =
  BatchCase
    { name = prepared ^. #displayName,
      artifactStem = prepared ^. #artifactStem,
      request =
        RunRequest
          { renderedWorkflow = prepared ^. #renderedWorkflow,
            fileRoot = prepared ^. #fileRoot,
            mode = runMode,
            bindings = prepared ^. #bindings,
            options = prepared ^. #options,
            outputPolicy = output,
            reportTargets = reports
          }
    }

renderPreparationError :: PreparationError -> Text
renderPreparationError = \case
  RunFileRootFailed err -> renderFileRootError err
  SelectionPreparationFailed err -> renderSelectionError err
  RunRenderFailed name err -> prefix name <> renderRenderError err
  RunFormatFailed name err -> prefix name <> renderHurlfmtError err
  RunBindingFailed name err -> prefix name <> renderBindingError err
  where
    prefix name = "run \"" <> name <> "\": "
