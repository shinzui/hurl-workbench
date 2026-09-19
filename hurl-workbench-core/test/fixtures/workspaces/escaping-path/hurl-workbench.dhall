let Schema = ../../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , fragments =
      [ Schema.Fragment::{ name = "parent", path = "../minimal/hurl/health.hurl" }
      , Schema.Fragment::{ name = "absolute", path = "/etc/hosts" }
      , Schema.Fragment::{ name = "not-hurl", path = "outside-notes.txt" }
      , Schema.Fragment::{ name = "missing", path = "hurl/missing.hurl" }
      ]
    }
