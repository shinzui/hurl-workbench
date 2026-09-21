let Schema = ../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , fragments =
      [ Schema.Fragment::{ name = "health", path = "health.hurl" } ]
    , workflows =
      [ Schema.Workflow::{ name = "health", fragments = [ "health" ] } ]
    , recipes =
      [ Schema.Recipe::{
        , name = "health"
        , workflow = "health"
        , safety = Schema.Safety.ReadOnly
        }
      ]
    , services =
      [ Schema.Service::{
        , name = "failure"
        , command = Schema.CommandSpec::{
          , executable = "python3"
          , arguments = [ "-c", "import sys; sys.exit(9)" ]
          }
        , readiness =
            Schema.Readiness.Command
              Schema.CommandReadiness::{
              , command = Schema.CommandSpec::{
                , executable = "python3"
                , arguments = [ "-c", "import time; time.sleep(0.2)" ]
                }
              }
        }
      ]
    , suites =
      [ Schema.Suite::{
        , name = "failure"
        , runs = [ Schema.RunReference.Recipe "health" ]
        , service = Some "failure"
        }
      ]
    }
