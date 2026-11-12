-- | Private caller-owned fixture assignments. Only full verification produces
-- executable per-scenario inputs; raw provider values never appear in errors.
module HurlWorkbench.Suite.Scenario
  ( ScenarioInputs (..),
    ScenarioAssignment (..),
    ScenarioBinding (..),
    ScenarioSecret (..),
    VerifiedScenarioInputs,
    ScenarioIssue (..),
    decodeScenarioInputs,
    loadScenarioInputs,
    verifyScenarioInputs,
    scenarioBindingInput,
    renderScenarioIssue,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser)
import Data.Bifunctor (first)
import Data.Bits ((.&.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as Char8
import Data.Char (isControl, isSpace)
import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import HurlWorkbench.Parameter.Properties
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate (isValidEntityName, isValidEnvironmentName)
import Network.HTTP.Client qualified as HTTP
import System.FilePath (splitDirectories)
import System.Posix.Files
  ( fileMode,
    getSymbolicLinkStatus,
    groupModes,
    isRegularFile,
    otherModes,
    unionFileModes,
  )

newtype ScenarioInputs = ScenarioInputs [ScenarioAssignment]
  deriving stock (Generic, Eq)

data ScenarioAssignment = ScenarioAssignment
  { scenario :: !FilePath,
    fixtureId :: !Text,
    endpoint :: !Text,
    endpointParameter :: !ParameterName,
    bindings :: ![ScenarioBinding],
    secretEnvironment :: ![ScenarioSecret]
  }
  deriving stock (Generic, Eq)

data ScenarioBinding = ScenarioBinding
  { parameter :: !ParameterName,
    value :: !Text
  }
  deriving stock (Generic, Eq)

data ScenarioSecret = ScenarioSecret
  { parameter :: !ParameterName,
    variable :: !Text
  }
  deriving stock (Generic, Eq)

newtype VerifiedScenarioInputs = VerifiedScenarioInputs (Map FilePath BindingInput)

instance Show ScenarioInputs where show _ = "ScenarioInputs <redacted>"

instance Show ScenarioAssignment where show _ = "ScenarioAssignment <redacted>"

instance Show ScenarioBinding where show _ = "ScenarioBinding <redacted>"

instance Show ScenarioSecret where show _ = "ScenarioSecret <redacted>"

instance Show VerifiedScenarioInputs where show _ = "VerifiedScenarioInputs <redacted>"

data ScenarioIssue
  = ScenarioFileUnreadable
  | ScenarioFileNotPrivateRegular
  | ScenarioMalformedInput
  | ScenarioUnsupportedVersion
  | ScenarioInvalidLabel
  | ScenarioAssignmentMismatch
  | ScenarioDuplicateFixture
  | ScenarioInvalidFixture
  | ScenarioDuplicateEndpoint
  | ScenarioInvalidEndpoint
  | ScenarioInvalidParameter
  | ScenarioDuplicateParameter
  | ScenarioConflictingBinding
  | ScenarioRuntimeInputFailed
  deriving stock (Generic, Eq, Show)

instance Aeson.FromJSON ScenarioInputs where
  parseJSON = Aeson.withObject "scenario-inputs" $ \object -> do
    exactFields ["version", "scenarios"] object
    version <- object Aeson..: "version" :: Parser Int
    unless (version == 1) (fail "unsupported-version")
    ScenarioInputs <$> object Aeson..: "scenarios"

instance Aeson.FromJSON ScenarioAssignment where
  parseJSON = Aeson.withObject "assignment" $ \object -> do
    exactFields ["scenario", "fixtureId", "endpoint", "endpointParameter", "bindings", "secretEnvironment"] object
    ScenarioAssignment <$> object Aeson..: "scenario" <*> object Aeson..: "fixtureId" <*> object Aeson..: "endpoint" <*> (ParameterName <$> object Aeson..: "endpointParameter") <*> object Aeson..: "bindings" <*> object Aeson..: "secretEnvironment"

instance Aeson.FromJSON ScenarioBinding where
  parseJSON = Aeson.withObject "binding" $ \object -> do
    exactFields ["parameter", "value"] object
    ScenarioBinding <$> (ParameterName <$> object Aeson..: "parameter") <*> object Aeson..: "value"

instance Aeson.FromJSON ScenarioSecret where
  parseJSON = Aeson.withObject "secret" $ \object -> do
    exactFields ["parameter", "variable"] object
    ScenarioSecret <$> (ParameterName <$> object Aeson..: "parameter") <*> object Aeson..: "variable"

exactFields :: [Aeson.Key] -> Aeson.Object -> Parser ()
exactFields expected object = unless (Set.fromList expected == Set.fromList (KeyMap.keys object)) (fail "invalid-fields")

decodeScenarioInputs :: ByteString.ByteString -> Either ScenarioIssue ScenarioInputs
decodeScenarioInputs bytes = case Aeson.eitherDecodeStrict @Aeson.Value bytes of
  Left _ -> Left ScenarioMalformedInput
  Right (Aeson.Object object)
    | Just (Aeson.Number version) <- KeyMap.lookup "version" object, version /= 1 -> Left ScenarioUnsupportedVersion
  Right _ -> first (const ScenarioMalformedInput) (Aeson.eitherDecodeStrict bytes)

loadScenarioInputs :: FilePath -> IO (Either ScenarioIssue ScenarioInputs)
loadScenarioInputs path = do
  status <- try @IOException (getSymbolicLinkStatus path)
  case status of
    Left _ -> pure (Left ScenarioFileUnreadable)
    Right file
      | not (isRegularFile file) || fileMode file .&. (groupModes `unionFileModes` otherModes) /= 0 -> pure (Left ScenarioFileNotPrivateRegular)
      | otherwise -> fmap (either (const (Left ScenarioFileUnreadable)) decodeScenarioInputs) (try @IOException (ByteString.readFile path))

-- | Validate the entire assignment and common input before any run preparation.
-- File channels are inspected for conflicting names; the existing binding
-- resolver retains ordinary suite input precedence.
verifyScenarioInputs :: ValidatedWorkspace -> [ExpandedRun] -> BindingInput -> ScenarioInputs -> IO (Either ScenarioIssue VerifiedScenarioInputs)
verifyScenarioInputs workspace runs common (ScenarioInputs assignments) = do
  loaded <- snapshotInputs common
  origins <- traverse (endpointOrigin . view #endpoint) assignments
  pure $ do
    (input, fileNames) <- loaded
    endpointKeys <- sequence origins
    let expected = map (view #artifactStem) runs
        labels = map (view #scenario) assignments
    ensure (all validLabel labels) ScenarioInvalidLabel
    ensure (unique expected && unique labels && Set.fromList expected == Set.fromList labels) ScenarioAssignmentMismatch
    ensure (all (validFixture . view #fixtureId) assignments) ScenarioInvalidFixture
    ensure (unique (map (view #fixtureId) assignments)) ScenarioDuplicateFixture
    ensure (unique endpointKeys) ScenarioDuplicateEndpoint
    let assignmentsByStem = Map.fromList [(assignment ^. #scenario, assignment) | assignment <- assignments]
    verified <- traverse (verifyRun input fileNames assignmentsByStem) runs
    pure (VerifiedScenarioInputs (Map.fromList verified))
  where
    verifyRun input fileNames assignmentsByStem run = do
      assignment <- maybe (Left ScenarioAssignmentMismatch) Right (Map.lookup (run ^. #artifactStem) assignmentsByStem)
      let endpointName = assignment ^. #endpointParameter
          plain = (endpointName, assignment ^. #endpoint) : [(binding ^. #parameter, binding ^. #value) | binding <- assignment ^. #bindings]
          secret = [(binding ^. #parameter, binding ^. #variable) | binding <- assignment ^. #secretEnvironment]
          names = map fst plain <> map fst secret
          supplied = Set.fromList names
          committed = Set.unions (map (Map.keysSet . view #values) (run ^. #bindingLayers))
          runtime = Map.keysSet (input ^. #plainOverrides) <> Map.keysSet (input ^. #secretEnvironmentOverrides)
          declared = Set.fromList (run ^. #workflow . #workflow . #parameters)
          checkKind kind name = name `Set.member` declared && maybe False ((== kind) . view #kind) (lookupParameter name workspace)
      ensure (unique names) ScenarioDuplicateParameter
      ensure (all (checkKind Plain . fst) plain && all (checkKind Secret . fst) secret && all (isValidEnvironmentName . snd) secret) ScenarioInvalidParameter
      ensure (Set.null (supplied `Set.intersection` (committed <> runtime <> fileNames))) ScenarioConflictingBinding
      values <- traverse (\(name, value) -> (name,) <$> first (const ScenarioRuntimeInputFailed) (mkHurlValueLiteral value)) plain
      pure (run ^. #artifactStem, input {plainOverrides = Map.fromList values <> input ^. #plainOverrides, secretEnvironmentOverrides = Map.fromList secret <> input ^. #secretEnvironmentOverrides})

-- | Verified assignments are immutable; callers cannot manufacture a verified
-- value or change its mapping. Only expanded logical scenarios can select input.
scenarioBindingInput :: VerifiedScenarioInputs -> ExpandedRun -> Maybe BindingInput
scenarioBindingInput (VerifiedScenarioInputs inputs) run = Map.lookup (run ^. #artifactStem) inputs

snapshotInputs :: BindingInput -> IO (Either ScenarioIssue (BindingInput, Set ParameterName))
snapshotInputs input = do
  variables <- traverse (load parseVariableProperties) (input ^. #variableFiles)
  secrets <- traverse (load parseSecretProperties) (input ^. #secretFiles)
  pure $ do
    plainFiles <- sequence variables
    secretMaps <- sequence secrets
    pure (input, Set.unions (map Map.keysSet plainFiles <> map Map.keysSet secretMaps))
  where
    load parser path = do
      bytes <- try @IOException (ByteString.readFile path)
      pure $ first (const ScenarioRuntimeInputFailed) (bytes >>= first (const (userError "invalid runtime input")) . parser path)

endpointOrigin :: Text -> IO (Either ScenarioIssue (Bool, Text, Int))
endpointOrigin endpoint
  | Text.any (\c -> isControl c || isSpace c || c `elem` ("@?#" :: String)) endpoint = pure (Left ScenarioInvalidEndpoint)
  | not (any (`Text.isPrefixOf` lowered) ["http://", "https://"]) = pure (Left ScenarioInvalidEndpoint)
  | otherwise = do
      parsed <- try @HTTP.HttpException (HTTP.parseRequest (Text.unpack lowered))
      pure $ case parsed of
        Left _ -> Left ScenarioInvalidEndpoint
        Right request
          | HTTP.path request /= "/" || ByteString.null (HTTP.host request) || HTTP.port request < 1 || HTTP.port request > 65535 -> Left ScenarioInvalidEndpoint
          | otherwise -> Right (HTTP.secure request, Text.toLower (Text.pack (Char8.unpack (HTTP.host request))), HTTP.port request)
  where
    lowered = Text.toLower endpoint

validLabel :: FilePath -> Bool
validLabel path = not (null path) && all (isValidEntityName . Text.pack) (splitDirectories path)

validFixture :: Text -> Bool
validFixture value = not (Text.null value) && not (Text.any isControl value)

unique :: (Ord a) => [a] -> Bool
unique values = Set.size (Set.fromList values) == length values

ensure :: Bool -> issue -> Either issue ()
ensure condition issue = if condition then Right () else Left issue

renderScenarioIssue :: ScenarioIssue -> Text
renderScenarioIssue = \case
  ScenarioFileUnreadable -> "scenario-file-unreadable"
  ScenarioFileNotPrivateRegular -> "scenario-file-not-private-regular"
  ScenarioMalformedInput -> "scenario-malformed-input"
  ScenarioUnsupportedVersion -> "scenario-unsupported-version"
  ScenarioInvalidLabel -> "scenario-invalid-label"
  ScenarioAssignmentMismatch -> "scenario-assignment-mismatch"
  ScenarioDuplicateFixture -> "scenario-duplicate-fixture"
  ScenarioInvalidFixture -> "scenario-invalid-fixture"
  ScenarioDuplicateEndpoint -> "scenario-duplicate-endpoint"
  ScenarioInvalidEndpoint -> "scenario-invalid-endpoint"
  ScenarioInvalidParameter -> "scenario-invalid-parameter"
  ScenarioDuplicateParameter -> "scenario-duplicate-parameter"
  ScenarioConflictingBinding -> "scenario-conflicting-binding"
  ScenarioRuntimeInputFailed -> "scenario-runtime-input-failed"
