-- | @hurl-workbench list@: print workspace entities and their relationships
--   as aligned, line-oriented tables in declaration order.
--
--   Listing never reads parameter environments and never prints secret
--   values; an @ENVIRONMENT@ column names the variable, not its value.
module HurlWorkbench.Cli.Command.List
  ( runList,
    listLines,
  )
where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import HurlWorkbench.Cli.Options (GlobalOptions, ListCategory (..))
import HurlWorkbench.Cli.Output (CommandResult, renderTable, success)
import HurlWorkbench.Cli.Workspace (withValidatedWorkspace)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context (ValidatedWorkspace, validatedWorkspace)
import HurlWorkbench.Workspace.Types

runList :: GlobalOptions -> FilePath -> ListCategory -> IO CommandResult
runList options currentDirectory category =
  withValidatedWorkspace options currentDirectory (success . listLines category)

listLines :: ListCategory -> ValidatedWorkspace -> [Text]
listLines category vw = case category of
  AllCategories ->
    intercalateBlank
      [ heading title : section c
      | c <- [ParametersCategory .. SuitesCategory],
        let title = categoryTitle c
      ]
  single -> section single
  where
    ws = validatedWorkspace vw
    heading title = title <> ":"
    intercalateBlank = concat . zipWith (\i block -> [Text.empty | i > (0 :: Int)] <> block) [0 ..]
    section = \case
      AllCategories -> []
      ParametersCategory -> table ["NAME", "KIND", "DEFAULT", "ENVIRONMENT", "DESCRIPTION"] (map parameterRow (ws ^. #parameters))
      FragmentsCategory -> table ["NAME", "PATH", "DESCRIPTION"] (map fragmentRow (ws ^. #fragments))
      WorkflowsCategory -> table ["NAME", "FRAGMENTS", "PARAMETERS", "DESCRIPTION"] (map workflowRow (ws ^. #workflows))
      RecipesCategory -> table ["NAME", "WORKFLOW", "SAFETY", "BINDINGS", "DESCRIPTION"] (map recipeRow (ws ^. #recipes))
      MatricesCategory -> table ["NAME", "RECIPE", "CASES", "FAIL-FAST", "DESCRIPTION"] (map matrixRow (ws ^. #matrices))
      ServicesCategory -> table ["NAME", "COMMAND", "READINESS", "DESCRIPTION"] (map serviceRow (ws ^. #services))
      SuitesCategory -> table ["NAME", "RUNS", "SERVICE", "FAIL-FAST", "DESCRIPTION"] (map suiteRow (ws ^. #suites))

table :: [Text] -> [[Text]] -> [Text]
table _ [] = ["(none)"]
table headings rows = renderTable headings rows

categoryTitle :: ListCategory -> Text
categoryTitle = \case
  AllCategories -> "All"
  ParametersCategory -> "Parameters"
  FragmentsCategory -> "Fragments"
  WorkflowsCategory -> "Workflows"
  RecipesCategory -> "Recipes"
  MatricesCategory -> "Matrices"
  ServicesCategory -> "Services"
  SuitesCategory -> "Suites"

parameterRow :: Parameter -> [Text]
parameterRow p =
  [ unParameterName (p ^. #name),
    case p ^. #kind of
      Plain -> "plain"
      Secret -> "secret",
    maybe "" (displayLiteral . hurlValueLiteralText) (p ^. #defaultValue),
    fromMaybe "" (p ^. #environment),
    describe (p ^. #description)
  ]

fragmentRow :: Fragment -> [Text]
fragmentRow f = [unFragmentName (f ^. #name), Text.pack (f ^. #path), describe (f ^. #description)]

workflowRow :: Workflow -> [Text]
workflowRow w =
  [ unWorkflowName (w ^. #name),
    commaList (map unFragmentName (w ^. #fragments)),
    commaList (map unParameterName (w ^. #parameters)),
    describe (w ^. #description)
  ]

recipeRow :: Recipe -> [Text]
recipeRow r =
  [ unRecipeName (r ^. #name),
    unWorkflowName (r ^. #workflow),
    case r ^. #safety of
      ReadOnly -> "read-only"
      Mutating -> "mutating",
    bindingList (r ^. #bindings),
    describe (r ^. #description)
  ]

matrixRow :: Matrix -> [Text]
matrixRow m =
  [ unMatrixName (m ^. #name),
    unRecipeName (m ^. #recipe),
    commaList (map (unMatrixCaseName . view #name) (m ^. #cases)),
    yesNo (m ^. #failFast),
    describe (m ^. #description)
  ]

serviceRow :: Service -> [Text]
serviceRow s =
  [ unServiceName (s ^. #name),
    s ^. #command . #executable,
    case s ^. #readiness of
      HttpReadinessCheck http -> "http " <> http ^. #url
      CommandReadinessCheck check -> "command " <> check ^. #command . #executable,
    describe (s ^. #description)
  ]

suiteRow :: Suite -> [Text]
suiteRow s =
  [ unSuiteName (s ^. #name),
    commaList (map runLabel (s ^. #runs)),
    maybe "" unServiceName (s ^. #service),
    yesNo (s ^. #failFast),
    describe (s ^. #description)
  ]
  where
    runLabel = \case
      WorkflowRun w -> "workflow:" <> unWorkflowName w
      RecipeRun r -> "recipe:" <> unRecipeName r
      MatrixRun m -> "matrix:" <> unMatrixName m

-- | Committed plain bindings are part of the workspace source, so they are
--   safe to display.
bindingList :: [Binding] -> Text
bindingList bindings =
  commaList [unParameterName (b ^. #parameter) <> "=" <> displayLiteral (hurlValueLiteralText (b ^. #value)) | b <- bindings]

displayLiteral :: Text -> Text
displayLiteral value = if Text.null value then "\"\"" else value

commaList :: [Text] -> Text
commaList = Text.intercalate ", "

describe :: Maybe Text -> Text
describe = fromMaybe ""

yesNo :: Bool -> Text
yesNo b = if b then "yes" else "no"
