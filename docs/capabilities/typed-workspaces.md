---
type: Capability
title: "Typed and validated workspaces"
description: "Discover, decode, validate, and inspect versioned Dhall workspaces with compatible schema-version-1 defaults."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-1
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "schema/package.dhall"
  - "hurl-workbench validate"
  - "hurl-workbench list"
  - "HurlWorkbench.Workspace.Context"
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Workspace/WorkspaceTest.hs
    proves: "Upward discovery, typed decoding, accumulated validation, and frozen old-manifest compatibility."
  - kind: example
    resource: examples/quick-start/hurl-workbench.dhall
    proves: "A minimal workspace using schema record completion."
  - kind: guide
    resource: docs/reference/workspace.md
    proves: "Public names, paths, fields, and compatibility contract."
---

# Typed and validated workspaces

Import `schema/package.dhall` and use `Schema.Workspace::{ ... }` and per-record
completion. Explicit `--workspace` wins over upward manifest discovery. The CLI
lists parameters, fragments, workflows, recipes, matrices, checks, services, and
suites without resolving runtime secrets. Core callers receive a validated
workspace with category-specific lookups.

Validation checks names, references, parameter channels, canonical fragment and
working paths, service transitions, and check declarations before execution.
`validate` also runs Hurlfmt against every composed workflow.

## Limits

Only schema version 1 is supported. Compatible normalization covers known older
record and union shapes; malformed values and unknown fields remain errors.
Dhall evaluation follows Dhall's own import behavior; workspace path containment
is not a sandbox for arbitrary Dhall imports.
