let Schema = ../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , fragments = [ Schema.Fragment::{ name = "a", path = "hurl/a.hurl" } ]
    , workflows =
      [ Schema.Workflow::{
        , name = "flow"
        , fragments = [ "a", "missing-fragment" ]
        , parameters = [ "missing_parameter" ]
        }
      , Schema.Workflow::{ name = "empty", fragments = [] : List Text }
      ]
    , recipes =
      [ Schema.Recipe::{
        , name = "orphan"
        , workflow = "missing-workflow"
        , safety = Schema.Safety.ReadOnly
        }
      ]
    , matrices =
      [ Schema.Matrix::{
        , name = "grid"
        , recipe = "missing-recipe"
        , cases = [] : List Schema.MatrixCase.Type
        }
      ]
    , suites =
      [ Schema.Suite::{
        , name = "all"
        , runs =
          [ Schema.RunReference.Workflow "flow"
          , Schema.RunReference.Matrix "missing-matrix"
          ]
        , service = Some "missing-service"
        }
      ]
    }
