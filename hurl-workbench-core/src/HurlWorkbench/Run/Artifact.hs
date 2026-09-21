-- | Collision-checked, owner-only response artifacts for batch client runs.
module HurlWorkbench.Run.Artifact
  ( ArtifactError (..),
    responseArtifactPath,
    prepareResponseArtifacts,
    renderArtifactError,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (foldM)
import Data.Bits ((.&.))
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Prepare (PreparedRun)
import System.Directory
  ( createDirectory,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesPathExist,
    pathIsSymbolicLink,
  )
import System.FilePath (addExtension, isAbsolute, splitDirectories, takeDirectory, (</>))
import System.IO (hClose)
import System.Posix.Files
  ( accessModes,
    fileMode,
    getFileStatus,
    ownerExecuteMode,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
    unionFileModes,
  )
import System.Posix.IO (OpenFileFlags (..), OpenMode (WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Posix.Types (FileMode)

data ArtifactError
  = InvalidArtifactStem !FilePath
  | DuplicateArtifactTarget !FilePath
  | ArtifactAlreadyExists !FilePath
  | ArtifactPathIsSymbolicLink !FilePath
  | ArtifactTargetIsDirectory !FilePath
  | ArtifactIoError !FilePath !Text
  deriving stock (Generic, Eq, Show)

responseArtifactPath :: FilePath -> PreparedRun -> Either ArtifactError FilePath
responseArtifactPath outputDirectory prepared
  | not (validStem stem) = Left (InvalidArtifactStem stem)
  | otherwise = Right (addExtension (outputDirectory </> stem) "response")
  where
    stem = prepared ^. #artifactStem

prepareResponseArtifacts :: FilePath -> Bool -> NonEmpty PreparedRun -> IO (Either (NonEmpty ArtifactError) (NonEmpty FilePath))
prepareResponseArtifacts outputDirectory overwrite prepared =
  case traverse (responseArtifactPath outputDirectory) prepared of
    Left err -> pure (Left (err :| []))
    Right targets -> do
      existingIssues <- fmap concat (traverse existingIssue (NonEmpty.toList targets))
      let duplicateIssues =
            [ DuplicateArtifactTarget path
            | (path, count) <- Map.toAscList (Map.fromListWith (+) [(path, 1 :: Int) | path <- NonEmpty.toList targets]),
              count > 1
            ]
          preflightIssues = duplicateIssues <> existingIssues
      case nonEmpty preflightIssues of
        Just issues -> pure (Left issues)
        Nothing -> do
          preparedTargets <- try @IOException (prepareAll targets)
          pure $ case preparedTargets of
            Left err -> Left (ArtifactIoError outputDirectory (Text.pack (displayException err)) :| [])
            Right () -> Right targets
  where
    existingIssue path = do
      exists <- doesPathExist path
      symbolic <- if exists then pathIsSymbolicLink path else pure False
      directory <- if exists && not symbolic then doesDirectoryExist path else pure False
      pure $
        [ArtifactPathIsSymbolicLink path | symbolic]
          <> [ArtifactTargetIsDirectory path | directory]
          <> [ArtifactAlreadyExists path | exists && not symbolic && not directory && not overwrite]

    prepareAll targets = do
      createDirectoryIfMissing True outputDirectory
      setFileMode outputDirectory secureDirectoryMode
      verifyMode secureDirectoryMode outputDirectory
      traverse_ (prepareTarget outputDirectory) targets

prepareTarget :: FilePath -> FilePath -> IO ()
prepareTarget outputDirectory target = do
  let relativeDirectories = filter (not . null) (splitDirectories (dropPrefix outputDirectory target))
  _ <- foldM ensureDirectory outputDirectory relativeDirectories
  handle <- fdToHandle =<< openFd target WriteOnly defaultFileFlags {creat = Just secureFileMode, trunc = True, nofollow = True}
  hClose handle
  setFileMode target secureFileMode
  verifyMode secureFileMode target

ensureDirectory :: FilePath -> FilePath -> IO FilePath
ensureDirectory parent component = do
  let path = parent </> component
  exists <- doesPathExist path
  if exists
    then do
      symbolic <- pathIsSymbolicLink path
      when symbolic (ioError (userError ("artifact directory is a symbolic link: " <> path)))
      directory <- doesDirectoryExist path
      unless directory (ioError (userError ("artifact parent is not a directory: " <> path)))
    else createDirectory path
  setFileMode path secureDirectoryMode
  verifyMode secureDirectoryMode path
  pure path

dropPrefix :: FilePath -> FilePath -> FilePath
dropPrefix outputDirectory target =
  let rootParts = splitDirectories outputDirectory
      targetParts = splitDirectories (takeDirectory target)
   in foldl' (</>) "" (drop (length rootParts) targetParts)

validStem :: FilePath -> Bool
validStem stem =
  not (null stem)
    && not (isAbsolute stem)
    && all validComponent (splitDirectories stem)
  where
    validComponent component = not (null component) && component /= "." && component /= ".."

verifyMode :: FileMode -> FilePath -> IO ()
verifyMode expected path = do
  actual <- (.&. accessModes) . fileMode <$> getFileStatus path
  unless (actual == expected) (ioError (userError ("insecure permissions on " <> path)))

secureFileMode :: FileMode
secureFileMode = ownerReadMode `unionFileModes` ownerWriteMode

secureDirectoryMode :: FileMode
secureDirectoryMode = secureFileMode `unionFileModes` ownerExecuteMode

renderArtifactError :: ArtifactError -> Text
renderArtifactError = \case
  InvalidArtifactStem stem -> "invalid generated artifact stem " <> quote stem
  DuplicateArtifactTarget path -> "more than one case resolves to artifact " <> quote path
  ArtifactAlreadyExists path -> "artifact already exists; use --overwrite to replace " <> quote path
  ArtifactPathIsSymbolicLink path -> "artifact path must not be a symbolic link: " <> quote path
  ArtifactTargetIsDirectory path -> "artifact target is a directory: " <> quote path
  ArtifactIoError path message -> "could not prepare artifacts under " <> quote path <> ": " <> message
  where
    quote = ("\"" <>) . (<> "\"") . Text.pack
