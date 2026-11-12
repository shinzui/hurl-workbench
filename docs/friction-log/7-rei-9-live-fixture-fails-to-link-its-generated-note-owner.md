---
type: Friction Entry
title: "Rei 9 live fixture fails to link its generated Note owner"
description: "The current Rei checkout compiles its core but the live schema-hook executable fails to link generated Note hole symbols, requiring the existing matching Rei 8 consumer cohort for acceptance."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T05:04:11Z"
frictionId: FRIC-7
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/rei"
affectedVersion: "9.0.0.0"
plan: "docs/plans/10-support-ordered-multi-service-suite-lifecycles.md"
workaround: "Use already-built matching Rei 8.0.0.0 API, CLI query-projection owner and live schema hook, explicitly recording that cohort and keeping the current source checkout unchanged."
resolution: "Real acceptance uses the existing supported matching Rei 8 binary cohort. The unrelated Rei 9 linker failure remains with its owner and is explicitly excluded from the acceptance claim."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T05:07:57Z"
    change: "Keep consumer build repair outside this workbench plan; record the verified cohort and artifact digests."
---
# Rei 9 live fixture fails to link its generated Note owner

## Attempted

nix develop -c cabal build rei-api:exe:rei-api rei-api:test:rei-api-live-test

## Encountered

The rei-api-live-test linker could not find generated Note.Holes transition symbols for arm64.

```text
ld: symbol(s) not found for architecture arm64; transition1NotCreatedApplyNoteCreatedHoleFoldVersion1_closure
```

## Workaround

Use already-built matching Rei 8.0.0.0 API, CLI query-projection owner and live schema hook, explicitly recording that cohort and keeping the current source checkout unchanged.
