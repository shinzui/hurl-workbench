{- A managed process that suites can start, wait for, and stop. -}
let CommandSpec = ./CommandSpec.dhall

let Readiness = ./Readiness.dhall

in  { Type =
        { name : Text
        , command : CommandSpec.Type
        , readiness : Readiness
        , shutdownTimeoutSeconds : Natural
        , description : Optional Text
        }
    , default = { shutdownTimeoutSeconds = 10, description = None Text }
    }
