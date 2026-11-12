-- | Suite-wide inputs only; argv templates never accept Secret or Generated.
module HurlWorkbench.Check.Resolve (ResolvedCheck (..), CheckResolutionError (..), prepareCheck, renderCheckResolutionError) where

import Data.Generics.Labels ()
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Time.Clock (NominalDiffTime)
import HurlWorkbench.Check.Template
import HurlWorkbench.Parameter.Resolve
import HurlWorkbench.Prelude
import HurlWorkbench.Service.Resolve
import HurlWorkbench.Service.Run (prepareCommand)
import HurlWorkbench.Workspace.Context
import HurlWorkbench.Workspace.Types

-- The command's Show instance redacts all resolved values.
data ResolvedCheck = ResolvedCheck
  { name :: !CheckName,
    processConfig :: !ResolvedCommand,
    expectedStatus :: !Int,
    timeout :: !NominalDiffTime
  }
  deriving stock (Generic, Eq, Show)

data CheckResolutionError = CheckBindingFailed !BindingError | CheckCommandFailed !ServiceError | CheckTemplateInvalid | CheckDefinitionMissing
  deriving stock (Generic, Eq, Show)

prepareCheck :: [(String, String)] -> ValidatedWorkspace -> BindingInput -> CheckName -> IO (Either CheckResolutionError ResolvedCheck)
prepareCheck ambient workspace input name = case (lookupCheck name workspace, lookupCheckExecutable name workspace) of
  (Just check, Just executable) -> case traverse parseTemplate (check ^. #command . #arguments) of
    Left _ -> pure (Left CheckTemplateInvalid)
    Right templates -> do
      let required = Set.fromList ([p | parts <- templates, Placeholder p <- parts] <> map (view #parameter) (check ^. #command . #environment))
      resolveParameterSubsetInEnvironment ambient workspace required input <&> \case
        Left err -> Left (CheckBindingFailed err)
        Right bindings -> do
          let render (Literal value) = Right value
              render (Placeholder parameter) = case lookupParameter parameter workspace of
                Just definition | definition ^. #kind == Plain -> maybe (Left CheckTemplateInvalid) (Right . hurlValueLiteralText) (Map.lookup parameter (bindings ^. #variables))
                _ -> Left CheckTemplateInvalid
          arguments <- traverse (fmap Text.unpack . fmap Text.concat . traverse render) templates
          command <- either (Left . CheckCommandFailed) Right (resolveCommand workspace bindings (check ^. #command))
          frozen <- either (Left . CheckCommandFailed) Right (prepareCommand ambient (ServiceName (unCheckName name)) "check" (command & #executable .~ executable & #arguments .~ arguments))
          pure (ResolvedCheck name frozen (fromIntegral (check ^. #expectedStatus)) (maybe 60 fromIntegral (check ^. #timeoutSeconds)))
  _ -> pure (Left CheckDefinitionMissing)

renderCheckResolutionError :: CheckResolutionError -> Text
renderCheckResolutionError = \case
  CheckBindingFailed err -> renderBindingError err
  CheckCommandFailed (ServiceEnvironmentMissing _ _ names) -> "check requires missing environment variables: " <> Text.intercalate ", " names
  CheckCommandFailed _ -> "check command preparation failed"
  CheckTemplateInvalid -> "invalid check argument template"
  CheckDefinitionMissing -> "check definition unavailable"
