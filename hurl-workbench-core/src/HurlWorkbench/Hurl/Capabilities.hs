-- | Detection of the external Hurl toolchain used by execution commands.
module HurlWorkbench.Hurl.Capabilities
  ( HurlCapabilities (..),
    detectHurlCapabilities,
    parseHurlVersion,
    hurlCapabilityWarnings,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Generics.Labels ()
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Version (Version, makeVersion, versionBranch)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.Process.Typed (proc, readProcess)

data HurlCapabilities = HurlCapabilities
  { hurlExecutable :: !FilePath,
    hurlVersion :: !Version,
    hurlfmt :: !HurlfmtCapabilities
  }
  deriving stock (Generic, Eq, Show)

detectHurlCapabilities :: IO (Either DependencyError HurlCapabilities)
detectHurlCapabilities = do
  located <- findExecutable "hurl"
  case located of
    Nothing -> pure (Left (DependencyNotFound "hurl" "hurl"))
    Just executable -> do
      probed <- try @IOException (readProcess (proc executable ["--version"]))
      case probed of
        Left err -> pure (Left (DependencyNotFound "hurl" (executable <> ": " <> displayException err)))
        Right (exitCode, stdout, stderr)
          | exitCode /= ExitSuccess -> pure (Left (DependencyProbeFailed "hurl" exitCode (decodeOutput stderr)))
          | otherwise -> case parseHurlVersion (decodeOutput stdout) of
              Nothing -> pure (Left (DependencyVersionUnrecognized "hurl" (decodeOutput stdout)))
              Just version
                | version < makeVersion [8, 0, 0] -> pure (Left (DependencyVersionUnsupported "hurl" version (makeVersion [8, 0, 0])))
                | otherwise ->
                    detectHurlfmtCapabilities <&> fmap (HurlCapabilities executable version)

parseHurlVersion :: Text -> Maybe Version
parseHurlVersion = parseHurlfmtVersion

hurlCapabilityWarnings :: HurlCapabilities -> [Text]
hurlCapabilityWarnings capabilities =
  [ "warning: Hurl major version "
      <> Text.pack (show major)
      <> " is newer than the tested Hurl 8.x adapter"
  | let major = case versionBranch (capabilities ^. #hurlVersion) of
          value : _ -> value
          [] -> 0,
    major > 8
  ]

decodeOutput :: LazyByteString.ByteString -> Text
decodeOutput = Text.Encoding.decodeUtf8With lenientDecode . LazyByteString.toStrict
