---
type: Capability
title: "Explicit inherited and clean command environments"
description: "Select ambient variable names independently for managed commands and overlay declared bindings from one preflight snapshot."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-7
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.CommandSpec.environmentPolicy"
  - "Schema.EnvironmentPolicy.Inherit / Clean"
  - "HurlWorkbench.Service.Environment"
requires:
  - CAP-1
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Service/RunTest.hs
    proves: "Native child environments, missing-name preflight, overlays, and redacted errors."
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Suite/LifecycleTest.hs
    proves: "All phases use the same snapshot across restart and teardown."
  - kind: example
    resource: examples/integration-service/hurl-workbench.dhall
    proves: "A Clean service and independent empty-environment readiness command."
---

# Explicit inherited and clean command environments

CommandSpec defaults to `Inherit`; `Clean [ "NAME", ... ]` selects only named
ambient entries, then explicit parameter bindings override them. Each selected
name must exist even when overridden, and empty values count as present. Missing
names are diagnosed without values before child startup.

Service, readiness, setup, teardown, and executable check commands use this
policy. Command readiness retains its prepared environment across retries;
service restarts and teardown retain the invocation snapshot.

## Limits

Clean has no implicit PATH, HOME, locale, or platform variables. The launched
runtime can add its own variables. Hurl's filtered environment and HTTP readiness
are separate contracts. External-service mode skips unused managed-command
policies but still prepares any executable checks.

Builds on [CAP-1](typed-workspaces.md).
