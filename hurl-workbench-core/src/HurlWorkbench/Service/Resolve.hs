-- | Resolve a validated service definition against suite-level runtime
--   bindings. Per-recipe and per-case binding layers never enter this module.
module HurlWorkbench.Service.Resolve
  ( ResolvedCommand (..),
    ResolvedReadiness (..),
    ResolvedService (..),
    ServiceError (..),
    requiredServiceParameters,
    resolveService,
    renderServiceError,
  )
where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime)
import HurlWorkbench.Parameter.Resolve (ResolvedBindings (..))
import HurlWorkbench.Parameter.Resolve.Internal (secretValueText)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import Numeric.Natural (Natural)
import System.Exit (ExitCode)
import System.FilePath ((</>))
import System.Posix.Types (ProcessID)

data ResolvedCommand = ResolvedCommand
  { executable :: !FilePath,
    arguments :: ![String],
    workingDirectory :: !FilePath,
    environment :: ![(String, String)]
  }
  deriving stock (Generic, Eq)

instance Show ResolvedCommand where
  show command =
    "ResolvedCommand {executable="
      <> show (command ^. #executable)
      <> ", arguments="
      <> show (command ^. #arguments)
      <> ", workingDirectory="
      <> show (command ^. #workingDirectory)
      <> ", environment=<redacted>}"

data ResolvedReadiness
  = ResolvedHttpReadiness !Text !Int !Int !NominalDiffTime
  | ResolvedCommandReadiness !ResolvedCommand !Int !NominalDiffTime
  deriving stock (Generic, Eq, Show)

data ResolvedService = ResolvedService
  { name :: !ServiceName,
    processConfig :: !ResolvedCommand,
    readiness :: !ResolvedReadiness,
    shutdownTimeout :: !NominalDiffTime
  }
  deriving stock (Generic, Eq, Show)

data ServiceError
  = ServiceBindingMissing !ParameterName
  | ServiceBindingUnknown !ParameterName
  | ServiceReadinessSecretPlaceholder !ParameterName
  | ServiceReadinessMalformedPlaceholder !Text
  | ServiceReadinessInvalidUrl !Text !Text
  | ServiceSpawnFailed !FilePath !Text
  | ServiceProcessIdUnavailable !ServiceName
  | ServiceExitedBeforeReady !ServiceName !ExitCode
  | ServiceReadinessTimedOut !ServiceName
  | ServiceReadinessProbeStartFailed !FilePath !Text
  | ServiceExitedDuringCallback !ServiceName !ExitCode
  | ServiceShutdownFailed !ServiceName !(Maybe ProcessID) !Text
  deriving stock (Generic, Eq, Show)

data UrlPart
  = UrlText !Text
  | UrlParameter !ParameterName

requiredServiceParameters :: Service -> Either ServiceError (Set ParameterName)
requiredServiceParameters service = do
  readinessParameters <- case service ^. #readiness of
    HttpReadinessCheck http ->
      Set.fromList . mapMaybe partParameter <$> parseUrlTemplate (http ^. #url)
    CommandReadinessCheck probe -> pure (commandParameters (probe ^. #command))
  pure (commandParameters (service ^. #command) <> readinessParameters)
  where
    commandParameters command = Set.fromList (map (view #parameter) (command ^. #environment))
    partParameter = \case
      UrlText _ -> Nothing
      UrlParameter name -> Just name

resolveService :: ValidatedWorkspace -> ResolvedBindings -> Service -> Either ServiceError ResolvedService
resolveService validated bindings service = do
  processConfig <- resolveCommand validated bindings (service ^. #command)
  readiness <- case service ^. #readiness of
    HttpReadinessCheck http ->
      ResolvedHttpReadiness
        <$> substituteReadinessUrl validated bindings (http ^. #url)
        <*> pure (fromIntegral (http ^. #expectedStatus))
        <*> pure (milliseconds (http ^. #intervalMilliseconds))
        <*> pure (seconds (http ^. #timeoutSeconds))
    CommandReadinessCheck probe ->
      ResolvedCommandReadiness
        <$> resolveCommand validated bindings (probe ^. #command)
        <*> pure (milliseconds (probe ^. #intervalMilliseconds))
        <*> pure (seconds (probe ^. #timeoutSeconds))
  pure
    ResolvedService
      { name = service ^. #name,
        processConfig,
        readiness,
        shutdownTimeout = seconds (service ^. #shutdownTimeoutSeconds)
      }

resolveCommand :: ValidatedWorkspace -> ResolvedBindings -> CommandSpec -> Either ServiceError ResolvedCommand
resolveCommand validated bindings command = do
  environment <- traverse resolveEnvironmentBinding (command ^. #environment)
  let WorkspaceRoot root = validatedRoot validated
      workingDirectory = maybe root (root </>) (command ^. #workingDirectory)
  pure
    ResolvedCommand
      { executable = Text.unpack (command ^. #executable),
        arguments = map Text.unpack (command ^. #arguments),
        workingDirectory,
        environment
      }
  where
    resolveEnvironmentBinding binding = do
      value <- resolveValue (binding ^. #parameter)
      pure (Text.unpack (binding ^. #variable), Text.unpack value)

    resolveValue name =
      case Map.lookup name (bindings ^. #variables) of
        Just value -> Right (hurlValueLiteralText value)
        Nothing -> case Map.lookup name (bindings ^. #secrets) of
          Just value -> Right (secretValueText value)
          Nothing -> Left (ServiceBindingMissing name)

substituteReadinessUrl :: ValidatedWorkspace -> ResolvedBindings -> Text -> Either ServiceError Text
substituteReadinessUrl validated bindings template = do
  urlParts <- parseUrlTemplate template
  Text.concat <$> traverse renderPart urlParts
  where
    renderPart = \case
      UrlText value -> Right value
      UrlParameter name -> readinessValue name

    readinessValue name = case lookupParameter name validated of
      Nothing -> Left (ServiceBindingUnknown name)
      Just parameter
        | parameter ^. #kind == Secret -> Left (ServiceReadinessSecretPlaceholder name)
        | otherwise -> case Map.lookup name (bindings ^. #variables) of
            Nothing -> Left (ServiceBindingMissing name)
            Just value -> Right (hurlValueLiteralText value)

parseUrlTemplate :: Text -> Either ServiceError [UrlPart]
parseUrlTemplate template = go [] template
  where
    go accumulated remaining =
      case Text.breakOn "{{" remaining of
        (prefix, rest)
          | Text.null rest ->
              if "}}" `Text.isInfixOf` prefix
                then malformed
                else Right (reverse (prependText prefix accumulated))
          | otherwise ->
              let afterOpen = Text.drop 2 rest
                  (rawName, close) = Text.breakOn "}}" afterOpen
               in if Text.null close || Text.null rawName || "{{" `Text.isInfixOf` rawName
                    then malformed
                    else go (UrlParameter (ParameterName rawName) : prependText prefix accumulated) (Text.drop 2 close)

    prependText value accumulated
      | Text.null value = accumulated
      | otherwise = UrlText value : accumulated
    malformed = Left (ServiceReadinessMalformedPlaceholder template)

milliseconds :: Natural -> Int
milliseconds value = fromIntegral value * 1000

seconds :: Natural -> NominalDiffTime
seconds = fromIntegral

renderServiceError :: ServiceError -> Text
renderServiceError = \case
  ServiceBindingMissing name -> "service parameter " <> quotedParameter name <> " has no suite-level runtime value"
  ServiceBindingUnknown name -> "readiness URL refers to unknown parameter " <> quotedParameter name
  ServiceReadinessSecretPlaceholder name -> "readiness URL must not contain secret parameter " <> quotedParameter name
  ServiceReadinessMalformedPlaceholder value -> "readiness URL contains a malformed placeholder near " <> quote value
  ServiceReadinessInvalidUrl url message -> "invalid readiness URL " <> quote url <> ": " <> message
  ServiceSpawnFailed executable message -> "service executable " <> quote (Text.pack executable) <> " could not be started: " <> message
  ServiceProcessIdUnavailable name -> "service " <> quotedService name <> " started without an observable process id"
  ServiceExitedBeforeReady name exitCode -> "service " <> quotedService name <> " exited before readiness with " <> Text.pack (show exitCode)
  ServiceReadinessTimedOut name -> "service " <> quotedService name <> " did not become ready before its timeout"
  ServiceReadinessProbeStartFailed executable message -> "readiness executable " <> quote (Text.pack executable) <> " could not be started: " <> message
  ServiceExitedDuringCallback name exitCode -> "service " <> quotedService name <> " exited while its suite was running with " <> Text.pack (show exitCode)
  ServiceShutdownFailed name processId message ->
    "service "
      <> quotedService name
      <> maybe "" ((" (pid " <>) . (<> ")") . Text.pack . show) processId
      <> " could not be shut down cleanly: "
      <> message
  where
    quotedParameter = quote . unParameterName
    quotedService = quote . unServiceName
    quote value = "\"" <> value <> "\""
