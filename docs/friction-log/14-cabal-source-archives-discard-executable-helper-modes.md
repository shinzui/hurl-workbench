---
type: Friction Entry
title: "Cabal source archives discard executable helper modes"
description: "Raw cabal sdist archives normalize every extra source file to 0644, requiring release archive normalization for workspace executable checks."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T14:35:35Z"
frictionId: FRIC-14
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/hurl-workbench"
affects: "mori://haskell/cabal"
plan: "docs/plans/13-run-executable-checks-as-ordered-suite-barriers.md"
workaround: "Normalize the two explicitly declared executable helper entries in the release source archive before extraction and validation."
resolution: "The canonical release wrapper restores only declared helper tar modes; unpacked archives execute the matching and deliberately failing examples successfully."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T14:40:20Z"
    change: "Resolve source archive mode loss with a verified release archive normalization boundary."
---
# Cabal source archives discard executable helper modes

## Attempted

Run the unpacked executable-check example through scripts/check-sdist.sh

## Encountered

The archive contained both parity.py helpers as 0644 despite executable source files, so executable containment validation refused the unpacked example.

```text
tar -tvzf: -rw-r--r-- examples/executable-checks/parity.py; Cabal SrcDist documents no executable files since Cabal 3.4 and assigns ordinaryFilePermissions.
```

## Workaround

Normalize the two explicitly declared executable helper entries in the release source archive before extraction and validation.
