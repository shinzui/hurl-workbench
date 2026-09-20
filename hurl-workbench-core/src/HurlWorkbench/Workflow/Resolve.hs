-- | Resolve a validated workflow to the canonical files that supply its
--   ordered Hurl entries.
module HurlWorkbench.Workflow.Resolve
  ( ResolvedFragment (..),
    ResolvedWorkflow (..),
    WorkflowError (..),
    resolveWorkflow,
    renderWorkflowError,
  )
where

import Data.Generics.Labels ()
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types

-- | One declared fragment paired with the canonical, root-contained file
--   proved by semantic workspace validation.
data ResolvedFragment = ResolvedFragment
  { fragment :: !Fragment,
    fragmentPath :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

-- | A workflow whose ordered fragment names have all been resolved.
data ResolvedWorkflow = ResolvedWorkflow
  { workspaceRoot :: !WorkspaceRoot,
    workflow :: !Workflow,
    sourceFragments :: !(NonEmpty ResolvedFragment)
  }
  deriving stock (Generic, Eq, Show)

-- | A defensive resolution failure. Public command paths normally cannot see
--   the latter two cases because 'ValidatedWorkspace' rejects them first.
data WorkflowError
  = WorkflowNotFound !WorkflowName
  | WorkflowHasNoFragments !WorkflowName
  | WorkflowFragmentNotFound !WorkflowName !FragmentName
  deriving stock (Generic, Eq, Show)

resolveWorkflow :: ValidatedWorkspace -> WorkflowName -> Either WorkflowError ResolvedWorkflow
resolveWorkflow validated selected = do
  definition <- maybe (Left (WorkflowNotFound selected)) Right (lookupWorkflow selected validated)
  fragmentNames <- maybe (Left (WorkflowHasNoFragments selected)) Right (nonEmpty (definition ^. #fragments))
  resolved <- traverse resolveFragment fragmentNames
  pure
    ResolvedWorkflow
      { workspaceRoot = validatedRoot validated,
        workflow = definition,
        sourceFragments = resolved
      }
  where
    resolveFragment fragmentName =
      case (lookupFragment fragmentName validated, lookupFragmentFile fragmentName validated) of
        (Just definition, Just path) -> Right ResolvedFragment {fragment = definition, fragmentPath = path}
        _ -> Left (WorkflowFragmentNotFound selected fragmentName)

renderWorkflowError :: WorkflowError -> Text
renderWorkflowError = \case
  WorkflowNotFound name -> "unknown workflow " <> quote (unWorkflowName name)
  WorkflowHasNoFragments name -> "workflow " <> quote (unWorkflowName name) <> " has no fragments"
  WorkflowFragmentNotFound workflowName fragmentName ->
    "workflow "
      <> quote (unWorkflowName workflowName)
      <> " refers to unresolved fragment "
      <> quote (unFragmentName fragmentName)

quote :: Text -> Text
quote value = "\"" <> value <> "\""
