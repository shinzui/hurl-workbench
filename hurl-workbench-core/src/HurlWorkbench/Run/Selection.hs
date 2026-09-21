-- | Pure expansion of workflow, recipe, and matrix selections. Each expanded
--   run names one resolved workflow plus ordered committed plain bindings.
module HurlWorkbench.Run.Selection
  ( RunSelection (..),
    SafetyDisposition (..),
    BindingLayer (..),
    ExpandedRun (..),
    SelectionError (..),
    resolveSelection,
    renderSelectionError,
  )
where

import Data.Bifunctor (first)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import HurlWorkbench.Parameter.Resolve (BindingLayer (..), BindingSource (..))
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Resolve
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import System.FilePath ((</>))

data RunSelection
  = SelectWorkflow !WorkflowName
  | SelectRecipe !RecipeName
  | SelectMatrix !MatrixName
  deriving stock (Generic, Eq, Show)

data SafetyDisposition
  = Classified !Safety
  | UnclassifiedWorkflow
  deriving stock (Generic, Eq, Show)

data ExpandedRun = ExpandedRun
  { displayName :: !Text,
    workflow :: !ResolvedWorkflow,
    safety :: !SafetyDisposition,
    bindingLayers :: ![BindingLayer],
    artifactStem :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

data SelectionError
  = SelectedWorkflowInvalid !WorkflowError
  | SelectedRecipeNotFound !RecipeName
  | SelectedMatrixNotFound !MatrixName
  | RecipeWorkflowNotFound !RecipeName !WorkflowName
  | MatrixRecipeNotFound !MatrixName !RecipeName
  | MatrixHasNoCases !MatrixName
  | DuplicateMatrixCase !MatrixName !MatrixCaseName
  | DuplicateCommittedBinding !Text !ParameterName
  | UndeclaredCommittedBinding !Text !WorkflowName !ParameterName
  | SecretCommittedBinding !Text !ParameterName
  deriving stock (Generic, Eq, Show)

resolveSelection :: ValidatedWorkspace -> RunSelection -> Either SelectionError (NonEmpty ExpandedRun)
resolveSelection validated = \case
  SelectWorkflow name -> do
    resolved <- first SelectedWorkflowInvalid (resolveWorkflow validated name)
    pure
      ( ExpandedRun
          { displayName = unWorkflowName name,
            workflow = resolved,
            safety = UnclassifiedWorkflow,
            bindingLayers = [],
            artifactStem = Text.unpack (unWorkflowName name)
          }
          :| []
      )
  SelectRecipe name -> do
    recipe <- maybe (Left (SelectedRecipeNotFound name)) Right (lookupRecipe name validated)
    expanded <- expandRecipe validated recipe
    pure (expanded :| [])
  SelectMatrix name -> do
    matrix <- maybe (Left (SelectedMatrixNotFound name)) Right (lookupMatrix name validated)
    recipe <- maybe (Left (MatrixRecipeNotFound name (matrix ^. #recipe))) Right (lookupRecipe (matrix ^. #recipe) validated)
    let duplicateCase = firstDuplicate (map (view #name) (matrix ^. #cases))
    maybe (pure ()) (Left . DuplicateMatrixCase name) duplicateCase
    cases <- maybe (Left (MatrixHasNoCases name)) Right (nonEmpty (matrix ^. #cases))
    base <- expandRecipe validated recipe
    traverse (expandCase validated matrix base) cases

expandRecipe :: ValidatedWorkspace -> Recipe -> Either SelectionError ExpandedRun
expandRecipe validated recipe = do
  resolved <- first (const (RecipeWorkflowNotFound (recipe ^. #name) (recipe ^. #workflow))) (resolveWorkflow validated (recipe ^. #workflow))
  layer <- bindingLayer validated resolved (recipeLabel recipe) (recipe ^. #bindings)
  pure
    ExpandedRun
      { displayName = unRecipeName (recipe ^. #name),
        workflow = resolved,
        safety = Classified (recipe ^. #safety),
        bindingLayers = [layer],
        artifactStem = Text.unpack (unRecipeName (recipe ^. #name))
      }

expandCase :: ValidatedWorkspace -> Matrix -> ExpandedRun -> MatrixCase -> Either SelectionError ExpandedRun
expandCase validated matrix base matrixCase = do
  layer <- bindingLayer validated (base ^. #workflow) (matrixCaseLabel matrix matrixCase) (matrixCase ^. #bindings)
  let matrixName = unMatrixName (matrix ^. #name)
      caseName = unMatrixCaseName (matrixCase ^. #name)
  pure
    base
      { displayName = matrixName <> "/" <> caseName,
        bindingLayers = layer : base ^. #bindingLayers,
        artifactStem = Text.unpack matrixName </> Text.unpack caseName
      }

bindingLayer :: ValidatedWorkspace -> ResolvedWorkflow -> Text -> [Binding] -> Either SelectionError BindingLayer
bindingLayer validated resolved label bindings = do
  let duplicate = firstDuplicate (map (view #parameter) bindings)
  maybe (pure ()) (Left . DuplicateCommittedBinding label) duplicate
  traverse_ validateBinding bindings
  pure
    BindingLayer
      { source = CommittedBinding label,
        values = Map.fromList [(binding ^. #parameter, binding ^. #value) | binding <- bindings]
      }
  where
    definition = resolved ^. #workflow
    declared = Set.fromList (definition ^. #parameters)
    validateBinding binding
      | (binding ^. #parameter) `Set.notMember` declared =
          Left (UndeclaredCommittedBinding label (definition ^. #name) (binding ^. #parameter))
      | otherwise = case lookupParameter (binding ^. #parameter) validated of
          Just parameter | parameter ^. #kind == Secret -> Left (SecretCommittedBinding label (binding ^. #parameter))
          _ -> Right ()

firstDuplicate :: (Ord value) => [value] -> Maybe value
firstDuplicate values = go Set.empty values
  where
    go _ [] = Nothing
    go seen (value : remaining)
      | value `Set.member` seen = Just value
      | otherwise = go (Set.insert value seen) remaining

recipeLabel :: Recipe -> Text
recipeLabel recipe = "recipe " <> quote (unRecipeName (recipe ^. #name))

matrixCaseLabel :: Matrix -> MatrixCase -> Text
matrixCaseLabel matrix matrixCase =
  "matrix "
    <> quote (unMatrixName (matrix ^. #name))
    <> " case "
    <> quote (unMatrixCaseName (matrixCase ^. #name))

renderSelectionError :: SelectionError -> Text
renderSelectionError = \case
  SelectedWorkflowInvalid err -> renderWorkflowError err
  SelectedRecipeNotFound name -> "unknown recipe " <> quote (unRecipeName name)
  SelectedMatrixNotFound name -> "unknown matrix " <> quote (unMatrixName name)
  RecipeWorkflowNotFound recipe workflow ->
    "recipe " <> quote (unRecipeName recipe) <> " refers to unknown workflow " <> quote (unWorkflowName workflow)
  MatrixRecipeNotFound matrix recipe ->
    "matrix " <> quote (unMatrixName matrix) <> " refers to unknown recipe " <> quote (unRecipeName recipe)
  MatrixHasNoCases matrix -> "matrix " <> quote (unMatrixName matrix) <> " has no cases"
  DuplicateMatrixCase matrix matrixCase ->
    "matrix " <> quote (unMatrixName matrix) <> " declares case " <> quote (unMatrixCaseName matrixCase) <> " more than once"
  DuplicateCommittedBinding label parameter -> label <> " binds parameter " <> quotedParameter parameter <> " more than once"
  UndeclaredCommittedBinding label workflow parameter ->
    label <> " binds parameter " <> quotedParameter parameter <> " which workflow " <> quote (unWorkflowName workflow) <> " does not declare"
  SecretCommittedBinding label parameter -> label <> " commits a value for secret parameter " <> quotedParameter parameter
  where
    quotedParameter = quote . unParameterName

quote :: Text -> Text
quote value = "\"" <> value <> "\""
