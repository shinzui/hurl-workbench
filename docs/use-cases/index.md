---
okf_version: "0.2"
title: "Hurl Workbench Use Cases"
type: use-case-index
description: "Jobs-to-be-done and acceptance contracts that validate the Hurl Workbench API before implementation."
generated:
  by: process:openai-codex
  at: "2026-09-18T18:40:21Z"
links:
  - docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md
  - docs/use-cases/themes/developer-tooling.md
---

# Hurl Workbench Use Cases

This OKF bundle validates the Hurl Workbench from user goals inward. It does not duplicate
the implementation plans. Instead, each use case connects this chain:

    job-to-be-done -> feature acceptance -> public contract -> owning ExecPlan

A use case marked `validated` means its actor, situation, desired outcome, and acceptance
contract are coherent and backed by an observed workflow. It does **not** mean the feature
has shipped. Every initial feature remains `planned` until its owning plan records evidence.

## Initial contract set

| ID | Use case | Primary contract owners | Maturity |
|---|---|---|---|
| [UC-1](001-reuse-authenticated-api-workflows.md) | Reuse authenticated API workflows | EP-1, EP-2, EP-3 | validated; 1 of 3 features delivered (EP-1) |
| [UC-2](002-run-parameterized-api-scenarios.md) | Run parameterized API scenarios | EP-3, EP-4 | validated; delivery planned |
| [UC-3](003-run-repeatable-integration-suites.md) | Run repeatable integration suites | EP-3, EP-4, EP-5 | validated; delivery planned |
| [UC-4](004-inspect-raw-api-behavior.md) | Inspect raw API behavior | EP-2, EP-3, EP-4 | validated; delivery planned |

All four belong to the [developer tooling](themes/developer-tooling.md) theme. Any API
change in an owning ExecPlan must preserve the corresponding acceptance statements or
update the use case and explain the changed user contract first.

These scenarios validate observable contracts, not internal Haskell style. Implementation
acceptance separately follows `mori://shinzui/haskell-jitsurei/docs/core-standards`,
`mori://shinzui/haskell-jitsurei/docs/cli-option-groups`, and
`mori://shinzui/haskell-jitsurei/docs/api-hurl-integration-testing` as assigned by the
MasterPlan. Where the concerns meet, the use cases demand the same outcomes: explicit safe
suite membership, isolated mutations, faithful Hurl output, and typed non-shell process
boundaries.
