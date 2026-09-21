-- | Command-line grammar:
--
-- > hurl-workbench [--workspace FILE] validate
-- > hurl-workbench [--workspace FILE] list [all|parameters|fragments|workflows|recipes|matrices|services|suites]
-- > hurl-workbench [--workspace FILE] render (workflow|recipe) NAME [--output FILE]
-- > hurl-workbench [--workspace FILE] run (workflow|recipe) NAME [OPTIONS]
-- > hurl-workbench [--workspace FILE] test (workflow|recipe) NAME [OPTIONS]
-- > hurl-workbench [--workspace FILE] test suite NAME [OPTIONS]
-- > hurl-workbench [--workspace FILE] matrix NAME [OPTIONS]
-- > hurl-workbench doctor
module HurlWorkbench.Cli.Options
  ( Options (..),
    GlobalOptions (..),
    Command (..),
    RenderOptions (..),
    ExecuteOptions (..),
    MatrixOptions (..),
    SuiteCommandOptions (..),
    BindingOptions (..),
    emptyBindingOptions,
    CliHurlOptions (..),
    defaultCliHurlOptions,
    ListCategory (..),
    allListCategories,
    listCategoryName,
    parseListCategory,
    parserInfo,
  )
where

import Data.Text qualified as Text
import HurlWorkbench.Hurl.Run (HurlRunMode (..), HurlVerbosity (..))
import HurlWorkbench.Prelude hiding (argument)
import HurlWorkbench.Run.Batch (PositiveInt, mkPositiveInt)
import HurlWorkbench.Run.Selection (RunSelection (..))
import HurlWorkbench.Suite.Resolve (ReportFormat (..))
import HurlWorkbench.Workspace.Types (MatrixName (..), RecipeName (..), SuiteName (..), WorkflowName (..))
import Options.Applicative
  ( Parser,
    ParserInfo,
    argument,
    auto,
    command,
    completeWith,
    eitherReader,
    flag',
    fullDesc,
    header,
    help,
    helper,
    hsubparser,
    info,
    long,
    many,
    metavar,
    option,
    optional,
    parserOptionGroup,
    progDesc,
    strArgument,
    strOption,
    switch,
    value,
    (<**>),
    (<|>),
  )
import Text.Read (readMaybe)

-- | Parsed argv.
data Options = Options
  { global :: !GlobalOptions,
    cmd :: !Command
  }
  deriving stock (Generic, Eq, Show)

-- | Options shared by every command.
data GlobalOptions = GlobalOptions
  { -- | Explicit manifest; otherwise discovered from the current directory.
    workspace :: !(Maybe FilePath)
  }
  deriving stock (Generic, Eq, Show)

-- | A subcommand.
data Command
  = ValidateCommand
  | ListCommand !ListCategory
  | RenderCommand !RenderOptions
  | RunCommand !ExecuteOptions
  | TestCommand !ExecuteOptions
  | MatrixCommand !MatrixOptions
  | SuiteCommand !SuiteCommandOptions
  | DoctorCommand
  deriving stock (Generic, Eq, Show)

-- | Options for rendering one named workflow.
data RenderOptions = RenderOptions
  { selection :: !RunSelection,
    output :: !(Maybe FilePath),
    explain :: !Bool
  }
  deriving stock (Generic, Eq, Show)

data ExecuteOptions = ExecuteOptions
  { selection :: !RunSelection,
    bindings :: !BindingOptions,
    hurl :: !CliHurlOptions,
    allowMutating :: !Bool
  }
  deriving stock (Generic, Eq, Show)

data MatrixOptions = MatrixOptions
  { matrix :: !MatrixName,
    mode :: !HurlRunMode,
    jobs :: !PositiveInt,
    failFastOverride :: !(Maybe Bool),
    allowMutating :: !Bool,
    outputDirectory :: !(Maybe FilePath),
    overwrite :: !Bool,
    bindings :: !BindingOptions,
    hurl :: !CliHurlOptions
  }
  deriving stock (Generic, Eq, Show)

data SuiteCommandOptions = SuiteCommandOptions
  { suite :: !SuiteName,
    jobs :: !PositiveInt,
    failFastOverride :: !(Maybe Bool),
    allowMutating :: !Bool,
    externalService :: !Bool,
    reportFormats :: ![ReportFormat],
    reportDirectory :: !(Maybe FilePath),
    overwrite :: !Bool,
    bindings :: !BindingOptions,
    hurl :: !CliHurlOptions
  }
  deriving stock (Generic, Eq, Show)

data BindingOptions = BindingOptions
  { variables :: ![Text],
    variableFiles :: ![FilePath],
    secretEnvironments :: ![Text],
    secretFiles :: ![FilePath]
  }
  deriving stock (Generic, Eq, Show)

emptyBindingOptions :: BindingOptions
emptyBindingOptions = BindingOptions [] [] [] []

data CliHurlOptions = CliHurlOptions
  { connectTimeoutSeconds :: !(Maybe Int),
    maxTimeSeconds :: !(Maybe Int),
    retryCount :: !(Maybe Int),
    retryIntervalMilliseconds :: !(Maybe Int),
    insecureTls :: !Bool,
    includeHeaders :: !Bool,
    jsonOutput :: !Bool,
    verbosity :: !(Maybe HurlVerbosity),
    curlExportPath :: !(Maybe FilePath),
    additionalArguments :: ![Text]
  }
  deriving stock (Generic, Eq, Show)

defaultCliHurlOptions :: CliHurlOptions
defaultCliHurlOptions =
  CliHurlOptions
    { connectTimeoutSeconds = Nothing,
      maxTimeSeconds = Nothing,
      retryCount = Nothing,
      retryIntervalMilliseconds = Nothing,
      insecureTls = False,
      includeHeaders = False,
      jsonOutput = False,
      verbosity = Nothing,
      curlExportPath = Nothing,
      additionalArguments = []
    }

data HttpRetryOptions = HttpRetryOptions !(Maybe Int) !(Maybe Int) !(Maybe Int) !(Maybe Int) !Bool

data OutputDiagnosticOptions = OutputDiagnosticOptions !Bool !Bool !(Maybe HurlVerbosity) !(Maybe FilePath)

data BatchControlOptions = BatchControlOptions !HurlRunMode !PositiveInt !(Maybe Bool) !Bool

data MatrixOutputOptions = MatrixOutputOptions !(Maybe FilePath) !Bool !OutputDiagnosticOptions

data SuiteControlOptions = SuiteControlOptions !PositiveInt !(Maybe Bool) !Bool

data SuiteReportOptions = SuiteReportOptions ![ReportFormat] !(Maybe FilePath) !Bool

-- | Which entities @list@ prints.
data ListCategory
  = AllCategories
  | ParametersCategory
  | FragmentsCategory
  | WorkflowsCategory
  | RecipesCategory
  | MatricesCategory
  | ServicesCategory
  | SuitesCategory
  deriving stock (Generic, Eq, Ord, Show, Enum, Bounded)

allListCategories :: [ListCategory]
allListCategories = [minBound .. maxBound]

-- | The command-line spelling of a category.
listCategoryName :: ListCategory -> Text
listCategoryName = \case
  AllCategories -> "all"
  ParametersCategory -> "parameters"
  FragmentsCategory -> "fragments"
  WorkflowsCategory -> "workflows"
  RecipesCategory -> "recipes"
  MatricesCategory -> "matrices"
  ServicesCategory -> "services"
  SuitesCategory -> "suites"

parseListCategory :: String -> Either String ListCategory
parseListCategory raw =
  case filter ((== Text.pack raw) . listCategoryName) allListCategories of
    [category] -> Right category
    _ ->
      Left
        ( "unknown category "
            <> show raw
            <> "; expected one of: "
            <> Text.unpack (Text.intercalate ", " (map listCategoryName allListCategories))
        )

parserInfo :: ParserInfo Options
parserInfo =
  info
    (optionsParser <**> helper)
    ( fullDesc
        <> header "hurl-workbench - compose, explore, and test reusable Hurl workflows"
        <> progDesc "Keep each Hurl entry once, combine entries into named workflows, and validate the workspace that describes them."
    )

optionsParser :: Parser Options
optionsParser = Options <$> globalOptionsParser <*> commandParser

globalOptionsParser :: Parser GlobalOptions
globalOptionsParser =
  parserOptionGroup "Workspace" $
    GlobalOptions
      <$> optional
        ( strOption
            ( long "workspace"
                <> metavar "FILE"
                <> help "Workspace manifest to use instead of discovering hurl-workbench.dhall from the current directory upward"
            )
        )

commandParser :: Parser Command
commandParser =
  hsubparser
    ( command
        "validate"
        ( info
            (pure ValidateCommand)
            (progDesc "Check the workspace and report every problem at once")
        )
        <> command
          "list"
          ( info
              (ListCommand <$> listCategoryParser)
              (progDesc "List the named entities in the workspace")
          )
        <> command
          "render"
          ( info
              renderCommandParser
              (progDesc "Compose and syntax-check inspectable Hurl source")
          )
        <> command
          "run"
          ( info
              (executeCommandParser RunCommand)
              (progDesc "Execute one workflow in Hurl client mode")
          )
        <> command
          "test"
          ( info
              testCommandParser
              (progDesc "Execute one workflow, recipe, or integration suite in Hurl test mode")
          )
        <> command
          "matrix"
          ( info
              (MatrixCommand <$> matrixOptionsParser)
              (progDesc "Execute every declared case in one named matrix")
          )
        <> command
          "doctor"
          ( info
              (pure DoctorCommand)
              (progDesc "Report Hurl and Hurlfmt paths, versions, and support status")
          )
    )

renderCommandParser :: Parser Command
renderCommandParser =
  hsubparser
    ( command
        "workflow"
        ( info
            (RenderCommand <$> renderOptionsParser (SelectWorkflow . WorkflowName . Text.pack))
            (progDesc "Render one named workflow")
        )
        <> command
          "recipe"
          ( info
              (RenderCommand <$> renderOptionsParser (SelectRecipe . RecipeName . Text.pack))
              (progDesc "Render the workflow selected by one named recipe")
          )
    )

renderOptionsParser :: (String -> RunSelection) -> Parser RenderOptions
renderOptionsParser selectionConstructor =
  RenderOptions
    <$> (selectionConstructor <$> strArgument (metavar "NAME" <> help "Workflow or recipe name"))
    <*> parserOptionGroup
      "Output"
      ( optional
          ( strOption
              ( long "output"
                  <> metavar "FILE"
                  <> help "Atomically replace FILE instead of writing Hurl source to stdout"
              )
          )
      )
    <*> switch (long "explain" <> help "Print the recipe's binding sources to stderr without values")

executeCommandParser :: (ExecuteOptions -> Command) -> Parser Command
executeCommandParser constructor =
  hsubparser
    ( command
        "workflow"
        ( info
            (constructor <$> executeOptionsParser (SelectWorkflow . WorkflowName . Text.pack))
            (progDesc "Execute one unclassified low-level workflow")
        )
        <> command
          "recipe"
          ( info
              (constructor <$> executeOptionsParser (SelectRecipe . RecipeName . Text.pack))
              (progDesc "Execute one safety-classified recipe")
          )
    )

testCommandParser :: Parser Command
testCommandParser =
  hsubparser
    ( command
        "workflow"
        ( info
            (TestCommand <$> executeOptionsParser (SelectWorkflow . WorkflowName . Text.pack))
            (progDesc "Execute one unclassified low-level workflow")
        )
        <> command
          "recipe"
          ( info
              (TestCommand <$> executeOptionsParser (SelectRecipe . RecipeName . Text.pack))
              (progDesc "Execute one safety-classified recipe")
          )
        <> command
          "suite"
          ( info
              (SuiteCommand <$> suiteCommandOptionsParser)
              (progDesc "Execute every run in one integration suite")
          )
    )

executeOptionsParser :: (String -> RunSelection) -> Parser ExecuteOptions
executeOptionsParser selectionConstructor =
  ExecuteOptions
    <$> (selectionConstructor <$> strArgument (metavar "NAME" <> help "Workflow or recipe name"))
    <*> bindingOptionsParser
    <*> cliHurlOptionsParser
    <*> parserOptionGroup
      "Execution safety"
      (switch (long "allow-mutating" <> help "Authorize this invocation to run a mutating recipe"))

matrixOptionsParser :: Parser MatrixOptions
matrixOptionsParser =
  assemble
    <$> (MatrixName . Text.pack <$> strArgument (metavar "NAME" <> help "Matrix name"))
    <*> batchControlOptionsParser
    <*> bindingOptionsParser
    <*> httpRetryOptionsParser
    <*> matrixOutputOptionsParser
    <*> advancedArgumentsParser
  where
    assemble
      matrix
      (BatchControlOptions mode jobs failFastOverride allowMutating)
      bindings
      http
      (MatrixOutputOptions outputDirectory overwrite diagnostics)
      additionalArguments =
        MatrixOptions
          { matrix,
            mode,
            jobs,
            failFastOverride,
            allowMutating,
            outputDirectory,
            overwrite,
            bindings,
            hurl = assembleCliHurlOptions http diagnostics additionalArguments
          }

suiteCommandOptionsParser :: Parser SuiteCommandOptions
suiteCommandOptionsParser =
  assemble
    <$> (SuiteName . Text.pack <$> strArgument (metavar "NAME" <> help "Suite name"))
    <*> suiteControlOptionsParser
    <*> parserOptionGroup
      "Service lifecycle"
      (switch (long "external-service" <> help "Use an already-running service and skip managed startup, readiness, and shutdown"))
    <*> suiteReportOptionsParser
    <*> bindingOptionsParser
    <*> httpRetryOptionsParser
    <*> outputDiagnosticOptionsParser
    <*> advancedArgumentsParser
  where
    assemble
      suite
      (SuiteControlOptions jobs failFastOverride allowMutating)
      externalService
      (SuiteReportOptions reportFormats reportDirectory overwrite)
      bindings
      http
      diagnostics
      additionalArguments =
        SuiteCommandOptions
          { suite,
            jobs,
            failFastOverride,
            allowMutating,
            externalService,
            reportFormats,
            reportDirectory,
            overwrite,
            bindings,
            hurl = assembleCliHurlOptions http diagnostics additionalArguments
          }

suiteControlOptionsParser :: Parser SuiteControlOptions
suiteControlOptionsParser =
  parserOptionGroup "Suite control" $
    SuiteControlOptions
      <$> option
        (eitherReader parsePositiveInt)
        (long "jobs" <> metavar "N" <> value oneJob <> help "Maximum concurrent Hurl processes (default: 1)")
      <*> optional
        ( flag' True (long "fail-fast" <> help "Stop scheduling after the first observed failure")
            <|> flag' False (long "keep-going" <> help "Run every case despite failures")
        )
      <*> switch (long "allow-mutating" <> help "Authorize mutating and unclassified runs in this invocation")

suiteReportOptionsParser :: Parser SuiteReportOptions
suiteReportOptionsParser =
  parserOptionGroup "Reports" $
    SuiteReportOptions
      <$> many
        ( option
            (eitherReader parseReportFormat)
            (long "report" <> metavar "junit|html|json|tap" <> help "Emit one isolated report of this format per expanded run; repeat for several formats")
        )
      <*> optional
        (strOption (long "report-dir" <> metavar "DIR" <> help "Write per-run reports and summary.json beneath DIR/SUITE"))
      <*> switch (long "overwrite" <> help "Replace only the selected suite subtree beneath --report-dir")

batchControlOptionsParser :: Parser BatchControlOptions
batchControlOptionsParser =
  parserOptionGroup "Batch control" $
    BatchControlOptions
      <$> option
        (eitherReader parseMode)
        (long "mode" <> metavar "run|test" <> value ClientMode <> help "Use Hurl client mode (run) or test mode")
      <*> option
        (eitherReader parsePositiveInt)
        (long "jobs" <> metavar "N" <> value oneJob <> help "Maximum concurrent Hurl processes (default: 1)")
      <*> optional
        ( flag' True (long "fail-fast" <> help "Stop scheduling after the first observed failure")
            <|> flag' False (long "keep-going" <> help "Run every case despite failures")
        )
      <*> switch (long "allow-mutating" <> help "Authorize every mutating case in this invocation")

matrixOutputOptionsParser :: Parser MatrixOutputOptions
matrixOutputOptionsParser =
  parserOptionGroup "Output" $
    MatrixOutputOptions
      <$> optional
        ( strOption
            (long "output-dir" <> metavar "DIR" <> help "Write one owner-only client response artifact per case")
        )
      <*> switch (long "overwrite" <> help "Replace the exact response artifacts for this batch")
      <*> outputDiagnosticOptionsFields

bindingOptionsParser :: Parser BindingOptions
bindingOptionsParser =
  parserOptionGroup "Bindings" $
    BindingOptions
      <$> many
        ( Text.pack
            <$> strOption
              ( long "variable"
                  <> metavar "NAME=VALUE"
                  <> help "Set one plain workflow parameter; repeat for several parameters"
              )
        )
      <*> many
        ( strOption
            ( long "variables-file"
                <> metavar "FILE"
                <> help "Load plain parameters from a Hurl properties file; later files win"
            )
        )
      <*> many
        ( Text.pack
            <$> strOption
              ( long "secret-env"
                  <> metavar "NAME=ENVIRONMENT_NAME"
                  <> help "Read a secret parameter from the named environment variable"
              )
        )
      <*> many
        ( strOption
            ( long "secrets-file"
                <> metavar "FILE"
                <> help "Load secret parameters from a Hurl secrets file; later files win"
            )
        )

cliHurlOptionsParser :: Parser CliHurlOptions
cliHurlOptionsParser = assembleCliHurlOptions <$> httpRetryOptionsParser <*> outputDiagnosticOptionsParser <*> advancedArgumentsParser

assembleCliHurlOptions :: HttpRetryOptions -> OutputDiagnosticOptions -> [Text] -> CliHurlOptions
assembleCliHurlOptions
  (HttpRetryOptions connectTimeout maxTime retries retryInterval insecure)
  (OutputDiagnosticOptions include json verbosity curl)
  additional =
    CliHurlOptions
      { connectTimeoutSeconds = connectTimeout,
        maxTimeSeconds = maxTime,
        retryCount = retries,
        retryIntervalMilliseconds = retryInterval,
        insecureTls = insecure,
        includeHeaders = include,
        jsonOutput = json,
        verbosity,
        curlExportPath = curl,
        additionalArguments = additional
      }

httpRetryOptionsParser :: Parser HttpRetryOptions
httpRetryOptionsParser =
  parserOptionGroup "HTTP and retry" $
    HttpRetryOptions
      <$> optional (integerOption "connect-timeout" "SECONDS" "Maximum connection time in seconds")
      <*> optional (integerOption "max-time" "SECONDS" "Maximum transfer time in seconds")
      <*> optional (integerOption "retry" "NUM" "Maximum retry count")
      <*> optional (integerOption "retry-interval" "MILLISECONDS" "Delay between retries in milliseconds")
      <*> switch (long "insecure" <> help "Allow insecure TLS connections")

outputDiagnosticOptionsParser :: Parser OutputDiagnosticOptions
outputDiagnosticOptionsParser =
  parserOptionGroup "Output and diagnostics" outputDiagnosticOptionsFields

outputDiagnosticOptionsFields :: Parser OutputDiagnosticOptions
outputDiagnosticOptionsFields =
  OutputDiagnosticOptions
    <$> switch (long "include" <> help "Include response headers in client output")
    <*> switch (long "json" <> help "Emit JSON output where Hurl supports it")
    <*> optional
      ( flag' Verbose (long "verbose" <> help "Enable Hurl verbose diagnostics")
          <|> flag' VeryVerbose (long "very-verbose" <> help "Enable Hurl and libcurl debug diagnostics")
      )
    <*> optional
      ( strOption
          ( long "curl"
              <> metavar "FILE"
              <> help "Export requests as curl commands to an owner-only file"
          )
      )

advancedArgumentsParser :: Parser [Text]
advancedArgumentsParser =
  parserOptionGroup "Advanced Hurl arguments" $
    many
      ( Text.pack
          <$> strOption
            ( long "hurl-arg"
                <> metavar "FLAG"
                <> help "Pass one audited zero-argument Hurl flag"
            )
      )

integerOption :: String -> String -> String -> Parser Int
integerOption name valueName description =
  option auto (long name <> metavar valueName <> help description)

parseMode :: String -> Either String HurlRunMode
parseMode = \case
  "run" -> Right ClientMode
  "test" -> Right TestMode
  other -> Left ("unknown matrix mode " <> show other <> "; expected run or test")

parsePositiveInt :: String -> Either String PositiveInt
parsePositiveInt raw = case readMaybe raw of
  Nothing -> Left ("expected a positive integer, got " <> show raw)
  Just parsedValue -> case mkPositiveInt parsedValue of
    Left _ -> Left ("expected a positive integer, got " <> show raw)
    Right positive -> Right positive

parseReportFormat :: String -> Either String ReportFormat
parseReportFormat = \case
  "junit" -> Right JUnit
  "html" -> Right Html
  "json" -> Right Json
  "tap" -> Right Tap
  other -> Left ("unknown report format " <> show other <> "; expected junit, html, json, or tap")

oneJob :: PositiveInt
oneJob = case mkPositiveInt 1 of
  Right positive -> positive
  Left _ -> error "one is positive"

listCategoryParser :: Parser ListCategory
listCategoryParser =
  argument
    (eitherReader parseListCategory)
    ( metavar "CATEGORY"
        <> value AllCategories
        <> completeWith (map (Text.unpack . listCategoryName) allListCategories)
        <> help "One of all, parameters, fragments, workflows, recipes, matrices, services, suites (default: all)"
    )
