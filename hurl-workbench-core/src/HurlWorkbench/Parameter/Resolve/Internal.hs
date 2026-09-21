-- | Internal representation of resolved parameter values. The public module
--   keeps the secret constructor and accessor abstract; the Hurl adapter is
--   the only production consumer of 'secretValueText'.
module HurlWorkbench.Parameter.Resolve.Internal
  ( BindingInput (..),
    BindingSource (..),
    SecretValue,
    SecretValueError (..),
    ResolvedBindings (..),
    BindingIssue (..),
    BindingError (..),
    mkSecretValue,
    secretValueText,
  )
where

import HurlWorkbench.Parameter.Properties (PropertyError, PropertyFileKind)
import HurlWorkbench.Prelude
import HurlWorkbench.Workspace.Types

data BindingInput = BindingInput
  { plainOverrides :: !(Map ParameterName HurlValueLiteral),
    secretEnvironmentOverrides :: !(Map ParameterName Text),
    variableFiles :: ![FilePath],
    secretFiles :: ![FilePath]
  }
  deriving stock (Generic, Eq, Show)

data BindingSource
  = ExplicitVariable
  | ExplicitSecretEnvironment !Text
  | VariableFile !FilePath
  | SecretFile !FilePath
  | DeclaredEnvironment !Text
  | DefaultValue
  deriving stock (Generic, Eq, Ord, Show)

newtype SecretValue = SecretValue Text
  deriving stock (Generic, Eq)

instance Show SecretValue where
  show _ = "SecretValue <redacted>"

data SecretValueError
  = SecretContainsLineBreakOrNul
  | SecretHasSurroundingWhitespace
  deriving stock (Generic, Eq, Show)

data ResolvedBindings = ResolvedBindings
  { variables :: !(Map ParameterName HurlValueLiteral),
    secrets :: !(Map ParameterName SecretValue)
  }
  deriving stock (Generic, Eq)

instance Show ResolvedBindings where
  show _ = "ResolvedBindings <redacted>"

data BindingIssue
  = UnexpectedBinding !ParameterName !BindingSource
  | BindingKindMismatch !ParameterName !ParameterKind !BindingSource
  | MissingBinding !ParameterName
  | MissingBindingEnvironment !ParameterName !Text !BindingSource
  | InvalidBindingEnvironmentName !ParameterName !Text !BindingSource
  | InvalidPlainBinding !ParameterName !BindingSource !HurlValueLiteralError
  | InvalidSecretBinding !ParameterName !BindingSource !SecretValueError
  | UnknownDeclaredParameter !ParameterName
  deriving stock (Generic, Eq, Show)

data BindingError
  = BindingFileReadError !PropertyFileKind !FilePath
  | BindingPropertyError !PropertyError
  | BindingIssues !(NonEmpty BindingIssue)
  deriving stock (Generic, Eq, Show)

mkSecretValue :: Text -> Either SecretValueError SecretValue
mkSecretValue value = case mkHurlValueLiteral value of
  Left ContainsLineBreakOrNul -> Left SecretContainsLineBreakOrNul
  Left SurroundingWhitespace -> Left SecretHasSurroundingWhitespace
  Right _ -> Right (SecretValue value)

secretValueText :: SecretValue -> Text
secretValueText (SecretValue value) = value
