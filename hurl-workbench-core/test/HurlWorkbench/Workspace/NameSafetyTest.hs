{-# OPTIONS_GHC -fdefer-type-errors -Wno-deferred-type-errors #-}

-- | Compile-time name safety, checked at run time: this module is compiled
--   with deferred type errors, so each ill-typed top-level binding below
--   compiles into a 'TypeError' exception. Each test forces one binding and
--   expects that exception, proving that category-specific names cannot be
--   interchanged. Each binding must stay top-level: GHC floats deferred-error
--   evidence to the enclosing binding, so an inline expression would throw
--   before the surrounding 'try' runs.
module HurlWorkbench.Workspace.NameSafetyTest (tests) where

import Control.Exception (TypeError (..), evaluate, try)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase)

tests :: TestTree
tests =
  testGroup
    "category-specific names"
    [ testCase "a recipe name is not a workflow name" (expectTypeError recipeAsWorkflow),
      testCase "a workflow name is not a fragment name" (expectTypeError workflowAsFragment),
      testCase "a matrix name is not a suite name" (expectTypeError matrixAsSuite),
      testCase "plain text is not a parameter name" (expectTypeError textAsParameter)
    ]

recipeAsWorkflow :: ValidatedWorkspace -> Maybe Workflow
recipeAsWorkflow = lookupWorkflow (RecipeName "top-properties")

workflowAsFragment :: ValidatedWorkspace -> Maybe Fragment
workflowAsFragment = lookupFragment (WorkflowName "list-properties")

matrixAsSuite :: ValidatedWorkspace -> Maybe Suite
matrixAsSuite = lookupSuite (MatrixName "grid")

textAsParameter :: ValidatedWorkspace -> Maybe Parameter
textAsParameter = lookupParameter ("base_url" :: Text)

expectTypeError :: a -> IO ()
expectTypeError value = do
  result <- try (evaluate value)
  case result of
    Left (TypeError _) -> pure ()
    Right _ -> assertFailure "expected the expression to be rejected by the type checker"
