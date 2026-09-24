---
type: Improvement Request
title: Allow a run-scoped file root for file request bodies
description: >-
  The workbench always passes the workspace root as Hurl's file root, so a fragment that sends a
  file body can only reference committed files; integration runs that write request files per run,
  with per-run keys or signatures, have nowhere the workbench will read them from.
generated:
  by: anthropic/claude-fable-5-1
  at: "2026-09-24T14:20:00Z"
requestId: IR-3
status: proposed
origin: mori://tan/notification-hub
acceptanceCriteria:
  - id: AC-1
    statement: A fragment that sends file,request.json; resolves the file against the directory given by --file-root when the option is present, and against the workspace root otherwise.
    verification: A CLI test that runs a workflow with a file body from a temporary directory and asserts the request bytes at a fixture server.
  - id: AC-2
    statement: A --file-root value that is missing, not a directory, or not readable fails preflight with exit 2 before any child process starts.
    verification: Negative CLI tests for each case.
  - id: AC-3
    statement: Rendering and validation are unchanged, and summary.json records neither the directory nor the file contents.
    verification: Existing render and summary tests extended with the option present.
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

# Allow a run-scoped file root for file request bodies

## Context

The acceptance harness of `mori://tan/notification-hub` writes `notification-request.json` and
`delivery-webhook.json` into a run-owned temporary directory and runs its Hurl families with
`--file-root "$run_root"`. The webhook body must be sent byte for byte because its HMAC signature
is computed over it per run, and the notification request carries a per-run key. The same pattern
serves its throughput harness, which writes a generated broadcast audience to a file.

The workbench fixes `--file-root` to the manifest directory (`hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs`,
decided in `docs/plans/3-execute-hurl-workflows-securely.md`). Committing generated files into the
workspace is wrong for secrets and for per-run content, and writing into the workspace during a
run races parallel jobs and dirties the repository.

## Request

Accept a run-scoped file root on the execution commands (`run`, `test`, `matrix`, and
`test suite`), for example `--file-root DIR`, canonicalized and required to be an existing
readable directory, defaulting to the workspace root. `render` and `validate` do not change, since
they only see committed fragment paths. A suite may alternatively name a plain parameter whose
resolved value is the directory, following the same substitution rule as HTTP readiness URLs.

## What stays out

The option changes where Hurl looks for `file,…;` bodies and nothing else; it does not let fragments
escape the workspace for their own source paths.
