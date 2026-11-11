-- | Evaluate a @hurl-workbench.dhall@ manifest and decode it into a
--   'Workspace'.
--
--   Decoding checks @schemaVersion@ on the evaluated expression before the
--   typed decode, so a manifest written for another schema version is
--   reported as such instead of as an opaque Dhall type mismatch.
module HurlWorkbench.Workspace.Decode
  ( decodeWorkspaceFile,
  )
where

import Control.Exception (SomeAsyncException, SomeException, fromException, throwIO, try)
import Data.ByteString qualified as ByteString
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Void (Void)
import Dhall qualified
import Dhall.Core qualified as Dhall.Core
import Dhall.Map qualified
import Dhall.Parser (Src)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Error (WorkspaceError (..))
import HurlWorkbench.Workspace.Types (Workspace, supportedSchemaVersion)
import Numeric.Natural (Natural)
import System.FilePath (takeDirectory)

-- | Read, evaluate, version-check, and decode a manifest. Relative imports
--   inside the manifest resolve against the manifest's own directory. No
--   JSON or YAML fallback exists.
decodeWorkspaceFile :: FilePath -> IO (Either WorkspaceError Workspace)
decodeWorkspaceFile path = do
  readResult <- trySync (ByteString.readFile path)
  case readResult of
    Left exception -> pure (Left (ManifestUnreadable path (renderException exception)))
    Right bytes -> case Text.Encoding.decodeUtf8' bytes of
      Left exception -> pure (Left (ManifestUnreadable path (renderException exception)))
      Right source -> decodeSource source
  where
    settings =
      Dhall.defaultInputSettings
        & Dhall.rootDirectory
        .~ takeDirectory path
        & Dhall.sourceName
        .~ path

    decoder = Dhall.auto @Workspace

    decodeSource source = do
      evaluated <- trySync $ do
        parsed <- Dhall.parseWithSettings settings source
        resolved <- Dhall.resolveWithSettings settings parsed
        Dhall.typecheckWithSettings settings resolved
        pure resolved
      case evaluated of
        Left exception -> pure (Left (DhallFailure path (renderException exception)))
        Right resolved -> do
          let normalized = Dhall.normalizeWithSettings settings resolved
          case schemaVersionOf normalized of
            Nothing -> pure (Left (MissingSchemaVersion path))
            Just version
              | version /= supportedSchemaVersion ->
                  pure (Left (UnsupportedSchemaVersion path version supportedSchemaVersion))
              | otherwise -> decodeTyped (normalizeCommandPolicies normalized)

    decodeTyped normalized = do
      expected <- trySync (Dhall.expectWithSettings settings decoder normalized)
      pure $ case expected of
        Left exception -> Left (DhallFailure path (renderException exception))
        Right () -> case Dhall.toMonadic (Dhall.extract decoder normalized) of
          Right workspace -> Right workspace
          Left errors -> Left (DhallFailure path (renderException errors))

-- | Find a literal @schemaVersion : Natural@ field on a normalized record.
schemaVersionOf :: Dhall.Core.Expr Src Void -> Maybe Natural
schemaVersionOf = \case
  Dhall.Core.RecordLit fields ->
    case Dhall.Core.recordFieldValue <$> Dhall.Map.lookup "schemaVersion" fields of
      Just (Dhall.Core.NaturalLit version) -> Just version
      _ -> Nothing
  _ -> Nothing

-- | Like 'try', but never intercepts asynchronous exceptions.
trySync :: IO a -> IO (Either SomeException a)
trySync action = do
  result <- try action
  case result of
    Left exception
      | Just (_ :: SomeAsyncException) <- fromException exception -> throwIO exception
    other -> pure other

-- | Render a library exception as plain text. Dhall colors some messages
--   with ANSI escape sequences, which are removed so redirected output stays
--   readable.
renderException :: (Show e) => e -> Text
renderException = stripAnsi . Text.pack . show

-- | Remove ANSI CSI sequences such as @ESC[1;31m@.
stripAnsi :: Text -> Text
stripAnsi text = case Text.breakOn "\ESC[" text of
  (before, rest)
    | Text.null rest -> before
    | otherwise ->
        let afterIntroducer = Text.drop 2 rest
            (_, final) = Text.span (\c -> c >= ' ' && c <= '?') afterIntroducer
         in before <> stripAnsi (Text.drop 1 final)

-- | Upgrade only the managed-service subtree, including the command types in
-- readiness unions and empty-list annotations. User expressions are typechecked
-- before this pass; explicit policy fields are never replaced.
normalizeCommandPolicies :: Dhall.Core.Expr Src Void -> Dhall.Core.Expr Src Void
normalizeCommandPolicies (Dhall.Core.RecordLit fields) =
  Dhall.Core.RecordLit
    ( Dhall.Map.fromList
        [(key, if key == "services" then field {Dhall.Core.recordFieldValue = upgrade (Dhall.Core.recordFieldValue field)} else field) | (key, field) <- Dhall.Map.toList fields]
    )
  where
    policyType = Dhall.Core.Union (Dhall.Map.fromList [("Inherit", Nothing), ("Clean", Just (Dhall.Core.App Dhall.Core.List Dhall.Core.Text))])
    inherited = Dhall.Core.Field policyType (Dhall.Core.makeFieldSelection "Inherit")
    upgrade expression =
      let nested = runIdentity (Dhall.Core.subExpressions (Identity . upgrade) expression)
          add value record =
            if all (\key -> isJust (Dhall.Map.lookup key record)) ["executable", "arguments", "workingDirectory", "environment"]
              && not (isJust (Dhall.Map.lookup "environmentPolicy" record))
              then Dhall.Map.insert "environmentPolicy" (Dhall.Core.makeRecordField value) record
              else record
       in case nested of
            Dhall.Core.RecordLit record -> Dhall.Core.RecordLit (add inherited record)
            Dhall.Core.Record record -> Dhall.Core.Record (add policyType record)
            other -> other
normalizeCommandPolicies other = other
