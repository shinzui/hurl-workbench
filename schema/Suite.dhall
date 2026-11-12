{- A non-empty collection of runs, optionally against a managed service. -}
let RunReference = ./RunReference.dhall

let IsolationPolicy = ./IsolationPolicy.dhall

in  { Type =
        { name : Text
        , runs : List RunReference
        , service : Optional Text
        , isolation : IsolationPolicy
        , failFast : Bool
        , description : Optional Text
        }
    , default =
        { service = None Text
        , isolation = IsolationPolicy.SharedState
        , failFast = False
        , description = None Text
        }
    }
