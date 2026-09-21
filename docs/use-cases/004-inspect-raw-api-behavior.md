---
title: "Use Case 004 — Inspect Raw API Behavior"
type: Use Case
description: "Reproduce a typed-client failure as a faithful Hurl exchange and retain the raw response needed for diagnosis."
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
    context: Reviewed against the observed decoder investigations, raw execution contracts, and canonical Mori references.
useCaseId: UC-4
status: validated
origin: mori://shinzui/hurl-workbench
themes:
  - developer-tooling
jobs:
  - name: diagnose-below-the-typed-client
    actor: typed API client maintainer
    situation: a production-shaped response fails decoding or differs from the documented schema
    motivation: separate wire behavior from client parsing and model assumptions
    outcome: a focused Hurl scenario reproduces the request and preserves status, headers, and body for inspection
  - name: preserve-bespoke-debug-scenario
    actor: typed API client maintainer
    situation: the diagnosis needs custom captures or assertions before it belongs in a broader suite
    motivation: keep native Hurl expressiveness without extending the workbench schema
    outcome: the exact scenario remains runnable and composable as an opaque complete-entry fragment
features:
  - name: faithful-client-output
    description: Preserve Hurl stdout, stderr, and exact exit status whenever the child process starts.
    status: delivered
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A failing diagnostic scenario returns the same Hurl exit status and byte-preserved captured streams as direct execution under the same controlled inputs.
    jobs:
      - diagnose-below-the-typed-client
  - name: native-hurl-scenario-support
    description: Keep request syntax, captures, assertions, comments, and response inspection in opaque Hurl fragments.
    status: delivered
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A bespoke capture-and-assert scenario renders without semantic rewriting and executes through the same runner as ordinary workflows.
    jobs:
      - preserve-bespoke-debug-scenario
  - name: redacted-runtime-boundary
    description: Allow raw response inspection while preventing declared secrets from appearing in argv or workbench diagnostics.
    status: delivered
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: Diagnostic output retains the child response unchanged, while workbench-generated errors and process metadata redact declared secret values.
    jobs:
      - diagnose-below-the-typed-client
links:
  - docs/use-cases/index.md
  - docs/use-cases/themes/developer-tooling.md
  - docs/plans/2-compose-and-render-reusable-hurl-workflows.md
  - docs/plans/3-execute-hurl-workflows-securely.md
  - docs/plans/4-add-recipes-matrices-and-exploratory-runs.md
  - mori://tan/constellation1-client-hs/repos/constellation1-client-hs
---

# Use Case 004 — Inspect Raw API Behavior

**Theme:** [developer tooling](themes/developer-tooling.md)

When a typed API client fails to decode a response, its abstraction is no longer sufficient
evidence. The maintainer reproduces the request as native Hurl, inspects the raw exchange,
and adds focused captures or assertions without teaching the workbench the HTTP grammar.

## Evidence

`mori://tan/constellation1-client-hs/repos/constellation1-client-hs`, beneath the
project-relative `playground/` tree, includes broken-property-decoding and co-buyer
investigations that inspect vendor behavior outside the typed client.

## Contract validation

| Requirement | Public contract | Owner |
|---|---|---|
| Preserve native Hurl text and source provenance | `ResolvedWorkflow`, fragment line spans, `RenderedWorkflow` | [EP-2](../plans/2-compose-and-render-reusable-hurl-workflows.md) |
| Preserve child output and exact status without leaking bindings | `RunOutputPolicy`, `HurlRunner`, `RunResult` | [EP-3](../plans/3-execute-hurl-workflows-securely.md) |
| Run an ad hoc workflow through the same selection path as repeated cases | `RunSelection`, `PreparedRun`, typed outcomes | [EP-4](../plans/4-add-recipes-matrices-and-exploratory-runs.md) |

The contract fails this use case if the workbench parses or rewrites Hurl semantics,
normalizes away diagnostic output, substitutes its own failure status after Hurl starts, or
requires a recipe merely to run a named workflow.
