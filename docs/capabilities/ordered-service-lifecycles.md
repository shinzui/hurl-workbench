---
type: Capability
title: "Ordered managed service lifecycles"
description: "Acquire services in readiness order, drain Hurl batches around lifecycle barriers, and clean process groups before bounded teardown."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-6
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.Suite.services"
  - "Schema.Suite.setup / teardown"
  - "Schema.ServiceStep.Stop / Start / Restart"
  - "HurlWorkbench.Service.Group"
requires:
  - CAP-5
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Suite/LifecycleTest.hs
    proves: "Ordered startup, restart barriers, cleanup ordering, failures, cancellation, and teardown budgets."
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Service/RunTest.hs
    proves: "HTTP/command readiness and TERM/KILL cleanup including surviving descendants."
  - kind: example
    resource: examples/multi-service/README.md
    proves: "Runnable stub/API/worker orchestration with mutation and read-only barrier suites."
---

# Ordered managed service lifecycles

Setup commands run before ordered service acquisition. Each executable/argv
service must become ready through HTTP or a command before the next starts.
Stop/Start/Restart steps drain prior Hurl work; restart repeats readiness and
updates reverse cleanup order. Unexpected service exit cancels active children.

Cleanup terminates service process groups and reaps leaders before teardown.
Setup, command, shutdown, and collective cleanup deadlines are bounded. Teardown
runs after partial setup too, and must tolerate incomplete acquisition.

## Limits

This owns processes, not databases, containers, or leases. External-service mode
bypasses setup, service ownership, and teardown and refuses lifecycle steps.
Neither mutations nor lifecycle actions are automatically retried. Lifecycle and
phase failures select exit 4 while preserving the earlier primary cause in results.

Builds on [CAP-5](safe-integration-suites.md).
