-- | @hurl-workbench validate@: report the manifest path and entity counts,
--   or every validation issue at once.
module HurlWorkbench.Cli.Command.Validate
  ( runValidate,
    validateSummary,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import HurlWorkbench.Cli.Options (GlobalOptions)
import HurlWorkbench.Cli.Output (CommandResult, plural, success)
import HurlWorkbench.Cli.Workspace (withValidatedWorkspace)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context (ValidatedWorkspace, validatedManifestPath, validatedWorkspace)

runValidate :: GlobalOptions -> FilePath -> IO CommandResult
runValidate options currentDirectory =
  withValidatedWorkspace options currentDirectory (success . validateSummary)

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
