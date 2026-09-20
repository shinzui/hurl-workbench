module HurlWorkbench.Workflow.WorkflowTest (tests) where

import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Version (makeVersion)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workflow.Resolve
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Discover (WorkspaceSource (..))
import HurlWorkbench.Workspace.Error (renderWorkspaceError)
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate
import System.Directory
  ( canonicalizePath,
    doesFileExist,
    getPermissions,
    removeFile,
    setOwnerExecutable,
    setPermissions,
  )
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

tests :: TestTree
tests =
  testGroup
    "workflow"
    [ resolutionTests,
      renderingTests,
      hurlfmtTests
    ]

resolutionTests :: TestTree
resolutionTests =
  testGroup
    "resolution"
    [ testCase "resolves declared fragments in workflow order" $
        withSystemTempDirectory "hurl-workbench-resolve" $ \dir -> do
          validated <- makeWorkspace dir [("first", "first.hurl", "GET https://first.test"), ("second", "second.hurl", "GET https://second.test")] [("ordered", ["second", "first"])]
          case resolveWorkflow validated (WorkflowName "ordered") of
            Left err -> assertFailure (Text.unpack (renderWorkflowError err))
            Right resolved ->
              map (view (#fragment . #name)) (NonEmpty.toList (resolved ^. #sourceFragments))
                @?= [FragmentName "second", FragmentName "first"],
      testCase "reports an unknown workflow without a partial lookup" $
        withSystemTempDirectory "hurl-workbench-resolve" $ \dir -> do
          validated <- makeWorkspace dir [("one", "one.hurl", "GET https://one.test")] [("known", ["one"])]
          resolveWorkflow validated (WorkflowName "missing") @?= Left (WorkflowNotFound (WorkflowName "missing"))
    ]

renderingTests :: TestTree
renderingTests =
  testGroup
    "rendering"
    [ testCase "preserves bytes and inserts only required line feeds" $
        withSystemTempDirectory "hurl-workbench-render" $ \dir -> do
          let first = Text.Encoding.encodeUtf8 "GET https://first.test\r\n# café"
              second = "POST https://second.test\n"
              third = "PUT https://third.test\n\n"
              fourth = "DELETE https://fourth.test"
          validated <-
            makeWorkspace
              dir
              [("first", "first.hurl", first), ("second", "second.hurl", second), ("third", "third.hurl", third), ("fourth", "fourth.hurl", fourth)]
              [("flow", ["first", "second", "third", "fourth"])]
          rendered <- renderNamed validated "flow"
          rendered ^. #contents
            @?= Text.Encoding.decodeUtf8 first
              <> "\n\n"
              <> Text.Encoding.decodeUtf8 second
              <> "\n"
              <> Text.Encoding.decodeUtf8 third
              <> Text.Encoding.decodeUtf8 fourth
              <> "\n"
          map (\span_ -> (span_ ^. #fragmentName, span_ ^. #firstLine, span_ ^. #lastLine)) (NonEmpty.toList (rendered ^. #fragmentSpans))
            @?= [ (FragmentName "first", 1, 2),
                  (FragmentName "second", 4, 4),
                  (FragmentName "third", 6, 7),
                  (FragmentName "fourth", 8, 8)
                ],
      testCase "keeps capture and use entries ordered with placeholders unresolved" $ do
        validated <- fullFixture
        rendered <- renderNamed validated "list-properties"
        let output = rendered ^. #contents
            (_beforeCapture, fromCapture) = Text.breakOn "access_token: jsonpath" output
            (_beforeUse, fromUse) = Text.breakOn "Authorization: Bearer {{access_token}}" output
        assertBool "contains the OAuth capture" (not (Text.null fromCapture))
        assertBool "contains the unresolved use" (not (Text.null fromUse))
        assertBool "capture precedes use" (Text.length fromCapture > Text.length fromUse),
      testCase "rejects an empty fragment" $
        withSystemTempDirectory "hurl-workbench-render" $ \dir -> do
          validated <- makeWorkspace dir [("empty", "empty.hurl", "")] [("flow", ["empty"])]
          resolved <- resolveNamed validated "flow"
          renderWorkflow resolved >>= \case
            Left (EmptyFragment (FragmentName "empty") _) -> pure ()
            other -> assertFailure ("expected EmptyFragment, got " <> show other),
      testCase "reports the invalid UTF-8 byte offset" $
        withSystemTempDirectory "hurl-workbench-render" $ \dir -> do
          validated <- makeWorkspace dir [("bad", "bad.hurl", ByteString.pack [0x47, 0x45, 0xFF, 0x54])] [("flow", ["bad"])]
          resolved <- resolveNamed validated "flow"
          renderWorkflow resolved >>= \case
            Left (InvalidFragmentUtf8 (FragmentName "bad") _ 2 _) -> pure ()
            other -> assertFailure ("expected byte offset 2, got " <> show other),
      testCase "turns a post-validation filesystem change into a render error" $
        withSystemTempDirectory "hurl-workbench-render" $ \dir -> do
          validated <- makeWorkspace dir [("gone", "gone.hurl", "GET https://gone.test")] [("flow", ["gone"])]
          resolved <- resolveNamed validated "flow"
          removeFile (dir </> "gone.hurl")
          renderWorkflow resolved >>= \case
            Left (FragmentReadFailed (FragmentName "gone") _ _) -> pure ()
            other -> assertFailure ("expected FragmentReadFailed, got " <> show other)
    ]

hurlfmtTests :: TestTree
hurlfmtTests =
  testGroup
    "hurlfmt"
    [ testCase "parses the released Hurlfmt version format" $ do
        parseHurlfmtVersion "hurlfmt 8.0.1" @?= Just (makeVersion [8, 0, 1])
        parseHurlfmtVersion "not a version" @?= Nothing,
      testCase "maps a Hurlfmt line diagnostic to its source fragment and cleans the temporary file" $
        withSystemTempDirectory "hurl-workbench-format" $ \dir -> do
          validated <- makeWorkspace dir [("broken", "broken.hurl", "GET https://example.test\n[Asserts")] [("flow", ["broken"])]
          rendered <- renderNamed validated "flow"
          executable <- writeFailingHurlfmt dir
          let capabilities = HurlfmtCapabilities (HurlfmtExecutable executable) (makeVersion [8, 0, 1])
          validateRenderedWorkflow capabilities rendered >>= \case
            Left (InvalidHurl (WorkflowName "flow") (Just span_) diagnostics) -> do
              span_ ^. #fragmentName @?= FragmentName "broken"
              assertBool "keeps Hurlfmt diagnostics" ("expecting" `Text.isInfixOf` diagnostics)
            other -> assertFailure ("expected mapped InvalidHurl, got " <> show other)
          temporaryPath <- Text.unpack . Text.strip <$> Text.IO.readFile (executable <> ".called")
          remains <- doesFileExist temporaryPath
          assertBool "temporary Hurl source was removed" (not remains),
      testCase "validates every workflow in stable name order" $
        withSystemTempDirectory "hurl-workbench-format" $ \dir -> do
          validated <-
            makeWorkspace
              dir
              [("broken", "broken.hurl", "GET https://example.test\n[Asserts")]
              [("zeta", ["broken"]), ("alpha", ["broken"])]
          executable <- writeFailingHurlfmt dir
          let capabilities = HurlfmtCapabilities (HurlfmtExecutable executable) (makeVersion [8, 0, 1])
          validateWorkspaceSyntax capabilities validated >>= \case
            Right issues -> map syntaxWorkflowName issues @?= [Just (WorkflowName "alpha"), Just (WorkflowName "zeta")]
            Left err -> assertFailure (Text.unpack (renderDependencyError err)),
      testCase "reports an executable that disappears after detection" $
        withSystemTempDirectory "hurl-workbench-format" $ \dir -> do
          validated <- makeWorkspace dir [("one", "one.hurl", "GET https://one.test")] [("flow", ["one"])]
          rendered <- renderNamed validated "flow"
          let missing = dir </> "missing-hurlfmt"
          validateRenderedWorkflow (HurlfmtCapabilities (HurlfmtExecutable missing) (makeVersion [8, 0, 1])) rendered
            >>= (@?= Left (HurlfmtNotFound missing))
    ]

syntaxWorkflowName :: WorkflowSyntaxError -> Maybe WorkflowName
syntaxWorkflowName = \case
  SyntaxFormatFailed (InvalidHurl name _span _diagnostics) -> Just name
  SyntaxRenderFailed name _err -> Just name
  SyntaxResolutionFailed _err -> Nothing
  SyntaxFormatFailed _err -> Nothing

makeWorkspace :: FilePath -> [(Text, FilePath, ByteString.ByteString)] -> [(Text, [Text])] -> IO ValidatedWorkspace
makeWorkspace directory fragmentInputs workflowInputs = do
  canonicalRoot <- canonicalizePath directory
  for_ fragmentInputs $ \(_name, path, bytes) -> ByteString.writeFile (canonicalRoot </> path) bytes
  let decoded =
        Workspace
          { schemaVersion = supportedSchemaVersion,
            parameters = [],
            fragments = [Fragment (FragmentName name) path Nothing | (name, path, _bytes) <- fragmentInputs],
            workflows =
              [ Workflow
                  { name = WorkflowName name,
                    fragments = map FragmentName fragmentNames,
                    parameters = [],
                    description = Nothing
                  }
              | (name, fragmentNames) <- workflowInputs
              ],
            recipes = [],
            matrices = [],
            services = [],
            suites = []
          }
      context =
        WorkspaceContext
          { manifestPath = canonicalRoot </> "hurl-workbench.dhall",
            workspaceRoot = WorkspaceRoot canonicalRoot,
            workspace = decoded
          }
  validateWorkspace context >>= \case
    Left issues -> assertFailure (Text.unpack (Text.unlines (map renderValidationIssue (toList issues))))
    Right validated -> pure validated

resolveNamed :: ValidatedWorkspace -> Text -> IO ResolvedWorkflow
resolveNamed validated name =
  case resolveWorkflow validated (WorkflowName name) of
    Left err -> assertFailure (Text.unpack (renderWorkflowError err))
    Right resolved -> pure resolved

renderNamed :: ValidatedWorkspace -> Text -> IO RenderedWorkflow
renderNamed validated name = do
  resolved <- resolveNamed validated name
  renderWorkflow resolved >>= \case
    Left err -> assertFailure (Text.unpack (renderRenderError err))
    Right rendered -> pure rendered

fullFixture :: IO ValidatedWorkspace
fullFixture = do
  context <-
    loadWorkspaceContext (ExplicitWorkspace "test/fixtures/workspaces/full/hurl-workbench.dhall") >>= \case
      Left err -> assertFailure (Text.unpack (renderWorkspaceError err))
      Right loaded -> pure loaded
  validateWorkspace context >>= \case
    Left issues -> assertFailure (Text.unpack (Text.unlines (map renderValidationIssue (toList issues))))
    Right validated -> pure validated

writeFailingHurlfmt :: FilePath -> IO FilePath
writeFailingHurlfmt directory = do
  let executable = directory </> "hurlfmt-failure"
  Text.IO.writeFile
    executable
    ( Text.unlines
        [ "#!/bin/sh",
          "last=''",
          "for arg in \"$@\"; do last=\"$arg\"; done",
          "printf '%s\\n' \"$last\" > \"$0.called\"",
          "printf 'error: Parsing JSON\\n  --> %s:2:3\\n   |\\n 2 | [Asserts\\n   |   ^ expecting a closing bracket\\n' \"$last\" >&2",
          "exit 1"
        ]
    )
  permissions <- getPermissions executable
  setPermissions executable (setOwnerExecutable True permissions)
  pure executable
