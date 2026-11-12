---
type: Friction Entry
title: "Clean Linux release driver defaults to an ASCII filesystem locale"
description: "The Apple-container release gate could not construct required Unicode path fixtures because its inherited locale used ASCII."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T13:50:08Z"
frictionId: FRIC-12
status: "resolved"
impact: detour
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/hurl-workbench"
plan: "docs/plans/12-support-caller-owned-file-roots-for-hurl-executions.md"
workaround: "Select the C.UTF-8 locale explicitly after entering the container Nix shell, then rerun the complete Linux gate."
resolution: "The Linux driver now selects C.UTF-8 after Nix shell startup; all Unicode root tests and the uid-65534 permission scenario pass in the clean container."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T13:55:49Z"
    change: "Resolve the locale friction with explicit release-driver environment and cross-platform acceptance evidence."
---
# Clean Linux release driver defaults to an ASCII filesystem locale

## Attempted

just linux-check

## Encountered

Core and CLI Unicode root tests raised recoverEncode: invalid argument (cannot encode character) before execution.

```text
Exception: recoverEncode: invalid argument (cannot encode character U+96EA)
```

## Workaround

Select the C.UTF-8 locale explicitly after entering the container Nix shell, then rerun the complete Linux gate.
