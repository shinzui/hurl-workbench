-- | Caller-owned Hurl body directories. Validation uses filesystem operations
-- under the effective identity; no mode-bit inference or process-global cwd.
module HurlWorkbench.Run.FileRoot
  ( FileRoot,
    FileRootError,
    validateFileRoot,
    fileRootPath,
    checkFileRootOutputs,
    selectSuiteFileRoot,
    renderFileRootError,
  )
where

import Control.Exception (IOException, try)
import Data.Generics.Labels ()
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import System.Directory (canonicalizePath, listDirectory)
import System.FilePath (isAbsolute, splitDirectories, (</>))
import System.Posix.Files (getFileStatus, isDirectory)

-- The flag records explicit selection, which requires disjoint output trees.
data FileRoot = FileRoot !FilePath !Bool
  deriving stock (Generic, Eq)

instance Show FileRoot where
  show _ = "FileRoot <redacted>"

data FileRootError = InvalidFileRoot | FileRootBindingFailed !BindingError | FileRootOutputOverlap | FileRootOutputUnreadable
  deriving stock (Generic, Eq)

instance Show FileRootError where
  show = Text.unpack . renderFileRootError

-- | Nothing selects the supplied workspace base. Explicit relative paths use
-- the supplied invocation or workspace base, according to the caller.
validateFileRoot :: FilePath -> Maybe FilePath -> IO (Either FileRootError FileRoot)
validateFileRoot base requested = do
  attempted <- try @IOException $ do
    let selected = fromMaybe base requested
        absolute = case requested of
          Nothing -> base
          Just _ -> if isAbsolute selected then selected else base </> selected
    when (maybe False null requested) (ioError (userError "empty file root"))
    canonical <- canonicalizePath absolute
    -- stat of root/. needs directory search access, and listing needs read
    -- access. Both use the effective identity, including ACLs and privileges.
    status <- getFileStatus (canonical </> ".")
    unless (isDirectory status) (ioError (userError "file root is not a directory"))
    _ <- listDirectory canonical
    pure (FileRoot canonical (isJust requested))
  pure (either (const (Left InvalidFileRoot)) Right attempted)

fileRootPath :: FileRoot -> FilePath
fileRootPath (FileRoot path _) = path

-- | Canonicalize existing parent components even for not-yet-created outputs.
-- This check must run before report reservation, overwrite, or chmod.
checkFileRootOutputs :: FileRoot -> [FilePath] -> IO (Either FileRootError ())
checkFileRootOutputs (FileRoot _ False) _ = pure (Right ())
checkFileRootOutputs (FileRoot root True) targets = do
  inspected <- try @IOException (traverse canonicalizePath targets)
  pure $ case inspected of
    Left _ -> Left FileRootOutputUnreadable
    Right paths
      | any overlaps paths -> Left FileRootOutputOverlap
      | otherwise -> Right ()
  where
    overlaps path = let a = splitDirectories root; b = splitDirectories path in a `isPrefixOf` b || b `isPrefixOf` a

-- | Only suite-wide bindings participate. A typed CLI selection wins without
-- resolving the shadowed parameter. Static workspace validation checks its kind.
selectSuiteFileRoot :: ValidatedWorkspace -> SuiteName -> BindingInput -> Maybe FileRoot -> IO (Either FileRootError FileRoot)
selectSuiteFileRoot workspace name input selected = case selected of
  Just root -> pure (Right root)
  Nothing -> case lookupSuite name workspace >>= view #fileRootParameter of
    Nothing -> validateFileRoot base Nothing
    Just parameter ->
      resolveParameterSubset workspace (Set.singleton parameter) input >>= \case
        Left err -> pure (Left (FileRootBindingFailed err))
        Right bindings -> case Map.lookup parameter (bindings ^. #variables) of
          Nothing -> pure (Left InvalidFileRoot)
          Just value -> validateFileRoot base (Just (Text.unpack (hurlValueLiteralText value)))
  where
    base = unWorkspaceRoot (validatedRoot workspace)

renderFileRootError :: FileRootError -> Text
renderFileRootError = \case
  InvalidFileRoot -> "--file-root must select an existing readable, searchable directory"
  FileRootBindingFailed err -> "suite file-root parameter: " <> renderBindingError err
  FileRootOutputOverlap -> "file-root input and output trees must be disjoint"
  FileRootOutputUnreadable -> "could not inspect file-root output layout"
