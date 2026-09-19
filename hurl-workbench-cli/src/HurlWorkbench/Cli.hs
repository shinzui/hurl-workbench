-- | Top-level CLI entry point: parse argv and dispatch to a command.
module HurlWorkbench.Cli
  ( runCli,
    runCommand,
  )
where

import HurlWorkbench.Cli.Command.List (runList)
import HurlWorkbench.Cli.Command.Validate (runValidate)
import HurlWorkbench.Cli.Options (Command (..), GlobalOptions, Options (..), parserInfo)
import HurlWorkbench.Cli.Output (CommandResult, emitResult)
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
runCommand global currentDirectory = \case
  ValidateCommand -> runValidate global currentDirectory
  ListCommand category -> runList global currentDirectory category
