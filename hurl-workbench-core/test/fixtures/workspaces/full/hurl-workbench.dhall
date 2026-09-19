-- One OAuth fragment reused by two resource workflows, plus a recipe, a
-- matrix, a managed service, and a suite.
let Schema = ../../../../../schema/package.dhall

let oauthParameters = [ "auth_url", "client_id", "client_secret" ]

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters = ./parameters.dhall
    , fragments =
      [ Schema.Fragment::{
        , name = "oauth"
        , path = "hurl/oauth.hurl"
        , description = Some "Client-credentials token"
        }
      , Schema.Fragment::{ name = "properties", path = "hurl/properties.hurl" }
      , Schema.Fragment::{ name = "members", path = "hurl/members.hurl" }
      ]
    , workflows =
      [ Schema.Workflow::{
        , name = "list-properties"
        , fragments = [ "oauth", "properties" ]
        , parameters = oauthParameters # [ "base_url", "top" ]
        }
      , Schema.Workflow::{
        , name = "list-members"
        , fragments = [ "oauth", "members" ]
        , parameters = oauthParameters # [ "base_url", "top" ]
        }
      ]
    , recipes =
      [ Schema.Recipe::{
        , name = "top-properties"
        , workflow = "list-properties"
        , bindings = [ Schema.Binding::{ parameter = "top", value = "10" } ]
        , safety = Schema.Safety.ReadOnly
        }
      ]
    , matrices =
      [ Schema.Matrix::{
        , name = "property-page-sizes"
        , recipe = "top-properties"
        , cases =
          [ Schema.MatrixCase::{
            , name = "small"
            , bindings = [ Schema.Binding::{ parameter = "top", value = "1" } ]
            }
          , Schema.MatrixCase::{
            , name = "large"
            , bindings = [ Schema.Binding::{ parameter = "top", value = "100" } ]
            }
          ]
        }
      ]
    , services =
      [ Schema.Service::{
        , name = "api"
        , command = Schema.CommandSpec::{
          , executable = "python3"
          , arguments = [ "-m", "http.server", "8080" ]
          , workingDirectory = Some "."
          , environment =
            [ Schema.EnvironmentBinding::{ variable = "CLIENT_ID", parameter = "client_id" } ]
          }
        , readiness =
            Schema.Readiness.Http
              Schema.HttpReadiness::{ url = "http://127.0.0.1:8080/" }
        }
      ]
    , suites =
      [ Schema.Suite::{
        , name = "smoke"
        , runs =
          [ Schema.RunReference.Workflow "list-members"
          , Schema.RunReference.Recipe "top-properties"
          , Schema.RunReference.Matrix "property-page-sizes"
          ]
        , service = Some "api"
        }
      ]
    }
