-- The same workspace as ../minimal, with every field spelled out and no
-- schema import. Both must decode to the same Haskell value.
{ schemaVersion = 1
, parameters =
  [ { name = "base_url"
    , description = None Text
    , kind = < Plain | Secret >.Plain
    , defaultValue = Some "https://api.example.test"
    , environment = None Text
    }
  ]
, fragments =
  [ { name = "health", path = "hurl/health.hurl", description = None Text } ]
, workflows =
  [ { name = "check-health"
    , fragments = [ "health" ]
    , parameters = [ "base_url" ]
    , description = None Text
    }
  ]
, recipes =
    [] : List
           { name : Text
           , workflow : Text
           , bindings : List { parameter : Text, value : Text }
           , safety : < ReadOnly | Mutating >
           , description : Optional Text
           }
, matrices =
    [] : List
           { name : Text
           , recipe : Text
           , cases :
               List { name : Text, bindings : List { parameter : Text, value : Text } }
           , failFast : Bool
           , description : Optional Text
           }
, services =
    [] : List
           { name : Text
           , command :
               { executable : Text
               , arguments : List Text
               , workingDirectory : Optional Text
               , environment : List { variable : Text, parameter : Text }
               }
           , readiness :
               < Http :
                   { url : Text
                   , expectedStatus : Natural
                   , intervalMilliseconds : Natural
                   , timeoutSeconds : Natural
                   }
               | Command :
                   { command :
                       { executable : Text
                       , arguments : List Text
                       , workingDirectory : Optional Text
                       , environment : List { variable : Text, parameter : Text }
                       }
                   , intervalMilliseconds : Natural
                   , timeoutSeconds : Natural
                   }
               >
           , shutdownTimeoutSeconds : Natural
           , description : Optional Text
           }
, suites =
    [] : List
           { name : Text
           , runs : List < Workflow : Text | Recipe : Text | Matrix : Text >
           , service : Optional Text
           , failFast : Bool
           , description : Optional Text
           }
}
