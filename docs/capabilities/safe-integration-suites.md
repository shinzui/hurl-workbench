---
type: Capability
title: "Preflighted integration suites and reports"
description: "Execute explicit suite membership with shared-state safety gates, bounded Hurl batches, private reports, and redacted summaries."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-5
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.Suite"
  - "hurl-workbench test suite NAME"
  - "HurlWorkbench.Suite.Run"
requires:
  - CAP-4
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Suite/RunTest.hs
    proves: "Early mutation refusal, full preparation, isolated reports, safe refusal summaries, and cancellation."
  - kind: example
    resource: examples/integration-service/hurl-workbench.dhall
    proves: "Default read-only, explicitly mutating, and opt-in perimeter suites."
  - kind: guide
    resource: docs/guides/integration-testing.md
    proves: "Suite authoring, artifacts, failure modes, and ownership."
---

# Preflighted integration suites and reports

Suites expand declared workflows, recipes, and matrices into Hurl runs and can
interleave explicit checks and service barriers. SharedState is the default:
parallel Hurl work must use ReadOnly recipes; shared mutations and unclassified
direct workflows require `--jobs 1 --allow-mutating`. Whole-suite preparation
precedes setup and execution.

Optional JUnit, HTML, JSON, and TAP reports have per-run paths. Selecting a report
directory also writes `summary.json` with logical names, statuses, isolation,
ordered steps, durations, and relative artifacts. Cancellation retains completed
outcomes and finalizes owned children before propagating interruption.

## Limits

Safety classifications are author declarations, not HTTP method inference.
Checks are application-owned executable assertions and carry no recipe safety
classification. A suite containing checks requires a report directory. Summaries
omit input values and captures; Hurl and command output artifacts remain sensitive.
Overwrite applies only to the validated selected suite subtree.

Builds on [CAP-4](recipes-and-bounded-matrices.md).
