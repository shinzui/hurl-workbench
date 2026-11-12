-- | Exact {{parameter}} placeholders. Substitution preserves argv boundaries.
module HurlWorkbench.Check.Template (TemplatePart (..), parseTemplate) where

import Data.Text qualified as Text
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Types (ParameterName (..))

data TemplatePart = Literal !Text | Placeholder !ParameterName
  deriving stock (Eq, Show)

parseTemplate :: Text -> Either Text [TemplatePart]
parseTemplate = go
  where
    go remaining = case Text.breakOn "{{" remaining of
      (prefix, rest)
        | "}}" `Text.isInfixOf` prefix -> malformed
        | Text.null rest -> Right [Literal prefix]
        | otherwise ->
            let (name, close) = Text.breakOn "}}" (Text.drop 2 rest)
             in if Text.null close || Text.null name || Text.any (`elem` ['{', '}']) name
                  then malformed
                  else (Literal prefix :) . (Placeholder (ParameterName name) :) <$> go (Text.drop 2 close)
    malformed = Left "malformed parameter placeholder"
