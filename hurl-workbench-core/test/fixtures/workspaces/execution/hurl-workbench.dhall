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
    , recipes =
      [ Schema.Recipe::{
        , name = "health"
        , workflow = "health"
        , safety = Schema.Safety.ReadOnly
        }
      ]
    , matrices =
      [ Schema.Matrix::{
        , name = "health-cases"
        , recipe = "health"
        , cases =
          [ Schema.MatrixCase::{ name = "first" }
          , Schema.MatrixCase::{ name = "second" }
          , Schema.MatrixCase::{ name = "third" }
          ]
        }
      ]
    }
