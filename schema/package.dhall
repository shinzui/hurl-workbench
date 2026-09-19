{- The hurl-workbench workspace schema, version 1.

   Import it by relative path from a workspace manifest:

       let Schema = ../schema/package.dhall
       in  Schema.Workspace::{ schemaVersion = Schema.schemaVersion, ... }

   Record modules expose `Type` and `default` for record completion (`::`).
   Union modules (`ParameterKind`, `Safety`, `Readiness`, `RunReference`) are the
   union types themselves.
-}
{ schemaVersion = 1
, Workspace = ./Workspace.dhall
, Parameter = ./Parameter.dhall
, ParameterKind = ./ParameterKind.dhall
, Fragment = ./Fragment.dhall
, Workflow = ./Workflow.dhall
, Binding = ./Binding.dhall
, Safety = ./Safety.dhall
, Recipe = ./Recipe.dhall
, MatrixCase = ./MatrixCase.dhall
, Matrix = ./Matrix.dhall
, EnvironmentBinding = ./EnvironmentBinding.dhall
, CommandSpec = ./CommandSpec.dhall
, HttpReadiness = ./HttpReadiness.dhall
, CommandReadiness = ./CommandReadiness.dhall
, Readiness = ./Readiness.dhall
, Service = ./Service.dhall
, RunReference = ./RunReference.dhall
, Suite = ./Suite.dhall
}
