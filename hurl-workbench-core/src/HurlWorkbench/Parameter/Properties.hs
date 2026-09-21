-- | The deliberately small properties-file language accepted by Hurl 8 for
--   variables and secrets. This module parses the transport format; it does
--   not decide whether a parameter is plain or secret in the workspace.
module HurlWorkbench.Parameter.Properties
  ( PropertyFileKind (..),
    PropertyError (..),
    parseVariableProperties,
    parseSecretProperties,
    renderPropertyError,
  )
where

import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Types
import HurlWorkbench.Workspace.Validate (isValidParameterName)

data PropertyFileKind = VariableProperties | SecretProperties
  deriving stock (Generic, Eq, Show)

-- | A parse error which never retains a property value. That invariant is
--   important for secret files because callers may safely render or show it.
data PropertyError
  = InvalidPropertiesUtf8 !PropertyFileKind !FilePath !Int
  | MissingPropertyEquals !PropertyFileKind !FilePath !Int
  | InvalidPropertyName !PropertyFileKind !FilePath !Int !ParameterName
  | DuplicatePropertyName !PropertyFileKind !FilePath !Int !ParameterName
  | InvalidPropertyValue !PropertyFileKind !FilePath !Int !ParameterName !HurlValueLiteralError
  deriving stock (Generic, Eq, Show)

parseVariableProperties :: FilePath -> ByteString -> Either PropertyError (Map ParameterName HurlValueLiteral)
parseVariableProperties path bytes =
  parseProperties VariableProperties path bytes $ \line name value ->
    first (InvalidPropertyValue VariableProperties path line name) (mkHurlValueLiteral value)

parseSecretProperties :: FilePath -> ByteString -> Either PropertyError (Map ParameterName Text)
parseSecretProperties path bytes =
  parseProperties SecretProperties path bytes $ \line name value ->
    hurlValueLiteralText
      <$> first (InvalidPropertyValue SecretProperties path line name) (mkHurlValueLiteral value)

parseProperties :: PropertyFileKind -> FilePath -> ByteString -> (Int -> ParameterName -> Text -> Either PropertyError value) -> Either PropertyError (Map ParameterName value)
parseProperties kind path bytes parseValue = do
  input <- case Text.Encoding.decodeUtf8' bytes of
    Left _err -> Left (InvalidPropertiesUtf8 kind path (firstInvalidUtf8Offset bytes))
    Right value -> Right value
  foldMLine Map.empty (zip [1 ..] (Text.lines input))
  where
    foldMLine values [] = Right values
    foldMLine values ((lineNumber, rawLine) : remaining) =
      let line = Text.strip rawLine
       in if Text.null line || "#" `Text.isPrefixOf` line
            then foldMLine values remaining
            else case Text.breakOn "=" line of
              (_nameText, rest) | Text.null rest -> Left (MissingPropertyEquals kind path lineNumber)
              (nameText, rest) -> do
                let name = ParameterName nameText
                    valueText = Text.drop 1 rest
                unlessEither (isValidParameterName nameText) (InvalidPropertyName kind path lineNumber name)
                unlessEither (Map.notMember name values) (DuplicatePropertyName kind path lineNumber name)
                value <- parseValue lineNumber name valueText
                foldMLine (Map.insert name value values) remaining

unlessEither :: Bool -> err -> Either err ()
unlessEither condition err = if condition then Right () else Left err

firstInvalidUtf8Offset :: ByteString -> Int
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

renderPropertyError :: PropertyError -> Text
renderPropertyError = \case
  InvalidPropertiesUtf8 kind path offset -> prefix kind path <> "is not UTF-8 at byte " <> tshow offset
  MissingPropertyEquals kind path line -> atLine kind path line <> "must contain NAME=VALUE"
  InvalidPropertyName kind path line name -> atLine kind path line <> "has invalid parameter name " <> quote (unParameterName name)
  DuplicatePropertyName kind path line name -> atLine kind path line <> "repeats parameter " <> quote (unParameterName name)
  InvalidPropertyValue kind path line name err ->
    atLine kind path line <> "cannot transport parameter " <> quote (unParameterName name) <> ": " <> renderHurlValueLiteralError err
  where
    prefix kind path = label kind <> " file " <> quote (Text.pack path) <> " "
    atLine kind path line = prefix kind path <> "line " <> tshow line <> " "
    label VariableProperties = "variables"
    label SecretProperties = "secrets"
    quote value = "\"" <> value <> "\""

tshow :: (Show a) => a -> Text
tshow = Text.pack . show
