{- A process invocation as an executable plus argv; there is no shell-string form.
   `workingDirectory` is relative to the workspace root.
-}
let EnvironmentBinding = ./EnvironmentBinding.dhall

in  { Type =
        { executable : Text
        , arguments : List Text
        , workingDirectory : Optional Text
        , environment : List EnvironmentBinding.Type
        }
    , default =
      { arguments = [] : List Text
      , workingDirectory = None Text
      , environment = [] : List EnvironmentBinding.Type
      }
    }
