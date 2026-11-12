---
type: Friction Entry
title: "Mori registry unavailable through PostgreSQL tunnel"
description: "Registry discovery and provider source lookup cannot proceed while the Sungkyung PostgreSQL tunnel refuses connections."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T03:27:07Z"
frictionId: FRIC-4
status: "resolved"
impact: blocked
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/9-declare-scenario-isolation-and-guard-parallel-mutations.md"
resolution: "The inherited Mori endpoint was stale; a command-local override from the current shell profile restores registry discovery without changing services."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T03:35:12Z"
    change: "Registry list/search/show/docs succeed with the current profile endpoint; continue dependency and Hinagata integration."
---
# Mori registry unavailable through PostgreSQL tunnel

## Attempted

mori registry list; mori doctor

## Encountered

PostgreSQL local socket refuses connections; existing tunnel log reports SSH timeouts.

```text
NotifierConnectError: connection to server on socket failed: Connection refused
```
