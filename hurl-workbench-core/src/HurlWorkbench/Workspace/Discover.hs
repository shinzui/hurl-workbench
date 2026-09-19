-- | Locate the workspace manifest.
--
--   An explicit @--workspace FILE@ always wins. Otherwise the start directory
--   and each of its parents are searched for 'manifestFileName', stopping at
--   the filesystem root. Neither @$HOME@, a global configuration directory,
--   nor the network is ever consulted.
module HurlWorkbench.Workspace.Discover
  ( WorkspaceSource (..),
    manifestFileName,
    discoverWorkspace,
    workspaceSourcePath,
  )
where

import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Error (WorkspaceError (..))
import System.Directory (doesFileExist, makeAbsolute)
import System.FilePath (normalise, takeDirectory, (</>))

-- | Where the manifest came from.
data WorkspaceSource
  = -- | Named with @--workspace FILE@.
    ExplicitWorkspace !FilePath
  | -- | Found by walking up from the start directory.
    DiscoveredWorkspace !FilePath
  deriving stock (Generic, Eq, Show)

-- | The manifest file name searched for during discovery.
manifestFileName :: FilePath
manifestFileName = "hurl-workbench.dhall"

-- | The absolute manifest path of a source.
workspaceSourcePath :: WorkspaceSource -> FilePath
workspaceSourcePath = \case
  ExplicitWorkspace path -> path
  DiscoveredWorkspace path -> path

-- | @discoverWorkspace explicit startDirectory@. A relative explicit path is
--   resolved against @startDirectory@.
discoverWorkspace :: Maybe FilePath -> FilePath -> IO (Either WorkspaceError WorkspaceSource)
discoverWorkspace explicit startDirectory = do
  start <- normalise <$> makeAbsolute startDirectory
  case explicit of
    Just file -> do
      let candidate = normalise (start </> file)
      exists <- doesFileExist candidate
      pure $
        if exists
          then Right (ExplicitWorkspace candidate)
          else Left (ManifestNotFound candidate)
    Nothing -> walk start start
  where
    walk start directory = do
      let candidate = directory </> manifestFileName
      exists <- doesFileExist candidate
      let parent = takeDirectory directory
      if exists
        then pure (Right (DiscoveredWorkspace candidate))
        else
          if parent == directory
            then pure (Left (NoWorkspaceFound start))
            else walk start parent
