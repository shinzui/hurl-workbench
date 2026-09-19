-- | The decoded, pre-validation representation of a @hurl-workbench.dhall@
--   workspace. Every field corresponds one-to-one to the Dhall schema under
--   @schema/@ at the repository root.
--
--   These values describe existing Hurl source; they never describe HTTP
--   methods, URLs, bodies, captures, or assertions. Semantic guarantees
--   (unique names, resolved references, safe paths) only hold once a
--   'Workspace' has been turned into a
--   'HurlWorkbench.Workspace.Context.ValidatedWorkspace'.
module HurlWorkbench.Workspace.Types
  ( -- * Workspace
    Workspace (..),
    supportedSchemaVersion,

    -- * Category-specific names
    ParameterName (..),
    FragmentName (..),
    WorkflowName (..),
    RecipeName (..),
    MatrixName (..),
    MatrixCaseName (..),
    ServiceName (..),
    SuiteName (..),
    WorkspaceRoot (..),

    -- * Plain Hurl values
    HurlValueLiteral,
    HurlValueLiteralError (..),
    mkHurlValueLiteral,
    hurlValueLiteralText,
    renderHurlValueLiteralError,

    -- * Entities
    Parameter (..),
    ParameterKind (..),
    Fragment (..),
    Workflow (..),
    Binding (..),
    Safety (..),
    Recipe (..),
    MatrixCase (..),
    Matrix (..),
    EnvironmentBinding (..),
    CommandSpec (..),
    HttpReadiness (..),
    CommandReadiness (..),
    Readiness (..),
    Service (..),
    RunReference (..),
    Suite (..),
  )
where

import Data.Text qualified as Text
import Dhall (FromDhall (..), InterpretOptions (..), defaultInterpretOptions, genericAutoWith)
import HurlWorkbench.Prelude
import Numeric.Natural (Natural)

-- | The only @schemaVersion@ this build understands.
supportedSchemaVersion :: Natural
supportedSchemaVersion = 1

-- | A complete workspace manifest after Dhall evaluation and decoding.
data Workspace = Workspace
  { schemaVersion :: !Natural,
    parameters :: ![Parameter],
    fragments :: ![Fragment],
    workflows :: ![Workflow],
    recipes :: ![Recipe],
    matrices :: ![Matrix],
    services :: ![Service],
    suites :: ![Suite]
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | Name of an externally injected Hurl variable.
newtype ParameterName = ParameterName {unParameterName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of a fragment: one file containing complete Hurl entries.
newtype FragmentName = FragmentName {unFragmentName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of a workflow: an ordered list of fragments.
newtype WorkflowName = WorkflowName {unWorkflowName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of a recipe: a workflow plus plain bindings and a safety class.
newtype RecipeName = RecipeName {unRecipeName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of a matrix: a recipe applied to several binding sets.
newtype MatrixName = MatrixName {unMatrixName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of one case inside a matrix. Unique only within its matrix.
newtype MatrixCaseName = MatrixCaseName {unMatrixCaseName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of a managed service process.
newtype ServiceName = ServiceName {unServiceName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Name of a suite: a collection of workflow, recipe, or matrix runs.
newtype SuiteName = SuiteName {unSuiteName :: Text}
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Canonical absolute directory containing @hurl-workbench.dhall@.
newtype WorkspaceRoot = WorkspaceRoot {unWorkspaceRoot :: FilePath}
  deriving stock (Generic, Eq, Ord, Show)

-- | A plain (non-secret) Hurl variable value that survives transport through
--   a Hurl 8 variables file unchanged.
--
--   Hurl reads such files line by line, trims each line, and splits it at the
--   first @=@. The remaining text is then inferred by Hurl as @true@,
--   @false@, @null@, an integer, a float, or a string. The smart constructor
--   therefore rejects CR, LF, and NUL characters and leading or trailing
--   whitespace; an @=@ inside the value is fine. The text is otherwise passed
--   through as written and Hurl's inference applies.
--
--   Values decoded from Dhall are checked by semantic validation, which
--   reports the offending location; runtime values must go through
--   'mkHurlValueLiteral'.
newtype HurlValueLiteral = HurlValueLiteral Text
  deriving stock (Generic, Eq, Ord, Show)
  deriving newtype (FromDhall)

-- | Why a text value cannot be a 'HurlValueLiteral'.
data HurlValueLiteralError
  = -- | The value contains a carriage return, line feed, or NUL character.
    ContainsLineBreakOrNul
  | -- | The value begins or ends with whitespace that Hurl would trim.
    SurroundingWhitespace
  deriving stock (Generic, Eq, Show)

-- | Check the lossless single-line transport rule.
mkHurlValueLiteral :: Text -> Either HurlValueLiteralError HurlValueLiteral
mkHurlValueLiteral value
  | Text.any (`elem` ['\r', '\n', '\0']) value = Left ContainsLineBreakOrNul
  | hasSurroundingWhitespace = Left SurroundingWhitespace
  | otherwise = Right (HurlValueLiteral value)
  where
    hasSurroundingWhitespace = case (Text.uncons value, Text.unsnoc value) of
      (Just (first, _), Just (_, final)) -> isTrimmed first || isTrimmed final
      _ -> False
    -- Hurl uses Rust's `str::trim`, which trims Unicode White_Space.
    isTrimmed c = Text.null (Text.strip (Text.singleton c)) || c `elem` ['\x85', '\x2028', '\x2029']

-- | The literal text written to a Hurl variables file.
hurlValueLiteralText :: HurlValueLiteral -> Text
hurlValueLiteralText (HurlValueLiteral value) = value

-- | Human-readable explanation of a 'HurlValueLiteralError'.
renderHurlValueLiteralError :: HurlValueLiteralError -> Text
renderHurlValueLiteralError = \case
  ContainsLineBreakOrNul -> "value contains a line break or NUL character, which Hurl variable files cannot carry"
  SurroundingWhitespace -> "value has leading or trailing whitespace, which Hurl variable files would trim"

-- | Whether a parameter's value may be committed and displayed.
data ParameterKind
  = Plain
  | Secret
  deriving stock (Generic, Eq, Ord, Show)
  deriving anyclass (FromDhall)

-- | An externally injected Hurl variable.
data Parameter = Parameter
  { name :: !ParameterName,
    description :: !(Maybe Text),
    kind :: !ParameterKind,
    -- | Committed default; never allowed for a secret.
    defaultValue :: !(Maybe HurlValueLiteral),
    -- | Environment variable that supplies the value at run time.
    environment :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | A file of one or more complete Hurl entries, relative to the workspace
--   root.
data Fragment = Fragment
  { name :: !FragmentName,
    path :: !FilePath,
    description :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | An ordered composition of fragments and the parameters it consumes.
data Workflow = Workflow
  { name :: !WorkflowName,
    fragments :: ![FragmentName],
    parameters :: ![ParameterName],
    description :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | A plain value bound to a parameter.
data Binding = Binding
  { parameter :: !ParameterName,
    value :: !HurlValueLiteral
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | Whether running a recipe may change remote state.
data Safety
  = ReadOnly
  | Mutating
  deriving stock (Generic, Eq, Ord, Show)
  deriving anyclass (FromDhall)

-- | A workflow with committed plain bindings and a safety classification.
data Recipe = Recipe
  { name :: !RecipeName,
    workflow :: !WorkflowName,
    bindings :: ![Binding],
    safety :: !Safety,
    description :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | One named set of bindings layered over a matrix's recipe.
data MatrixCase = MatrixCase
  { name :: !MatrixCaseName,
    bindings :: ![Binding]
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | A recipe applied to several binding sets.
data Matrix = Matrix
  { name :: !MatrixName,
    recipe :: !RecipeName,
    cases :: ![MatrixCase],
    failFast :: !Bool,
    description :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | Export a workspace parameter to a child process under @variable@.
data EnvironmentBinding = EnvironmentBinding
  { variable :: !Text,
    parameter :: !ParameterName
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | A process invocation as an executable plus argv. There is deliberately
--   no shell-string form.
data CommandSpec = CommandSpec
  { executable :: !Text,
    arguments :: ![Text],
    workingDirectory :: !(Maybe FilePath),
    environment :: ![EnvironmentBinding]
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | Poll an HTTP URL until it answers with the expected status.
data HttpReadiness = HttpReadiness
  { url :: !Text,
    expectedStatus :: !Natural,
    intervalMilliseconds :: !Natural,
    timeoutSeconds :: !Natural
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | Run a command until it exits successfully.
data CommandReadiness = CommandReadiness
  { command :: !CommandSpec,
    intervalMilliseconds :: !Natural,
    timeoutSeconds :: !Natural
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | How to decide that a service is ready. Dhall alternatives are @Http@ and
--   @Command@.
data Readiness
  = HttpReadinessCheck !HttpReadiness
  | CommandReadinessCheck !CommandReadiness
  deriving stock (Generic, Eq, Show)

instance FromDhall Readiness where
  autoWith _ = genericAutoWith (stripConstructorAffixes "Readiness" "Check")

-- | A managed process that suites can start and stop.
data Service = Service
  { name :: !ServiceName,
    command :: !CommandSpec,
    readiness :: !Readiness,
    shutdownTimeoutSeconds :: !Natural,
    description :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | What a suite runs. Dhall alternatives are @Workflow@, @Recipe@, and
--   @Matrix@.
data RunReference
  = WorkflowRun !WorkflowName
  | RecipeRun !RecipeName
  | MatrixRun !MatrixName
  deriving stock (Generic, Eq, Show)

instance FromDhall RunReference where
  autoWith _ = genericAutoWith (stripConstructorAffixes "" "Run")

-- | A named collection of runs, optionally against a managed service.
data Suite = Suite
  { name :: !SuiteName,
    runs :: ![RunReference],
    service :: !(Maybe ServiceName),
    failFast :: !Bool,
    description :: !(Maybe Text)
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (FromDhall)

-- | Map Haskell constructor names such as @HttpReadinessCheck@ to Dhall
--   alternative names such as @Http@.
stripConstructorAffixes :: Text -> Text -> InterpretOptions
stripConstructorAffixes infix_ suffix =
  defaultInterpretOptions {constructorModifier = strip}
  where
    strip constructor =
      let withoutSuffix = fromMaybe constructor (Text.stripSuffix suffix constructor)
       in fromMaybe withoutSuffix (Text.stripSuffix infix_ withoutSuffix)
