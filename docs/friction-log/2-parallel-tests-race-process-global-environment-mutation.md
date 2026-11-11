---
type: Friction Entry
title: "Parallel tests race process-global environment mutation"
description: "Existing binding tests mutate libc environ while unrelated tests spawn children, intermittently causing posix_spawnp Bad address."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-11T22:51:24Z"
frictionId: FRIC-2
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/hurl-workbench"
plan: "docs/plans/8-support-explicit-clean-environments-for-managed-processes.md"
workaround: "Serialize core test cases and supply the native compiler an explicit environment snapshot."
resolution: "Core test cases now run sequentially, avoiding concurrent libc environment mutation during child startup."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-11T22:52:59Z"
    change: "Serialize the test harness while preserving explicit batch concurrency tests."
---
# Parallel tests race process-global environment mutation

## Attempted

nix develop -c cabal test all --test-show-details=direct

## Encountered

Intermittent cc and python3 startProcess: posix_spawnp: failed (Bad address)

## Workaround

Serialize core test cases and supply the native compiler an explicit environment snapshot.
