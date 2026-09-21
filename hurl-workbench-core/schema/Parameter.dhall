{- An externally injected Hurl variable.

   `defaultValue` is a committed plain value and is rejected for secrets.
   `environment` names an environment variable that supplies the value at run time.
-}
let ParameterKind = ./ParameterKind.dhall

in  { Type =
        { name : Text
        , description : Optional Text
        , kind : ParameterKind
        , defaultValue : Optional Text
        , environment : Optional Text
        }
    , default =
      { description = None Text
      , kind = ParameterKind.Plain
      , defaultValue = None Text
      , environment = None Text
      }
    }
