---
type: Friction Entry
title: "Mori registry unavailable during dependency and lease discovery"
description: "The registry requires an unavailable local PostgreSQL socket, preventing source and Hinagata discovery."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-11T22:43:13Z"
frictionId: FRIC-1
status: "resolved"
impact: blocked
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/8-support-explicit-clean-environments-for-managed-processes.md"
resolution: "The agent inherited a stale Sungkyung MORI_PG_CONNECTION_STRING; the current endpoint in the user shell profile restores Mori discovery."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T03:01:45Z"
    change: "Verified registry search/show/docs against the current local PostgreSQL endpoint; no database service change was necessary."
---
# Mori registry unavailable during dependency and lease discovery

## Attempted

mori registry list; mori registry search dhall; mori registry search typed-process; mori registry search hinagata

## Encountered

NotifierConnectError: local PostgreSQL socket connection refused
