{- Hurl runs and named service lifecycle barriers. -}
let ServiceStep = ./ServiceStep.dhall

in < Workflow : Text | Recipe : Text | Matrix : Text | Service : ServiceStep >
