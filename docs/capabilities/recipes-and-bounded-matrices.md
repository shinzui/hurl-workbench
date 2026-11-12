---
type: Capability
title: "Recipes and bounded scenario matrices"
description: "Layer reviewed recipe defaults and named case overrides over a workflow, then execute cases with bounded concurrency and ordered results."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-4
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.Recipe"
  - "Schema.Matrix"
  - "hurl-workbench matrix NAME --mode run|test --jobs N"
  - "HurlWorkbench.Run.Batch"
requires:
  - CAP-3
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Run/SelectionTest.hs
    proves: "Layer precedence, declaration ordering, concurrency bounds, fail-fast, and isolated artifacts."
  - kind: example
    resource: examples/vendor-odata/hurl-workbench.dhall
    proves: "Read-only resource recipes and an MLS matrix using a shared OAuth workflow."
---

# Recipes and bounded scenario matrices

Recipes pair a workflow with committed Plain bindings and `ReadOnly` or
`Mutating` metadata. Matrices apply named case bindings above the recipe layer.
Every run is prepared before scheduling, worker count is bounded, and results
retain declaration order. Fail-fast stops scheduling later work.

Parallel client mode requires `--output-dir` so response bodies have distinct
`MATRIX/CASE.response` files. Existing targets require explicit overwrite;
artifact directories and files use owner-only permissions.

## Limits

Mutating matrices require `--allow-mutating --jobs 1`. Separate Hurl processes do
not establish separate application state. Standalone matrices have no independent
scenario handoff; use a suite for caller-provisioned independent scenarios.

Builds on [CAP-3](secure-hurl-execution.md).
