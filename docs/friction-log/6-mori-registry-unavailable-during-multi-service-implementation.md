---
type: Friction Entry
title: "Mori registry unavailable during multi-service implementation"
description: "The configured Mori PostgreSQL socket refuses connections, blocking dependency-source and real-consumer discovery."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T04:30:16Z"
frictionId: FRIC-6
status: "resolved"
impact: blocked
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/10-support-ordered-multi-service-suite-lifecycles.md"
resolution: "Clearing inherited Home Manager session markers before a fresh login shell loads current Mori connection settings."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T04:31:31Z"
    change: "User identified stale shell; registry discovery now succeeds."
---
# Mori registry unavailable during multi-service implementation

## Attempted

mori registry list; mori registry search typed-process; mori registry search dhall

## Encountered

NotifierConnectError on configured local PostgreSQL socket

```text
connection to server on socket /Users/shinzui/.local/state/sungkyung-clients/postgresql/.s.PGSQL.5432 failed: Connection refused
```
