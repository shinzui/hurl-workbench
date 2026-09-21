{- An ordered, non-empty list of fragment names and the parameters they consume. -}
{ Type =
    { name : Text
    , fragments : List Text
    , parameters : List Text
    , description : Optional Text
    }
, default = { parameters = [] : List Text, description = None Text }
}
