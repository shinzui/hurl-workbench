---
type: Friction Entry
title: "Mori dependency discovery requires unavailable PostgreSQL"
description: "The Mori registry fails before dependency discovery because its local PostgreSQL socket refuses connections."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T05:52:17Z"
frictionId: FRIC-9
status: "accepted"
impact: detour
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/11-generate-fresh-parameters-for-each-workflow-execution.md"
workaround: "Keep existing dependency bounds, use established project APIs and upstream specifications, and verify compilation locally."
resolution: "Registry remains unavailable; the feature uses existing dependencies and independently verified format specifications with compiled acceptance tests."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T06:02:34Z"
    change: "Accept the local registry outage for this implementation without dependency changes."
---
# Mori dependency discovery requires unavailable PostgreSQL

## Attempted

mori registry list; mori registry search bytestring

## Encountered

NotifierConnectError: local PostgreSQL connection refused

## Workaround

Keep existing dependency bounds, use established project APIs and upstream specifications, and verify compilation locally.
