-- | Top-level CLI entry point: parse argv and dispatch to a command.
module HurlWorkbench.Cli
  ( runCli,
    runCommand,
    runCommandWithHurlfmt,
    runCommandWithDependencies,
  )
where

import Data.Text qualified as Text
import HurlWorkbench.Cli.Command.Doctor (runDoctorWith)
import HurlWorkbench.Cli.Command.List (runList)
import HurlWorkbench.Cli.Command.Matrix (runMatrixWith)
import HurlWorkbench.Cli.Command.Render (runRenderWith)
import HurlWorkbench.Cli.Command.Run (runExecuteWith)
import HurlWorkbench.Cli.Command.Suite (runSuiteCommandWith)
import HurlWorkbench.Cli.Command.Validate (runValidateWith)
import HurlWorkbench.Cli.Help (helpPreferences, resolveHelpColumns)
import HurlWorkbench.Cli.Options (Command (..), CompletionShell (..), GlobalOptions, Options (..), parserInfo)
import HurlWorkbench.Cli.Output (CommandResult, emitResult, success)
import HurlWorkbench.Hurl.Capabilities (HurlCapabilities, detectHurlCapabilities)
import HurlWorkbench.Hurl.Format
  ( DependencyError,
    HurlfmtCapabilities,
    HurlfmtError,
    WorkflowSyntaxError,
    detectHurlfmtCapabilities,
    validateRenderedWorkflow,
    validateWorkspaceSyntax,
  )
import HurlWorkbench.Hurl.Run (HurlRunMode (..))
import HurlWorkbench.Prelude (Text)
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)
import Options.Applicative (customExecParser)
import Options.Applicative.BashCompletion
  ( bashCompletionScript,
    fishCompletionScript,
    zshCompletionScript,
  )
import System.Directory (getCurrentDirectory)

-- | Parse argv, run the command from the current directory, print its
--   output, and exit with its status.
runCli :: IO ()
runCli = do
  helpColumns <- resolveHelpColumns
  Options {global, cmd} <- customExecParser (helpPreferences helpColumns) parserInfo
  currentDirectory <- getCurrentDirectory
  runCommand global currentDirectory cmd >>= emitResult

-- | Run a parsed command as if started in the given directory.
runCommand :: GlobalOptions -> FilePath -> Command -> IO CommandResult
runCommand =
  runCommandWithDependencies
    detectHurlfmtCapabilities
    detectHurlCapabilities
    validateRenderedWorkflow
    validateWorkspaceSyntax

-- | Test seam for supplying a deterministic Hurlfmt capability probe.
runCommandWithHurlfmt ::
  IO (Either DependencyError HurlfmtCapabilities) ->
  (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) ->
  (HurlfmtCapabilities -> ValidatedWorkspace -> IO (Either DependencyError [WorkflowSyntaxError])) ->
  GlobalOptions ->
  FilePath ->
  Command ->
  IO CommandResult
runCommandWithHurlfmt detectCapabilities validateRendered validateSyntax global currentDirectory = \case
  command ->
    runCommandWithDependencies
      detectCapabilities
      detectHurlCapabilities
      validateRendered
      validateSyntax
      global
      currentDirectory
      command

runCommandWithDependencies ::
  IO (Either DependencyError HurlfmtCapabilities) ->
  IO (Either DependencyError HurlCapabilities) ->
  (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) ->
  (HurlfmtCapabilities -> ValidatedWorkspace -> IO (Either DependencyError [WorkflowSyntaxError])) ->
  GlobalOptions ->
  FilePath ->
  Command ->
  IO CommandResult
runCommandWithDependencies detectHurlfmt detectHurl validateRendered validateSyntax global currentDirectory = \case
  ValidateCommand -> runValidateWith detectHurlfmt validateSyntax global currentDirectory
  ListCommand category -> runList global currentDirectory category
  RenderCommand options -> runRenderWith detectHurlfmt validateRendered global currentDirectory options
  RunCommand options -> runExecuteWith detectHurl validateRendered global currentDirectory ClientMode options
  TestCommand options -> runExecuteWith detectHurl validateRendered global currentDirectory TestMode options
  MatrixCommand options -> runMatrixWith detectHurl validateRendered global currentDirectory options
  SuiteCommand options -> runSuiteCommandWith detectHurl validateRendered global currentDirectory options
  CompletionsCommand shell -> pure (success (completionLines shell))
  DoctorCommand -> runDoctorWith detectHurl

completionLines :: CompletionShell -> [Text]
completionLines shell =
  Text.lines . Text.pack $
    case shell of
      Bash -> bashCompletionScript commandName commandName
      Zsh -> zshCompletionScript commandName commandName
      Fish -> fishCompletionScript commandName commandName
  where
    commandName = "hurl-workbench"
