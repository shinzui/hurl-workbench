-- | @hurl-workbench validate@: report the manifest path and entity counts,
--   or every validation issue at once.
module HurlWorkbench.Cli.Command.Validate
  ( runValidate,
    runValidateWith,
    validateSummary,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import HurlWorkbench.Cli.Options (GlobalOptions)
import HurlWorkbench.Cli.Output (CommandResult, failure, plural, success)
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context (ValidatedWorkspace, validatedManifestPath, validatedWorkspace)

runValidate :: GlobalOptions -> FilePath -> IO CommandResult
runValidate = runValidateWith detectHurlfmtCapabilities validateWorkspaceSyntax

runValidateWith ::
  IO (Either DependencyError HurlfmtCapabilities) ->
  (HurlfmtCapabilities -> ValidatedWorkspace -> IO (Either DependencyError [WorkflowSyntaxError])) ->
  GlobalOptions ->
  FilePath ->
  IO CommandResult
runValidateWith detectCapabilities validateSyntax options currentDirectory =
  loadValidatedWorkspace options currentDirectory >>= \case
    Left errors -> pure (failure errors)
    Right validated ->
      detectCapabilities >>= \case
        Left err -> pure (failure ["error: " <> renderDependencyError err])
        Right capabilities ->
          validateSyntax capabilities validated >>= \case
            Left err -> pure (failure ["error: " <> renderDependencyError err])
            Right [] -> pure (success (validateSummary validated))
            Right issues ->
              pure
                ( failure
                    ( ["Invalid Hurl syntax: " <> Text.pack (validatedManifestPath validated)]
                        <> map (("  " <>) . indentMultiline . renderWorkflowSyntaxError) issues
                        <> [plural (length issues) "workflow issue" "workflow issues" <> " found"]
                    )
                )

indentMultiline :: Text -> Text
indentMultiline = Text.replace "\n" "\n  "

validateSummary :: ValidatedWorkspace -> [Text]
validateSummary vw =
  [ "Valid workspace: " <> Text.pack (validatedManifestPath vw),
    Text.intercalate
      ", "
      [ plural (length (ws ^. #parameters)) "parameter" "parameters",
        plural (length (ws ^. #fragments)) "fragment" "fragments",
        plural (length (ws ^. #workflows)) "workflow" "workflows",
        plural (length (ws ^. #recipes)) "recipe" "recipes",
        plural (length (ws ^. #matrices)) "matrix" "matrices",
        plural (length (ws ^. #services)) "service" "services",
        plural (length (ws ^. #suites)) "suite" "suites"
      ]
  ]
  where
    ws = validatedWorkspace vw
