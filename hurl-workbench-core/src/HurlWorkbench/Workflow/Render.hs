-- | Byte-faithful composition of complete Hurl entry fragments.
module HurlWorkbench.Workflow.Render
  ( RenderedFragmentSpan (..),
    RenderedWorkflow (..),
    RenderError (..),
    renderWorkflow,
    renderRenderError,
  )
where

import Control.Exception (IOException, displayException, try)
import Data.ByteString qualified as ByteString
import Data.Generics.Labels ()
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import HurlWorkbench.Prelude
import HurlWorkbench.Workflow.Resolve
import HurlWorkbench.Workspace.Types

-- | Inclusive rendered line range occupied by one source fragment. Separator
--   lines inserted by the composer do not belong to either adjacent fragment.
data RenderedFragmentSpan = RenderedFragmentSpan
  { fragmentName :: !FragmentName,
    fragmentPath :: !FilePath,
    firstLine :: !Int,
    lastLine :: !Int
  }
  deriving stock (Generic, Eq, Show)

-- | Deterministic Hurl source plus the provenance needed to explain parser
--   diagnostics.
data RenderedWorkflow = RenderedWorkflow
  { workspaceRoot :: !WorkspaceRoot,
    workflowName :: !WorkflowName,
    sourceFragments :: !(NonEmpty ResolvedFragment),
    fragmentSpans :: !(NonEmpty RenderedFragmentSpan),
    contents :: !Text
  }
  deriving stock (Generic, Eq, Show)

data RenderError
  = FragmentReadFailed !FragmentName !FilePath !Text
  | InvalidFragmentUtf8 !FragmentName !FilePath !Int !Text
  | EmptyFragment !FragmentName !FilePath
  deriving stock (Generic, Eq, Show)

data LoadedFragment = LoadedFragment
  { resolved :: !ResolvedFragment,
    text :: !Text
  }
  deriving stock (Generic, Eq, Show)

renderWorkflow :: ResolvedWorkflow -> IO (Either RenderError RenderedWorkflow)
renderWorkflow resolvedWorkflow = do
  loaded <- traverse loadFragment (resolvedWorkflow ^. #sourceFragments)
  pure $ do
    fragments <- sequenceA loaded
    let (renderedText, spans) = composeFragments fragments
        definition = resolvedWorkflow ^. #workflow
    pure
      RenderedWorkflow
        { workspaceRoot = resolvedWorkflow ^. #workspaceRoot,
          workflowName = definition ^. #name,
          sourceFragments = resolvedWorkflow ^. #sourceFragments,
          fragmentSpans = spans,
          contents = ensureFinalLineFeed renderedText
        }

loadFragment :: ResolvedFragment -> IO (Either RenderError LoadedFragment)
loadFragment resolvedFragment = do
  let definition = resolvedFragment ^. #fragment
      name = definition ^. #name
      path = resolvedFragment ^. #fragmentPath
  readResult <- try (ByteString.readFile path)
  pure $ case readResult of
    Left (err :: IOException) -> Left (FragmentReadFailed name path (Text.pack (displayException err)))
    Right bytes
      | ByteString.null bytes -> Left (EmptyFragment name path)
      | otherwise -> case Text.Encoding.decodeUtf8' bytes of
          Right decoded -> Right LoadedFragment {resolved = resolvedFragment, text = decoded}
          Left err ->
            Left
              ( InvalidFragmentUtf8
                  name
                  path
                  (firstInvalidUtf8Offset bytes)
                  (Text.pack (displayException err))
              )

composeFragments :: NonEmpty LoadedFragment -> (Text, NonEmpty RenderedFragmentSpan)
composeFragments fragments =
  case NonEmpty.toList fragments of
    first : rest ->
      let initialText = first ^. #text
          initialSpan = spanAt 1 first
          initialNextLine = 1 + lineFeeds initialText
          (pieces, spans, _, _) = foldl appendOne ([initialText], [initialSpan], initialNextLine, initialText) rest
       in (Text.concat (reverse pieces), NonEmpty.fromList (reverse spans))
    [] -> error "composeFragments: impossible empty NonEmpty"
  where
    appendOne (pieces, spans, nextLine, priorText) loaded =
      let separator = fragmentSeparator priorText
          first = nextLine + lineFeeds separator
          currentText = loaded ^. #text
          currentSpan = spanAt first loaded
          followingLine = first + lineFeeds currentText
       in (currentText : separator : pieces, currentSpan : spans, followingLine, currentText)

spanAt :: Int -> LoadedFragment -> RenderedFragmentSpan
spanAt first loaded =
  let resolvedFragment = loaded ^. #resolved
      definition = resolvedFragment ^. #fragment
      fragmentText = loaded ^. #text
      final = first + lineFeeds fragmentText - if Text.isSuffixOf "\n" fragmentText then 1 else 0
   in RenderedFragmentSpan
        { fragmentName = definition ^. #name,
          fragmentPath = resolvedFragment ^. #fragmentPath,
          firstLine = first,
          lastLine = max first final
        }

-- | Leave at least one blank line between fragments while never removing
--   source bytes.
fragmentSeparator :: Text -> Text
fragmentSeparator prior
  | Text.isSuffixOf "\n\n" prior = ""
  | Text.isSuffixOf "\n" prior = "\n"
  | otherwise = "\n\n"

ensureFinalLineFeed :: Text -> Text
ensureFinalLineFeed value
  | Text.isSuffixOf "\n" value = value
  | otherwise = value <> "\n"

lineFeeds :: Text -> Int
lineFeeds = Text.count "\n"

-- | Locate the first byte that makes the input invalid UTF-8. The public
--   decoder still decides validity; this scanner exists only to make its
--   otherwise offset-free error actionable.
firstInvalidUtf8Offset :: ByteString.ByteString -> Int
firstInvalidUtf8Offset bytes = go 0
  where
    length_ = ByteString.length bytes
    byte = ByteString.index bytes

    go offset
      | offset >= length_ = max 0 (length_ - 1)
      | current <= 0x7F = go (offset + 1)
      | current >= 0xC2 && current <= 0xDF = continuationSequence offset [continuation]
      | current == 0xE0 = continuationSequence offset [between 0xA0 0xBF, continuation]
      | current >= 0xE1 && current <= 0xEC = continuationSequence offset [continuation, continuation]
      | current == 0xED = continuationSequence offset [between 0x80 0x9F, continuation]
      | current >= 0xEE && current <= 0xEF = continuationSequence offset [continuation, continuation]
      | current == 0xF0 = continuationSequence offset [between 0x90 0xBF, continuation, continuation]
      | current >= 0xF1 && current <= 0xF3 = continuationSequence offset [continuation, continuation, continuation]
      | current == 0xF4 = continuationSequence offset [between 0x80 0x8F, continuation, continuation]
      | otherwise = offset
      where
        current = byte offset

    continuationSequence start checks = check (start + 1) checks
      where
        check next [] = go next
        check next (valid : remaining)
          | next >= length_ = start
          | valid (byte next) = check (next + 1) remaining
          | otherwise = next

    continuation = between 0x80 0xBF
    between lower upper value = value >= lower && value <= upper

renderRenderError :: RenderError -> Text
renderRenderError = \case
  FragmentReadFailed name path message ->
    "could not read fragment " <> quoteName name <> " at " <> Text.pack path <> ": " <> message
  InvalidFragmentUtf8 name path offset message ->
    "fragment "
      <> quoteName name
      <> " at "
      <> Text.pack path
      <> " is not valid UTF-8 at byte offset "
      <> Text.pack (show offset)
      <> ": "
      <> message
  EmptyFragment name path ->
    "fragment " <> quoteName name <> " at " <> Text.pack path <> " is empty"
  where
    quoteName = ("\"" <>) . (<> "\"") . unFragmentName
