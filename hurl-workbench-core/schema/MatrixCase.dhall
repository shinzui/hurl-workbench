{- One named set of bindings layered over a matrix's recipe. -}
let Binding = ./Binding.dhall

in  { Type = { name : Text, bindings : List Binding.Type }
    , default.bindings = [] : List Binding.Type
    }
