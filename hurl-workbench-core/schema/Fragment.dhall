{- A file of one or more complete Hurl entries.
   `path` is relative to the directory containing `hurl-workbench.dhall`.
-}
{ Type = { name : Text, path : Text, description : Optional Text }
, default.description = None Text
}
