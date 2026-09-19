-- | Loaded workspaces.
--
--   A 'WorkspaceContext' is a decoded manifest plus its location. A
--   'ValidatedWorkspace' is the only value later features accept: it can be
--   obtained solely through 'HurlWorkbench.Workspace.Validate.validateWorkspace',
--   carries its own root, and offers typed lookups by category-specific name.
module HurlWorkbench.Workspace.Context
  ( -- * Decoded context
    WorkspaceContext (..),
    loadWorkspaceContext,

    -- * Validated workspace
    ValidatedWorkspace,
    validatedContext,
    validatedManifestPath,
    validatedRoot,
    validatedWorkspace,

    -- ** Indexes
    validatedParameters,
    validatedFragments,
    validatedWorkflows,
    validatedRecipes,
    validatedMatrices,
    validatedServices,
    validatedSuites,

    -- ** Lookups
    lookupParameter,
    lookupFragment,
    lookupFragmentFile,
    lookupWorkflow,
    lookupRecipe,
    lookupMatrix,
    lookupService,
    lookupSuite,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context.Internal (ValidatedWorkspace (..), WorkspaceContext (..))
import HurlWorkbench.Workspace.Decode (decodeWorkspaceFile)
import HurlWorkbench.Workspace.Discover (WorkspaceSource, workspaceSourcePath)
import HurlWorkbench.Workspace.Error (WorkspaceError)
import HurlWorkbench.Workspace.Types
import System.Directory (canonicalizePath)
import System.FilePath (takeDirectory)

-- | Canonicalize the manifest path and decode it. The workspace root is the
--   canonical directory containing the manifest.
loadWorkspaceContext :: WorkspaceSource -> IO (Either WorkspaceError WorkspaceContext)
loadWorkspaceContext source = do
  manifest <- canonicalizePath (workspaceSourcePath source)
  decoded <- decodeWorkspaceFile manifest
  pure $
    decoded <&> \ws ->
      WorkspaceContext
        { manifestPath = manifest,
          workspaceRoot = WorkspaceRoot (takeDirectory manifest),
          workspace = ws
        }

validatedContext :: ValidatedWorkspace -> WorkspaceContext
validatedContext = view #context

validatedManifestPath :: ValidatedWorkspace -> FilePath
validatedManifestPath = view (#context . #manifestPath)

validatedRoot :: ValidatedWorkspace -> WorkspaceRoot
validatedRoot = view (#context . #workspaceRoot)

-- | The decoded workspace, with every list in declaration order.
validatedWorkspace :: ValidatedWorkspace -> Workspace
validatedWorkspace = view (#context . #workspace)

validatedParameters :: ValidatedWorkspace -> Map ParameterName Parameter
validatedParameters = view #parameterIndex

validatedFragments :: ValidatedWorkspace -> Map FragmentName Fragment
validatedFragments = view #fragmentIndex

validatedWorkflows :: ValidatedWorkspace -> Map WorkflowName Workflow
validatedWorkflows = view #workflowIndex

validatedRecipes :: ValidatedWorkspace -> Map RecipeName Recipe
validatedRecipes = view #recipeIndex

validatedMatrices :: ValidatedWorkspace -> Map MatrixName Matrix
validatedMatrices = view #matrixIndex

validatedServices :: ValidatedWorkspace -> Map ServiceName Service
validatedServices = view #serviceIndex

validatedSuites :: ValidatedWorkspace -> Map SuiteName Suite
validatedSuites = view #suiteIndex

lookupParameter :: ParameterName -> ValidatedWorkspace -> Maybe Parameter
lookupParameter name = Map.lookup name . validatedParameters

lookupFragment :: FragmentName -> ValidatedWorkspace -> Maybe Fragment
lookupFragment name = Map.lookup name . validatedFragments

-- | Canonical absolute path of a fragment file, guaranteed to be a regular
--   file inside the workspace root at validation time.
lookupFragmentFile :: FragmentName -> ValidatedWorkspace -> Maybe FilePath
lookupFragmentFile name = Map.lookup name . view #fragmentFiles

lookupWorkflow :: WorkflowName -> ValidatedWorkspace -> Maybe Workflow
lookupWorkflow name = Map.lookup name . validatedWorkflows

lookupRecipe :: RecipeName -> ValidatedWorkspace -> Maybe Recipe
lookupRecipe name = Map.lookup name . validatedRecipes

lookupMatrix :: MatrixName -> ValidatedWorkspace -> Maybe Matrix
lookupMatrix name = Map.lookup name . validatedMatrices

lookupService :: ServiceName -> ValidatedWorkspace -> Maybe Service
lookupService name = Map.lookup name . validatedServices

lookupSuite :: SuiteName -> ValidatedWorkspace -> Maybe Suite
lookupSuite name = Map.lookup name . validatedSuites
