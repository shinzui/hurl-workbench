-- | One environment selection contract for managed command consumers.
module HurlWorkbench.Service.Environment (selectEnvironment) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Types (EnvironmentPolicy (..))

-- | Selected inherited names are required even when explicitly overridden.
-- Empty values count as present. No implicit platform variables are introduced.
selectEnvironment :: EnvironmentPolicy -> [(String, String)] -> [(String, String)] -> Either [Text] [(String, String)]
selectEnvironment policy ambient overrides =
  case policy of
    Inherit -> Right (overlay parent)
    Clean names ->
      let missing = filter (\name -> Map.notMember (Text.unpack name) parent) names
       in if null missing
            then Right (overlay (Map.filterWithKey (\key _ -> Text.pack key `elem` names) parent))
            else Left missing
  where
    parent = Map.fromList ambient
    overlay selected = Map.toAscList (Map.fromList overrides `Map.union` selected)
