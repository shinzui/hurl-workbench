---
type: Friction Entry
title: "Mori registry unavailable during dependency and lease discovery"
description: "The registry requires an unavailable local PostgreSQL socket, preventing source and Hinagata discovery."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-11T22:43:13Z"
frictionId: FRIC-1
status: logged
impact: blocked
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/8-support-explicit-clean-environments-for-managed-processes.md"
---
# Mori registry unavailable during dependency and lease discovery

## Attempted

mori registry list; mori registry search dhall; mori registry search typed-process; mori registry search hinagata

## Encountered

NotifierConnectError: local PostgreSQL socket connection refused
