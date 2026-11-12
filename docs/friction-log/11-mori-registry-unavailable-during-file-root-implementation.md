---
type: Friction Entry
title: "Mori registry unavailable during file-root implementation"
description: "The local registry PostgreSQL socket refused connections, preventing dependency source discovery."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T13:31:43Z"
frictionId: FRIC-11
status: logged
impact: detour
kind: environment
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/mori"
plan: "docs/plans/12-support-caller-owned-file-roots-for-hurl-executions.md"
workaround: "Use repository-established APIs and authoritative upstream documentation for filesystem access semantics."
---
# Mori registry unavailable during file-root implementation

## Attempted

mori registry list

## Encountered

NotifierConnectError: local PostgreSQL socket connection refused

## Workaround

Use repository-established APIs and authoritative upstream documentation for filesystem access semantics.
