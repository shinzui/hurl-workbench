---
title: "Use Case 001 — Reuse Authenticated API Workflows"
type: Use Case
description: "Define authentication once, compose it with resource requests, and inspect the exact Hurl program before execution."
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
    context: Reviewed against the observed OAuth and OData experiments, the proposed public contracts, and canonical Mori references.
useCaseId: UC-1
status: validated
origin: mori://shinzui/hurl-workbench
themes:
  - developer-tooling
jobs:
  - name: remove-repeated-authentication-setup
    actor: API client developer
    situation: several resource explorations require the same OAuth capture before their requests
    motivation: maintain authentication once without hiding the native Hurl exchange
    outcome: one authentication fragment feeds multiple named workflows with no copied OAuth entry
  - name: review-exact-request-program
    actor: API client developer
    situation: a composed workflow is about to contact a vendor environment
    motivation: verify ordering, variables, captures, and assertions before sending requests
    outcome: the developer can inspect deterministic Hurl source identical to the executed source
features:
  - name: typed-reusable-workspace
    description: Define fragments, workflows, parameters, and secret declarations in one validated workspace.
    status: delivered
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A workspace declares one OAuth fragment and two resource fragments; validation succeeds and listing shows two workflows that reference the same OAuth fragment.
    jobs:
      - remove-repeated-authentication-setup
  - name: deterministic-session-composition
    description: Compose complete Hurl entries in declared order while preserving capture and cookie-session flow.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: Rendering either workflow emits the shared OAuth entry once, then its selected resource entry, with byte-stable output and source provenance.
    jobs:
      - remove-repeated-authentication-setup
      - review-exact-request-program
  - name: secure-runtime-bindings
    description: Resolve declared plain and secret values without exposing secret material in argv or rendered source.
    status: planned
    owners:
      - mori://shinzui/hurl-workbench
    acceptance: A workflow executes with required OAuth secrets supplied through protected files; process argv, rendered output, and diagnostics contain no secret values.
    jobs:
      - remove-repeated-authentication-setup
links:
  - docs/use-cases/index.md
  - docs/use-cases/themes/developer-tooling.md
  - docs/plans/1-define-the-typed-hurl-workspace-contract.md
  - docs/plans/2-compose-and-render-reusable-hurl-workflows.md
  - docs/plans/3-execute-hurl-workflows-securely.md
  - mori://tan/constellation1-client-hs/repos/constellation1-client-hs
---

# Use Case 001 — Reuse Authenticated API Workflows

**Theme:** [developer tooling](themes/developer-tooling.md)

The developer has several API investigations that all begin with the same OAuth exchange.
They want Hurl's capture and cookie behavior, but they do not want the authentication entry
copied into every file. They define complete Hurl entries once, compose named workflows,
inspect the resulting source, and execute that exact source with runtime secrets.

## Evidence

`mori://tan/constellation1-client-hs/repos/constellation1-client-hs`, under the
project-relative `playground/` tree, contains repeated OAuth setup paired with multiple
resource explorations. This validates the job without making that project an implementation
dependency.

## Contract validation

| Requirement | Public contract | Owner |
|---|---|---|
| Valid names, paths, parameters, and references | opaque `ValidatedWorkspace`, category-specific name newtypes, `HurlValueLiteral` | [EP-1](../plans/1-define-the-typed-hurl-workspace-contract.md) |
| One deterministic source with entry provenance | `ResolvedWorkflow`, fragment line spans, `RenderedWorkflow` | [EP-2](../plans/2-compose-and-render-reusable-hurl-workflows.md) |
| Execute exactly the reviewed source without leaking secrets | `HurlRunner`, `RunRequest`, binding resolution, `RunResult` | [EP-3](../plans/3-execute-hurl-workflows-securely.md) |

The contract fails this use case if composition invents a new request DSL, changes fragment
contents, prevents captures from flowing to later entries, or transports secrets through
command arguments.
