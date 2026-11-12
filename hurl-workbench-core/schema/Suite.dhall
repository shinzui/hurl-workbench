{- A non-empty collection of runs, optionally against a managed service. -}
let RunReference = ./RunReference.dhall

let CommandSpec = ./CommandSpec.dhall

let IsolationPolicy = ./IsolationPolicy.dhall

in  { Type =
        { name : Text
        , runs : List RunReference
        , service : Optional Text
        , services : List Text
        , setup : List CommandSpec.Type
        , teardown : List CommandSpec.Type
        , commandTimeoutSeconds : Natural
        , cleanupTimeoutSeconds : Natural
        , isolation : IsolationPolicy
        , failFast : Bool
        , description : Optional Text
        }
    , default =
        { service = None Text
        , services = [] : List Text
        , setup = [] : List CommandSpec.Type
        , teardown = [] : List CommandSpec.Type
        , commandTimeoutSeconds = 60
        , cleanupTimeoutSeconds = 30
        , isolation = IsolationPolicy.SharedState
        , failFast = False
        , description = None Text
        }
    }
