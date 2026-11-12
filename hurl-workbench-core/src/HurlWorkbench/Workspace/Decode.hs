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
import HurlWorkbench.Workspace.Types (Check, Workspace, supportedSchemaVersion)
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
              | otherwise -> decodeTyped (normalizeChecks (normalizeParameterKinds (normalizeCommandPolicies (normalizeSuiteLifecycle normalized))))

    decodeTyped normalized = do
      expected <- trySync $ do
        Dhall.typecheckWithSettings settings normalized
        Dhall.expectWithSettings settings decoder normalized
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
        [(key, if key `elem` ["checks", "services", "suites"] then field {Dhall.Core.recordFieldValue = upgrade (Dhall.Core.recordFieldValue field)} else field) | (key, field) <- Dhall.Map.toList fields]
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

-- | Version-1 additive conversion, scoped to suites. Preserve explicit fields
-- and widen only the known Hurl run union (including empty-list annotations).
-- Both the original expression and the converted expression are typechecked.
normalizeSuiteLifecycle :: Dhall.Core.Expr Src Void -> Dhall.Core.Expr Src Void
normalizeSuiteLifecycle (Dhall.Core.RecordLit fields) =
  Dhall.Core.RecordLit
    ( Dhall.Map.fromList
        [(key, if key == "suites" then field {Dhall.Core.recordFieldValue = upgrade (Dhall.Core.recordFieldValue field)} else field) | (key, field) <- Dhall.Map.toList fields]
    )
  where
    list = Dhall.Core.App Dhall.Core.List
    record = Dhall.Core.Record . Dhall.Map.fromList . map (\(key, value) -> (key, Dhall.Core.makeRecordField value))
    union names = Dhall.Core.Union (Dhall.Map.fromList [(key, value) | (key, value) <- names])
    policyType = union [("SharedState", Nothing), ("IndependentState", Nothing)]
    commandType =
      record
        [ ("executable", Dhall.Core.Text),
          ("arguments", list Dhall.Core.Text),
          ("workingDirectory", Dhall.Core.App Dhall.Core.Optional Dhall.Core.Text),
          ("environmentPolicy", union [("Inherit", Nothing), ("Clean", Just (list Dhall.Core.Text))]),
          ("environment", list (record [("variable", Dhall.Core.Text), ("parameter", Dhall.Core.Text)]))
        ]
    stepType = union [(key, Just Dhall.Core.Text) | key <- ["Stop", "Start", "Restart"]]
    defaults =
      [ ("fileRootParameter", Dhall.Core.App Dhall.Core.Optional Dhall.Core.Text, Dhall.Core.App Dhall.Core.None Dhall.Core.Text),
        ("isolation", policyType, Dhall.Core.Field policyType (Dhall.Core.makeFieldSelection "SharedState")),
        ("services", list Dhall.Core.Text, Dhall.Core.ListLit (Just (list Dhall.Core.Text)) mempty),
        ("setup", list commandType, Dhall.Core.ListLit (Just (list commandType)) mempty),
        ("teardown", list commandType, Dhall.Core.ListLit (Just (list commandType)) mempty),
        ("commandTimeoutSeconds", Dhall.Core.Natural, Dhall.Core.NaturalLit 60),
        ("cleanupTimeoutSeconds", Dhall.Core.Natural, Dhall.Core.NaturalLit 30)
      ]
    add isType fields_ =
      if all (\key -> isJust (Dhall.Map.lookup key fields_)) ["name", "runs", "service", "failFast", "description"]
        then foldl (\acc (key, type_, value) -> if isJust (Dhall.Map.lookup key acc) then acc else Dhall.Map.insert key (Dhall.Core.makeRecordField (if isType then type_ else value)) acc) fields_ defaults
        else fields_
    upgrade expression =
      let nested = runIdentity (Dhall.Core.subExpressions (Identity . upgrade) expression)
       in case nested of
            Dhall.Core.RecordLit fields_ -> Dhall.Core.RecordLit (add False fields_)
            Dhall.Core.Record fields_ -> Dhall.Core.Record (add True fields_)
            Dhall.Core.Union alternatives
              | all (\key -> Dhall.Map.lookup key alternatives == Just (Just Dhall.Core.Text)) ["Workflow", "Recipe", "Matrix"],
                not (isJust (Dhall.Map.lookup "Service" alternatives)) ->
                  Dhall.Core.Union (Dhall.Map.insert "Service" (Just stepType) alternatives)
            other -> other
normalizeSuiteLifecycle other = other

-- | Widen the legacy parameter kind in values and empty typed lists. The
-- original and upgraded expressions both pass Dhall type checking.
normalizeParameterKinds :: Dhall.Core.Expr Src Void -> Dhall.Core.Expr Src Void
normalizeParameterKinds expression =
  let nested = runIdentity (Dhall.Core.subExpressions (Identity . normalizeParameterKinds) expression)
      record key type_ = Dhall.Core.Record (Dhall.Map.fromList [(key, Dhall.Core.makeRecordField type_)])
      generator =
        Dhall.Core.Union
          ( Dhall.Map.fromList
              [ ("Uuid4", Nothing),
                ("Uuid7", Nothing),
                ("TypeId", Just (record "prefix" Dhall.Core.Text)),
                ("Rfc3339Now", Nothing),
                ("RandomAlphanumeric", Just (record "length" Dhall.Core.Natural))
              ]
          )
   in case nested of
        Dhall.Core.Union alternatives
          | Dhall.Map.toList alternatives == [("Plain", Nothing), ("Secret", Nothing)] ->
              Dhall.Core.Union (Dhall.Map.insert "Generated" (Just generator) alternatives)
        other -> other

-- | Add the absent category and widen legacy run unions, including annotations
-- on empty lists. Original and upgraded expressions are both typechecked.
normalizeChecks :: Dhall.Core.Expr Src Void -> Dhall.Core.Expr Src Void
normalizeChecks (Dhall.Core.RecordLit fields) =
  let checkList = Dhall.Core.App Dhall.Core.List checkType
      withChecks = if isJust (Dhall.Map.lookup "checks" fields) then fields else Dhall.Map.insert "checks" (Dhall.Core.makeRecordField (Dhall.Core.ListLit (Just checkList) mempty)) fields
   in Dhall.Core.RecordLit (Dhall.Map.fromList [(key, if key == "suites" then field {Dhall.Core.recordFieldValue = upgrade (Dhall.Core.recordFieldValue field)} else field) | (key, field) <- Dhall.Map.toList withChecks])
  where
    checkType = case toList (Dhall.expected (Dhall.auto @Check)) of type_ : _ -> type_; [] -> error "invalid check decoder"
    upgrade expression =
      let nested = runIdentity (Dhall.Core.subExpressions (Identity . upgrade) expression)
       in case nested of
            Dhall.Core.Union alternatives
              | all (\key -> Dhall.Map.lookup key alternatives == Just (Just Dhall.Core.Text)) ["Workflow", "Recipe", "Matrix"],
                not (isJust (Dhall.Map.lookup "Check" alternatives)) ->
                  Dhall.Core.Union (Dhall.Map.insert "Check" (Just Dhall.Core.Text) alternatives)
            other -> other
normalizeChecks other = other
