-- | Consistent CLI failure rendering and exit construction.
module HurlWorkbench.Cli.Error
  ( cliFailure,
    cliErrors,
    renderCliError,
  )
where

import Data.Text qualified as Text
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Prelude
import System.Exit (ExitCode (..))

-- | Render one safe, already-domain-specific diagnostic.
renderCliError :: Text -> Text
renderCliError message
  | "error:" `Text.isPrefixOf` Text.toLower message = message
  | otherwise = "error: " <> message

-- | Construct a failure whose first line introduces one possibly-multiline
-- diagnostic. Continuation lines retain their indentation and context.
cliFailure :: Int -> [Text] -> CommandResult
cliFailure status messages =
  CommandResult
    { stdoutLines = [],
      stderrLines = case messages of
        [] -> ["error: command failed"]
        first : rest -> renderCliError first : rest,
      exitCode = ExitFailure status
    }

-- | Construct a failure from several independent diagnostics.
cliErrors :: Int -> [Text] -> CommandResult
cliErrors status = cliFailure status . map renderCliError
