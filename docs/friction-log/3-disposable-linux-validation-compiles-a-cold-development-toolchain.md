---
type: Friction Entry
title: "Disposable Linux validation compiles a cold development toolchain"
description: "The Apple-container release gate has no persistent Nix store, making its first development-shell realization compile many dependencies before project validation."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-11T23:00:32Z"
frictionId: FRIC-3
status: "accepted"
impact: slowdown
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/hurl-workbench"
plan: "docs/plans/8-support-explicit-clean-environments-for-managed-processes.md"
resolution: "Used the same compiler and command-line tools in a temporary HLS-free shell; permanent cold-cache and CI toolchain changes are outside this feature."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-11T23:26:50Z"
    change: "All Linux gate components passed through the temporary shell and a stable-source Nix retry."
---
# Disposable Linux validation compiles a cold development toolchain

## Attempted

just linux-check

## Encountered

The disposable ARM64 Nix container spends more than ten minutes realizing development-toolchain dependencies before running repository checks.
