module Main (main) where

import HurlWorkbench.Hurl.RunTest qualified as RunTest
import HurlWorkbench.Parameter.ParameterTest qualified as ParameterTest
import HurlWorkbench.Run.SelectionTest qualified as SelectionTest
import HurlWorkbench.Service.RunTest qualified as ServiceRunTest
import HurlWorkbench.Suite.RunTest qualified as SuiteRunTest
import HurlWorkbench.Workflow.WorkflowTest qualified as WorkflowTest
import HurlWorkbench.Workspace.NameSafetyTest qualified as NameSafetyTest
import HurlWorkbench.Workspace.WorkspaceTest qualified as WorkspaceTest
import Test.Tasty (defaultMain, testGroup)

main :: IO ()
main =
  defaultMain $
    testGroup
      "hurl-workbench-core"
      [ RunTest.tests,
        ParameterTest.tests,
        SelectionTest.tests,
        ServiceRunTest.tests,
        SuiteRunTest.tests,
        WorkspaceTest.tests,
        NameSafetyTest.tests,
        WorkflowTest.tests
      ]
