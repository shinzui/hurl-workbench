module HurlWorkbench.Cli.Command.Run
  ( runExecute,
    runExecuteWith,
  )
where

import Data.Bifunctor (first)
import Data.Generics.Labels ()
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Capabilities
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Hurl.Run
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workflow.Resolve
import HurlWorkbench.Workspace.Context (lookupWorkflow)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate (isValidEnvironmentName, isValidParameterName)
import System.Exit (ExitCode (..))

runExecute :: GlobalOptions -> FilePath -> HurlRunMode -> ExecuteOptions -> IO CommandResult
runExecute = runExecuteWith detectHurlCapabilities validateRenderedWorkflow

runExecuteWith ::
  IO (Either DependencyError HurlCapabilities) ->
  (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) ->
  GlobalOptions ->
  FilePath ->
  HurlRunMode ->
  ExecuteOptions ->
  IO CommandResult
runExecuteWith detectCapabilities validateRendered global currentDirectory mode executeOptions =
  loadValidatedWorkspace global currentDirectory >>= \case
    Left errors -> pure (workbenchFailure 2 errors)
    Right validated -> case lookupWorkflow (executeOptions ^. #workflow) validated of
      Nothing -> pure (workbenchFailure 2 ["error: unknown workflow \"" <> unWorkflowName (executeOptions ^. #workflow) <> "\""])
      Just workflow -> case resolveWorkflow validated (executeOptions ^. #workflow) of
        Left err -> pure (workbenchFailure 2 ["error: " <> renderWorkflowError err])
        Right resolved ->
          renderWorkflow resolved >>= \case
            Left err -> pure (workbenchFailure 2 ["error: " <> renderRenderError err])
            Right rendered ->
              detectCapabilities >>= \case
                Left err -> pure (workbenchFailure 3 ["error: " <> renderDependencyError err])
                Right capabilities ->
                  validateRendered (capabilities ^. #hurlfmt) rendered >>= \case
                    Left err -> pure (workbenchFailure (hurlfmtExitCode err) ["error: " <> renderHurlfmtError err])
                    Right () -> case buildInputs executeOptions of
                      Left errors -> pure (workbenchFailure 2 (map ("error: " <>) errors))
                      Right (bindingInput, hurlOptions) ->
                        resolveWorkflowBindings validated workflow bindingInput >>= \case
                          Left err -> pure (workbenchFailure 2 (map ("error: " <>) (Text.lines (renderBindingError err))))
                          Right bindings -> do
                            executed <-
                              runHurl
                                (mkHurlRunner capabilities)
                                RunRequest
                                  { renderedWorkflow = rendered,
                                    mode,
                                    bindings,
                                    options = hurlOptions,
                                    outputPolicy = InheritRunOutput,
                                    reportTargets = []
                                  }
                            pure $ case executed of
                              Left err ->
                                workbenchFailure
                                  (runStartExitCode err)
                                  ["error: " <> renderRunStartError err]
                              Right result ->
                                CommandResult
                                  { stdoutLines = [],
                                    stderrLines = hurlCapabilityWarnings capabilities,
                                    exitCode = result ^. #exitCode
                                  }

buildInputs :: ExecuteOptions -> Either [Text] (BindingInput, HurlOptions)
buildInputs executeOptions = do
  plain <- parseUnique "--variable" parsePlain (executeOptions ^. #bindings . #variables)
  secretEnvironments <- parseUnique "--secret-env" parseSecretEnvironment (executeOptions ^. #bindings . #secretEnvironments)
  additional <- collect (map (first renderCliHurlOptionError . mkAllowedHurlArgument) (executeOptions ^. #hurl . #additionalArguments))
  let cli = executeOptions ^. #hurl
  pure
    ( BindingInput
        { plainOverrides = plain,
          secretEnvironmentOverrides = secretEnvironments,
          variableFiles = executeOptions ^. #bindings . #variableFiles,
          secretFiles = executeOptions ^. #bindings . #secretFiles
        },
      HurlOptions
        { connectTimeoutSeconds = cli ^. #connectTimeoutSeconds,
          maxTimeSeconds = cli ^. #maxTimeSeconds,
          retryCount = cli ^. #retryCount,
          retryIntervalMilliseconds = cli ^. #retryIntervalMilliseconds,
          insecureTls = cli ^. #insecureTls,
          includeHeaders = cli ^. #includeHeaders,
          jsonOutput = cli ^. #jsonOutput,
          verbosity = cli ^. #verbosity,
          curlExportPath = cli ^. #curlExportPath,
          additionalArguments = additional
        }
    )

parsePlain :: Text -> Either Text (ParameterName, HurlValueLiteral)
parsePlain raw = do
  (name, value) <- splitAssignment "--variable" raw
  validateParameterName "--variable" name
  literal <- first (\err -> "--variable " <> name <> ": " <> renderHurlValueLiteralError err) (mkHurlValueLiteral value)
  pure (ParameterName name, literal)

parseSecretEnvironment :: Text -> Either Text (ParameterName, Text)
parseSecretEnvironment raw = do
  (name, environment) <- splitAssignment "--secret-env" raw
  validateParameterName "--secret-env" name
  unlessEither (isValidEnvironmentName environment) ("--secret-env " <> name <> " names invalid environment variable " <> quote environment)
  pure (ParameterName name, environment)

splitAssignment :: Text -> Text -> Either Text (Text, Text)
splitAssignment option raw = case Text.breakOn "=" raw of
  (name, rest)
    | Text.null rest || Text.null name -> Left (option <> " expects NAME=VALUE")
    | otherwise -> Right (name, Text.drop 1 rest)

validateParameterName :: Text -> Text -> Either Text ()
validateParameterName option name =
  unlessEither (isValidParameterName name) (option <> " has invalid parameter name " <> quote name)

parseUnique :: (Ord key) => Text -> (value -> Either Text (key, parsed)) -> [value] -> Either [Text] (Map key parsed)
parseUnique option parser values = do
  parsed <- collect (map parser values)
  let duplicateKeys = duplicates (map fst parsed)
  case duplicateKeys of
    [] -> Right (Map.fromList parsed)
    _ -> Left [option <> " defines the same parameter more than once"]

collect :: [Either Text value] -> Either [Text] [value]
collect values = case [err | Left err <- values] of
  [] -> Right [value | Right value <- values]
  errors -> Left errors

duplicates :: (Ord value) => [value] -> [value]
duplicates values = [value | value : _duplicate : _rest <- groupSorted (sort values)]
  where
    groupSorted [] = []
    groupSorted (value : remaining) =
      let (same, rest) = span (== value) remaining
       in (value : same) : groupSorted rest

unlessEither :: Bool -> err -> Either err ()
unlessEither condition err = if condition then Right () else Left err

workbenchFailure :: Int -> [Text] -> CommandResult
workbenchFailure code errors =
  CommandResult
    { stdoutLines = [],
      stderrLines = errors,
      exitCode = ExitFailure code
    }

hurlfmtExitCode :: HurlfmtError -> Int
hurlfmtExitCode = \case
  InvalidHurl {} -> 2
  HurlfmtNotFound {} -> 3
  HurlfmtFailed {} -> 3

runStartExitCode :: RunStartError -> Int
runStartExitCode = \case
  HurlSpawnFailed {} -> 3
  InvalidRunOptions {} -> 2
  SecureRunFileError {} -> 2

quote :: Text -> Text
quote value = "\"" <> value <> "\""

renderCliHurlOptionError :: HurlOptionError -> Text
renderCliHurlOptionError = \case
  UnsupportedHurlArgument rawArgument -> "unsupported --hurl-arg " <> rawArgument
  NegativeOption name value -> name <> " must not be negative, got " <> Text.pack (show value)
  DuplicateReportFormat format -> "duplicate " <> format <> " report target"
