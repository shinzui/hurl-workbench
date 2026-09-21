-- | Command-line grammar:
--
-- > hurl-workbench [--workspace FILE] validate
-- > hurl-workbench [--workspace FILE] list [all|parameters|fragments|workflows|recipes|matrices|services|suites]
-- > hurl-workbench [--workspace FILE] render workflow NAME [--output FILE]
-- > hurl-workbench [--workspace FILE] run workflow NAME [OPTIONS]
-- > hurl-workbench [--workspace FILE] test workflow NAME [OPTIONS]
-- > hurl-workbench doctor
module HurlWorkbench.Cli.Options
  ( Options (..),
    GlobalOptions (..),
    Command (..),
    RenderOptions (..),
    ExecuteOptions (..),
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
import HurlWorkbench.Hurl.Run (HurlVerbosity (..))
import HurlWorkbench.Prelude hiding (argument)
import HurlWorkbench.Workspace.Types (WorkflowName (..))
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
  | DoctorCommand
  deriving stock (Generic, Eq, Show)

-- | Options for rendering one named workflow.
data RenderOptions = RenderOptions
  { workflow :: !WorkflowName,
    output :: !(Maybe FilePath)
  }
  deriving stock (Generic, Eq, Show)

data ExecuteOptions = ExecuteOptions
  { workflow :: !WorkflowName,
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
              (executeCommandParser TestCommand)
              (progDesc "Execute one workflow in Hurl test mode")
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
            (RenderCommand <$> renderOptionsParser)
            (progDesc "Render one named workflow")
        )
    )

renderOptionsParser :: Parser RenderOptions
renderOptionsParser =
  RenderOptions
    <$> (WorkflowName . Text.pack <$> strArgument (metavar "NAME" <> help "Workflow name"))
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

executeCommandParser :: (ExecuteOptions -> Command) -> Parser Command
executeCommandParser constructor =
  hsubparser
    ( command
        "workflow"
        ( info
            (constructor <$> executeOptionsParser)
            (progDesc "Execute one named workflow")
        )
    )

executeOptionsParser :: Parser ExecuteOptions
executeOptionsParser =
  ExecuteOptions
    <$> (WorkflowName . Text.pack <$> strArgument (metavar "NAME" <> help "Workflow name"))
    <*> bindingOptionsParser
    <*> cliHurlOptionsParser

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
cliHurlOptionsParser = assemble <$> httpRetryOptionsParser <*> outputDiagnosticOptionsParser <*> advancedArgumentsParser
  where
    assemble
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
  parserOptionGroup "Output and diagnostics" $
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

listCategoryParser :: Parser ListCategory
listCategoryParser =
  argument
    (eitherReader parseListCategory)
    ( metavar "CATEGORY"
        <> value AllCategories
        <> completeWith (map (Text.unpack . listCategoryName) allListCategories)
        <> help "One of all, parameters, fragments, workflows, recipes, matrices, services, suites (default: all)"
    )
