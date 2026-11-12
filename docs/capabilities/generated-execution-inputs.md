---
type: Capability
title: "Fresh generated inputs per Hurl execution"
description: "Generate UUID4, UUID7, TypeID, UTC timestamps, and bounded alphanumeric values once per parameter per prepared Hurl execution."
generated:
  by: process:openai-codex
  at: "2026-11-12T15:05:23Z"
capabilityId: CAP-8
provider: mori://shinzui/hurl-workbench
status: shipped
stability: experimental
since: unreleased
packages:
  - hurl-workbench-core
  - hurl-workbench-cli
interface:
  - "Schema.ParameterKind.Generated"
  - "Schema.Generator"
  - "HurlWorkbench.Parameter.Generate"
requires:
  - CAP-3
evidence:
  - kind: test
    resource: hurl-workbench-core/test/HurlWorkbench/Parameter/GenerateTest.hs
    proves: "Generator formats, bounds, injected clock/entropy, per-execution resolution, and overrides."
  - kind: example
    resource: examples/generated-parameters/README.md
    proves: "Two fragments sharing an identity and reproducible explicit overrides."
---

# Fresh generated inputs per Hurl execution

Declare a Generated parameter with Uuid4, Uuid7, TypeId, Rfc3339Now, or
RandomAlphanumeric. All fragments and Hurl retries in one execution share its
resolved value; matrix cases and suite Hurl runs resolve independently. Explicit
Plain runtime overrides, variable files, or a declared environment source can
supply reproducible values. Static validate/list/render do not draw entropy or
read the clock.

## Limits

Generated inputs cannot have committed defaults or recipe/case bindings and
cannot enter Secret channels. Suite commands, checks, and readiness cannot consume
them; use a Plain runtime value to share an identity. A declared environment
source that is absent fails unless a higher-priority binding wins. Preflight may
generate values for cases later skipped by fail-fast. Time-based IDs make no
monotonicity or application-isolation promise.

Builds on [CAP-3](secure-hurl-execution.md).
