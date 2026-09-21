-- | Top-level CLI entry point: parse argv and dispatch to a command.
module HurlWorkbench.Cli
  ( runCli,
    runCommand,
    runCommandWithHurlfmt,
    runCommandWithDependencies,
  )
where

import HurlWorkbench.Cli.Command.Doctor (runDoctorWith)
import HurlWorkbench.Cli.Command.List (runList)
import HurlWorkbench.Cli.Command.Matrix (runMatrixWith)
import HurlWorkbench.Cli.Command.Render (runRenderWith)
import HurlWorkbench.Cli.Command.Run (runExecuteWith)
import HurlWorkbench.Cli.Command.Suite (runSuiteCommandWith)
import HurlWorkbench.Cli.Command.Validate (runValidateWith)
import HurlWorkbench.Cli.Options (Command (..), GlobalOptions, Options (..), parserInfo)
import HurlWorkbench.Cli.Output (CommandResult, emitResult)
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
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import HurlWorkbench.Workspace.Context (ValidatedWorkspace)
import Options.Applicative
  ( CompletionResult (..),
    ParserResult (..),
    defaultPrefs,
    execParserPure,
    renderFailure,
  )
import System.Directory (getCurrentDirectory)
import System.Environment (getArgs, getProgName)
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr)

-- | Parse argv, run the command from the current directory, print its
--   output, and exit with its status.
runCli :: IO ()
runCli = do
  arguments <- getArgs
  program <- getProgName
  Options {global, cmd} <- case execParserPure defaultPrefs parserInfo arguments of
    Success options -> pure options
    Failure parserFailure -> do
      let (message, originalExit) = renderFailure parserFailure program
      case originalExit of
        ExitSuccess -> putStrLn message >> exitSuccess
        ExitFailure _ -> hPutStrLn stderr message >> exitWith (ExitFailure 2)
    CompletionInvoked completion -> do
      execCompletion completion program >>= putStr
      exitSuccess
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
  DoctorCommand -> runDoctorWith detectHurl
