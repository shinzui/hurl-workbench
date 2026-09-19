let Schema = ../../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{ name = "padded", defaultValue = Some "value " }
      , Schema.Parameter::{ name = "multiline", defaultValue = Some "line one\nline two" }
      , Schema.Parameter::{ name = "equals", defaultValue = Some "a=b" }
      , Schema.Parameter::{ name = "newUuid" }
      ]
    }
