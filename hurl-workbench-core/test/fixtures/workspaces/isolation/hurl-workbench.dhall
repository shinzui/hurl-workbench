let Schema = ../../../../schema/package.dhall

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
      , Schema.Recipe::{
        , name = "dangerous-health"
        , workflow = "health"
        , safety = Schema.Safety.Mutating
        }
      ]
    , suites =
      [ Schema.Suite::{ name = "mixed", runs = [ Schema.RunReference.Recipe "health", Schema.RunReference.Recipe "dangerous-health", Schema.RunReference.Matrix "writes", Schema.RunReference.Workflow "health" ], service = Some "marker" }
      , Schema.Suite::{ name = "single-write", runs = [ Schema.RunReference.Recipe "dangerous-health" ] }
      , Schema.Suite::{ name = "reads", runs = [ Schema.RunReference.Matrix "health-cases" ] }
      , Schema.Suite::{ name = "independent", runs = [ Schema.RunReference.Matrix "writes" ], isolation = Schema.IsolationPolicy.IndependentState }
      ]
    , services =
      [ Schema.Service::{ name = "marker", command = Schema.CommandSpec::{ executable = "sh", arguments = [ "-c", "touch service-started; exit 1" ] }, readiness = Schema.Readiness.Command Schema.CommandReadiness::{ command = Schema.CommandSpec::{ executable = "sh", arguments = [ "-c", "touch readiness-started; exit 1" ] } } } ]
    , matrices =
      [ Schema.Matrix::{ name = "single-write", recipe = "dangerous-health", cases = [ Schema.MatrixCase::{ name = "only" } ] }
      , Schema.Matrix::{ name = "writes", recipe = "dangerous-health", cases = [ Schema.MatrixCase::{ name = "first" }, Schema.MatrixCase::{ name = "second" } ] }
      , Schema.Matrix::{
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
