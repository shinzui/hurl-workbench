let Schema = ../../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , fragments =
      [ Schema.Fragment::{ name = "a", path = "hurl/a.hurl" }
      , Schema.Fragment::{ name = "a", path = "hurl/a.hurl" }
      ]
    , workflows =
      [ Schema.Workflow::{ name = "flow", fragments = [ "a" ] }
      , Schema.Workflow::{ name = "flow", fragments = [ "a" ] }
      , Schema.Workflow::{ name = "9-bad name", fragments = [ "a" ] }
      ]
    }
