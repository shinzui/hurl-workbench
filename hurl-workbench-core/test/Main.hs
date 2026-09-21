module Main (main) where

import HurlWorkbench.Parameter.ParameterTest qualified as ParameterTest
import HurlWorkbench.Workflow.WorkflowTest qualified as WorkflowTest
import HurlWorkbench.Workspace.NameSafetyTest qualified as NameSafetyTest
import HurlWorkbench.Workspace.WorkspaceTest qualified as WorkspaceTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "hurl-workbench-core"
      [ ParameterTest.tests,
        WorkspaceTest.tests,
        NameSafetyTest.tests,
        WorkflowTest.tests
      ]
