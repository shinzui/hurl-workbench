---
type: Capability
title: "Reusable Hurl fragment composition"
description: "Compose complete Hurl entries in workflow order while preserving source text and mapping Hurlfmt diagnostics back to fragments."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-2
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "hurl-workbench render workflow NAME"
  - "hurl-workbench render recipe NAME --explain"
  - "HurlWorkbench.Workflow.Render"
requires:
  - CAP-1
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Workflow/WorkflowTest.hs
    proves: "Byte preservation, capture ordering, UTF-8 failures, source spans, and Hurlfmt diagnostic mapping."
  - kind: example
    resource: examples/vendor-odata/hurl-workbench.dhall
    proves: "One OAuth fragment reused by recipes and bespoke investigations."
---

# Reusable Hurl fragment composition

A workflow names an ordered list of ordinary `.hurl` fragments. Rendering keeps
source content, inserts the line feeds needed between fragments, and ensures a
final line feed. Hurl captures, assertions, and cookies remain native Hurl syntax.
`render` writes inspectable source to stdout or an output file; `--explain`
identifies binding sources without exposing runtime values.

## Limits

Fragments must be nonempty UTF-8 files containing complete entries inside the
workspace. The workbench does not parse partial request templates or invent an
HTTP/assertion language. Captures and cookies are shared only within a single
Hurl execution, never across matrix cases or suite runs.

Builds on [CAP-1](typed-workspaces.md).
