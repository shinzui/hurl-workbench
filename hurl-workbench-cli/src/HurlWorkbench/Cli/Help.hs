-- | Terminal-aware parser preferences.
module HurlWorkbench.Cli.Help
  ( helpPreferences,
    resolveHelpColumns,
  )
where

import Options.Applicative
  ( ParserPrefs,
    columns,
    prefs,
    showHelpOnEmpty,
    showHelpOnError,
  )
import System.Console.Terminal.Size qualified as Terminal
import System.IO (hIsTerminalDevice, stdout)

-- | Apply the public help behavior at a known output width.
helpPreferences :: Int -> ParserPrefs
helpPreferences width =
  prefs (showHelpOnError <> showHelpOnEmpty <> columns (max 1 width))

-- | Use the actual terminal width when interactive, capped for readability.
-- Piped output uses a stable 80-column layout.
resolveHelpColumns :: IO Int
resolveHelpColumns = do
  interactive <- hIsTerminalDevice stdout
  if not interactive
    then pure defaultColumns
    else do
      window <- Terminal.hSize stdout
      pure $ case window of
        Just size | Terminal.width size > 0 -> min maxColumns (Terminal.width size)
        _ -> defaultColumns
  where
    defaultColumns = 80
    maxColumns = 140
