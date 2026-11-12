---
type: Friction Entry
title: "Linux release gate realizes editor-only HLS dependencies"
description: "The Linux release script enters the full editor development shell and spends validation time building HLS dependencies unrelated to the release checks."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T04:01:09Z"
frictionId: FRIC-5
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/hurl-workbench"
plan: "docs/plans/9-declare-scenario-isolation-and-guard-parallel-mutations.md"
workaround: "Expose a check development shell using the same pinned GHC and tools with HLS disabled, and use that shell for the container release gate."
resolution: "The dedicated check shell keeps the pinned GHC and release tools, excludes editor-only HLS, and the complete ARM64 Linux check gate now passes."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T04:19:48Z"
    change: "Linux container release validation uses devShells.check; all 91 core and 37 CLI tests plus the complete release gate pass."
---
# Linux release gate realizes editor-only HLS dependencies

## Attempted

just linux-check in the local Apple container

## Encountered

The container spends several minutes building Haskell tooling dependencies before any release checks start, repeating the plan 8 delay.

## Workaround

Expose a check development shell using the same pinned GHC and tools with HLS disabled, and use that shell for the container release gate.
