-- One authentication entry reused by a parameterized resource request.
let Schema = ../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{ name = "auth_url" }
      , Schema.Parameter::{ name = "base_url" }
      , Schema.Parameter::{ name = "client_id" }
      , Schema.Parameter::{
        , name = "client_secret"
        , kind = Schema.ParameterKind.Secret
        }
      , Schema.Parameter::{ name = "top", defaultValue = Some "5" }
      ]
    , fragments =
      [ Schema.Fragment::{ name = "oauth", path = "hurl/oauth.hurl" }
      , Schema.Fragment::{ name = "property", path = "hurl/property.hurl" }
      ]
    , workflows =
      [ Schema.Workflow::{
        , name = "oauth-property"
        , fragments = [ "oauth", "property" ]
        , parameters = [ "auth_url", "base_url", "client_id", "client_secret", "top" ]
        }
      ]
    }
