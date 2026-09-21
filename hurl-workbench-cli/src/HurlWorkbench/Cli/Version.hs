{-# LANGUAGE CPP #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Build identity shown by @--version@.
module HurlWorkbench.Cli.Version
  ( versionText,
    revisionText,
  )
where

import Data.Version (showVersion)
import GitHash qualified
import Paths_hurl_workbench_cli qualified as Package

-- | The package version followed by the short build revision.
versionText :: String
versionText = "hurl-workbench " <> showVersion Package.version <> " (" <> revisionText <> ")"

-- | Prefer the reproducible revision injected by Nix. Local builds fall back
-- to the repository revision captured by Template Haskell; source archives
-- without either form of metadata remain buildable.
revisionText :: String
#ifdef GIT_HASH
revisionText = take 7 GIT_HASH
#else
revisionText =
  revisionFromGitInfo $$(GitHash.tGitInfoCwdTry)

revisionFromGitInfo :: Either String GitHash.GitInfo -> String
revisionFromGitInfo = \case
    Right gitInfo -> take 7 (GitHash.giHash gitInfo)
    Left _ -> "unknown"
#endif
