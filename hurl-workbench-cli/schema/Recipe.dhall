{- A workflow plus committed plain bindings and an explicit safety class.
   `safety` has no default so that a mutating recipe is never silently read-only.
-}
let Binding = ./Binding.dhall

let Safety = ./Safety.dhall

in  { Type =
        { name : Text
        , workflow : Text
        , bindings : List Binding.Type
        , safety : Safety
        , description : Optional Text
        }
    , default = { bindings = [] : List Binding.Type, description = None Text }
    }
