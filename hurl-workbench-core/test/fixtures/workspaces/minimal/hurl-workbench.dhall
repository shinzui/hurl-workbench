-- The smallest useful workspace, written with record completion so every
-- defaulted field is omitted.
let Schema = ../../../../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , parameters =
      [ Schema.Parameter::{
        , name = "base_url"
        , defaultValue = Some "https://api.example.test"
        }
      ]
    , fragments = [ Schema.Fragment::{ name = "health", path = "hurl/health.hurl" } ]
    , workflows =
      [ Schema.Workflow::{
        , name = "check-health"
        , fragments = [ "health" ]
        , parameters = [ "base_url" ]
        }
      ]
    }
