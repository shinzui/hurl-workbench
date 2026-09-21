let Schema = ../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{ name = "base_url", defaultValue = Some "http://127.0.0.1:18080" }
      , Schema.Parameter::{
        , name = "token"
        , kind = Schema.ParameterKind.Secret
        , environment = Some "QUICKSTART_TOKEN"
        }
      ]
    , fragments = [ Schema.Fragment::{ name = "health", path = "health.hurl" } ]
    , workflows =
      [ Schema.Workflow::{
        , name = "health"
        , fragments = [ "health" ]
        , parameters = [ "base_url", "token" ]
        }
      ]
    }
