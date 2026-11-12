module Main (main) where

import HurlWorkbench.Hurl.RunTest qualified as RunTest
import HurlWorkbench.Parameter.GenerateTest qualified as GenerateTest
import HurlWorkbench.Parameter.ParameterTest qualified as ParameterTest
import HurlWorkbench.Run.FileRootTest qualified as FileRootTest
import HurlWorkbench.Run.SelectionTest qualified as SelectionTest
import HurlWorkbench.Service.RunTest qualified as ServiceRunTest
import HurlWorkbench.Suite.RunTest qualified as SuiteRunTest
import HurlWorkbench.Suite.ScenarioTest qualified as ScenarioTest
import HurlWorkbench.Workflow.WorkflowTest qualified as WorkflowTest
import HurlWorkbench.Workspace.NameSafetyTest qualified as NameSafetyTest
import HurlWorkbench.Workspace.WorkspaceTest qualified as WorkspaceTest
import System.Environment (getArgs)
import Test.Tasty (defaultMain, localOption, testGroup)
import Test.Tasty.Runners (NumThreads (..))

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    ["--clean-environment-scenario", binary, directory] -> ServiceRunTest.runIsolatedScenario binary directory
    _ -> runTests

runTests :: IO ()
runTests =
  -- Existing environment-binding tests mutate process-global state. Serialize
  -- test cases so concurrent POSIX spawns cannot race libc environ updates.
  defaultMain $
    localOption (NumThreads 1) $
      testGroup
        "hurl-workbench-core"
        [ FileRootTest.tests,
          GenerateTest.tests,
          RunTest.tests,
          ParameterTest.tests,
          SelectionTest.tests,
          ServiceRunTest.tests,
          SuiteRunTest.tests,
          ScenarioTest.tests,
          WorkspaceTest.tests,
          NameSafetyTest.tests,
          WorkflowTest.tests
        ]
