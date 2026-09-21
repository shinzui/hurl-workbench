let Schema = ../../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{ name = "baseUrl" }
      ]
    , fragments =
      [ Schema.Fragment::{ name = "health", path = "hurl/health.hurl" }
      ]
    , workflows =
      [ Schema.Workflow::{
        , name = "health"
        , fragments = [ "health" ]
        , parameters = [ "baseUrl" ]
        }
      ]
    }
