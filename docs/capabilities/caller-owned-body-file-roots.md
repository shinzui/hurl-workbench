---
type: Capability
title: "Caller-owned request body file roots"
description: "Select a runtime Hurl body-file directory without relocating fragment sources or rewriting caller-owned bytes."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-9
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "hurl-workbench run|test|matrix --file-root DIR"
  - "Schema.Suite.fileRootParameter"
  - "HurlWorkbench.Run.FileRoot"
requires:
  - CAP-3
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Run/FileRootTest.hs
    proves: "Root validation, canonical aliases, permissions, and output overlap refusal."
  - kind: test
    resource: hurl-workbench-cli/test/FileRootTest.hs
    proves: "Execution option coverage and pre-spawn refusal through the public CLI."
  - kind: example
    resource: examples/file-body/README.md
    proves: "An echo/cmp proof preserving UTF-8, CRLF, and a final newline."
---

# Caller-owned request body file roots

Every Hurl execution command accepts `--file-root DIR`; relative CLI roots use
the invocation directory. Suites can instead name a Plain `fileRootParameter`,
resolved once from suite-wide inputs relative to the workspace. CLI selection
wins. The default remains the canonical workspace root.

Validation rejects invalid roots before subprocess probes. Explicit body roots
and report/response/curl output trees must be disjoint, including canonical
aliases and overwrite ancestors. Caller inputs are not rewritten, chmodded, or
removed by workbench.

## Limits

The caller keeps the directory readable and searchable until all Hurl children
exit and owns cleanup. Selecting a body root does not confine arbitrary paths
authored in Hurl. Inspection does not require runtime files; removal after
preflight becomes an ordinary runtime failure.

Builds on [CAP-3](secure-hurl-execution.md).
