module HurlWorkbench.Workspace.WorkspaceTest (tests) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Decode
import HurlWorkbench.Workspace.Discover
import HurlWorkbench.Workspace.Error
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory (canonicalizePath, createDirectoryIfMissing, createFileLink)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "workspace"
    [ decodingTests,
      discoveryTests,
      validationTests,
      literalTests
    ]

fixture :: FilePath -> FilePath
fixture name = "test/fixtures/workspaces" </> name </> "hurl-workbench.dhall"

--------------------------------------------------------------------------------
-- Decoding

decodingTests :: TestTree
decodingTests =
  testGroup
    "decoding"
    [ testCase "completion-based and fully specified manifests decode identically" $ do
        completed <- decodeOrFail (fixture "minimal")
        explicit <- decodeOrFail (fixture "minimal-explicit")
        completed @?= explicit
        completed ^. #schemaVersion @?= 1
        map (view #defaultValue) (completed ^. #parameters)
          @?= [Just (literal "https://api.example.test")],
      testCase "a manifest may import sibling Dhall modules" $ do
        ws <- decodeOrFail (fixture "full")
        map (unParameterName . view #name) (ws ^. #parameters)
          @?= ["auth_url", "base_url", "client_id", "client_secret", "top"],
      testCase "an unsupported schema version is reported before typed decoding" $ do
        path <- canonicalizePath (fixture "schema-version")
        result <- decodeWorkspaceFile path
        result @?= Left (UnsupportedSchemaVersion path 2 1),
      testCase "a Dhall type error is reported with the manifest path" $
        withSystemTempDirectory "hurl-workbench" $ \dir -> do
          let manifest = dir </> manifestFileName
          Text.IO.writeFile manifest "{ schemaVersion = 1, fragments = 42 }"
          result <- decodeWorkspaceFile manifest
          case result of
            Left (DhallFailure path message) -> do
              path @?= manifest
              assertBool "mentions the mismatch" ("doesn't match annotation" `Text.isInfixOf` message)
              assertBool "contains no ANSI escapes" (not ("\ESC" `Text.isInfixOf` message))
            other -> assertFailure ("expected a Dhall failure, got " <> show other)
    ]

decodeOrFail :: FilePath -> IO Workspace
decodeOrFail path =
  decodeWorkspaceFile path >>= \case
    Right ws -> pure ws
    Left err -> assertFailure (Text.unpack (renderWorkspaceError err))

literal :: Text -> HurlValueLiteral
literal value = either (error . show) id (mkHurlValueLiteral value)

--------------------------------------------------------------------------------
-- Discovery

discoveryTests :: TestTree
discoveryTests =
  testGroup
    "discovery"
    [ testCase "finds the manifest from a nested child directory" $
        withSystemTempDirectory "hurl-workbench" $ \dir -> do
          writeManifest dir []
          let nested = dir </> "a" </> "b" </> "c"
          createDirectoryIfMissing True nested
          result <- discoverWorkspace Nothing nested
          result @?= Right (DiscoveredWorkspace (dir </> manifestFileName)),
      testCase "an explicit manifest wins over discovery" $
        withSystemTempDirectory "hurl-workbench" $ \dir -> do
          writeManifest dir []
          let other = dir </> "other"
          createDirectoryIfMissing True other
          writeManifest other []
          result <- discoverWorkspace (Just ("other" </> manifestFileName)) dir
          result @?= Right (ExplicitWorkspace (other </> manifestFileName)),
      testCase "a missing explicit manifest is an error, even when discovery would succeed" $
        withSystemTempDirectory "hurl-workbench" $ \dir -> do
          writeManifest dir []
          result <- discoverWorkspace (Just "missing.dhall") dir
          result @?= Left (ManifestNotFound (dir </> "missing.dhall")),
      testCase "discovery stops at the filesystem root" $
        withSystemTempDirectory "hurl-workbench" $ \dir -> do
          result <- discoverWorkspace Nothing dir
          result @?= Left (NoWorkspaceFound dir)
    ]

-- | Write a manifest with the given @(name, path)@ fragments, importing the
--   repository schema by absolute path.
writeManifest :: FilePath -> [(Text, Text)] -> IO ()
writeManifest dir fragmentList = do
  schema <- canonicalizePath schemaPackage
  writeManifestWithSchema schema dir fragmentList

-- | The repository schema, relative to the package directory in which
--   @cabal test@ runs.
schemaPackage :: FilePath
schemaPackage = "../schema/package.dhall"

--------------------------------------------------------------------------------
-- Validation

validationTests :: TestTree
validationTests =
  testGroup
    "validation"
    [ testCase "a complete workspace validates and offers typed lookups" $ do
        vw <- validFixture "full"
        Map.keys (validatedWorkflows vw) @?= [WorkflowName "list-members", WorkflowName "list-properties"]
        let fragmentsOf name = maybe [] (view #fragments) (lookupWorkflow (WorkflowName name) vw)
        -- One OAuth fragment is shared by both resource workflows.
        take 1 (fragmentsOf "list-properties") @?= [FragmentName "oauth"]
        take 1 (fragmentsOf "list-members") @?= [FragmentName "oauth"]
        fmap (view #safety) (lookupRecipe (RecipeName "top-properties") vw) @?= Just ReadOnly
        fmap (length . view #cases) (lookupMatrix (MatrixName "property-page-sizes") vw) @?= Just 2
        fmap (view #service) (lookupSuite (SuiteName "smoke") vw) @?= Just (Just (ServiceName "api"))
        root <- canonicalizePath "test/fixtures/workspaces/full"
        validatedRoot vw @?= WorkspaceRoot root
        lookupFragmentFile (FragmentName "oauth") vw @?= Just (root </> "hurl/oauth.hurl"),
      testCase "every unresolved reference is reported together, in stable order" $ do
        issues <- invalidFixture "missing-reference"
        issues
          @?= [ ValidationIssue "workflows/empty/fragments" "workflow must list at least one fragment",
                ValidationIssue "workflows/flow/fragments" "unknown fragment \"missing-fragment\"",
                ValidationIssue "workflows/flow/parameters" "unknown parameter \"missing_parameter\"",
                ValidationIssue "recipes/orphan/workflow" "unknown workflow \"missing-workflow\"",
                ValidationIssue "matrices/grid/recipe" "unknown recipe \"missing-recipe\"",
                ValidationIssue "matrices/grid/cases" "matrix must have at least one case",
                ValidationIssue "suites/all/runs" "unknown matrix \"missing-matrix\"",
                ValidationIssue "suites/all/service" "unknown service \"missing-service\""
              ]
        again <- invalidFixture "missing-reference"
        again @?= issues,
      testCase "duplicate and malformed names are reported" $ do
        issues <- invalidFixture "duplicate"
        map (view #location) issues @?= ["fragments/a", "workflows/9-bad name", "workflows/flow"]
        assertMentions issues "duplicate fragment name declared 2 times"
        assertMentions issues "duplicate workflow name declared 2 times",
      testCase "unsafe fragment paths are rejected" $ do
        issues <- invalidFixture "escaping-path"
        issues
          @?= [ ValidationIssue "fragments/absolute/path" "path \"/etc/hosts\" must be relative to the workspace root",
                ValidationIssue "fragments/missing/path" "path \"hurl/missing.hurl\" does not exist as a regular file",
                ValidationIssue "fragments/not-hurl/path" "fragment path \"outside-notes.txt\" must end in .hurl",
                ValidationIssue "fragments/parent/path" "path \"../minimal/hurl/health.hurl\" escapes the workspace root"
              ],
      testCase "a symlink that leaves the workspace is rejected" $
        withSystemTempDirectory "hurl-workbench" $ \dir -> do
          let workspaceDir = dir </> "workspace"
          createDirectoryIfMissing True (workspaceDir </> "hurl")
          Text.IO.writeFile (dir </> "outside.hurl") "GET https://example.test\n"
          Text.IO.writeFile (workspaceDir </> "hurl" </> "inside.hurl") "GET https://example.test\n"
          createFileLink (dir </> "outside.hurl") (workspaceDir </> "hurl" </> "escape.hurl")
          createFileLink (workspaceDir </> "hurl" </> "inside.hurl") (workspaceDir </> "hurl" </> "alias.hurl")
          writeManifest workspaceDir [("escape", "hurl/escape.hurl"), ("alias", "hurl/alias.hurl")]
          issues <- invalidManifest (workspaceDir </> manifestFileName)
          issues @?= [ValidationIssue "fragments/escape/path" "path \"hurl/escape.hurl\" escapes the workspace root"],
      testCase "a secret with a committed default is rejected" $ do
        issues <- invalidFixture "secret-default"
        issues @?= [ValidationIssue "parameters/api_key" "secret parameters must not have a committed defaultValue"],
      testCase "values that Hurl variable files cannot carry are rejected with their location" $ do
        issues <- invalidFixture "invalid-value"
        map (view #location) issues
          @?= ["parameters/multiline/defaultValue", "parameters/newUuid", "parameters/padded/defaultValue"]
    ]
  where
    assertMentions issues needle =
      assertBool
        ("expected an issue mentioning " <> Text.unpack needle)
        (any (Text.isInfixOf needle . view #message) issues)

writeManifestWithSchema :: FilePath -> FilePath -> [(Text, Text)] -> IO ()
writeManifestWithSchema schema dir fragmentList =
  Text.IO.writeFile (dir </> manifestFileName) $
    Text.unlines
      [ "let Schema = " <> Text.pack schema,
        "in Schema.Workspace::{ schemaVersion = 1, fragments = ["
          <> Text.intercalate ", " [fragmentLiteral name path | (name, path) <- fragmentList]
          <> "] : List Schema.Fragment.Type }"
      ]
  where
    fragmentLiteral name path = "Schema.Fragment::{ name = \"" <> name <> "\", path = \"" <> path <> "\" }"

loadManifest :: FilePath -> IO (Either (NonEmpty ValidationIssue) ValidatedWorkspace)
loadManifest manifest = do
  context <-
    discoverWorkspace (Just manifest) "." >>= \case
      Left err -> assertFailure (Text.unpack (renderWorkspaceError err))
      Right source ->
        loadWorkspaceContext source >>= \case
          Left err -> assertFailure (Text.unpack (renderWorkspaceError err))
          Right ctx -> pure ctx
  validateWorkspace context

validFixture :: FilePath -> IO ValidatedWorkspace
validFixture name =
  loadManifest (fixture name) >>= \case
    Right vw -> pure vw
    Left issues -> assertFailure (Text.unpack (Text.unlines (map renderValidationIssue (toList issues))))

invalidFixture :: FilePath -> IO [ValidationIssue]
invalidFixture = invalidManifest . fixture

invalidManifest :: FilePath -> IO [ValidationIssue]
invalidManifest manifest =
  loadManifest manifest >>= \case
    Right _ -> assertFailure "expected validation to fail"
    Left issues -> pure (toList issues)

--------------------------------------------------------------------------------
-- Hurl value literals

literalTests :: TestTree
literalTests =
  testGroup
    "HurlValueLiteral"
    [ testCase "accepts values Hurl reads back unchanged" $
        for_ ["", "true", "null", "42", "3.5", "a=b", "has inner space", "\"quoted\""] $ \value ->
          fmap hurlValueLiteralText (mkHurlValueLiteral value) @?= Right value,
      testCase "rejects line breaks and NUL" $
        for_ ["a\nb", "a\rb", "a\0b"] $ \value ->
          mkHurlValueLiteral value @?= Left ContainsLineBreakOrNul,
      testCase "rejects surrounding whitespace that Hurl trims" $
        for_ [" a", "a ", "\ta", "a\x2028", "\x85"] $ \value ->
          mkHurlValueLiteral value @?= Left SurroundingWhitespace
    ]
