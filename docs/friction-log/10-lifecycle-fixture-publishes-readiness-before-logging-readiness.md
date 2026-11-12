---
type: Friction Entry
title: "Lifecycle fixture publishes readiness before logging readiness"
description: "The existing suite fixture allows Hurl and cancellation to race its readiness event, making release checks fail intermittently."
generated:
  by: "codex-cli/gpt-6.1-sol"
  at: "2026-11-12T06:01:31Z"
frictionId: FRIC-10
status: "resolved"
impact: detour
kind: tooling
origin: "mori://shinzui/hurl-workbench"
affects: "mori://shinzui/hurl-workbench"
plan: "docs/plans/11-generate-fresh-parameters-for-each-workflow-execution.md"
workaround: "Publish the readiness file after writing the readiness event in the Python fixture."
resolution: "The lifecycle test fixture logs its readiness event before publishing readiness; the full core suite now passes."
amended:
  - by: "codex-cli/gpt-6.1-sol"
    at: "2026-11-12T06:02:35Z"
    change: "Fix readiness publication ordering in the existing fixture."
---
# Lifecycle fixture publishes readiness before logging readiness

## Attempted

Run core tests and just check

## Encountered

Lifecycle ordering tests observed hurl-start-1 before s3-ready or lost s3-stop during cancellation.

## Workaround

Publish the readiness file after writing the readiness event in the Python fixture.
