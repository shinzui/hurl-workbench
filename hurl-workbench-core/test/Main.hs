module Main (main) where

import HurlWorkbench.Hurl.RunTest qualified as RunTest
import HurlWorkbench.Parameter.ParameterTest qualified as ParameterTest
import HurlWorkbench.Run.SelectionTest qualified as SelectionTest
import HurlWorkbench.Service.RunTest qualified as ServiceRunTest
import HurlWorkbench.Suite.RunTest qualified as SuiteRunTest
import HurlWorkbench.Workflow.WorkflowTest qualified as WorkflowTest
import HurlWorkbench.Workspace.NameSafetyTest qualified as NameSafetyTest
import HurlWorkbench.Workspace.WorkspaceTest qualified as WorkspaceTest
import Test.Tasty (defaultMain, localOption, testGroup)
import Test.Tasty.Runners (NumThreads (..))

main :: IO ()
main =
  -- Existing environment-binding tests mutate process-global state. Serialize
  -- test cases so concurrent POSIX spawns cannot race libc environ updates.
  defaultMain $
    localOption (NumThreads 1) $
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
