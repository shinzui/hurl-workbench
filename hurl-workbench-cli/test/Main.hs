module Main (main) where

import Data.Generics.Labels ()
import Data.Text qualified as Text
import HurlWorkbench.Cli (runCommand)
import HurlWorkbench.Cli.Options
import HurlWorkbench.Cli.Output (CommandResult (..))
import HurlWorkbench.Prelude
import Options.Applicative (ParserResult (..), defaultPrefs, execParserPure, renderFailure)
import System.Directory (canonicalizePath)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

main :: IO ()
main = defaultMain (testGroup "hurl-workbench-cli" [parserTests, commandTests])

fixtureDir :: FilePath -> FilePath
fixtureDir name = "../hurl-workbench-core/test/fixtures/workspaces" </> name

fixtureManifest :: FilePath -> FilePath
fixtureManifest name = fixtureDir name </> "hurl-workbench.dhall"

parse :: [String] -> ParserResult Options
parse = execParserPure defaultPrefs parserInfo

parserTests :: TestTree
parserTests =
  testGroup
    "parser"
    [ testCase "validate with an explicit workspace" $
        successOf (parse ["--workspace", "ws.dhall", "validate"])
          >>= (@?= Options (GlobalOptions (Just "ws.dhall")) ValidateCommand),
      testCase "list defaults to all categories" $
        successOf (parse ["list"]) >>= (@?= Options (GlobalOptions Nothing) (ListCommand AllCategories)),
      testCase "list accepts every category name" $
        for_ allListCategories $ \category ->
          successOf (parse ["list", Text.unpack (listCategoryName category)])
            >>= (@?= Options (GlobalOptions Nothing) (ListCommand category)),
      testCase "list rejects an unknown category" $
        case parse ["list", "widgets"] of
          Failure _ -> pure ()
          _ -> assertFailure "expected a parse failure",
      testCase "help lists validate and list, and no longer mentions hello" $ do
        helpText <- case parse ["--help"] of
          Failure failure -> pure (fst (renderFailure failure "hurl-workbench"))
          _ -> assertFailure "expected --help to produce help text"
        assertBool "mentions validate" ("validate" `isIn` helpText)
        assertBool "mentions list" ("list" `isIn` helpText)
        assertBool "mentions --workspace" ("--workspace" `isIn` helpText)
        assertBool "does not mention hello" (not ("hello" `isIn` helpText))
    ]
  where
    isIn needle haystack = Text.pack needle `Text.isInfixOf` Text.pack haystack

successOf :: ParserResult a -> IO a
successOf = \case
  Success a -> pure a
  _ -> assertFailure "expected the arguments to parse"

commandTests :: TestTree
commandTests =
  testGroup
    "commands"
    [ testCase "validate discovers a parent workspace and reports counts" $ do
        result <- runCommand (GlobalOptions Nothing) (fixtureDir "full" </> "hurl") ValidateCommand
        manifest <- canonicalizePath (fixtureManifest "full")
        result
          @?= CommandResult
            { stdoutLines =
                [ "Valid workspace: " <> Text.pack manifest,
                  "5 parameters, 3 fragments, 2 workflows, 1 recipe, 1 matrix, 1 service, 1 suite"
                ],
              stderrLines = [],
              exitCode = ExitSuccess
            },
      testCase "validate reports every invalid reference and exits non-zero" $ do
        result <- runCommand (GlobalOptions (Just (fixtureManifest "missing-reference"))) "." ValidateCommand
        result ^. #exitCode @?= ExitFailure 1
        result ^. #stdoutLines @?= []
        let err = result ^. #stderrLines
        take 1 err @?= take 1 (filter ("Invalid workspace: " `Text.isPrefixOf`) err)
        for_ ["missing-fragment", "missing_parameter", "missing-workflow", "missing-recipe", "missing-matrix", "missing-service"] $ \name ->
          assertBool ("reports " <> Text.unpack name) (any (Text.isInfixOf name) err)
        drop (length err - 1) err @?= ["8 issues found"],
      testCase "a missing explicit workspace is a workbench error" $ do
        result <- runCommand (GlobalOptions (Just "does-not-exist.dhall")) "." ValidateCommand
        result ^. #exitCode @?= ExitFailure 1
        assertBool "names the missing manifest" (any (Text.isInfixOf "workspace manifest not found") (result ^. #stderrLines)),
      testCase "list all groups every category and shows relationships" $ do
        result <- runCommand (GlobalOptions (Just (fixtureManifest "full"))) "." (ListCommand AllCategories)
        result ^. #exitCode @?= ExitSuccess
        let out = result ^. #stdoutLines
        for_ ["Parameters:", "Fragments:", "Workflows:", "Recipes:", "Matrices:", "Services:", "Suites:"] $ \title ->
          assertBool ("has heading " <> Text.unpack title) (title `elem` out)
        assertBool "workflow shares the oauth fragment" (any (Text.isInfixOf "list-properties  oauth, properties") out)
        assertBool "suite lists its runs" (any (Text.isInfixOf "workflow:list-members, recipe:top-properties, matrix:property-page-sizes") out),
      testCase "list parameters names environment variables but never reads them" $ do
        result <- runCommand (GlobalOptions (Just (fixtureManifest "full"))) "." (ListCommand ParametersCategory)
        result ^. #stdoutLines
          @?= [ "NAME           KIND    DEFAULT                    ENVIRONMENT            DESCRIPTION",
                "auth_url       plain   https://auth.example.test  -                      -",
                "base_url       plain   https://api.example.test   -                      -",
                "client_id      plain   -                          EXAMPLE_CLIENT_ID      -",
                "client_secret  secret  -                          EXAMPLE_CLIENT_SECRET  OAuth client secret",
                "top            plain   5                          -                      -"
              ],
      testCase "list of an empty category says so" $ do
        result <- runCommand (GlobalOptions (Just (fixtureManifest "minimal"))) "." (ListCommand SuitesCategory)
        result ^. #stdoutLines @?= ["(none)"]
    ]
