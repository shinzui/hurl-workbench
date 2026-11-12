---
type: Friction Entry
title: "Inherited Mori endpoint uses retired PostgreSQL socket"
description: "Mori registry discovery failed until a command-local override selected the endpoint already declared in the shell profile."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T14:05:31Z"
frictionId: FRIC-13
status: logged
impact: detour
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/13-run-executable-checks-as-ordered-suite-barriers.md"
workaround: "Use command-local MORI_PG_CONNECTION_STRING from current shell profile"
---
# Inherited Mori endpoint uses retired PostgreSQL socket

## Attempted

mori registry list

## Encountered

Connection refused at inherited sungkyung-clients/postgresql socket

## Workaround

Use command-local MORI_PG_CONNECTION_STRING from current shell profile
