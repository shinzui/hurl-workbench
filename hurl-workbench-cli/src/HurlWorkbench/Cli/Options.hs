-- | Command-line grammar:
--
-- > hurl-workbench [--workspace FILE] validate
-- > hurl-workbench [--workspace FILE] list [all|parameters|fragments|workflows|recipes|matrices|services|suites]
module HurlWorkbench.Cli.Options
  ( Options (..),
    GlobalOptions (..),
    Command (..),
    ListCategory (..),
    allListCategories,
    listCategoryName,
    parseListCategory,
    parserInfo,
  )
where

import Data.Text qualified as Text
import HurlWorkbench.Prelude hiding (argument)
import Options.Applicative
  ( Parser,
    ParserInfo,
    argument,
    command,
    completeWith,
    eitherReader,
    fullDesc,
    header,
    help,
    helper,
    hsubparser,
    info,
    long,
    metavar,
    optional,
    parserOptionGroup,
    progDesc,
    strOption,
    value,
    (<**>),
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
  deriving stock (Generic, Eq, Show)

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
    )

listCategoryParser :: Parser ListCategory
listCategoryParser =
  argument
    (eitherReader parseListCategory)
    ( metavar "CATEGORY"
        <> value AllCategories
        <> completeWith (map (Text.unpack . listCategoryName) allListCategories)
        <> help "One of all, parameters, fragments, workflows, recipes, matrices, services, suites (default: all)"
    )
