---
type: Friction Entry
title: "Linux checks overwrite the macOS Cabal package database"
description: "The Apple-container gate mounted the developer checkout for builds, allowing Linux Cabal registrations and Git hooks to overwrite macOS state."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T05:16:00Z"
frictionId: FRIC-8
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/hurl-workbench"
plan: "docs/plans/10-support-ordered-multi-service-suite-lifecycles.md"
workaround: "Build Linux from a private snapshot of tracked working files and Git identity; preserve mixed generated metadata as backups and regenerate the native package DB."
resolution: "Linux release checks now build a private tracked-tree snapshot. The full Linux tests and archives pass while a native package-database fingerprint remains unchanged."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T05:26:04Z"
    change: "Eliminate shared cross-platform build metadata and host hook writes from the Linux gate."
---
# Linux checks overwrite the macOS Cabal package database

## Attempted

Run native and Apple-container release validation for the same working tree.

## Encountered

The macOS build saw unusable local package registrations referencing Linux dependency unit IDs.

```text
hurl-workbench-cli-0.1.0.0-inplace is unusable due to missing dependencies: base-4.21.2.0-28c1
```

## Workaround

Build Linux from a private snapshot of tracked working files and Git identity; preserve mixed generated metadata as backups and regenerate the native package DB.
