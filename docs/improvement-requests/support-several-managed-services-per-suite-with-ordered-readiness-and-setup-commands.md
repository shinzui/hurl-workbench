---
type: Improvement Request
title: Support several managed services per suite with ordered readiness and setup commands
description: >-
  A suite can own one managed service and no setup or teardown commands, so an integration test
  that needs a database cluster, migrations, a stub provider, an HTTP server, and a background
  worker cannot be a workbench suite without a shell wrapper around it.
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-11T16:18:19Z"
requestId: IR-1
status: completed
completedAt: "2026-11-12T14:23:03Z"
targetPlan: docs/plans/10-support-ordered-multi-service-suite-lifecycles.md
resolution: "AC-1 through AC-7 verified by ExecPlan 10 (commits 1d3b545 and 1cae8df): ordered multi-service startup, setup/teardown phases, Stop/Start/Restart barriers at jobs=2, reverse cleanup and exit-4 semantics, and a real Rei 8 API/stub/projection-owner run inside a caller-owned Hinagata lease recorded in docs/evidence/10-multi-service-lifecycle.json, with IR-5 isolation refusal and IR-6 Clean policy jointly exercised. The AC-2 check-failure variant was completed by ExecPlan 13 (commit 64af575, CLI test 'a check failure still tears down services before teardown'). macOS and ARM64 Linux release gates pass."
origin: mori://tan/notification-hub
acceptanceCriteria:
  - id: AC-1
    statement: A suite can declare several managed services, and each one starts only after the previous one's readiness probe has succeeded.
    verification: An example workspace with three fixture services whose start order and readiness order are recorded by the fixtures and asserted by the CLI test suite.
  - id: AC-2
    statement: Setup commands run before the first service starts and teardown commands run after the last service has stopped, including when readiness, a run, or a check fails.
    verification: A fixture that appends to an invocation log, asserted for the success path and for an injected readiness failure.
  - id: AC-3
    statement: A suite run can stop, start, or restart a named managed service between two Hurl runs, and the summary records the lifecycle step with its outcome.
    verification: A fixture service that answers differently before and after a restart, with a workflow asserting each state.
  - id: AC-4
    statement: A failure of any managed service cancels active Hurl children and cleans up every process group with the existing exit 4 semantics.
    verification: The existing lifecycle tests extended to a suite with more than one service.
  - id: AC-5
    statement: "Services shut down in reverse successful-start order after partial startup, failed readiness, unexpected exit, or cancellation; teardown follows service shutdown and preserves the original failure alongside cleanup diagnostics."
    verification: "Record process/phase events while failing the second or third service and interrupting a live suite; assert bounded cleanup and the retained primary failure."
  - id: AC-6
    statement: "Explicit stop/start/restart steps are execution barriers even when jobs is greater than one; an intentional stop is not classified as an unexpected service death."
    verification: "Run Hurl cases around a worker restart with jobs=2 and assert no case overlaps the lifecycle step, readiness is rechecked, and the summary distinguishes expected stop from failure."
  - id: AC-7
    statement: "A real API, stub provider, and projection owner can share an externally leased disposable fixture, and a single accepted mutation is observed by bounded GET polling before all services stop."
    verification: "Add a command/read integration example with all three services and failure/cancellation cases; assert one mutation attempt, owner-backed visibility, and release only after consumer processes exit."
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: "2026-09-24T14:25:00Z"
    document_timestamp: "2026-09-24T14:20:00Z"
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5-1
    effort: high
    context: >-
      The authoring model's own in-repository verification, not an independent review: every claim
      about the workbench was checked at commit a29d26a against docs/reference/workspace.md,
      docs/reference/cli.md, docs/guides/integration-testing.md, ADR 6, ADR 7,
      hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs (fixed --file-root), and flake.module.nix
      (packages.default exists, so packaging was not filed), and every claim about the requesting
      project against scripts/runtime-acceptance.sh and api/test/hurl in mori://tan/notification-hub.
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
      Author's source assessment for the Rei adoption amendment, not independent
      approval or implementation acceptance. Checked the current command, suite,
      and lifecycle interfaces against Rei MP29 fixture requirements. Historical
      reviews and confirmations remain tied to their original document revision.
verified:
  - by: anthropic/claude-fable-5-1
    at: "2026-09-24T14:25:00Z"
---

# Support several managed services per suite with ordered readiness and setup commands

## Context

`mori://tan/notification-hub` proves its runtime with a process acceptance harness
(`scripts/runtime-acceptance.sh` in that repository). One run creates a PostgreSQL cluster with
`initdb` and `pg_ctl`, creates a database, applies migrations twice, ensures two Kafka topics, then
starts three processes in order: a stub renderer and provider (HTTP readiness on `/health`), the
HTTP server (readiness on `/health/ready`), and the background worker (readiness by a log pattern).
It runs Hurl families against that environment, stops the worker in the middle of a broadcast,
restarts it, and proves that nothing accepted was redelivered. Cleanup stops the processes and the
cluster and deletes only the topics the run created.

The workbench today gives a suite one optional `service` (`Service` with a `command`, an `Http` or
`Command` readiness probe, and a shutdown timeout), owns it through a POSIX process group
(`docs/adr/6-managed-service-process-group-lifecycle.md`), and states in
`docs/guides/integration-testing.md` that arbitrary pre and post hooks are intentionally outside
the workbench. A wrapper executable that boots everything and stays in the foreground can stand in
as the one service, because the group signal reaches its children, but the wrapper reintroduces the
shell harness the workbench exists to replace, its readiness can only describe one process, and a
mid-suite stop and restart of one member is impossible.

## Request

Let a suite own an ordered list of managed services and a bounded set of commands around them,
keeping every existing safety rule.

- `Suite.services : List Text` in declaration order, each started only after the previous one is
  ready; keep `service` as sugar for a one-element list so existing manifests are unchanged.
- `Suite.setup` and `Suite.teardown : List CommandSpec`, run before the first service starts and
  after the last one stops. They are executables plus argv with environment bindings and no shell
  string, exactly like `CommandSpec` today. Teardown always runs, after success, failure, and
  cancellation.
- A lifecycle step as a run reference, for example `RunReference.Service ServiceStep` with
  `Stop`, `Start`, and `Restart` of a named service, ordered among Hurl runs, so a suite can stop
  a worker, run a workflow, and start it again.
- No new readiness kind is required: a worker without a port is covered by `CommandReadiness`
  running a pattern search over its log file.

## What stays out

Shell strings, hooks that run at arbitrary points, and service configuration derived from recipe
or matrix bindings remain excluded, as ADR 6 and ADR 7 decide. Load generation is not part of this
request.

## Rei adoption amendment — 2026-10-11

mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract supplies a second consumer: its disposable fixture starts the production API, a Mori stub, and an existing projection owner. The workbench interface still owns one service at `a29d26ad5e90aa762de88be18f06fddf67b6d02f`. Replacing that harness requires preserving both public command visibility and the order in which consumers stop before the database lease is released.

Make lifecycle steps barriers around parallel HTTP batches. Intentional worker stops must suspend the relevant monitor rather than trigger the unexpected-exit path. Record every start, readiness, stop, restart, and cleanup outcome by logical service name. Stop successfully started services in reverse order after partial startup; retain the primary test/startup failure separately from cleanup errors, and report failure when cleanup alone fails. Teardown executes within a bounded cleanup phase even after interruption.

Keep a caller-provided PostgreSQL lease outside workbench ownership. In the `mori://shinzui/hinagata` handoff, workbench stops API/stub/worker consumers before returning to lease release. Joint verification with `mori://shinzui/hurl-workbench/okf/improvement-requests/concepts/IR-5` and `mori://shinzui/hurl-workbench/okf/improvement-requests/concepts/IR-6` must preserve scenario isolation and the selected clean environment policy. Existing one-service manifests remain compatible. The added criteria describe required future evidence; this amendment does not claim implementation or passing tests.

## Implementation plan

[ExecPlan 10: Support ordered multi-service suite lifecycles](../plans/10-support-ordered-multi-service-suite-lifecycles.md). ExecPlan 10 delivered AC-1 through AC-7 and the 2026-10-11 amendment on 2026-11-12 (commits `1d3b545` and `1cae8df`). Real-consumer acceptance used the Rei 8.0.0.0 cohort, not Rei 9, inside a caller-owned Hinagata lease; the sanitized record is [docs/evidence/10-multi-service-lifecycle.json](../evidence/10-multi-service-lifecycle.json). AC-2's check-failure variant waited for the executable-check interface and was completed by [ExecPlan 13](../plans/13-run-executable-checks-as-ordered-suite-barriers.md) (commit `64af575`).
