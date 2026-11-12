---
type: Capability
title: "Caller-provisioned independent scenario handoffs"
description: "Validate and consume one private fixture and endpoint assignment per expanded suite scenario before scheduling independent Hurl runs."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-10
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.IsolationPolicy.IndependentState"
  - "hurl-workbench test suite NAME --external-service --scenario-inputs FILE"
  - "HurlWorkbench.Suite.Scenario"
requires:
  - CAP-5
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Suite/ScenarioTest.hs
    proves: "Versioned private-file decoding, origin uniqueness, channel conflicts, and complete assignments."
  - kind: test
    resource: scripts/check-scenario-isolation-local.py
    proves: "Concurrent isolated local fixtures, refusal paths, cancellation, and summary redaction."
  - kind: guide
    resource: docs/guides/integration-testing.md
    proves: "Caller handoff contract and separately recorded real-provider acceptance."
---

# Caller-provisioned independent scenario handoffs

IndependentState suites require external-service mode and a version-1 private
regular non-symlink handoff file. Each expanded logical scenario appears exactly
once, with a unique fixture ID and HTTP(S) origin. Endpoint and extra Plain values
and Secret environment references enter validated channels; conflicting runtime
or committed bindings are refused before scheduling.

## Limits

Workbench validates declarations; it cannot prove two endpoint names lead to
different databases. The caller provisions independent fixtures, verifies
readiness and identity, keeps them alive until children stop, and releases them.
Managed services cannot be declared on IndependentState suites. Mutation still
requires explicit authorization. Cross-repository lease provisioning/release is
consumer evidence, not a workbench provision claim.

Builds on [CAP-5](safe-integration-suites.md).
