let Schema = ../../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{
        , name = "api_key"
        , kind = Schema.ParameterKind.Secret
        , defaultValue = Some "committed-secret"
        }
      ]
    }
