---
type: Improvement Request
title: "Declare scenario isolation and guard parallel mutations"
description: "Make suite state sharing explicit and reject parallel mutating or unclassified runs against shared state, while permitting bounded concurrency for independently provisioned fixtures."
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-11T16:18:19Z"
requestId: IR-5
status: completed
completedAt: "2026-11-12T04:23:02Z"
targetPlan: docs/plans/9-declare-scenario-isolation-and-guard-parallel-mutations.md
resolution: "AC-1 through AC-5 verified by ExecPlan 9 (commits f078060 and 0d7a85b): old manifests decode as SharedState, unsafe parallel shared-state runs are refused before any child starts, two real Hinagata-leased databases isolate concurrent writes with duplicate-identity refusal, serial and read-only parallel modes keep working, and success, refusal, setup-failure, and cancellation summaries expose only logical isolation metadata. macOS and ARM64 Linux release gates pass (91 core, 37 CLI tests)."
origin: mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract
acceptanceCriteria:
  - id: AC-1
    statement: "A suite declares shared state or independently provisioned state; an omitted declaration is treated as shared state."
    verification: "Decode original manifests and verify the conservative default without changing existing read-only execution."
  - id: AC-2
    statement: "Preflight rejects jobs greater than one when a shared-state suite includes mutating or unclassified runs, before service or Hurl processes start."
    verification: "Negative CLI cases record zero child starts for a mutating recipe, matrix expansion, and direct workflow."
  - id: AC-3
    statement: "Parallel independent scenarios receive distinct fixture identities, service endpoints, and generated runtime bindings; provisioning or verification failure prevents affected runs from starting."
    verification: "Run two concurrent state-changing scenarios through caller-owned Hinagata leases and services; each sees only its own writes. Inject a duplicate lease or endpoint identity and assert refusal."
  - id: AC-4
    statement: "Serial shared-state mutation suites and parallel shared-state read-only suites continue to work under existing mutating opt-in and fail-fast rules."
    verification: "Regression scenarios cover both execution modes and declaration-ordered summaries."
  - id: AC-5
    statement: "Reports identify the isolation policy and logical scenario identity without exposing connection strings, credentials, or runtime binding values."
    verification: "Inspect JSON reports from success, refusal, setup failure, and cancellation; assert ownership cleanup remains with the fixture provider."
reviews:
  - kind: model
    reviewer: codex-cli
    reviewed_at: "2026-10-11T16:18:19Z"
    document_timestamp: "2026-10-11T16:18:19Z"
    scope: technical-accuracy
    outcome: commented
    provider: openai
    model: gpt-6.1-sol
    effort: high
    context: >-
      Author's source assessment for Rei MP29 adoption, not an independent approval
      or implementation test result. Current interfaces and limitations were checked
      against the repository source and integration documentation; acceptance tests
      below are proposed verification procedures.
---

# Declare scenario isolation and guard parallel mutations

## Context

At source commit `a29d26ad5e90aa762de88be18f06fddf67b6d02f`, `Suite` owns one optional service and `Suite.Resolve` passes the selected `jobs` count to batch execution. The mutating opt-in classifies permission to write; it does not establish independent database or service state for each run. A matrix or suite can therefore schedule state-changing cases against the same fixture.

mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract requires separate disposable fixtures for command families and independent CLI/API twins. Concurrency must preserve that boundary rather than making tests depend on execution order.

## Request

Introduce an explicit isolation policy with a conservative shared-state default. Reject parallel mutating or unclassified shared-state runs at preflight. A serial mutating suite still requires the existing opt-in.

Define an integration contract for caller-provisioned independent scenarios. Each expanded run must receive its own endpoint and opaque fixture identity before concurrency is enabled; a declaration of independence alone is insufficient. A caller-owned runner may provision each fixture and invoke workbench separately. A native batch path must verify the per-run handoff before starting children. Keep database acquisition and release in the provider, such as `mori://shinzui/hinagata`, and record only logical isolation metadata in reports.

## Scope and adoption

This request is a prerequisite for moving parallel mutation execution into workbench. Serial execution under Rei's existing fixture harness remains a valid first adoption. No reusable pool of previously mutated databases or automatic PostgreSQL provisioning is requested. HTTP mutation scenarios retain single POST attempts and bounded GET observation.

## Implementation plan

[ExecPlan 9: Declare scenario isolation and guard parallel mutations](../plans/9-declare-scenario-isolation-and-guard-parallel-mutations.md). ExecPlan 9 delivered AC-1 through AC-5 on 2026-11-12 (commits `f078060` and `0d7a85b`), including the real two-lease Hinagata provider run.
