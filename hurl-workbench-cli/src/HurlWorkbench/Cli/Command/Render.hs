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
import HurlWorkbench.Cli.Output (CommandResult (..), failure, success)
import HurlWorkbench.Cli.Workspace (loadValidatedWorkspace)
import HurlWorkbench.Hurl.Format
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Render
import HurlWorkbench.Workflow.Resolve
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
    Right validated -> case resolveWorkflow validated (options ^. #workflow) of
      Left err -> pure (failure ["error: " <> renderWorkflowError err])
      Right resolved ->
        renderWorkflow resolved >>= \case
          Left err -> pure (failure ["error: " <> renderRenderError err])
          Right rendered ->
            detectCapabilities >>= \case
              Left err -> pure (failure ["error: " <> renderDependencyError err])
              Right capabilities ->
                validateRendered capabilities rendered >>= \case
                  Left err -> pure (failure ["error: " <> renderHurlfmtError err])
                  Right () -> emitRendered currentDirectory options rendered

emitRendered :: FilePath -> RenderOptions -> RenderedWorkflow -> IO CommandResult
emitRendered currentDirectory options rendered =
  case options ^. #output of
    Nothing -> pure (success (Text.lines (rendered ^. #contents)))
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
                        stderrLines = [Text.pack canonicalOutput],
                        exitCode = ExitSuccess
                      }
  where
    sourcePaths = map (view #fragmentPath) . NonEmpty.toList . view #sourceFragments

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
