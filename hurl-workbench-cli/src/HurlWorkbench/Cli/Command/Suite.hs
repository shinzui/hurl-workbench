-- | @hurl-workbench test suite@: whole-suite preflight, optional managed
--   service ownership, bounded Hurl execution, and report summaries.
module HurlWorkbench.Cli.Command.Suite
  ( runSuiteCommand,
    runSuiteCommandWith,
  )
where

import Data.Generics.Labels ()
import Data.Set qualified as Set
import Data.Text qualified as Text
import HurlWorkbench.Cli.Command.Matrix (renderCaseSummary, replayCaptured)
import HurlWorkbench.Cli.Command.Run (buildRuntimeInputs)
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run (mkHurlRunner)
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Prepare (PreparationError (..))
import HurlWorkbench.Service.Resolve (renderServiceError)
import HurlWorkbench.Suite.Resolve qualified as Suite
import HurlWorkbench.Suite.Run qualified as Suite
import HurlWorkbench.Workflow.Render (RenderedWorkflow)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, (</>))

runSuiteCommand :: GlobalOptions -> FilePath -> SuiteCommandOptions -> IO CommandResult
runSuiteCommand = runSuiteCommandWith detectHurlCapabilities validateRenderedWorkflow

runSuiteCommandWith ::
  IO (Either DependencyError HurlCapabilities) ->
  (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) ->
  GlobalOptions ->
  FilePath ->
  SuiteCommandOptions ->
  IO CommandResult
runSuiteCommandWith detectCapabilities validateRendered global currentDirectory options =
  loadValidatedWorkspace global currentDirectory >>= \case
    Left errors -> pure (failure 2 errors)
    Right validated -> case validateOptions options of
      Just problem -> pure (failure 2 ["error: " <> problem])
      Nothing -> case buildRuntimeInputs (options ^. #bindings) (options ^. #hurl) of
        Left errors -> pure (failure 2 (map ("error: " <>) errors))
        Right (bindingInput, hurlOptions) ->
          detectCapabilities >>= \case
            Left err -> pure (failure 3 ["error: " <> renderDependencyError err])
            Right capabilities -> do
              let requestedReportDirectory = fmap resolvePath (options ^. #reportDirectory)
                  request =
                    Suite.SuiteRequest
                      { suiteName = options ^. #suite,
                        bindingInput,
                        hurlOptions,
                        suiteOptions =
                          Suite.SuiteOptions
                            { jobs = options ^. #jobs,
                              failFastOverride = options ^. #failFastOverride,
                              allowMutating = options ^. #allowMutating,
                              manageService = not (options ^. #externalService),
                              reportFormats = Set.fromList (options ^. #reportFormats),
                              reportDirectory = requestedReportDirectory,
                              overwriteReports = options ^. #overwrite
                            }
                      }
              Suite.runSuiteWith
                validateRendered
                (mkHurlRunner capabilities)
                (capabilities ^. #hurlfmt)
                validated
                request
                <&> \case
                  Left err ->
                    failure
                      (preflightExitCode err)
                      (map (("error: " <>) . Suite.renderSuitePreflightIssue) (toList (err ^. #issues)))
                  Right result ->
                    CommandResult
                      { stdoutLines = [],
                        stderrLines =
                          hurlCapabilityWarnings capabilities
                            <> replayCaptured (result ^. #cases)
                            <> map renderCaseSummary (toList (result ^. #cases))
                            <> renderServiceOutcome (result ^. #serviceOutcome)
                            <> maybe [] (pure . ("SUMMARY " <>) . Text.pack) (result ^. #summaryPath)
                            <> maybe [] (pure . ("ERROR " <>)) (result ^. #summaryError),
                        exitCode = result ^. #selectedExitCode
                      }
  where
    resolvePath path
      | isAbsolute path = path
      | otherwise = currentDirectory </> path

validateOptions :: SuiteCommandOptions -> Maybe Text
validateOptions options
  | options ^. #overwrite && isNothing (options ^. #reportDirectory) = Just "--overwrite requires --report-dir"
  | Set.size (Set.fromList (options ^. #reportFormats)) /= length (options ^. #reportFormats) = Just "each --report format may be requested at most once"
  | otherwise = Nothing

preflightExitCode :: Suite.SuitePreflightError -> Int
preflightExitCode error_ = maximum (2 : map issueExitCode (toList (error_ ^. #issues)))
  where
    issueExitCode = \case
      Suite.SuiteRunPreparationFailed (RunFormatFailed _ HurlfmtNotFound {}) -> 3
      Suite.SuiteRunPreparationFailed (RunFormatFailed _ HurlfmtFailed {}) -> 3
      _ -> 2

renderServiceOutcome :: Maybe Suite.ServiceOutcome -> [Text]
renderServiceOutcome = \case
  Nothing -> []
  Just Suite.ServiceStopped -> ["SERVICE stopped"]
  Just (Suite.ServiceFailed err) -> ["SERVICE failed (" <> renderServiceError err <> ")"]

failure :: Int -> [Text] -> CommandResult
failure status messages =
  CommandResult
    { stdoutLines = [],
      stderrLines = messages,
      exitCode = ExitFailure status
    }
