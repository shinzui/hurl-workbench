---
type: Improvement Request
title: Support several managed services per suite with ordered readiness and setup commands
description: >-
  A suite can own one managed service and no setup or teardown commands, so an integration test
  that needs a database cluster, migrations, a stub provider, an HTTP server, and a background
  worker cannot be a workbench suite without a shell wrapper around it.
generated:
  by: anthropic/claude-fable-5-1
  at: "2026-09-24T14:20:00Z"
requestId: IR-1
status: proposed
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
