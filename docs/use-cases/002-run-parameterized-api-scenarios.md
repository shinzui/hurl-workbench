---
title: "Use Case 002 — Run Parameterized API Scenarios"
type: Use Case
description: "Run one reusable API workflow across named input cases without copying requests or interleaving their results."
generated:
  by: process:openai-codex
  at: "2026-09-18T18:40:21Z"
verified:
  - by: process:openai-codex
    at: "2026-09-18T18:44:55Z"
reviews:
  - kind: model
    reviewer: process:openai-codex
    reviewed_at: "2026-09-18T18:44:55Z"
    document_timestamp: "2026-09-18T18:40:21Z"
    scope: content-and-metadata
    outcome: approved
    provider: openai
    model: gpt-5.6-sol
    effort: unspecified
    context: Reviewed against the observed parameterized API experiments, batch outcome contracts, and canonical Mori references.
useCaseId: UC-2
status: validated
origin: mori://shinzui/hurl-workbench
themes:
  - developer-tooling
jobs:
  - name: compare-api-behavior-across-cases
    actor: API client developer
    situation: the same resource query must run for several markets, identifiers, or boundary values
    motivation: vary data rather than duplicate and manually edit request files
    outcome: every named case runs the same reviewed workflow with its own resolved inputs and result
  - name: understand-each-concurrent-result
    actor: API client developer
    situation: multiple independent cases run with bounded parallelism
    motivation: diagnose each case without mixed stdout, invented exit codes, or missing provenance
    outcome: each case has isolated output, exact Hurl status when started, and an explicit non-Hurl outcome otherwise
features:
  - name: recipe-and-matrix-expansion
    description: Bind reusable workflow defaults and expand named matrix cases deterministically.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A three-case matrix expands in declared order to three prepared runs with distinct bindings and stable case identities.
    jobs:
      - compare-api-behavior-across-cases
  - name: bounded-isolated-execution
    description: Execute independent cases with bounded concurrency and per-case output capture.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A concurrent three-case run never exceeds the configured limit and reports non-interleaved stdout, stderr, provenance, duration, and outcome for every case.
    jobs:
      - understand-each-concurrent-result
  - name: mutating-run-gate
    description: Require explicit runtime authorization before executing a mutating recipe or matrix.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A mutating case is rejected before Hurl starts unless the invocation explicitly allows mutation; read-only cases need no such flag.
    jobs:
      - compare-api-behavior-across-cases
links:
  - docs/use-cases/index.md
  - docs/use-cases/themes/developer-tooling.md
  - docs/plans/3-execute-hurl-workflows-securely.md
  - docs/plans/4-add-recipes-matrices-and-exploratory-runs.md
  - mori://tan/constellation1-client-hs/repos/constellation1-client-hs
---

# Use Case 002 — Run Parameterized API Scenarios

**Theme:** [developer tooling](themes/developer-tooling.md)

The developer needs to run one request shape against multiple MLS markets, record IDs, or
edge values. Recipes give the workflow a reusable set of defaults; a matrix supplies named
case-specific overrides. Direct workflow runs remain conservative because they have no
declared safety classification.

## Evidence

`mori://tan/constellation1-client-hs/repos/constellation1-client-hs`, in the
project-relative `playground/` experiments, varies closely related OData requests across
resources and cases. The repeated shape and changed inputs establish the parameterization
job.

## Contract validation

| Requirement | Public contract | Owner |
|---|---|---|
| Resolve bindings and execute one case faithfully | `RunRequest`, `RunOutputPolicy`, `HurlRunner`, `RunResult` | [EP-3](../plans/3-execute-hurl-workflows-securely.md) |
| Expand cases and retain truthful outcomes | `RunSelection`, `ExpandedRun`, `PreparedRun`, `BatchCase`, `BatchResult`, typed case outcomes | [EP-4](../plans/4-add-recipes-matrices-and-exploratory-runs.md) |

The contract fails this use case if concurrency inherits shared terminal streams, a skipped
or start-failed case is assigned a fabricated Hurl exit code, or case ordering and identity
change nondeterministically.
