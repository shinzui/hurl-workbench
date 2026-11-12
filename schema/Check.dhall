{- A single application-owned executable assertion, run as a suite barrier. -}
let CommandSpec = ./CommandSpec.dhall

in  { Type =
        { name : Text
        , command : CommandSpec.Type
        , expectedStatus : Natural
        , timeoutSeconds : Optional Natural
        , description : Optional Text
        }
    , default =
      { expectedStatus = 0
      , timeoutSeconds = None Natural
      , description = None Text
      }
    }
