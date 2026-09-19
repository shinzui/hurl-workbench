-- | Failures that prevent a workspace from being located or decoded at all.
--   Semantic problems in a decoded workspace are reported separately as
--   'HurlWorkbench.Workspace.Validate.ValidationIssue' values.
module HurlWorkbench.Workspace.Error
  ( WorkspaceError (..),
    renderWorkspaceError,
  )
where

import Data.Text qualified as Text
import HurlWorkbench.Prelude
import Numeric.Natural (Natural)

-- | Why a workspace could not be discovered, read, or decoded.
data WorkspaceError
  = -- | An explicit @--workspace FILE@ does not name an existing file.
    ManifestNotFound !FilePath
  | -- | No @hurl-workbench.dhall@ exists in the start directory or any parent.
    NoWorkspaceFound !FilePath
  | -- | The manifest exists but could not be read as UTF-8 text.
    ManifestUnreadable !FilePath !Text
  | -- | Dhall parsing, import resolution, type checking, or decoding failed.
    DhallFailure !FilePath !Text
  | -- | The manifest's top level is not a record with a @schemaVersion@.
    MissingSchemaVersion !FilePath
  | -- | The manifest declares a schema version this build does not support.
    UnsupportedSchemaVersion !FilePath !Natural !Natural
  deriving stock (Generic, Eq, Show)

-- | Render an error for a human, naming the manifest path.
renderWorkspaceError :: WorkspaceError -> Text
renderWorkspaceError = \case
  ManifestNotFound path ->
    "workspace manifest not found: " <> Text.pack path
  NoWorkspaceFound start ->
    "no hurl-workbench.dhall found in "
      <> Text.pack start
      <> " or any parent directory (use --workspace FILE to name one)"
  ManifestUnreadable path reason ->
    "cannot read workspace manifest " <> Text.pack path <> ": " <> reason
  DhallFailure path reason ->
    "invalid Dhall in workspace manifest " <> Text.pack path <> ":\n" <> Text.strip reason
  MissingSchemaVersion path ->
    "workspace manifest "
      <> Text.pack path
      <> " must evaluate to a record with a Natural schemaVersion field"
  UnsupportedSchemaVersion path found supported ->
    "workspace manifest "
      <> Text.pack path
      <> " declares schemaVersion "
      <> Text.pack (show found)
      <> ", but this hurl-workbench supports only schemaVersion "
      <> Text.pack (show supported)
