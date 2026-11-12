---
type: Capability
title: "Secure parameter binding and Hurl execution"
description: "Run workflows and recipes through the official Hurl executable with separate plain and secret input channels and controlled child options."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-3
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "hurl-workbench run workflow|recipe NAME"
  - "hurl-workbench test workflow|recipe NAME"
  - "hurl-workbench doctor"
  - "HurlWorkbench.Hurl.Run"
requires:
  - CAP-2
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Parameter/ParameterTest.hs
    proves: "Binding precedence, channel separation, and properties-file literal validation."
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Hurl/RunTest.hs
    proves: "Protected temporary input, child environment/argv, process cleanup, and exit behavior."
  - kind: guide
    resource: docs/security.md
    proves: "Secret transport, ambient filtering, and output sensitivity boundaries."
---

# Secure parameter binding and Hurl execution

Plain inputs resolve from CLI overrides, variable files, committed recipe/case
bindings, declared environment sources, and defaults. Secret inputs use explicit
secret environment mappings or secret files and never enter Hurl argv. Private
temporary properties files are removed after execution. Hurl owns HTTP behavior,
captures, retries, assertions, and response output.

The CLI supplies typed timeout, retry, TLS, output, and diagnostic options plus a
small flag-only passthrough allowlist. A started single Hurl run preserves its
exit status; workbench preflight failures have separate diagnostics.

## Limits

Hurl and Hurlfmt 8.0 or newer are required; later major versions are reported as
untested. Plain values are not secret channels. Server responses, Hurl reports,
and explicitly selected curl/verbose output can contain sensitive data. Filtering
the child environment does not make an untrusted Hurl source safe.

Builds on [CAP-2](reusable-hurl-composition.md).
