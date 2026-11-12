---
id: 12
slug: support-caller-owned-file-roots-for-hurl-executions
title: "Support caller-owned file roots for Hurl executions"
kind: exec-plan
created_at: 2026-11-11T20:51:21Z
intention: "intention_01m7663c9aexfr68prg1qgcnec"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-11-11T20:51:21Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-11T21:02:49Z
      mode: "other"
      note: "Complete initial IR plan, link created Mina intention, and check cross-plan acceptance contracts"
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-12T13:31:42Z
      mode: "implement"
      note: "Implement validated caller-owned file roots and acceptance coverage"
---

# Support caller-owned file roots for Hurl executions


This ExecPlan is a living document. Update Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective as implementation proceeds. Record implementation friction through `agents/skills/exec-plan/FRICTION.md` and promote durable decisions into `docs/adr/` on completion.


## Purpose / Big Picture


A caller can generate request bodies in a private temporary directory and run a committed Hurl workflow with `--file-root DIR`. Hurl will read file bodies from that directory without changing fragment source resolution or writing generated files into the workspace. Two concurrent invocations can each use `request.json` with different bytes and send exactly their own content.

This implements [IR-3](../improvement-requests/allow-a-run-scoped-file-root-for-file-request-bodies.md), including AC-1 through AC-5 and the concurrent-content amendment. The file root is the base directory Hurl uses for a body such as `file,request.json;`; it is separate from the workspace root that contains the committed fragment source files. The caller owns the supplied directory and decides when to delete it.


## Progress


- [x] Milestone 1 (2026-11-12): CLI execution options and the optional Plain suite parameter resolve before subprocess probes. Injected callback tests cover missing, regular-file, empty, unreadable, and unsearchable roots; frozen version-1 manifests still pass schema compatibility.
- [x] Milestone 2 (2026-11-12): Typed roots reach single requests, matrix cases, and suite batches. Captured argv, core preparation, artifact-overlap, and refusal-summary tests pass; source escape tests remain green. Core suite: 123 tests passed.
- [x] Milestone 3 (2026-11-12): Real Hurl byte capture, concurrent invocations, failure/cancellation ownership, and the public example pass. Complete macOS `just check` and Apple-container ARM64 Linux `just linux-check` pass, each with 123 core and 44 CLI tests, schema/release-copy checks, examples, source distributions, and flake checks. Effective permission refusal is proven as uid 501 on macOS and uid 65534 on Linux.

Completed in commits `fb580c7` (feature) and `c749bec` (Linux locale correction), with the final acceptance record following them. No implementation or validation work remains. No dependency version or bound changed.


## Surprises & Discoveries

2026-11-12: The clean Linux gate defaulted to ASCII. Both new Unicode filename scenarios failed at directory creation with `recoverEncode`, before testing file-root execution. FRIC-12 in `docs/friction-log/` records the driver correction and rerun.

2026-11-12: The existing fixture echo endpoint already preserves raw request bytes. Live tests capture strict raw bodies directly before responding, so no new production fixture endpoint is needed. Effective permission checks use directory listing plus stat of the directory’s dot entry; both run under the effective identity and include ACL/privilege behavior. Linux root-run release checks use a separate public CLI test that drops to uid 65534.


## Decision Log

2026-11-12: Select C.UTF-8 explicitly after entering the Linux container Nix shell. The positive Unicode path criterion needs a UTF-8 filesystem locale; the test driver must provide it rather than dropping that criterion or changing process-global encoding in library execution.


2026-11-11: A supplied CLI path is relative to the invocation working directory, as report/output paths are today. A suite parameter path is relative to the workspace root, keeping manifest semantics stable when invoked from a different directory. CLI selection wins over the suite parameter; otherwise the default is the canonical workspace root.

2026-11-11: Support `Suite.fileRootParameter : Optional Text` with default None as the request's manifest alternative. It must reference a declared Plain parameter resolved only from suite-level sources. Reject Secret and Generated kinds; file-root selection cannot depend on per-case values or expose a secret through Hurl argv.

2026-11-11: Canonicalize once and retain the result in an immutable validated value, never in process-global state or a changed current directory. An explicitly selected external directory is allowed, including a symlink whose canonical target is readable. This is a Hurl file base, not a new filesystem sandbox: do not claim that arbitrary file paths within user-authored Hurl are confined by this option.

2026-11-11: Invalid roots return exit 2 before capability/version probes, hurlfmt, Hurl, setup commands, checks, or managed services. Validation of the selected root must therefore precede the current capability detection and rendering sequence.


## Outcomes & Retrospective

2026-11-12: IR-3 AC-1 through AC-5 and its concurrent-content amendment are implemented. Execution commands accept caller-owned body roots and suites can select a Plain parameter; CLI selection takes precedence. Typed immutable roots stay separate from fragment resolution. Preflight checks effective directory access and disjoint output trees, including refusal-summary reservation. Exact UTF-8 and newline bytes, simultaneous separate roots, unchanged workspace files, preserved caller file modes/content after Hurl failure and interruption, runtime disappearance, inspection, and root-free summaries are verified.

The complete macOS and local ARM64 Linux release gates pass. Each runs 123 core tests and 44 CLI tests, and includes schema compatibility, release-copy synchronization, the raw echo/cmp example, source-distribution builds, and flake checks. The Linux gate explicitly selects UTF-8 and tests permission refusal under uid 65534; chmod-only tests running as root are not treated as permission-denial evidence. Durable process-boundary and release-environment context is recorded in ADR 4 and ADR 8.

[FRIC-11](../friction-log/11-mori-registry-unavailable-during-file-root-implementation.md) is accepted: the registry database remains unavailable, while established filesystem APIs and behavioral checks let this feature proceed without dependency changes. [FRIC-12](../friction-log/12-clean-linux-release-driver-defaults-to-an-ascii-filesystem-locale.md) is resolved: the Linux release driver now supplies C.UTF-8, and the Unicode scenarios pass without changing library process-global encoding.


## Context and Orientation


`hurl-workbench-core/src/HurlWorkbench/Run/FileRoot.hs` owns the abstract FileRoot, directory validation, suite-wide parameter selection, and output-tree overlap checking. `hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs` constructs `--file-root` in `buildArguments` from `RunRequest.fileRoot`. `hurl-workbench-core/src/HurlWorkbench/Run/Prepare.hs` carries that value through PreparedRun and buildBatchCase, with default workspace-validation wrappers and explicit typed-root preparation variants. RenderedWorkflow still describes only workspace source resolution.

`hurl-workbench-cli/src/HurlWorkbench/Cli/Options.hs` defines the raw execution-only option in CliHurlOptions and assembles it for single runs, matrices, and suites. `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Run.hs`, `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Matrix.hs`, and `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Suite.hs` select and validate roots before capability detection. Core preparation and suite preflight provide the corresponding direct-library safeguards; suite refusal summaries retain the original selected root.

`hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs` resolves suite-level inputs and prepares every child before execution. `schema/Suite.dhall` and `hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs` define fileRootParameter; `hurl-workbench-core/src/HurlWorkbench/Workspace/Decode.hs` inserts its missing default into old records and empty-list annotations through normalizeSuiteLifecycle. `hurl-workbench-core/src/HurlWorkbench/Workspace/Validate.hs` statically checks the parameter reference and Plain kind without reading the runtime directory. Inspection commands require no runtime payloads.

Relevant ADRs are [ADR 1](../adr/1-versioned-dhall-workspace-schema.md), preserving old schema-version-1 manifests; [ADR 2](../adr/2-validated-workspace-boundary.md), retaining canonical fragment paths; [ADR 3](../adr/3-opaque-hurl-fragment-composition.md), leaving fragment bytes unchanged; [ADR 4](../adr/4-secure-hurl-process-boundary.md), using typed options and private artifacts; [ADR 5](../adr/5-bounded-isolated-batch-execution.md), isolating batch requests; [ADR 7](../adr/7-suite-preflight-safety-and-report-isolation.md), requiring preflight before side effects and value-free summaries; and [ADR 8](../adr/8-self-contained-multi-package-release-builds.md), synchronizing schema/example copies. The old fixed-root choice appears in [Plan 3](3-execute-hurl-workflows-securely.md); ADR 4 now distinguishes body roots from source roots.

[IR-1's plan](10-support-ordered-multi-service-suite-lifecycles.md) supplies the ordered suite lifecycle and [Plan 8](8-support-explicit-clean-environments-for-managed-processes.md) supplies the shared compatibility conversion. This implementation reuses both interfaces. The caller content requirement is recorded by `mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract` and the originating `mori://tan/notification-hub` request.


## Plan of Work


### Milestone 1: Validate execution roots before subprocess work


Add `hurl-workbench-core/src/HurlWorkbench/Run/FileRoot.hs` with an abstract `FileRoot`, a smart constructor accepting a base directory plus optional requested path, a typed failure, and a process-boundary accessor. The constructor chooses the default workspace root when no override exists, canonicalizes the selected directory, checks existence and directory type, and verifies effective read and search/execute access under the invoking user. Catch filesystem IO errors and return a preflight error. Redact its Show instance and keep paths out of structured summaries. Register the module in `hurl-workbench-core/hurl-workbench-core.cabal`.

Add `--file-root DIR` to single `run`/`test`, matrix, and `test suite` execution option records and parser assembly. It must not become a passthrough `--hurl-arg`, a global option, or an option of render/validate. Reject duplicate values consistently with the parser's normal option handling. Update help and completion tests.

Add `fileRootParameter` to Suite with default None and a matching Haskell field. Normalize its absence in old evaluated Suite records before exact Dhall extraction, including empty list annotations, using the shared compatibility converter if one exists. Keep old fixtures unchanged. Static validation requires an existing Plain parameter; malformed or unknown references fail even if a later CLI override could shadow them. Do not inspect the filesystem at static validation time.

Implement a shared selection/preflight operation: choose explicit CLI path first, otherwise resolve only the named suite parameter through existing suite-level binding rules, otherwise use the workspace root. A shadowed suite parameter does not need a runtime value. Resolve the CLI path from the invocation working directory and the parameter value from the workspace root. Pass the resulting `FileRoot` through core preparation, requiring successful selection before dependency detection or hurlfmt invocation in the CLI. Do not duplicate full workflow binding resolution just to select a root. For core callers, expose the smart constructor and require the typed root at the request/preparation boundary; validate it before calling injected rendering/dependency callbacks where applicable.

Use tests with injected capability/format callbacks and startup markers to prove that missing, regular-file, unreadable, and unsearchable directory arguments return exit 2 with zero child invocations. A privileged user can bypass mode-bit denial, so run effective-permission refusal tests under an unprivileged identity or report that specific test as unsupported; do not claim a chmod-only test proved unreadability when it did not. Positive tests cover relative paths, spaces, Unicode, and canonical symlink targets.


### Milestone 2: Carry the selected directory to each Hurl request


Add the validated root to `PreparedRun` and `RunRequest`, updating `buildBatchCase` and the single-run constructor. `buildArguments` must read this field rather than `RenderedWorkflow.workspaceRoot`. For callers that use default preparation wrappers, resolve the workspace root through the same smart constructor to preserve behavior; expose explicit-root variants for the CLI and direct library use. Never let a raw optional string silently bypass validation.

Thread one selected root through all matrix cases and all Hurl batches in a suite. Independent invocations may use different values concurrently; no mutable shared cache or `setCurrentDirectory` is allowed. Leave `RenderedWorkflow`, validated fragment paths, process working directory, and source composition unchanged. A file outside the workspace can be a request body under the explicitly selected root, but cannot become a fragment source through this option.

Before execution side effects, validate output/report layout against an explicit or parameter-selected body root. Require those input and output trees to be disjoint: reject output targets inside the input root and destructive overwrite subtrees that contain it, accounting for canonical parent paths and symlink aliases. Include matrix response, suite report, and curl-export targets. This prevents `--overwrite` or report preparation from deleting, rewriting, or chmodding caller input. The default workspace-root case retains existing output-layout rules; do not blanket-reject ordinary reports beneath the workspace or parse fragments to discover body filenames. Document that selecting the workspace itself explicitly opts into the stronger disjoint-tree rule.

Retain the absolute canonical root in memory only for request construction. `summary.json` must continue recording logical names, statuses, durations, and relative report paths without the root or file contents. Typed root failures may identify the bad option/path in an immediate CLI diagnostic, but normal summaries and Show output must not include it. On success, Hurl failure, pre-spawn failure, and interruption, workbench must never remove, chmod, or rewrite caller payload files. Document that the caller must keep the root readable and alive until execution finishes; disappearance after preflight is a normal runtime failure, not an excuse to recreate or substitute a directory.

Acceptance extends `hurl-workbench-core/test/HurlWorkbench/Hurl/RunTest.hs` with captured argv assertions for explicit/default roots, plus `hurl-workbench-core/test/HurlWorkbench/Run/SelectionTest.hs` and `hurl-workbench-core/test/HurlWorkbench/Suite/RunTest.hs` for propagation and no child work on invalid roots. Preserve source-path escape tests in workspace tests.


### Milestone 3: Prove exact bytes, concurrency, and ownership


Extend `hurl-workbench-cli/test/fixture-server/FixtureServer.hs` with a raw request-body capture endpoint if the existing echo handler cannot prove exact bytes. Register `hurl-workbench-cli/test/FileRootTest.hs` from `hurl-workbench-cli/test/Main.hs` and create two independent temporary roots, each containing `request.json`, with different UTF-8 content, CRLF versus LF, and distinct final-newline choices. Run the same committed fragment concurrently against separate fixture endpoints and compare captured bytes or independently computed hashes to each source file. Avoid text normalization in the fixture or test comparison.

Cover `run workflow`, `test workflow`, `run/test recipe`, matrix, and suite propagation. The two-invocation test must use real Hurl and isolated output directories, not just mocked argv. Repeat a focused ownership scenario with Hurl assertion failure and an interrupted slow request; compare directory contents and file modes before/after and verify all caller files remain. Exercise the suite parameter alternative, CLI precedence over it, and relative resolution from a nested working directory. Assert report summaries contain neither root sentinel nor payload sentinel and that render output is byte-identical with the new feature present in the manifest.

Add `examples/file-body/hurl-workbench.dhall`, `examples/file-body/request.hurl`, and a README describing caller creation/lifetime and exact-byte verification. The committed fragment uses `file,request.json;`; the example runner creates payloads outside the workspace. Add it to `just examples`. Update `docs/reference/cli.md`, `docs/reference/workspace.md`, `docs/guides/integration-testing.md`, `docs/security.md`, and ADR context. Synchronize schemas and examples into package copies, and run release checks. No upstream upload storage, payload generation service, or cross-repository implementation is part of this change.


## Concrete Steps


Run from the repository root while implementing:

```bash
nix develop -c cabal test hurl-workbench-core-test --test-show-details=direct
nix develop -c cabal test hurl-workbench-cli-test --test-show-details=direct
nix develop -c just sync-check schema-check
```

After the new fixture exists, its tests provide automatic server startup and byte comparison. The example runner must also exercise the equivalent public command with its private generated root and active loopback fixture:

```bash
hurl-workbench --workspace examples/file-body/hurl-workbench.dhall test workflow send-body --file-root "$payload_root" --variable baseUrl="$fixture_url"
```

Here `payload_root` is the caller-created directory containing `request.json`, and `fixture_url` is the URL returned by the started fixture. Implement and document those allocations in `just examples`, so no caller needs to guess port or server startup details. The reproducible repository checks are:

```bash
nix develop -c just examples
nix develop -c just check
just linux-check
```

Expect passing tests, `release copies: PASS`, `schema compatibility: PASS`, and `examples: PASS`. Run `just linux-check` from macOS outside the Nix shell, preferring its Apple-container path. Verify effective unreadability under an appropriate non-root process on each supported platform.


## Validation and Acceptance


AC-1 requires exact body bytes from an override root and the workspace-root fallback, verified through a real fixture server. AC-2 requires missing/not-directory/not-readable roots to return exit 2 before any subprocess, including version probes and hurlfmt. AC-3 requires render/validate behavior to remain inspection-only and summaries to omit root/content values; render and validate do not acquire a new CLI option. A manifest may declare a runtime file-root parameter without supplying it during inspection.

AC-4 requires simultaneous independent invocations with identically named payload files and different byte content; each endpoint must capture its own exact bytes and the workspace must remain unchanged. AC-5 requires caller-owned files to survive success, failure, and interruption unchanged, while fragment containment rejection still applies. Add report-overwrite overlap refusal, parameter/CLI precedence, secret/generated parameter rejection, valid symlink canonicalization, and root removal after preflight as focused edge cases. File-root selection must neither weaken IR-5 fixture isolation nor change IR-6 command environments.


## Idempotence and Recovery


Use fresh payload and report directories for each test. Workbench does not create or clean payload roots; the caller cleans them after workbench and its child processes have exited. If a supplied root fails preflight, fix that path or its permissions and rerun without any execution side effects. If it disappears during Hurl execution, preserve the failure and retry only after the caller restores its own input. Never delete payloads as part of report overwrite or generic temporary-file cleanup.


## Interfaces and Dependencies


The important interface is an abstract `FileRoot` produced by IO validation and carried through prepared runs to `RunRequest`. CLI options are raw input only; core execution receives validated values. `Suite.fileRootParameter` resolves once per suite and cannot depend on recipe or matrix binding layers. Other plans adding suite fields must preserve its compatibility default and select the root before setup or check processes.

Use existing directory/filepath/unix support and the already implemented Hurl `--file-root` argument; no new package version is selected. Retry `mori registry list`, then relevant package searches and owning-project `show --full`/`docs` before using unfamiliar filesystem APIs. If dependency bounds need to change, verify them against the authoritative package registry and upstream release tags first. No new Hurl grammar parsing is authorized.
