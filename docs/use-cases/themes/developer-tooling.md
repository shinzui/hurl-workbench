---
title: "Theme — Developer Tooling"
type: Use Case Theme
description: "Use cases for composing, exercising, and diagnosing HTTP API workflows with reproducible developer tools."
generated:
  by: process:openai-codex
  at: "2026-09-18T18:40:21Z"
verified:
  - by: process:openai-codex
    at: "2026-09-18T18:44:55Z"
reviews:
  - kind: model
    reviewer: process:openai-codex
    reviewed_at: "2026-09-18T18:44:55Z"
    document_timestamp: "2026-09-18T18:40:21Z"
    scope: content-and-metadata
    outcome: approved
    provider: openai
    model: gpt-5.6-sol
    effort: unspecified
    context: Reviewed for consistency with all four use cases and the bundle's developer-tooling boundary.
origin: mori://shinzui/hurl-workbench
links:
  - docs/use-cases/index.md
---

# Theme — Developer Tooling

This theme groups work in which a developer needs repeatable, inspectable tooling around
an HTTP API: removing setup duplication, varying inputs without copying requests, running
the same checks locally and in CI, and dropping below a typed client to inspect wire
behavior. Hurl remains the HTTP and assertion language; the workbench supplies reusable
composition and execution policy.

Use cases declare `developer-tooling` in frontmatter and link this concept from their body.
