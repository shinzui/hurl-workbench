-- | Convert pure selections into fully rendered, syntax-checked, bound runs
--   before any Hurl process starts.
module HurlWorkbench.Run.Prepare
  ( PreparedRun (..),
    PreparationError (..),
    prepareSelection,
    buildBatchCase,
    renderPreparationError,
  )
where

import Control.Monad (foldM)
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)

data PreparedRun = PreparedRun
  { displayName :: !Text,
    artifactStem :: !FilePath,
    safety :: !SafetyDisposition,
    renderedWorkflow :: !RenderedWorkflow,
    bindings :: !ResolvedBindings,
    options :: !HurlOptions
  }
  deriving stock (Generic, Eq, Show)

data PreparationError
  = SelectionPreparationFailed !SelectionError
  | RunRenderFailed !Text !RenderError
  | RunFormatFailed !Text !HurlfmtError
  | RunBindingFailed !Text !BindingError
  deriving stock (Generic, Eq, Show)

data CachedWorkflow
  = CachedRenderFailure !RenderError
  | CachedFormatFailure !HurlfmtError
  | CachedRendered !RenderedWorkflow

prepareSelection :: HurlfmtCapabilities -> ValidatedWorkspace -> BindingInput -> HurlOptions -> RunSelection -> IO (Either (NonEmpty PreparationError) (NonEmpty PreparedRun))
prepareSelection capabilities validated input hurlOptions selection =
  case resolveSelection validated selection of
    Left err -> pure (Left (SelectionPreparationFailed err :| []))
    Right expanded -> do
      (_cache, errors, prepared) <- foldM prepareOne (Map.empty, [], []) (NonEmpty.toList expanded)
      pure $ case (nonEmpty (reverse errors), nonEmpty (reverse prepared)) of
        (Just problems, _) -> Left problems
        (Nothing, Just ready) -> Right ready
        (Nothing, Nothing) -> error "prepareSelection: impossible empty expanded selection"
  where
    prepareOne (cache, errors, prepared) expanded = do
      (nextCache, cached) <- cachedWorkflow cache expanded
      case cached of
        CachedRenderFailure err -> pure (nextCache, RunRenderFailed (expanded ^. #displayName) err : errors, prepared)
        CachedFormatFailure err -> pure (nextCache, RunFormatFailed (expanded ^. #displayName) err : errors, prepared)
        CachedRendered rendered -> do
          resolved <-
            resolveWorkflowBindingsWithLayers
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
          validateRenderedWorkflow capabilities rendered <&> \case
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
            mode = runMode,
            bindings = prepared ^. #bindings,
            options = prepared ^. #options,
            outputPolicy = output,
            reportTargets = reports
          }
    }

renderPreparationError :: PreparationError -> Text
renderPreparationError = \case
  SelectionPreparationFailed err -> renderSelectionError err
  RunRenderFailed name err -> prefix name <> renderRenderError err
  RunFormatFailed name err -> prefix name <> renderHurlfmtError err
  RunBindingFailed name err -> prefix name <> renderBindingError err
  where
    prefix name = "run \"" <> name <> "\": "
