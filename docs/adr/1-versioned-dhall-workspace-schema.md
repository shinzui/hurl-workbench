# ADR 1: Versioned Dhall workspace schema with completion defaults


Status: Accepted

Date: 2026-09-19

Origin: [EP-1](../plans/1-define-the-typed-hurl-workspace-contract.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


A hurl-workbench workspace is a `hurl-workbench.dhall` manifest that names Hurl fragment
files and combines them into workflows, recipes, matrices, services, and suites. It must be
authored by hand, reused through Dhall imports, and keep working as later releases add
fields. In Dhall, adding a field to a record type is a breaking change for every expression
that spells the record out in full; the schema-evolution guidance in
`mori://dhall-lang/dhall-haskell/docs/dhall-schema-evolution-pattern` recommends normalizing
user input through record-completion defaults instead.

A manifest written for a newer schema also fails Haskell's typed decode with a long Dhall
type mismatch, which does not tell the user that the real problem is a version skew.


## Decision


The schema lives in this repository under `schema/`, is imported by relative path (never a
network import), and is exposed through `schema/package.dhall`. Every record module exports
`Type` and `default` so manifests use completion (`Schema.Fragment::{ ... }`). Union modules
(`ParameterKind`, `Safety`, `Readiness`, `RunReference`) are the union types themselves.

Compatibility rules for schema version 1:

- A new optional field or category is added with a default in the owning module's
  `default`, so manifests written with completion keep type-checking. Every top-level list
  defaults to empty.
- Fields whose omission would be unsafe or ambiguous stay required and have no default:
  `Workspace.schemaVersion`, and `Recipe.safety` so a mutating recipe can never silently
  become read-only.
- Renaming or removing a field, changing a field's type, or changing a default's meaning is
  an incompatible change and requires a new `schemaVersion`. Compatibility fixtures under
  `hurl-workbench-core/test/fixtures/workspaces/` (a completion-based manifest and a fully
  specified one that must decode to the same value) must keep passing; do not rewrite them
  to hide a break.
- The decoder evaluates the manifest, reads `schemaVersion` from the normalized record,
  and rejects unknown versions before the typed decode. There is no JSON or YAML fallback.

The Haskell field for a parameter's committed value is `defaultValue` (Dhall field
`defaultValue`) because `default` is a Haskell keyword and would also be confusable with
the completion record's `default`.


## Consequences


Manifests stay small and forward-compatible, and a version skew is reported as one sentence
naming both versions. Adding a required field is deliberately expensive: it forces a schema
version bump. The schema directory is part of the product surface and must ship with
releases and examples.
