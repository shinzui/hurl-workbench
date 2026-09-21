-- | Resolve all runtime values for a validated workflow. Plain values and
--   secrets remain separate from discovery through serialization.
module HurlWorkbench.Parameter.Resolve
  ( BindingInput (..),
    BindingSource (..),
    BindingLayer (..),
    SecretValue,
    SecretValueError (..),
    ResolvedBindings (..),
    BindingIssue (..),
    BindingError (..),
    emptyBindingInput,
    mkSecretValue,
    resolveParameters,
    resolveParameterSubset,
    resolveParametersWithLayers,
    resolveWorkflowBindings,
    resolveWorkflowBindingsWithLayers,
    resolveWorkflowBindingSubsetWithLayers,
    renderBindingError,
    renderBindingIssue,
  )
where

import Control.Exception (IOException, try)
import Data.Bifunctor (first)
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import HurlWorkbench.Parameter.Properties
import HurlWorkbench.Parameter.Resolve.Internal
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate (isValidEnvironmentName)
import System.Environment (lookupEnv)

emptyBindingInput :: BindingInput
emptyBindingInput =
  BindingInput
    { plainOverrides = Map.empty,
      secretEnvironmentOverrides = Map.empty,
      variableFiles = [],
      secretFiles = []
    }

resolveWorkflowBindings :: ValidatedWorkspace -> Workflow -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveWorkflowBindings validated workflow input =
  resolveParameters validated (Set.fromList (workflow ^. #parameters)) input

resolveWorkflowBindingsWithLayers :: ValidatedWorkspace -> Workflow -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveWorkflowBindingsWithLayers validated workflow layers input =
  resolveParametersWithLayers validated (Set.fromList (workflow ^. #parameters)) layers input

resolveWorkflowBindingSubsetWithLayers :: ValidatedWorkspace -> Workflow -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveWorkflowBindingSubsetWithLayers validated workflow layers input =
  resolveParametersWithMode False validated (Set.fromList (workflow ^. #parameters)) layers input

resolveParameters :: ValidatedWorkspace -> Set ParameterName -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveParameters validated selected = resolveParametersWithLayers validated selected []

-- | Resolve one consumer's parameter subset from a shared runtime input.
--   Bindings for other declared consumers are ignored, while selected names
--   retain the same kind and precedence validation as normal resolution.
resolveParameterSubset :: ValidatedWorkspace -> Set ParameterName -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveParameterSubset validated selected = resolveParametersWithMode False validated selected []

-- | Resolve runtime inputs over committed plain-value layers ordered from
--   highest to lowest precedence. Runtime overrides and variable files remain
--   above these layers; declared environments and defaults remain below them.
resolveParametersWithLayers :: ValidatedWorkspace -> Set ParameterName -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveParametersWithLayers = resolveParametersWithMode True

resolveParametersWithMode :: Bool -> ValidatedWorkspace -> Set ParameterName -> [BindingLayer] -> BindingInput -> IO (Either BindingError ResolvedBindings)
resolveParametersWithMode rejectUnselected validated selected layers input = do
  loadedVariables <- loadVariableFiles (input ^. #variableFiles)
  loadedSecrets <- loadSecretFiles (input ^. #secretFiles)
  case (loadedVariables, loadedSecrets) of
    (Left err, _) -> pure (Left err)
    (_, Left err) -> pure (Left err)
    (Right variableMaps, Right secretMaps) -> do
      let fileVariables = laterWins variableMaps
          fileSecrets = laterWins secretMaps
          explicitVariables = Map.map (,ExplicitVariable) (input ^. #plainOverrides)
          explicitSecrets = Map.mapWithKey (\_ env -> (env, ExplicitSecretEnvironment env)) (input ^. #secretEnvironmentOverrides)
          committedVariables = map sourcedLayer layers
          parameters = validatedParameters validated
          staticIssues =
            unknownSelected parameters selected
              <> [ issue
                 | rejectUnselected,
                   issue <-
                     unexpected selected explicitVariables
                       <> unexpected selected explicitSecrets
                       <> unexpected selected fileVariables
                       <> unexpected selected fileSecrets
                       <> concatMap (unexpected selected) committedVariables
                 ]
              <> kindMismatches parameters selected explicitVariables explicitSecrets fileVariables fileSecrets committedVariables
      resolved <- traverse (resolveOne parameters explicitVariables explicitSecrets fileVariables fileSecrets committedVariables) (Set.toAscList selected)
      let dynamicIssues = concatMap (\(issues, _, _) -> issues) resolved
          allIssues = staticIssues <> dynamicIssues
      pure $ case nonEmpty allIssues of
        Just issues -> Left (BindingIssues issues)
        Nothing ->
          Right
            ResolvedBindings
              { variables = Map.fromList (mapMaybe (\(_, variable, _) -> variable) resolved),
                secrets = Map.fromList (mapMaybe (\(_, _, secret) -> secret) resolved)
              }
  where
    sourcedLayer layer = Map.map (,(layer ^. #source)) (layer ^. #values)

type Sourced value = Map ParameterName (value, BindingSource)

loadVariableFiles :: [FilePath] -> IO (Either BindingError [Sourced HurlValueLiteral])
loadVariableFiles = loadFiles VariableProperties parseVariableProperties

loadSecretFiles :: [FilePath] -> IO (Either BindingError [Sourced Text])
loadSecretFiles = loadFiles SecretProperties parseSecretProperties

loadFiles :: PropertyFileKind -> (FilePath -> ByteString.ByteString -> Either PropertyError (Map ParameterName value)) -> [FilePath] -> IO (Either BindingError [Sourced value])
loadFiles kind parser = go []
  where
    go loaded [] = pure (Right (reverse loaded))
    go loaded (path : remaining) = do
      bytes <- try @IOException (ByteString.readFile path)
      case bytes of
        Left _err -> pure (Left (BindingFileReadError kind path))
        Right contents -> case parser path contents of
          Left err -> pure (Left (BindingPropertyError err))
          Right values ->
            let source = case kind of
                  VariableProperties -> VariableFile path
                  SecretProperties -> SecretFile path
             in go (Map.map (,source) values : loaded) remaining

laterWins :: [Sourced value] -> Sourced value
laterWins = foldl' (flip Map.union) Map.empty

unknownSelected :: Map ParameterName Parameter -> Set ParameterName -> [BindingIssue]
unknownSelected parameters selected =
  [UnknownDeclaredParameter name | name <- Set.toAscList selected, Map.notMember name parameters]

unexpected :: Set ParameterName -> Sourced value -> [BindingIssue]
unexpected selected values =
  [ UnexpectedBinding name source
  | (name, (_, source)) <- Map.toAscList values,
    name `Set.notMember` selected
  ]

kindMismatches :: Map ParameterName Parameter -> Set ParameterName -> Sourced HurlValueLiteral -> Sourced Text -> Sourced HurlValueLiteral -> Sourced Text -> [Sourced HurlValueLiteral] -> [BindingIssue]
kindMismatches parameters selected explicitVariables explicitSecrets fileVariables fileSecrets committedVariables =
  concatMap one (Set.toAscList selected)
  where
    one name = case Map.lookup name parameters of
      Nothing -> []
      Just parameter -> case parameter ^. #kind of
        Plain -> [BindingKindMismatch name Secret source | source <- sourcesFor name explicitSecrets <> sourcesFor name fileSecrets]
        Secret -> [BindingKindMismatch name Plain source | source <- sourcesFor name explicitVariables <> sourcesFor name fileVariables <> concatMap (sourcesFor name) committedVariables]

sourcesFor :: ParameterName -> Sourced value -> [BindingSource]
sourcesFor name values = maybe [] (pure . snd) (Map.lookup name values)

resolveOne :: Map ParameterName Parameter -> Sourced HurlValueLiteral -> Sourced Text -> Sourced HurlValueLiteral -> Sourced Text -> [Sourced HurlValueLiteral] -> ParameterName -> IO ([BindingIssue], Maybe (ParameterName, HurlValueLiteral), Maybe (ParameterName, SecretValue))
resolveOne parameters explicitVariables explicitSecrets fileVariables fileSecrets committedVariables name =
  case Map.lookup name parameters of
    Nothing -> pure ([], Nothing, Nothing)
    Just parameter -> case parameter ^. #kind of
      Plain -> do
        environmentValue <- traverse (lookupPlainEnvironment name) (parameter ^. #environment)
        let selectedValue =
              firstJust
                [ Right <$> Map.lookup name explicitVariables,
                  Right <$> Map.lookup name fileVariables,
                  firstLayerValue name committedVariables,
                  environmentValue,
                  Right . (,DefaultValue) <$> parameter ^. #defaultValue
                ]
        pure $ case selectedValue of
          Nothing -> ([MissingBinding name], Nothing, Nothing)
          Just (Left issue) -> ([issue], Nothing, Nothing)
          Just (Right (value, _source)) -> ([], Just (name, value), Nothing)
      Secret -> do
        explicitValue <- traverse (lookupSecretEnvironment name) (Map.lookup name explicitSecrets)
        declaredValue <- traverse (\env -> lookupSecretEnvironment name (env, DeclaredEnvironment env)) (parameter ^. #environment)
        let fileValue = case Map.lookup name fileSecrets of
              Nothing -> Nothing
              Just (value, source) -> Just (first (InvalidSecretBinding name source) (mkSecretValue value) <&> (,source))
            selectedValue = firstJust [explicitValue, fileValue, declaredValue]
        pure $ case selectedValue of
          Nothing -> ([MissingBinding name], Nothing, Nothing)
          Just (Left issue) -> ([issue], Nothing, Nothing)
          Just (Right (value, _source)) -> ([], Nothing, Just (name, value))

lookupPlainEnvironment :: ParameterName -> Text -> IO (Either BindingIssue (HurlValueLiteral, BindingSource))
lookupPlainEnvironment name environmentName
  | not (isValidEnvironmentName environmentName) =
      pure (Left (InvalidBindingEnvironmentName name environmentName (DeclaredEnvironment environmentName)))
  | otherwise = do
      value <- lookupEnv (Text.unpack environmentName)
      pure $ case value of
        Nothing -> Left (MissingBindingEnvironment name environmentName (DeclaredEnvironment environmentName))
        Just raw -> first (InvalidPlainBinding name (DeclaredEnvironment environmentName)) (mkHurlValueLiteral (Text.pack raw)) <&> (,DeclaredEnvironment environmentName)

lookupSecretEnvironment :: ParameterName -> (Text, BindingSource) -> IO (Either BindingIssue (SecretValue, BindingSource))
lookupSecretEnvironment name (environmentName, source)
  | not (isValidEnvironmentName environmentName) =
      pure (Left (InvalidBindingEnvironmentName name environmentName source))
  | otherwise = do
      value <- lookupEnv (Text.unpack environmentName)
      pure $ case value of
        Nothing -> Left (MissingBindingEnvironment name environmentName source)
        Just raw -> first (InvalidSecretBinding name source) (mkSecretValue (Text.pack raw)) <&> (,source)

firstJust :: [Maybe a] -> Maybe a
firstJust = \case
  [] -> Nothing
  Nothing : rest -> firstJust rest
  Just value : _ -> Just value

firstLayerValue :: ParameterName -> [Sourced value] -> Maybe (Either issue (value, BindingSource))
firstLayerValue name = firstJust . map (fmap Right . Map.lookup name)

renderBindingError :: BindingError -> Text
renderBindingError = \case
  BindingFileReadError kind path -> label kind <> " file could not be read: " <> Text.pack path
  BindingPropertyError err -> renderPropertyError err
  BindingIssues issues -> Text.intercalate "\n" (map renderBindingIssue (toList issues))
  where
    label VariableProperties = "variables"
    label SecretProperties = "secrets"

renderBindingIssue :: BindingIssue -> Text
renderBindingIssue = \case
  UnexpectedBinding name source -> "parameter " <> quoted name <> " from " <> renderSource source <> " is not declared by the selected workflow"
  BindingKindMismatch name expected source -> "parameter " <> quoted name <> " from " <> renderSource source <> " must be supplied as " <> kindName expected
  MissingBinding name -> "required parameter " <> quoted name <> " has no value"
  MissingBindingEnvironment name environmentName source -> "environment variable " <> quote environmentName <> " for parameter " <> quoted name <> " from " <> renderSource source <> " is not set"
  InvalidBindingEnvironmentName name environmentName source -> "environment variable name " <> quote environmentName <> " for parameter " <> quoted name <> " from " <> renderSource source <> " is invalid"
  InvalidPlainBinding name source err -> "plain parameter " <> quoted name <> " from " <> renderSource source <> " is invalid: " <> renderHurlValueLiteralError err
  InvalidSecretBinding name source err -> "secret parameter " <> quoted name <> " from " <> renderSource source <> " is invalid: " <> secretError err
  UnknownDeclaredParameter name -> "selected parameter " <> quoted name <> " does not exist in the validated workspace"
  where
    quoted = quote . unParameterName
    quote value = "\"" <> value <> "\""
    kindName Plain = "a plain value"
    kindName Secret = "a secret value"
    secretError SecretContainsLineBreakOrNul = "value contains a line break or NUL character, which Hurl secret files cannot carry"
    secretError SecretHasSurroundingWhitespace = "value has leading or trailing whitespace, which Hurl secret files would trim"

renderSource :: BindingSource -> Text
renderSource = \case
  ExplicitVariable -> "--variable"
  ExplicitSecretEnvironment env -> "--secret-env " <> env
  VariableFile path -> "variables file " <> Text.pack path
  SecretFile path -> "secrets file " <> Text.pack path
  CommittedBinding label -> "committed " <> label
  DeclaredEnvironment env -> "declared environment " <> env
  DefaultValue -> "the workspace default"
