---
type: Improvement Request
title: "Support explicit clean environments for managed processes"
description: "Allow managed services, readiness commands, and future lifecycle or check commands to receive only explicitly selected inherited environment variables plus declared bindings."
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-11T16:18:19Z"
requestId: IR-6
status: accepted
origin: mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract
acceptanceCriteria:
  - id: AC-1
    statement: "Managed commands select either existing inherited-environment behavior or a clean allowlist policy; existing manifests retain their current behavior."
    verification: "Decode original manifests and compare child environments under both policies."
  - id: AC-2
    statement: "Clean mode passes only declared inherited names and explicit bindings, with explicit bindings taking precedence; missing required names fail before child startup."
    verification: "A fixture prints environment names, proving ambient REI_PG_CONNECTION_STRING, REI_CONFIG, and MORI_API_URL do not appear unless selected and that a declared fixture binding wins."
  - id: AC-3
    statement: "The policy applies consistently to service startup and command readiness, and to lifecycle setup, teardown, and executable checks when those extensions are present."
    verification: "Exercise the same environment sentinel in each supported command phase and joint integration cases for the lifecycle/check extensions."
  - id: AC-4
    statement: "Validation rejects malformed or duplicate allowlist names and reports never include secret environment values."
    verification: "Negative manifests and sentinel-secret report assertions cover successful and failed commands."
  - id: AC-5
    statement: "Clean mode supports an explicitly passed PostgreSQL lease handoff without discarding its required connection variables."
    verification: "Run a Hinagata-leased service using declared PGHOST, PGPORT, PGUSER, PGDATABASE, and PGPASSFILE when needed; verify cleanup after failure and cancellation."
reviews:
  - kind: model
    reviewer: codex-cli
    reviewed_at: "2026-10-11T16:18:19Z"
    document_timestamp: "2026-10-11T16:18:19Z"
    scope: technical-accuracy
    outcome: commented
    provider: openai
    model: gpt-6.1-sol
    effort: high
    context: >-
      Author's source assessment for Rei MP29 adoption, not an independent approval
      or implementation test result. Current interfaces and limitations were checked
      against the repository source and integration documentation; acceptance tests
      below are proposed verification procedures.
---

# Support explicit clean environments for managed processes

## Context

`HurlWorkbench.Service.Run.withService` reads `getEnvironment`; `serviceProcessConfig` and `readinessProcessConfig` overlay declared values onto that ambient environment at source commit `a29d26ad5e90aa762de88be18f06fddf67b6d02f`. Explicit overrides exist, but there is no manifest policy for omitting unspecified ambient settings.

mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract preserves a scrubbed fixture environment. A service must use the test database, private workspace, and stub provider even when the caller has ordinary Rei settings in its shell. Moving lifecycle ownership into workbench must preserve that behavior.

## Request

Add a clean environment policy to the common command model, with a validated allowlist of inherited names and the existing explicit bindings. Provide PATH and HOME only when the caller selects or binds them; do not invent ambient defaults in clean mode. Keep existing inheritance as the compatibility default.

Use the same policy for command readiness and, when implemented, lifecycle commands and executable checks. Preserve secret channels and emit policy/name diagnostics without values. Document a Hinagata handoff that explicitly admits the application PG variables and protected password-file path while omitting unrelated application configuration.

## Scope and adoption

Required before workbench replaces Rei's scrubbed managed-process harness. An externally managed fixture can continue controlling its own environment during initial adoption. This is an explicit reproducibility feature; it does not infer which arbitrary environment variables a service needs.

## Implementation plan

[ExecPlan 8: Support explicit clean environments for managed processes](../plans/8-support-explicit-clean-environments-for-managed-processes.md) covers AC-1 through AC-5. The work is planned; implementation and acceptance verification have not started.
