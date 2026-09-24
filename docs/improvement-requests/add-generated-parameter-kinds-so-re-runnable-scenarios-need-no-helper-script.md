---
type: Improvement Request
title: Add generated parameter kinds so re-runnable scenarios need no helper script
description: >-
  Parameters are plain or secret and come from bindings, files, or the environment; a scenario
  that must be re-runnable against a persistent database needs a fresh identifier of a specific
  shape on every run, which neither the workspace nor Hurl's newUuid and newDate can produce.
generated:
  by: anthropic/claude-fable-5-1
  at: "2026-09-24T14:20:00Z"
requestId: IR-2
status: proposed
origin: mori://tan/notification-hub
acceptanceCriteria:
  - id: AC-1
    statement: A workflow declaring a parameter generated as a TypeID with prefix rcp receives a value matching ^rcp_[0-9a-hjkmnp-tv-z]{26}$ whose decoded UUID carries version 7.
    verification: A CLI test that captures the delivered properties file through a fixture and decodes the value.
  - id: AC-2
    statement: Two executions receive different generated values, and every fragment of one execution sees the same value.
    verification: A two-fragment workflow whose second fragment asserts equality with a capture from the first, run twice.
  - id: AC-3
    statement: A generated parameter can be overridden with --variable for reproduction, and validate rejects a committed defaultValue or a matrix-case binding for it.
    verification: Validation fixtures for both rejections and a run with an explicit override.
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: "2026-09-24T14:25:00Z"
    document_timestamp: "2026-09-24T14:20:00Z"
    scope: technical-accuracy
    outcome: approved
    provider: anthropic
    model: claude-fable-5-1
    effort: high
    context: >-
      The authoring model's own in-repository verification, not an independent review: every claim
      about the workbench was checked at commit a29d26a against docs/reference/workspace.md,
      docs/reference/cli.md, docs/guides/integration-testing.md, ADR 6, ADR 7,
      hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs (fixed --file-root), and flake.module.nix
      (packages.default exists, so packaging was not filed), and every claim about the requesting
      project against scripts/runtime-acceptance.sh and api/test/hurl in mori://tan/notification-hub.
verified:
  - by: anthropic/claude-fable-5-1
    at: "2026-09-24T14:25:00Z"
---

# Add generated parameter kinds so re-runnable scenarios need no helper script

## Context

Identifiers in `mori://tan/notification-hub` are TypeID v7 values with a prefix (`rcp_`, `ntf_`,
`bct_`), 26 Crockford base32 characters whose decoded UUID must carry version 7. Its consent
scenarios (`api/test/hurl/mutating/preferences.hurl` and `api/test/hurl/delivery/consent.hurl` in
that repository) must use a recipient that has never been seen, because the first `PUT` asserts
`changed == true` and consent persists; today the shell harness derives the recipient from its
process id and passes `--variable`.

The workbench's `Parameter` is `Plain` or `Secret`, bound from `--variable`, files, matrix and
recipe bindings, the environment, or a committed default. `docs/guides/integration-testing.md`
answers generated inputs with a dedicated helper that writes a properties file before the suite
runs, which puts a shell step around every invocation. Inside a fragment Hurl offers `newUuid`
(version 4) and `newDate`, but every occurrence yields a new value, there is no prefixed or
version-7 form, and a value cannot be shared across fragments without a capture.

## Request

Add a third parameter kind, `Generated`, with a small closed set of generators:

- `Uuid4` and `Uuid7`;
- `TypeId { prefix : Text }`, producing a version 7 TypeID with the given prefix;
- `Rfc3339Now`;
- `RandomAlphanumeric { length : Natural }`.

A generated parameter is resolved once per execution (a `run` or `test` of a workflow or recipe,
each matrix case, and each suite run), the same value for every fragment, delivered through the
same protected properties-file channel as plain values, never committed, and shown by `render
recipe --explain` as `generated` without its value. A `--variable` override wins, so a failing run
can be reproduced. `validate` rejects a committed `defaultValue` or a matrix-case binding for a
generated parameter, and the reserved Hurl function names stay reserved.

## What stays out

Nothing about this request changes fragments or asks the workbench to parse Hurl; the value enters
through the existing binding channel.
