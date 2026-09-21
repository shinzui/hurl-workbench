let Schema = ../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{ name = "base_url", defaultValue = Some "http://127.0.0.1:18080" }
      , Schema.Parameter::{ name = "service_port", defaultValue = Some "18080" }
      ]
    , fragments =
      [ Schema.Fragment::{ name = "health", path = "hurl/health.hurl" }
      , Schema.Fragment::{ name = "read-echo", path = "hurl/read-echo.hurl" }
      , Schema.Fragment::{ name = "create", path = "hurl/create.hurl" }
      , Schema.Fragment::{ name = "perimeter", path = "hurl/perimeter.hurl" }
      ]
    , workflows =
      [ Schema.Workflow::{
        , name = "health"
        , fragments = [ "health" ]
        , parameters = [ "base_url" ]
        }
      , Schema.Workflow::{
        , name = "read-echo"
        , fragments = [ "read-echo" ]
        , parameters = [ "base_url" ]
        }
      , Schema.Workflow::{
        , name = "create"
        , fragments = [ "create" ]
        , parameters = [ "base_url" ]
        }
      , Schema.Workflow::{
        , name = "perimeter"
        , fragments = [ "perimeter" ]
        , parameters = [ "base_url" ]
        }
      ]
    , recipes =
      [ Schema.Recipe::{
        , name = "health"
        , workflow = "health"
        , safety = Schema.Safety.ReadOnly
        }
      , Schema.Recipe::{
        , name = "read-echo"
        , workflow = "read-echo"
        , safety = Schema.Safety.ReadOnly
        }
      , Schema.Recipe::{
        , name = "create"
        , workflow = "create"
        , safety = Schema.Safety.Mutating
        }
      , Schema.Recipe::{
        , name = "perimeter"
        , workflow = "perimeter"
        , safety = Schema.Safety.ReadOnly
        }
      ]
    , services =
      [ Schema.Service::{
        , name = "fixture-api"
        , command = Schema.CommandSpec::{
          , executable = "cabal"
          , arguments = [ "--project-dir=../..", "run", "hurl-workbench-fixture-server" ]
          , environment =
            [ Schema.EnvironmentBinding::{ variable = "PORT", parameter = "service_port" } ]
          }
        , readiness =
            Schema.Readiness.Http
              Schema.HttpReadiness::{ url = "http://127.0.0.1:{{service_port}}/health" }
        }
      ]
    , suites =
      [ Schema.Suite::{
        , name = "default"
        , runs =
          [ Schema.RunReference.Recipe "health"
          , Schema.RunReference.Recipe "read-echo"
          ]
        , service = Some "fixture-api"
        , failFast = True
        }
      , Schema.Suite::{
        , name = "writes"
        , runs = [ Schema.RunReference.Recipe "create" ]
        , service = Some "fixture-api"
        , failFast = True
        }
      , Schema.Suite::{
        , name = "perimeter"
        , runs = [ Schema.RunReference.Recipe "perimeter" ]
        , service = Some "fixture-api"
        , failFast = True
        }
      ]
    }
