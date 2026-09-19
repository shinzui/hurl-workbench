-- | Internal representation of 'ValidatedWorkspace'. Only
--   "HurlWorkbench.Workspace.Validate" may construct it; everything else uses
--   the abstract type and accessors exported by
--   "HurlWorkbench.Workspace.Context".
module HurlWorkbench.Workspace.Context.Internal
  ( WorkspaceContext (..),
    ValidatedWorkspace (..),
  )
where

import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Types

-- | A decoded workspace together with where it was loaded from. It has not
--   been semantically validated.
data WorkspaceContext = WorkspaceContext
  { -- | Canonical absolute path of @hurl-workbench.dhall@.
    manifestPath :: !FilePath,
    -- | Canonical directory containing the manifest.
    workspaceRoot :: !WorkspaceRoot,
    workspace :: !Workspace
  }
  deriving stock (Generic, Eq, Show)

-- | A workspace that passed every semantic check, indexed by
--   category-specific names.
data ValidatedWorkspace = ValidatedWorkspace
  { context :: !WorkspaceContext,
    parameterIndex :: !(Map ParameterName Parameter),
    fragmentIndex :: !(Map FragmentName Fragment),
    -- | Canonical absolute path of each fragment file, inside the root.
    fragmentFiles :: !(Map FragmentName FilePath),
    workflowIndex :: !(Map WorkflowName Workflow),
    recipeIndex :: !(Map RecipeName Recipe),
    matrixIndex :: !(Map MatrixName Matrix),
    serviceIndex :: !(Map ServiceName Service),
    suiteIndex :: !(Map SuiteName Suite)
  }
  deriving stock (Generic, Eq, Show)
