{- A recipe applied to a non-empty list of uniquely named cases. -}
let MatrixCase = ./MatrixCase.dhall

in  { Type =
        { name : Text
        , recipe : Text
        , cases : List MatrixCase.Type
        , failFast : Bool
        , description : Optional Text
        }
    , default = { failFast = False, description = None Text }
    }
