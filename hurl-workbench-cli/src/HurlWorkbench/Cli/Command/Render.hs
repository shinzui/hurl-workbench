-- | @hurl-workbench render workflow@: exact, syntax-checked Hurl output.
module HurlWorkbench.Cli.Command.Render
  ( runRender,
    runRenderWith,
  )
where

import Control.Exception (IOException, displayException, mask, onException, try)
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import HurlWorkbench.Cli.Options (GlobalOptions, RenderOptions)
import HurlWorkbench.Cli.Output (CommandResult (..), failure)
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Parameter.Resolve (BindingSource (..))
import HurlWorkbench.Prelude
import HurlWorkbench.Run.Selection
import HurlWorkbench.Workflow.Render
import System.Directory (canonicalizePath, removeFile, renameFile)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, takeDirectory, takeFileName, (</>))
import System.IO (hClose, hFlush)
import System.IO.Temp (openBinaryTempFile)

runRender :: GlobalOptions -> FilePath -> RenderOptions -> IO CommandResult
runRender = runRenderWith detectHurlfmtCapabilities validateRenderedWorkflow

runRenderWith ::
  IO (Either DependencyError HurlfmtCapabilities) ->
  (HurlfmtCapabilities -> RenderedWorkflow -> IO (Either HurlfmtError ())) ->
  GlobalOptions ->
  FilePath ->
  RenderOptions ->
  IO CommandResult
runRenderWith detectCapabilities validateRendered global currentDirectory options =
  loadValidatedWorkspace global currentDirectory >>= \case
    Left errors -> pure (failure errors)
    Right validated -> case resolveSelection validated (options ^. #selection) of
      Left err -> pure (failure ["error: " <> renderSelectionError err])
      Right (expanded :| []) ->
        renderWorkflow (expanded ^. #workflow) >>= \case
          Left err -> pure (failure ["error: " <> renderRenderError err])
          Right rendered ->
            detectCapabilities >>= \case
              Left err -> pure (failure ["error: " <> renderDependencyError err])
              Right capabilities ->
                validateRendered capabilities rendered >>= \case
                  Left err -> pure (failure ["error: " <> renderHurlfmtError err])
                  Right () -> emitRendered currentDirectory options (explanation options expanded) rendered
      Right _ -> pure (failure ["error: render accepts one workflow or recipe, not a matrix"])

emitRendered :: FilePath -> RenderOptions -> [Text] -> RenderedWorkflow -> IO CommandResult
emitRendered currentDirectory options explanationLines rendered =
  case options ^. #output of
    Nothing ->
      pure
        CommandResult
          { stdoutLines = Text.lines (rendered ^. #contents),
            stderrLines = explanationLines,
            exitCode = ExitSuccess
          }
    Just requested -> do
      let requestedPath = if isAbsolute requested then requested else currentDirectory </> requested
      canonicalOutputResult <- try (canonicalizePath requestedPath)
      case canonicalOutputResult of
        Left (err :: IOException) -> pure (failure ["error: " <> Text.pack (displayException err)])
        Right canonicalOutput
          | canonicalOutput `elem` sourcePaths rendered ->
              pure
                ( failure
                    [ "error: refusing to overwrite source fragment "
                        <> Text.pack canonicalOutput
                    ]
                )
          | otherwise ->
              atomicWrite canonicalOutput (Text.Encoding.encodeUtf8 (rendered ^. #contents)) >>= \case
                Left err -> pure (failure ["error: " <> Text.pack (displayException err)])
                Right () ->
                  pure
                    CommandResult
                      { stdoutLines = [],
                        stderrLines = Text.pack canonicalOutput : explanationLines,
                        exitCode = ExitSuccess
                      }
  where
    sourcePaths = map (view #fragmentPath) . NonEmpty.toList . view #sourceFragments

explanation :: RenderOptions -> ExpandedRun -> [Text]
explanation options expanded
  | not (options ^. #explain) = []
  | null (expanded ^. #bindingLayers) = ["Binding sources: none (direct workflow; safety unclassified)"]
  | otherwise =
      "Binding sources (values redacted):"
        : [ "  "
              <> renderSource (layer ^. #source)
              <> " ("
              <> Text.pack (show (length (layer ^. #values)))
              <> " plain bindings)"
          | layer <- expanded ^. #bindingLayers
          ]
  where
    renderSource = \case
      CommittedBinding label -> label
      source -> Text.pack (show source)

atomicWrite :: FilePath -> ByteString.ByteString -> IO (Either IOException ())
atomicWrite target bytes =
  mask $ \restore -> do
    let directory = takeDirectory target
        template = takeFileName target <> ".tmp"
    opened <- try (openBinaryTempFile directory template)
    case opened of
      Left err -> pure (Left err)
      Right (temporaryPath, handle) -> do
        let cleanup = do
              _ <- try @IOException (hClose handle)
              _ <- try @IOException (removeFile temporaryPath)
              pure ()
            writeAndRename = do
              ByteString.hPut handle bytes
              hFlush handle
              hClose handle
              renameFile temporaryPath target
        try (restore writeAndRename `onException` cleanup)
