-- | Command results as data, so commands can be tested without capturing
--   process handles, plus a small aligned-table renderer.
module HurlWorkbench.Cli.Output
  ( CommandResult (..),
    success,
    failure,
    emitResult,
    renderTable,
    plural,
  )
where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import HurlWorkbench.Prelude
import System.Exit (ExitCode (..), exitWith)
import System.IO (stderr)

-- | What a command prints and how the process exits.
data CommandResult = CommandResult
  { stdoutLines :: ![Text],
    stderrLines :: ![Text],
    exitCode :: !ExitCode
  }
  deriving stock (Generic, Eq, Show)

success :: [Text] -> CommandResult
success out = CommandResult {stdoutLines = out, stderrLines = [], exitCode = ExitSuccess}

-- | Workbench failures (discovery, decoding, validation) exit with status 1.
failure :: [Text] -> CommandResult
failure err = CommandResult {stdoutLines = [], stderrLines = err, exitCode = ExitFailure 1}

emitResult :: CommandResult -> IO ()
emitResult CommandResult {stdoutLines, stderrLines, exitCode} = do
  traverse_ Text.IO.putStrLn stdoutLines
  traverse_ (Text.IO.hPutStrLn stderr) stderrLines
  when (exitCode /= ExitSuccess) (exitWith exitCode)

-- | Left-aligned columns separated by two spaces; empty cells print as @-@.
renderTable :: [Text] -> [[Text]] -> [Text]
renderTable headings rows =
  map renderRow (headings : map (map orDash) rows)
  where
    orDash cell = if Text.null cell then "-" else cell
    widths = foldr (zipWith max . map Text.length) (map (const 0) headings) (headings : map (map orDash) rows)
    renderRow cells = Text.stripEnd (Text.intercalate "  " (zipWith (`Text.justifyLeft` ' ') widths cells))

-- | @plural 2 "recipe" "recipes"@ is @2 recipes@.
plural :: Int -> Text -> Text -> Text
plural n one many = Text.pack (show n) <> " " <> (if n == 1 then one else many)
