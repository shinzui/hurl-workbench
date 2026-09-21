{- The top-level value of `hurl-workbench.dhall`.

   `schemaVersion` is required and has no default: a manifest states the schema
   version it was written for, and the workbench rejects versions it does not know.
   Every list defaults to empty so new categories never break existing manifests.
-}
let Parameter = ./Parameter.dhall

let Fragment = ./Fragment.dhall

let Workflow = ./Workflow.dhall

let Recipe = ./Recipe.dhall

let Matrix = ./Matrix.dhall

let Service = ./Service.dhall

let Suite = ./Suite.dhall

in  { Type =
        { schemaVersion : Natural
        , parameters : List Parameter.Type
        , fragments : List Fragment.Type
        , workflows : List Workflow.Type
        , recipes : List Recipe.Type
        , matrices : List Matrix.Type
        , services : List Service.Type
        , suites : List Suite.Type
        }
    , default =
      { parameters = [] : List Parameter.Type
      , fragments = [] : List Fragment.Type
      , workflows = [] : List Workflow.Type
      , recipes = [] : List Recipe.Type
      , matrices = [] : List Matrix.Type
      , services = [] : List Service.Type
      , suites = [] : List Suite.Type
      }
    }
