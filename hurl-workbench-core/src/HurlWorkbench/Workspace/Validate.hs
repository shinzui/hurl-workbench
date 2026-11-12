-- | Semantic validation of a decoded workspace.
--
--   Validation accumulates every independent issue instead of stopping at the
--   first one. Issues are reported in a fixed category order (schema,
--   parameters, fragments, workflows, recipes, matrices, services, suites) and
--   by entity name within a category, so the same workspace always produces
--   the same report.
module HurlWorkbench.Workspace.Validate
  ( ValidationIssue (..),
    validateWorkspace,
    renderValidationIssue,

    -- * Name rules
    isValidEntityName,
    isValidParameterName,
    isValidEnvironmentName,
    reservedParameterNames,
  )
where

import Control.Exception (IOException, try)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Generics.Labels ()
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import HurlWorkbench.Check.Template
import HurlWorkbench.Parameter.Generate (validateGenerator)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context.Internal (ValidatedWorkspace (..), WorkspaceContext (..))
import HurlWorkbench.Workspace.Types
import Numeric.Natural (Natural)
import System.Directory (canonicalizePath, doesDirectoryExist, doesFileExist, getPermissions)
import System.Directory qualified as Directory
import System.FilePath (isAbsolute, splitDirectories, takeExtension, (</>))

-- | One semantic problem, located by entity path such as
--   @workflows/list-properties@ or @matrices/by-mls/cases/west@.
data ValidationIssue = ValidationIssue
  { location :: !Text,
    message :: !Text
  }
  deriving stock (Generic, Eq, Show)

-- | @location: message@.
renderValidationIssue :: ValidationIssue -> Text
renderValidationIssue problem = problem ^. #location <> ": " <> problem ^. #message

-- | Validate every category and, on success, build the typed indexes.
validateWorkspace :: WorkspaceContext -> IO (Either (NonEmpty ValidationIssue) ValidatedWorkspace)
validateWorkspace ctx = do
  (fragmentIssues, fragmentFiles) <- validateFragments root ws
  (checkIssues, checkExecutables) <- validateChecks root ws
  serviceIssues <- validateServices root ws
  phaseIssues <- fmap concat $ for (ws ^. #suites) $ \suite -> fmap concat $ for [("setup", suite ^. #setup), ("teardown", suite ^. #teardown)] $ \(phase, commands) -> fmap concat $ for (zip [0 :: Int ..] commands) $ \(ordinal, command) -> commandIssues root ws (unSuiteName (suite ^. #name)) ("suites/" <> unSuiteName (suite ^. #name) <> "/" <> phase <> "/" <> tshow ordinal) command
  let issues =
        concat
          [ schemaIssues ws,
            ordered (validateParameters ws),
            ordered fragmentIssues,
            ordered (validateWorkflows ws),
            ordered (validateRecipes ws),
            ordered (validateMatrices ws),
            ordered checkIssues,
            ordered serviceIssues,
            ordered (validateSuites ws <> phaseIssues)
          ]
  pure $ case nonEmpty issues of
    Just problems -> Left problems
    Nothing ->
      Right
        ValidatedWorkspace
          { context = ctx,
            parameterIndex = indexBy (view #name) (ws ^. #parameters),
            fragmentIndex = indexBy (view #name) (ws ^. #fragments),
            fragmentFiles,
            workflowIndex = indexBy (view #name) (ws ^. #workflows),
            recipeIndex = indexBy (view #name) (ws ^. #recipes),
            matrixIndex = indexBy (view #name) (ws ^. #matrices),
            checkIndex = indexBy (view #name) (ws ^. #checks),
            checkExecutables,
            serviceIndex = indexBy (view #name) (ws ^. #services),
            suiteIndex = indexBy (view #name) (ws ^. #suites)
          }
  where
    ws = ctx ^. #workspace
    root = ctx ^. #workspaceRoot

-- | Issues tagged with the entity name used for ordering within a category.
type Tagged = [(Text, ValidationIssue)]

ordered :: Tagged -> [ValidationIssue]
ordered = map snd . sortOn fst

issue :: Text -> Text -> Text -> (Text, ValidationIssue)
issue key loc msg = (key, ValidationIssue {location = loc, message = msg})

-- | First declaration wins; duplicates are reported by validation.
indexBy :: (Ord k) => (a -> k) -> [a] -> Map k a
indexBy key = Map.fromListWith (\_new old -> old) . map (\a -> (key a, a))

schemaIssues :: Workspace -> [ValidationIssue]
schemaIssues ws =
  [ ValidationIssue
      { location = "schemaVersion",
        message =
          "unsupported schema version "
            <> tshow (ws ^. #schemaVersion)
            <> "; expected "
            <> tshow supportedSchemaVersion
      }
  | ws ^. #schemaVersion /= supportedSchemaVersion
  ]

--------------------------------------------------------------------------------
-- Names

-- | Fragment, workflow, recipe, matrix, matrix-case, service, and suite names
--   match @[A-Za-z][A-Za-z0-9._-]*@.
isValidEntityName :: Text -> Bool
isValidEntityName name = case Text.uncons name of
  Just (first, rest) -> isAsciiLetter first && Text.all (\c -> isAsciiLetter c || isDigit c || c `elem` ['.', '_', '-']) rest
  Nothing -> False

-- | Parameter names are Hurl-template-safe: @[A-Za-z_][A-Za-z0-9_-]*@ and not
--   one of 'reservedParameterNames'.
isValidParameterName :: Text -> Bool
isValidParameterName name =
  name `notElem` reservedParameterNames && case Text.uncons name of
    Just (first, rest) -> (isAsciiLetter first || first == '_') && Text.all (\c -> isAsciiLetter c || isDigit c || c `elem` ['_', '-']) rest
    Nothing -> False

-- | Hurl 8 template functions that cannot be shadowed by a variable.
reservedParameterNames :: [Text]
reservedParameterNames = ["getEnv", "newDate", "newUuid"]

-- | Environment variable names: @[A-Za-z_][A-Za-z0-9_]*@.
isValidEnvironmentName :: Text -> Bool
isValidEnvironmentName name = case Text.uncons name of
  Just (first, rest) -> (isAsciiLetter first || first == '_') && Text.all (\c -> isAsciiLetter c || isDigit c || c == '_') rest
  Nothing -> False

isAsciiLetter :: Char -> Bool
isAsciiLetter c = isAsciiLower c || isAsciiUpper c

-- | Check a name's syntax and uniqueness within one category.
nameIssues :: Text -> (Text -> Bool) -> Text -> [Text] -> Tagged
nameIssues category valid rule names =
  [ issue name (category <> "/" <> name) ("invalid " <> categoryLabel <> " name; names must match " <> rule)
  | name <- Set.toList (Set.fromList names),
    not (valid name)
  ]
    <> [ issue name (category <> "/" <> name) ("duplicate " <> categoryLabel <> " name declared " <> tshow count <> " times")
       | (name, count) <- Map.toList (Map.fromListWith (+) [(name, 1 :: Int) | name <- names]),
         count > 1
       ]
  where
    categoryLabel = case category of
      "parameters" -> "parameter"
      "fragments" -> "fragment"
      "workflows" -> "workflow"
      "recipes" -> "recipe"
      "matrices" -> "matrix"
      "services" -> "service"
      "suites" -> "suite"
      "cases" -> "matrix case"
      other -> other

entityNameRule :: Text
entityNameRule = "[A-Za-z][A-Za-z0-9._-]*"

--------------------------------------------------------------------------------
-- Parameters

validateParameters :: Workspace -> Tagged
validateParameters ws =
  nameIssues
    "parameters"
    isValidParameterName
    "[A-Za-z_][A-Za-z0-9_-]* and must not be getEnv, newDate, or newUuid"
    (map (unParameterName . view #name) (ws ^. #parameters))
    <> concatMap parameterIssues (ws ^. #parameters)
  where
    parameterIssues p =
      let name = unParameterName (p ^. #name)
          loc = "parameters/" <> name
       in [ issue name loc "secret parameters must not have a committed defaultValue"
          | p ^. #kind == Secret,
            isJust (p ^. #defaultValue)
          ]
            <> [issue name loc "generated parameters must not have a committed defaultValue" | Generated _ <- [p ^. #kind], isJust (p ^. #defaultValue)]
            <> [issue name loc problem | Generated generator <- [p ^. #kind], Left problem <- [validateGenerator generator]]
            <> [ issue name (loc <> "/defaultValue") (renderHurlValueLiteralError err)
               | Just value <- [p ^. #defaultValue],
                 Left err <- [literalCheck value]
               ]
            <> [ issue name (loc <> "/environment") ("invalid environment variable name " <> quote env)
               | Just env <- [p ^. #environment],
                 not (isValidEnvironmentName env)
               ]

literalCheck :: HurlValueLiteral -> Either HurlValueLiteralError HurlValueLiteral
literalCheck = mkHurlValueLiteral . hurlValueLiteralText

--------------------------------------------------------------------------------
-- Fragments

validateFragments :: WorkspaceRoot -> Workspace -> IO (Tagged, Map FragmentName FilePath)
validateFragments root ws = do
  checked <- for (ws ^. #fragments) $ \fragment -> do
    let name = unFragmentName (fragment ^. #name)
        loc = "fragments/" <> name <> "/path"
    result <- checkContainedPath root (fragment ^. #path) FileEntry
    pure $ case result of
      Left problem -> ([issue name loc problem], Nothing)
      Right canonical
        | takeExtension (fragment ^. #path) /= ".hurl" ->
            ([issue name loc ("fragment path " <> quote (Text.pack (fragment ^. #path)) <> " must end in .hurl")], Nothing)
        | otherwise -> ([], Just (fragment ^. #name, canonical))
  let names = map (unFragmentName . view #name) (ws ^. #fragments)
      files = Map.fromListWith (\_new old -> old) (catMaybes (map snd checked))
  pure (nameIssues "fragments" isValidEntityName entityNameRule names <> concatMap fst checked, files)

data EntryKind = FileEntry | DirectoryEntry
  deriving stock (Eq, Show)

-- | A relative path that canonicalizes inside the root and exists with the
--   expected kind. Symlinks are followed before the containment check, so a
--   link pointing outside the root is rejected.
checkContainedPath :: WorkspaceRoot -> FilePath -> EntryKind -> IO (Either Text FilePath)
checkContainedPath (WorkspaceRoot root) relative entryKind
  | null relative = pure (Left "path must not be empty")
  | isAbsolute relative = pure (Left ("path " <> shown <> " must be relative to the workspace root"))
  | otherwise = do
      canonical <- canonicalizePath (root </> relative)
      if not (splitDirectories root `isPrefixOfList` splitDirectories canonical)
        then pure (Left ("path " <> shown <> " escapes the workspace root"))
        else do
          exists <- case entryKind of
            FileEntry -> doesFileExist canonical
            DirectoryEntry -> doesDirectoryExist canonical
          pure $
            if exists
              then Right canonical
              else Left ("path " <> shown <> " does not exist as a " <> kindName)
  where
    shown = quote (Text.pack relative)
    kindName = case entryKind of
      FileEntry -> "regular file"
      DirectoryEntry -> "directory"

isPrefixOfList :: (Eq a) => [a] -> [a] -> Bool
isPrefixOfList prefix xs = take (length prefix) xs == prefix

--------------------------------------------------------------------------------
-- Workflows

validateWorkflows :: Workspace -> Tagged
validateWorkflows ws =
  nameIssues "workflows" isValidEntityName entityNameRule (map (unWorkflowName . view #name) (ws ^. #workflows))
    <> concatMap workflowIssues (ws ^. #workflows)
  where
    fragmentNames = Set.fromList (map (view #name) (ws ^. #fragments))
    parameterNames = Set.fromList (map (view #name) (ws ^. #parameters))
    workflowIssues w =
      let name = unWorkflowName (w ^. #name)
          loc = "workflows/" <> name
       in [issue name (loc <> "/fragments") "workflow must list at least one fragment" | null (w ^. #fragments)]
            <> [ issue name (loc <> "/fragments") ("unknown fragment " <> quote (unFragmentName f))
               | f <- w ^. #fragments,
                 f `Set.notMember` fragmentNames
               ]
            <> [ issue name (loc <> "/parameters") ("unknown parameter " <> quote (unParameterName p))
               | p <- w ^. #parameters,
                 p `Set.notMember` parameterNames
               ]
            <> [ issue name (loc <> "/parameters") ("parameter " <> quote (unParameterName p) <> " is listed more than once")
               | p <- duplicates (w ^. #parameters)
               ]

--------------------------------------------------------------------------------
-- Bindings, recipes, and matrices

-- | Check one binding set against the parameters declared by a workflow.
bindingIssues :: Workspace -> Maybe Workflow -> Text -> Text -> [Binding] -> Tagged
bindingIssues ws selected key loc bindings =
  [ issue key (loc <> "/bindings") ("parameter " <> quote (unParameterName p) <> " is bound more than once")
  | p <- duplicates (map (view #parameter) bindings)
  ]
    <> concatMap one bindings
  where
    parametersByName = indexBy (view #name) (ws ^. #parameters)
    one b =
      let pname = b ^. #parameter
          bloc = loc <> "/bindings/" <> unParameterName pname
          declared = case selected of
            -- An unresolved workflow is reported where it is referenced.
            Nothing -> True
            Just w -> pname `elem` w ^. #parameters
       in [ issue key bloc ("parameter is not declared by workflow " <> quote (maybe "" (unWorkflowName . view #name) selected))
          | not declared,
            Map.member pname parametersByName
          ]
            <> [ issue key bloc "secret parameters cannot be bound to committed values"
               | Just p <- [Map.lookup pname parametersByName],
                 p ^. #kind == Secret
               ]
            <> [issue key bloc "generated parameters cannot be bound to committed values" | Just p <- [Map.lookup pname parametersByName], Generated _ <- [p ^. #kind]]
            <> [ issue key bloc "unknown parameter"
               | Map.notMember pname parametersByName
               ]
            <> [ issue key bloc (renderHurlValueLiteralError err)
               | Left err <- [literalCheck (b ^. #value)]
               ]

validateRecipes :: Workspace -> Tagged
validateRecipes ws =
  nameIssues "recipes" isValidEntityName entityNameRule (map (unRecipeName . view #name) (ws ^. #recipes))
    <> concatMap recipeIssues (ws ^. #recipes)
  where
    workflowsByName = indexBy (view #name) (ws ^. #workflows)
    recipeIssues r =
      let name = unRecipeName (r ^. #name)
          loc = "recipes/" <> name
          selected = Map.lookup (r ^. #workflow) workflowsByName
       in [ issue name (loc <> "/workflow") ("unknown workflow " <> quote (unWorkflowName (r ^. #workflow)))
          | isNothing selected
          ]
            <> bindingIssues ws selected name loc (r ^. #bindings)

validateMatrices :: Workspace -> Tagged
validateMatrices ws =
  nameIssues "matrices" isValidEntityName entityNameRule (map (unMatrixName . view #name) (ws ^. #matrices))
    <> concatMap matrixIssues (ws ^. #matrices)
  where
    recipesByName = indexBy (view #name) (ws ^. #recipes)
    workflowsByName = indexBy (view #name) (ws ^. #workflows)
    matrixIssues m =
      let name = unMatrixName (m ^. #name)
          loc = "matrices/" <> name
          recipe = Map.lookup (m ^. #recipe) recipesByName
          selected = recipe >>= \r -> Map.lookup (r ^. #workflow) workflowsByName
          caseNames = map (unMatrixCaseName . view #name) (m ^. #cases)
       in [ issue name (loc <> "/recipe") ("unknown recipe " <> quote (unRecipeName (m ^. #recipe)))
          | isNothing recipe
          ]
            <> [issue name (loc <> "/cases") "matrix must have at least one case" | null (m ^. #cases)]
            <> map (\(_, i) -> (name, i & #location %~ ((loc <> "/") <>))) (nameIssues "cases" isValidEntityName entityNameRule caseNames)
            <> concat
              [ bindingIssues ws selected name (loc <> "/cases/" <> unMatrixCaseName (c ^. #name)) (c ^. #bindings)
              | c <- m ^. #cases
              ]

--------------------------------------------------------------------------------
-- Checks

validateChecks :: WorkspaceRoot -> Workspace -> IO (Tagged, Map CheckName FilePath)
validateChecks root ws = do
  checked <- for (ws ^. #checks) $ \check -> do
    let name = unCheckName (check ^. #name)
        loc = "checks/" <> name
        spec = check ^. #command
        relative = Text.unpack (spec ^. #executable)
    common <- commandIssues root ws name (loc <> "/command") spec
    inspected <-
      try @IOException $
        if Text.any (== '\0') (spec ^. #executable)
          then pure (Left "executable path must not contain NUL")
          else
            if ".." `elem` splitDirectories relative
              then pure (Left "executable path must not contain parent traversal")
              else checkContainedPath root relative FileEntry
    let target = either (const (Left "could not inspect check executable")) id inspected
    executableResult <- case target of
      Left problem -> pure (Left problem)
      Right path -> do
        permissions <- getPermissions path
        pure (if Directory.executable permissions then Right path else Left "check file must be executable")
    let problems =
          common
            <> [issue name (loc <> "/command/executable") problem | Left problem <- [executableResult]]
            <> [issue name (loc <> "/expectedStatus") "expected status must be between 0 and 255" | check ^. #expectedStatus > 255]
            <> maybe [] (positive name (loc <> "/timeoutSeconds")) (check ^. #timeoutSeconds)
            <> concat [argumentIssues name (loc <> "/command/arguments/" <> tshow ordinal) arg | (ordinal, arg) <- zip [0 :: Int ..] (spec ^. #arguments)]
    pure (problems, (check ^. #name,) <$> either (const Nothing) Just executableResult)
  pure (nameIssues "checks" isValidEntityName entityNameRule (map (unCheckName . view #name) (ws ^. #checks)) <> concatMap fst checked, Map.fromList (mapMaybe snd checked))
  where
    argumentIssues key loc arg = case parseTemplate arg of
      Left problem -> [issue key loc problem]
      Right templateParts ->
        concat
          [ case filter ((== name) . view #name) (ws ^. #parameters) of
              [] -> [issue key loc ("unknown parameter " <> quote (unParameterName name))]
              parameter : _ -> [issue key loc "only Plain parameters may appear in check arguments" | parameter ^. #kind /= Plain]
          | Placeholder name <- templateParts
          ]

--------------------------------------------------------------------------------
-- Services

validateServices :: WorkspaceRoot -> Workspace -> IO Tagged
validateServices root ws = do
  perService <- for (ws ^. #services) $ \s -> do
    let name = unServiceName (s ^. #name)
        loc = "services/" <> name
    commandProblems <- commandIssues root ws name (loc <> "/command") (s ^. #command)
    readinessProblems <- case s ^. #readiness of
      HttpReadinessCheck http ->
        pure $
          [issue name (loc <> "/readiness/url") "readiness URL must not be empty" | Text.null (Text.strip (http ^. #url))]
            <> [ issue name (loc <> "/readiness/expectedStatus") "expected HTTP status must be between 100 and 599"
               | http ^. #expectedStatus < 100 || http ^. #expectedStatus > 599
               ]
            <> [issue name (loc <> "/readiness/url") "generated parameters cannot be used in readiness URLs" | p <- ws ^. #parameters, Generated _ <- [p ^. #kind], ("{{" <> unParameterName (p ^. #name) <> "}}") `Text.isInfixOf` (http ^. #url)]
            <> positive name (loc <> "/readiness/intervalMilliseconds") (http ^. #intervalMilliseconds)
            <> positive name (loc <> "/readiness/timeoutSeconds") (http ^. #timeoutSeconds)
      CommandReadinessCheck check -> do
        problems <- commandIssues root ws name (loc <> "/readiness/command") (check ^. #command)
        pure $
          problems
            <> positive name (loc <> "/readiness/intervalMilliseconds") (check ^. #intervalMilliseconds)
            <> positive name (loc <> "/readiness/timeoutSeconds") (check ^. #timeoutSeconds)
    pure (commandProblems <> readinessProblems <> positive name (loc <> "/shutdownTimeoutSeconds") (s ^. #shutdownTimeoutSeconds))
  pure (nameIssues "services" isValidEntityName entityNameRule (map (unServiceName . view #name) (ws ^. #services)) <> concat perService)

positive :: Text -> Text -> Natural -> Tagged
positive key loc n = [issue key loc "must be greater than zero" | n == 0] <> [issue key loc "exceeds supported timer range" | n > fromIntegral (maxBound @Int `div` 1000000)]

commandIssues :: WorkspaceRoot -> Workspace -> Text -> Text -> CommandSpec -> IO Tagged
commandIssues root ws key loc spec = do
  workingDirectoryProblems <- case spec ^. #workingDirectory of
    Nothing -> pure []
    Just dir -> do
      result <- checkContainedPath root dir DirectoryEntry
      pure [issue key (loc <> "/workingDirectory") problem | Left problem <- [result]]
  pure $
    [issue key (loc <> "/executable") "executable must not be empty" | Text.null (Text.strip (spec ^. #executable))]
      <> [issue key loc "process arguments must not contain NUL" | any (Text.any (== '\0')) (spec ^. #executable : spec ^. #arguments)]
      <> [issue key loc "generated parameters cannot be used by suite-scoped commands" | b <- spec ^. #environment, p <- ws ^. #parameters, p ^. #name == b ^. #parameter, Generated _ <- [p ^. #kind]]
      <> policyProblems
      <> workingDirectoryProblems
      <> [ issue key (loc <> "/environment") ("environment variable " <> quote v <> " is bound more than once")
         | v <- duplicates (map (view #variable) (spec ^. #environment))
         ]
      <> concat
        [ [ issue key (loc <> "/environment/" <> b ^. #variable) "invalid environment variable name"
          | not (isValidEnvironmentName (b ^. #variable))
          ]
            <> [ issue key (loc <> "/environment/" <> b ^. #variable) ("unknown parameter " <> quote (unParameterName (b ^. #parameter)))
               | (b ^. #parameter) `Set.notMember` parameterNames
               ]
        | b <- spec ^. #environment
        ]
  where
    policyProblems = case spec ^. #environmentPolicy of
      Inherit -> []
      Clean names ->
        [issue key (loc <> "/environmentPolicy") ("invalid inherited environment variable name " <> quote n) | n <- names, not (isValidEnvironmentName n)]
          <> [issue key (loc <> "/environmentPolicy") ("inherited environment variable " <> quote n <> " is selected more than once") | n <- duplicates names]
    parameterNames = Set.fromList (map (view #name) (ws ^. #parameters))

--------------------------------------------------------------------------------
-- Suites

validateSuites :: Workspace -> Tagged
validateSuites ws =
  nameIssues "suites" isValidEntityName entityNameRule (map (unSuiteName . view #name) (ws ^. #suites))
    <> concatMap suiteIssues (ws ^. #suites)
  where
    workflows = Set.fromList (map (view #name) (ws ^. #workflows))
    recipes = Set.fromList (map (view #name) (ws ^. #recipes))
    matrices = Set.fromList (map (view #name) (ws ^. #matrices))
    checks = Set.fromList (map (view #name) (ws ^. #checks))
    services = Set.fromList (map (view #name) (ws ^. #services))
    suiteIssues s =
      let name = unSuiteName (s ^. #name)
          loc = "suites/" <> name
       in [issue name (loc <> "/runs") "suite must have at least one run" | all (\case ServiceRun _ -> True; _ -> False) (s ^. #runs)]
            <> [issue name (loc <> "/service") "independent-state suites cannot declare a shared managed service" | s ^. #isolation == IndependentState, not (null (suiteServices s))]
            <> [issue name (loc <> "/services") "service and nonempty services cannot both be supplied" | isJust (s ^. #service), not (null (s ^. #services))]
            <> [issue name (loc <> "/services") ("duplicate service " <> quote (unServiceName svc)) | svc <- duplicates (suiteServices s)]
            <> [issue name (loc <> "/fileRootParameter") problem | Just parameter <- [s ^. #fileRootParameter], problem <- fileRootIssues parameter]
            <> positive name (loc <> "/commandTimeoutSeconds") (s ^. #commandTimeoutSeconds)
            <> positive name (loc <> "/cleanupTimeoutSeconds") (s ^. #cleanupTimeoutSeconds)
            <> [issue name (loc <> "/commandTimeoutSeconds") "timeout exceeds supported microsecond range" | s ^. #commandTimeoutSeconds > fromIntegral (maxBound @Int `div` 1000000)]
            <> [issue name (loc <> "/cleanupTimeoutSeconds") "timeout exceeds supported microsecond range" | s ^. #cleanupTimeoutSeconds > fromIntegral (maxBound @Int `div` 1000000)]
            <> map (issue name (loc <> "/runs")) (transitions (Set.fromList (suiteServices s)) (s ^. #runs))
            <> mapMaybe (fmap (issue name (loc <> "/runs")) . unresolvedRun) (s ^. #runs)
            <> [ issue name (loc <> "/service") ("unknown service " <> quote (unServiceName svc))
               | svc <- suiteServices s,
                 svc `Set.notMember` services
               ]
    fileRootIssues parameter =
      ["invalid parameter name" | not (isValidParameterName (unParameterName parameter))]
        <> case filter ((== parameter) . view #name) (ws ^. #parameters) of
          [] -> ["unknown file-root parameter " <> quote (unParameterName parameter)]
          definition : _ -> ["file-root parameter must be Plain" | definition ^. #kind /= Plain]
    transitions initial = go initial
      where
        go _ [] = []
        go running (ServiceRun step : remaining) =
          let (svc, requiresRunning, next) = case step of
                Stop n -> (n, True, Set.delete n running)
                Start n -> (n, False, Set.insert n running)
                Restart n -> (n, True, running)
              problems =
                ["lifecycle service does not belong to suite: " <> quote (unServiceName svc) | svc `Set.notMember` initial]
                  <> ["invalid lifecycle transition for " <> quote (unServiceName svc) | Set.member svc running /= requiresRunning]
           in problems <> go next remaining
        go running (_ : remaining) = go running remaining
    unresolvedRun = \case
      WorkflowRun w | w `Set.notMember` workflows -> Just ("unknown workflow " <> quote (unWorkflowName w))
      RecipeRun r | r `Set.notMember` recipes -> Just ("unknown recipe " <> quote (unRecipeName r))
      CheckRun c | c `Set.notMember` checks -> Just ("unknown check " <> quote (unCheckName c))
      MatrixRun m | m `Set.notMember` matrices -> Just ("unknown matrix " <> quote (unMatrixName m))
      _ -> Nothing

--------------------------------------------------------------------------------
-- Helpers

duplicates :: (Ord a) => [a] -> [a]
duplicates xs = [x | (x, count) <- Map.toList (Map.fromListWith (+) [(x, 1 :: Int) | x <- xs]), count > 1]

quote :: Text -> Text
quote t = "\"" <> t <> "\""

tshow :: (Show a) => a -> Text
tshow = Text.pack . show
