{- Run `command` until it exits successfully. -}
let CommandSpec = ./CommandSpec.dhall

in  { Type =
        { command : CommandSpec.Type
        , intervalMilliseconds : Natural
        , timeoutSeconds : Natural
        }
    , default = { intervalMilliseconds = 500, timeoutSeconds = 30 }
    }
