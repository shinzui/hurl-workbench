---
type: Improvement Request
title: Allow a run-scoped file root for file request bodies
description: >-
  The workbench always passes the workspace root as Hurl's file root, so a fragment that sends a
  file body resolves under the workspace root; integration runs that write request files per run,
  with per-run keys or signatures, have nowhere the workbench will read them from.
generated:
  by: codex-cli/gpt-6.1-sol
  at: "2026-10-11T16:18:19Z"
requestId: IR-3
status: completed
completedAt: "2026-11-12T14:00:23Z"
targetPlan: docs/plans/12-support-caller-owned-file-roots-for-hurl-executions.md
resolution: "AC-1 through AC-5 and the concurrent-content amendment verified by ExecPlan 12 (commits fb580c7 and c749bec, acceptance recorded in b3f065c): --file-root resolution, exit-2 preflight refusals for missing, non-directory, and unreadable roots, root-free summaries, concurrent separate roots with exact non-ASCII and line-ending bytes, and caller-owned roots preserved after success, Hurl failure, and interruption. macOS and ARM64 Linux release gates pass (123 core, 44 CLI tests)."
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
  - id: AC-4
    statement: "Two concurrent executions can use separate temporary roots containing different files with the same relative filename, and each sends its own exact bytes without modifying the workspace."
    verification: "Run concurrent file-body scenarios against isolated endpoints and compare captured body hashes, including non-ASCII text and line endings."
  - id: AC-5
    statement: "The caller owns the supplied file root and its lifetime; workbench neither removes it nor resolves fragment source paths outside the workspace."
    verification: "Exercise success, Hurl failure, and interruption, verify caller files remain, and retain source-path containment negative tests."
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
      Author's source assessment for the Rei adoption amendment, not independent
      approval or implementation acceptance. Checked the current command, suite,
      and lifecycle interfaces against Rei MP29 fixture requirements. Historical
      reviews and confirmations remain tied to their original document revision.
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

## Rei adoption amendment — 2026-10-11

mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract includes note and document content workflows. Test payloads may be generated in fixture-owned temporary directories and must preserve exact bytes while concurrent scenarios use distinct roots. The current limitation is confinement to the workspace file root, not a Git-tracking requirement: generated files can exist there today, but that dirties shared workspaces and creates races.

Keep the option scoped to one execution. Parallel independently provisioned workbench invocations each receive their own root; no global mutable root or shared generated filename is introduced. Preserve caller ownership of temporary content and verify exact non-ASCII and line-ending bytes. Fragment sources still remain workspace-contained. These additions clarify adoption acceptance without adding upload storage, content generation, or arbitrary path resolution to workbench.

## Implementation plan

[ExecPlan 12: Support caller-owned file roots for Hurl executions](../plans/12-support-caller-owned-file-roots-for-hurl-executions.md). ExecPlan 12 delivered AC-1 through AC-5 and the 2026-10-11 amendment on 2026-11-12 (feature commit `fb580c7`, Linux locale correction `c749bec`, acceptance record `b3f065c`).
