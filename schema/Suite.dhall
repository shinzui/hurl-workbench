{- A non-empty collection of runs, optionally against a managed service. -}
let RunReference = ./RunReference.dhall

in  { Type =
        { name : Text
        , runs : List RunReference
        , service : Optional Text
        , failFast : Bool
        , description : Optional Text
        }
    , default = { service = None Text, failFast = False, description = None Text }
    }
