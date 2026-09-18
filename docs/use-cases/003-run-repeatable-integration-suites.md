---
title: "Use Case 003 — Run Repeatable Integration Suites"
type: Use Case
description: "Run explicit safe or mutating Hurl suites against an external or managed service with truthful lifecycle and report results."
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
    context: Reviewed against Mori's Hurl suite, service lifecycle contracts, Haskell Jitsurei guidance, and canonical references.
useCaseId: UC-3
status: validated
origin: mori://shinzui/hurl-workbench
themes:
  - developer-tooling
jobs:
  - name: run-safe-suite-in-local-and-ci-environments
    actor: service developer
    situation: an API service is already running locally or in CI and has a known safe test set
    motivation: execute the same explicit suite with reproducible variables and reports
    outcome: only declared safe cases run and their Hurl report and exact results are preserved
  - name: manage-fixture-service-for-a-suite
    actor: service developer
    situation: an integration suite needs a local fixture service that is not running yet
    motivation: start, probe, test, and stop it as one bounded operation
    outcome: tests begin only after readiness and the service is stopped on success, failure, or interruption
features:
  - name: explicit-safe-suite
    description: Select safe resources explicitly while keeping mutating, signed, and perimeter cases separately opt-in.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: The default suite runs only its enumerated read-only cases; adding files to the workspace cannot silently add them to the suite.
    jobs:
      - run-safe-suite-in-local-and-ci-environments
  - name: managed-service-lifecycle
    description: Start a service without a shell, wait for readiness, run prepared cases, and terminate the process group reliably.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A ready fixture runs its suite and is stopped; a never-ready fixture starts no Hurl case, records skipped outcomes, returns orchestration exit 4, and leaves no child process.
    jobs:
      - manage-fixture-service-for-a-suite
  - name: isolated-reports-and-results
    description: Give each suite run collision-free report paths and retain exact per-case Hurl outcomes.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: Parallel suite cases produce distinct report artifacts and stable summaries without overwriting each other or collapsing Hurl statuses.
    jobs:
      - run-safe-suite-in-local-and-ci-environments
links:
  - docs/use-cases/index.md
  - docs/use-cases/themes/developer-tooling.md
  - docs/plans/3-execute-hurl-workflows-securely.md
  - docs/plans/4-add-recipes-matrices-and-exploratory-runs.md
  - docs/plans/5-orchestrate-services-and-integration-test-suites.md
  - mori://shinzui/mori/repos/mori
---

# Use Case 003 — Run Repeatable Integration Suites

**Theme:** [developer tooling](themes/developer-tooling.md)

A service developer wants one suite definition to work against an already-running service
and against a locally managed fixture. Safe cases are enumerated rather than discovered by
glob; mutating and special perimeter scenarios remain explicit opt-ins. Service lifecycle
and Hurl case results remain distinguishable.

## Evidence

`mori://shinzui/mori/repos/mori`, under the project-relative `mori-api/test/hurl/` tree,
uses an explicit safe list and separates mutating, signed, and perimeter cases. Its runner
assumes an existing service and writes Hurl reports, establishing both the useful baseline
and the managed-service gap.

## Contract validation

| Requirement | Public contract | Owner |
|---|---|---|
| Preserve exact Hurl process behavior and reports | `HurlRunner`, `RunRequest`, typed report targets, `RunResult` | [EP-3](../plans/3-execute-hurl-workflows-securely.md) |
| Prepare selections and typed batch outcomes | `RunSelection`, `PreparedRun`, `BatchResult`, typed case outcomes | [EP-4](../plans/4-add-recipes-matrices-and-exploratory-runs.md) |
| Coordinate service readiness, cleanup, suite exit, and skipped work | managed-service and suite orchestration boundary | [EP-5](../plans/5-orchestrate-services-and-integration-test-suites.md) |

The contract fails this use case if suite membership is implicit, service commands pass
through a shell, Hurl runs before readiness, cleanup is best-effort only, or orchestration
failures become indistinguishable from Hurl assertion failures.
