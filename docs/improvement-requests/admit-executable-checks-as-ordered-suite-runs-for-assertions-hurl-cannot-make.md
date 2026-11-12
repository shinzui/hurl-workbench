---
type: Improvement Request
title: Admit executable checks as ordered suite runs for assertions Hurl cannot make
description: >-
  Integration suites often need one assertion that is not an HTTP response, such as a row count in
  the service's database or a message on a broker; because the workbench deliberately excludes
  arbitrary hooks, such suites keep a shell harness around the workbench and lose its single
  ordered report.
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-11T16:18:19Z"
requestId: IR-4
status: completed
completedAt: "2026-11-12T14:51:11Z"
targetPlan: docs/plans/13-run-executable-checks-as-ordered-suite-barriers.md
resolution: "AC-1 through AC-6 verified by ExecPlan 13 (commits 64af575 and 7200166): recipe/check/recipe ordering with named check failure in summary.json, Plain-only argv substitution with secrets through environment bindings, containment and duplicate-name validation, barrier ordering at jobs=2 with fail-fast, process-group timeout and cancellation reported apart from cleanup, and a real Rei CLI/HTTP category-parity check on two independent Hinagata clones with a failing mismatch. AC-6 is met through the parity alternative; semantic event-count checks were not exercised. macOS and ARM64 Linux release gates pass (135 core, 52 CLI tests)."
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
  - id: AC-4
    statement: "Executable checks are barriers: preceding runs finish before a check starts and later runs wait for its result, including suites configured with jobs greater than one."
    verification: "A recipe/check/recipe fixture records begin/end events with jobs=2 and proves both ordering boundaries and fail-fast behavior."
  - id: AC-5
    statement: "A check timeout or cancellation terminates its process group within the configured budget and reports the check failure separately from cleanup diagnostics."
    verification: "A check spawning a child process exercises timeout and interruption; assert no remaining child and named status/duration/artifact entries."
  - id: AC-6
    statement: "An application-owned check can compare independently provisioned CLI and HTTP fixture results or semantic event counts using declared runtime inputs without putting credentials in argv or summaries."
    verification: "Add a real command/parity example using supported domain/store APIs; assert mismatches fail and secret sentinels stay out of argv and summary metadata."
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

## Rei adoption amendment — 2026-10-11

mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract requires evidence that HTTP and CLI commands agree on changed/no-op, refusal, persisted facts, and discoverable information. Some checks inspect semantic event counts or compare normalized results from independent CLI/API twins. Those assertions belong in named application-owned executables using supported domain/store APIs; they must not introduce bespoke reads of framework-owned internal tables.

Define checks as ordering barriers around the existing parallel batch engine, not as another concurrently scheduled batch member. Each check owns a bounded process group and report directory. Timeout, cancellation, expected-status mismatch, and cleanup failure must be distinguishable, while fail-fast prevents later dependent steps from starting. Retain the primary check failure if cleanup also fails.

Allow declared runtime inputs to identify the two independent fixture targets. Apply the clean environment policy from `mori://shinzui/hurl-workbench/okf/improvement-requests/concepts/IR-6` when that extension is present. Typed contract/client, schema, and package-closure gates remain independently owned tests; this request enables useful ordered assertions rather than requiring every gate to move into workbench. Existing review entries cover the previous revision; the additional procedures are proposed acceptance evidence.

## Implementation plan

[ExecPlan 13: Run executable checks as ordered suite barriers](../plans/13-run-executable-checks-as-ordered-suite-barriers.md). ExecPlan 13 delivered AC-1 through AC-6 and the 2026-10-11 amendment on 2026-11-12 (commits `64af575` and `7200166`). AC-6 is satisfied by the independently provisioned CLI/HTTP parity alternative; semantic event-count checks were not exercised and complete Rei operation coverage is not claimed.
