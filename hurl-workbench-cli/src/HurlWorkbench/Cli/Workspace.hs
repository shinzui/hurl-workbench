-- | Load and validate the workspace once for every command. Command
--   handlers receive only a 'ValidatedWorkspace'.
module HurlWorkbench.Cli.Workspace
  ( loadValidatedWorkspace,
    withValidatedWorkspace,
    renderIssueReport,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import HurlWorkbench.Cli.Options (GlobalOptions)
import HurlWorkbench.Cli.Output (CommandResult, failure, plural)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context (ValidatedWorkspace, WorkspaceContext, loadWorkspaceContext)
import HurlWorkbench.Workspace.Discover (discoverWorkspace)
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Validate (ValidationIssue, renderValidationIssue, validateWorkspace)

-- | Discover, decode, and validate. The start directory is the process's
--   current directory, passed explicitly so tests can choose it.
loadValidatedWorkspace :: GlobalOptions -> FilePath -> IO (Either [Text] ValidatedWorkspace)
loadValidatedWorkspace options currentDirectory = do
  discovered <- discoverWorkspace (options ^. #workspace) currentDirectory
  case discovered of
    Left err -> pure (Left ["error: " <> renderWorkspaceError err])
    Right source ->
      loadWorkspaceContext source >>= \case
        Left err -> pure (Left ["error: " <> renderWorkspaceError err])
        Right context ->
          validateWorkspace context <&> \case
            Left issues -> Left (renderIssueReport context issues)
            Right validated -> Right validated

withValidatedWorkspace :: GlobalOptions -> FilePath -> (ValidatedWorkspace -> CommandResult) -> IO CommandResult
withValidatedWorkspace options currentDirectory handler =
  either failure handler <$> loadValidatedWorkspace options currentDirectory

renderIssueReport :: WorkspaceContext -> NonEmpty ValidationIssue -> [Text]
renderIssueReport context issues =
  ["Invalid workspace: " <> Text.pack (context ^. #manifestPath)]
    <> map (("  " <>) . renderValidationIssue) (toList issues)
    <> [plural (length issues) "issue" "issues" <> " found"]
