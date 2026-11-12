---
type: Capability
title: "Executable assertions as ordered suite barriers"
description: "Run named workspace executable checks once between drained Hurl batches with finite deadlines, private captures, and named ordered outcomes."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-11
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.Check"
  - "Schema.RunReference.Check"
  - "hurl-workbench list checks"
  - "hurl-workbench test suite NAME --report-dir DIR"
  - "HurlWorkbench.Check.Run"
requires:
  - CAP-5
  - CAP-7
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Check/RunTest.hs
    proves: "Expected nonzero results, timeout, signal, cancellation, descendants, and cleanup diagnostics."
  - kind: test
    resource: hurl-workbench-cli/test/CheckTest.hs
    proves: "Both jobs=2 barrier edges, whole-suite preflight, checks-only suites, and service death during checks."
  - kind: example
    resource: examples/executable-checks/README.md
    proves: "Independent local CLI/API fixtures with a matching check and deliberate HTTP-only mismatch."
---

# Executable assertions as ordered suite barriers

A Check names a workspace-relative executable and argv, an expected status
(default 0), and an optional positive timeout (default 60 seconds). Plain argv
placeholders remain individual arguments without shell splitting; Secret inputs
use environment bindings. Every check is prepared before setup. Each check runs
alone and finishes process-group cleanup before later work starts.

A report directory is required even for checks-only suites. Named CHECK results
and ordered summary steps reference private stdout/stderr files without replaying
them. Keep-going permits later work after ordinary mismatch or timeout if cleanup
succeeds; fail-fast spans Hurl and check steps.

## Limits

Executables must be executable files canonically contained in the workspace;
absolute paths and traversal are refused. Secret and Generated argv templates are
invalid. Checks have no standalone selector or mutation classifier: the author
owns their behavior and assertion semantics. Launch/cleanup failures and service
death can abort later work. Captured helper output remains sensitive.

Builds on [CAP-5](safe-integration-suites.md), [CAP-7](explicit-command-environments.md).
