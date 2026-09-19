-- A sibling module imported relative to the manifest.
let Schema = ../../../../../schema/package.dhall

in  [ Schema.Parameter::{ name = "auth_url", defaultValue = Some "https://auth.example.test" }
    , Schema.Parameter::{ name = "base_url", defaultValue = Some "https://api.example.test" }
    , Schema.Parameter::{ name = "client_id", environment = Some "EXAMPLE_CLIENT_ID" }
    , Schema.Parameter::{
      , name = "client_secret"
      , kind = Schema.ParameterKind.Secret
      , environment = Some "EXAMPLE_CLIENT_SECRET"
      , description = Some "OAuth client secret"
      }
    , Schema.Parameter::{ name = "top", defaultValue = Some "5" }
    ]
