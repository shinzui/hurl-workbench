---
type: Friction Entry
title: "Inherited Mori endpoint uses retired PostgreSQL socket"
description: "Mori registry discovery failed until a command-local override selected the endpoint already declared in the shell profile."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T14:05:31Z"
frictionId: FRIC-13
status: "resolved"
impact: detour
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/13-run-executable-checks-as-ordered-suite-barriers.md"
workaround: "Use command-local MORI_PG_CONNECTION_STRING from current shell profile"
resolution: "Command-local override selects the current endpoint already declared in the shell profile; registry and source discovery succeeded."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T14:28:13Z"
    change: "Resolve the inherited endpoint detour with verified current shell configuration."
---
# Inherited Mori endpoint uses retired PostgreSQL socket

## Attempted

mori registry list

## Encountered

Connection refused at inherited sungkyung-clients/postgresql socket

## Workaround

Use command-local MORI_PG_CONNECTION_STRING from current shell profile
