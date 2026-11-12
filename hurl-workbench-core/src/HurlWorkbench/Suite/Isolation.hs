-- | Pure application-state checks, before formatting, binding IO, capability
-- probes, report replacement, or service resolution.
module HurlWorkbench.Suite.Isolation
  ( IsolationIssue (..),
    checkIsolation,
    checkSuiteIsolation,
    checkSuiteIsolationWith,
    renderIsolationIssue,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Batch (PositiveInt, positiveIntValue)
import HurlWorkbench.Run.Selection
import HurlWorkbench.Suite.Scenario (VerifiedScenarioInputs)
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types

data IsolationIssue
  = SharedStateParallelUnsafe !Text !SafetyDisposition
  | IndependentStateHandoffRequired
  deriving stock (Generic, Eq, Show)

checkIsolation :: IsolationPolicy -> PositiveInt -> [ExpandedRun] -> [IsolationIssue]
checkIsolation IndependentState _ _ = [IndependentStateHandoffRequired]
checkIsolation SharedState jobs runs =
  [ SharedStateParallelUnsafe (Text.pack (run ^. #artifactStem)) (run ^. #safety)
  | positiveIntValue jobs > 1,
    run <- runs,
    run ^. #safety /= Classified ReadOnly
  ]

-- | Expansion is pure; malformed references are handled by normal preparation.
checkSuiteIsolation :: ValidatedWorkspace -> SuiteName -> PositiveInt -> [IsolationIssue]
checkSuiteIsolation workspace name jobs = checkSuiteIsolationWith Nothing workspace name jobs

checkSuiteIsolationWith :: Maybe VerifiedScenarioInputs -> ValidatedWorkspace -> SuiteName -> PositiveInt -> [IsolationIssue]
checkSuiteIsolationWith verified workspace name jobs = case lookupSuite name workspace of
  Nothing -> []
  Just suite | suite ^. #isolation == IndependentState, isJust verified -> []
  Just suite -> checkIsolation (suite ^. #isolation) jobs (concatMap expanded (suite ^. #runs))
  where
    expanded reference = either (const []) toList (resolveSelection workspace (selection reference))
    selection = \case
      WorkflowRun name_ -> SelectWorkflow name_
      RecipeRun name_ -> SelectRecipe name_
      MatrixRun name_ -> SelectMatrix name_

renderIsolationIssue :: IsolationIssue -> Text
renderIsolationIssue = \case
  SharedStateParallelUnsafe scenario _ ->
    "shared-state-parallel-unsafe: scenario \"" <> scenario <> "\" requires --jobs 1; mutation permission does not establish isolation"
  IndependentStateHandoffRequired -> "independent-state-handoff-required: independent scenarios require a verified runtime handoff"
