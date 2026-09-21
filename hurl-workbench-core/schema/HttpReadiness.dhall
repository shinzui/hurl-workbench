{- Poll `url` until it answers with `expectedStatus`. -}
{ Type =
    { url : Text
    , expectedStatus : Natural
    , intervalMilliseconds : Natural
    , timeoutSeconds : Natural
    }
, default = { expectedStatus = 200, intervalMilliseconds = 500, timeoutSeconds = 30 }
}
