-- | Top-level CLI entry point: parse argv and dispatch to a command.
module HurlWorkbench.Cli
  ( runCli,
    runCommand,
    runCommandWithHurlfmt,
  )
where

import HurlWorkbench.Cli.Command.List (runList)
import HurlWorkbench.Cli.Command.Render (runRenderWith)
import HurlWorkbench.Cli.Command.Validate (runValidateWith)
import HurlWorkbench.Cli.Options (Command (..), GlobalOptions, Options (..), parserInfo)
import HurlWorkbench.Cli.Output (CommandResult, emitResult)
import HurlWorkbench.Hurl.Format
  ( DependencyError,
    HurlfmtCapabilities,
    HurlfmtError,
    WorkflowSyntaxError,
    detectHurlfmtCapabilities,
    validateRenderedWorkflow,
    validateWorkspaceSyntax,
  )
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)
import Options.Applicative (execParser)
import System.Directory (getCurrentDirectory)

-- | Parse argv, run the command from the current directory, print its
--   output, and exit with its status.
runCli :: IO ()
runCli = do
  Options {global, cmd} <- execParser parserInfo
  currentDirectory <- getCurrentDirectory
  runCommand global currentDirectory cmd >>= emitResult

-- | Run a parsed command as if started in the given directory.
runCommand :: GlobalOptions -> FilePath -> Command -> IO CommandResult
runCommand =
  runCommandWithHurlfmt
    detectHurlfmtCapabilities
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
  ValidateCommand -> runValidateWith detectCapabilities validateSyntax global currentDirectory
  ListCommand category -> runList global currentDirectory category
  RenderCommand options -> runRenderWith detectCapabilities validateRendered global currentDirectory options
