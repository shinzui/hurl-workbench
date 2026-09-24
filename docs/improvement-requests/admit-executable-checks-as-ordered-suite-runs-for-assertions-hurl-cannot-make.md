---
type: Improvement Request
title: Admit executable checks as ordered suite runs for assertions Hurl cannot make
description: >-
  Integration suites often need one assertion that is not an HTTP response, such as a row count in
  the service's database or a message on a broker; because the workbench deliberately excludes
  arbitrary hooks, such suites keep a shell harness around the workbench and lose its single
  ordered report.
generated:
  by: anthropic/claude-fable-5-1
  at: "2026-09-24T14:20:00Z"
requestId: IR-4
status: proposed
origin: mori://tan/notification-hub
acceptanceCriteria:
  - id: AC-1
    statement: A suite whose runs are a recipe, a check, and a recipe executes them in that order, and a non-zero check exit marks the suite failed with the check named in summary.json.
    verification: A CLI test with a fixture check executable that exits with a configured status.
  - id: AC-2
    statement: A check's argv may substitute declared plain parameters and can receive secrets only through environment bindings, never in argv.
    verification: Validation fixtures rejecting a secret placeholder in argv and a run asserting the environment binding.
  - id: AC-3
    statement: validate rejects a check whose executable path escapes the workspace root or whose name collides with another check.
    verification: Negative validation fixtures.
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

# Admit executable checks as ordered suite runs for assertions Hurl cannot make

## Context

The consent scenario of `mori://tan/notification-hub` is pure Hurl except for one assertion: after
the marketing notification reads `skipped`, no `sender_attempts` row for it may have reached
`sent`, which is a `psql` count over the service's own tables. Its other scenarios inspect an
outbox row, consume one Kafka record, and wait for a worker log line. Each such assertion keeps a
bash harness around the Hurl files, and the harness, not the workbench, owns ordering and reporting.

`docs/guides/integration-testing.md` says that arbitrary pre and post hooks are intentionally
outside the workbench, and ADR 6 and ADR 7 exclude shell strings and unredacted diagnostics. This
request asks for the narrowest form that keeps those decisions.

## Request

Add a `Check` record and a `RunReference.Check Text`:

- `Check`: `name`, `command : CommandSpec` (executable plus argv with environment bindings, no
  shell), `expectedStatus` (default `0`), optional `timeoutSeconds`, and `description`.
- Argv may use `{{parameter}}` substitution from declared plain bindings, under the rule HTTP
  readiness URLs already follow; secrets reach a check only through environment bindings.
- A check is ordered among Hurl runs in a suite, respects fail-fast, is recorded in `summary.json`
  with the same fields as a run (name, status, duration, relative artifact path), and has its
  captured output stored in the run directory with the same sensitivity as Hurl reports.
- `validate` resolves the executable path inside the workspace root and rejects name collisions.

## What stays out

Checks do not run at arbitrary points, do not see recipe or matrix binding layers beyond the plain
values named in argv, and do not replace Hurl assertions where an HTTP response can carry the fact.
