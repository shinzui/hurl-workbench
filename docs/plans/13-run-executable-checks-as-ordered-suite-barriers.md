---
id: 13
slug: run-executable-checks-as-ordered-suite-barriers
title: "Run executable checks as ordered suite barriers"
kind: exec-plan
created_at: 2026-11-11T20:51:21Z
intention: "intention_01m7663e7yehy9z6jqbfv9vje7"
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
      at: 2026-11-12T14:05:21Z
      mode: "implement"
      note: "Implement validated checks, bounded process execution, and ordered suite reporting"
---

# Run executable checks as ordered suite barriers


This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current during implementation. Record implementation friction according to `agents/skills/exec-plan/FRICTION.md` and distill durable decisions into `docs/adr/` before completion.


## Purpose / Big Picture


A suite will be able to make an assertion that HTTP alone cannot express by running a named application-owned executable between Hurl runs. A check can compare normalized CLI/API results or inspect a supported semantic event-count API. It runs only after earlier Hurl work finishes, and later work waits for its result. Its outcome and private output belong to the suite's ordinary report tree.

This implements [IR-4](../improvement-requests/admit-executable-checks-as-ordered-suite-runs-for-assertions-hurl-cannot-make.md), including AC-1 through AC-6 and its 2026-10-11 amendment. A barrier is an execution step that waits for all preceding batch work and completes before any following batch starts. Checks are explicit suite steps, not arbitrary hooks or shell command strings.


## Progress


- [x] Milestone 1 (2026-11-12): Version-1 manifests remain compatible; named checks validate canonical executable containment, references, duplicate names, status/timer ranges, Plain argv templates and environment policies. All frozen compatibility fixtures and located negative check tests pass.
- [x] Milestone 2 (2026-11-12): The single-shot runner uses private separate file captures and the shared ten-second group cleanup policy. Tests prove expected zero/nonzero status, mismatch, spawn/capture failure, timeout, cancellation, TERM-ignoring descendants after leader exit, owner-only captures and injected secondary cleanup failure.
- [x] Milestone 3 (2026-11-12): Public CLI tests prove jobs=2 ordering on both barrier edges, checks-only execution, keep-going/fail-fast, whole-suite preflight, report refusal, redaction, timeout/cancellation summaries and service death during a check. Service cleanup precedes teardown after check failure. Core: 135 tests passed; CLI: 52 tests passed; a focused run also verifies cancellation during cleanup with an actual invocation environment snapshot.
- [x] Milestone 4 (2026-11-12): Local and actual Rei CLI/API category parity checks use declared inputs and independently provisioned fixtures. The HTTP-only mismatch is named and fails. Both macOS `nix develop -c just check` and Apple-container ARM64 `just linux-check` pass, including 135 core/52 CLI tests, examples, source-archive executable modes and Nix checks.

Completion (2026-11-12): All four milestones and AC-1 through AC-6 are verified.
The final macOS and Linux release gates both exit zero. Mori registry and dependency
source discovery succeeded using the current shell-profile endpoint; no dependency
bounds changed. FRIC-13 and FRIC-14 are resolved, strict friction validation passes,
and no entries under this plan remain logged. The actual independently provisioned
Rei evidence and reproducible caller invocation are recorded below.


## Surprises & Discoveries

2026-11-12: The existing summary-write fallback inferred service failure from numeric exit 4, which is also an ordinary Hurl/check child status. It now tests actual service failures. The regression creates a summary-write error after a check returns 4 and requires exit 3 while retaining the named check result.

2026-11-12: Cancellation can arrive after the check leader exits while a descendant holds the TERM grace open. Cleanup now runs as its own bounded task and is joined before propagating an interruption; a regression test cancels specifically during that interval and verifies the observed cancelled result and absence of a live descendant.

2026-11-12: Cabal sdist deliberately assigns 0644 to every extra-source file, including executable helpers (FRIC-14 in `docs/friction-log/`). The release wrapper now normalizes only the two declared helper tar entries to 0755 before unpacking; the archive acceptance runs their actual checks rather than repairing extracted files.

2026-11-12: The inherited Mori endpoint was stale; the current shell profile endpoint restored registry discovery without changing user configuration (FRIC-13 in `docs/friction-log/`). Checks-only suites require lists for aggregate Hurl cases and metadata while each prepared Hurl batch remains nonempty. Existing lifecycle scheduling and service monitors otherwise compose directly with a Check barrier.


## Decision Log

2026-11-12: Release archives use `scripts/build-sdist.sh` after Cabal source listing, with narrowly declared executable tar modes. This preserves the executable-file check contract in distributed examples without weakening validation or requiring manual chmod after extraction. ADR 8 records the packaging constraint.


2026-11-11: Require each check executable to be a workspace-relative executable file with a canonical target inside the workspace. Service commands retain their current executable lookup semantics. This check-specific rule prevents accidental changes to the existing service interface.

2026-11-11: Only declared Plain parameters may substitute argv placeholders, and only explicit environment bindings carry Secret parameters. Use suite-level bindings without recipe/matrix layers. Generated parameters remain per Hurl execution and cannot silently become shared check inputs.

2026-11-11: Omitted check timeout means a finite 60-second execution budget; explicit values must be positive. Group termination has a separate five-second TERM grace followed by a five-second KILL/reap budget. Return a primary outcome plus cleanup diagnostics instead of replacing the original assertion failure.

2026-11-11: Use the ordered suite sequence and group-ownership primitives from [IR-1's plan](10-support-ordered-multi-service-suite-lifecycles.md). Complete its milestones 1 through 3 before this plan's suite-integration milestone; schema and isolated runner work can proceed earlier. Reuse [Plan 8's](8-support-explicit-clean-environments-for-managed-processes.md) environment policy when available.

2026-11-11: Existing suites keep optional reports. A suite containing checks requires `--report-dir`, giving every check a durable private output location and a summary. This is a preflight requirement specific to the new feature and must be documented in help.


## Outcomes & Retrospective

All four milestones are complete on 2026-11-12. Named workspace executables now
run once as ordered barriers, with Plain-only argv substitution, explicit Secret
environments, whole-suite preflight, finite process ownership, private captures,
truthful ordered outcomes and global fail-fast. Checks-only suites preserve empty
Hurl collections without dummy requests. Service monitoring and cleanup/teardown
remain active around checks.

The final `nix develop -c just check` and `just linux-check` invocations both exit
zero. Each runs 135 core tests and 52 CLI tests, compatibility and release-copy
checks, live examples, performance, unpacked source distributions and Nix checks.
The Linux gate uses the unmodified final source snapshot in a disposable Apple
ARM64 container. Packaged examples actually execute the matching and deliberately
failing checks after archive extraction, with executable helper modes preserved.
The final regression distinguishes child status 4 from a true lifecycle failure
when summary writing fails. Cancellation is also exercised during descendant
cleanup after leader exit.

The real Rei consumer proves persisted category parity through supported CLI and
paged HTTP APIs on two independent Hinagata clones, then observes a meaningful
one-versus-two-category mismatch. Both process groups stop before caller release,
and tokens remain absent from argv, ordinary logs and summaries. It does not
claim complete Rei operation coverage, semantic event-count coverage or a newer
Rei cohort. The recorded binary evidence remains applicable after the subsequent
summary-error priority fix, which changes only the reporting-failure path; both
platform release gates exercise that final fix.

[FRIC-13](../friction-log/13-inherited-mori-endpoint-uses-retired-postgresql-socket.md)
is resolved by a command-local selection of the already-declared current database
endpoint. No user configuration was changed.
[FRIC-14](../friction-log/14-cabal-source-archives-discard-executable-helper-modes.md)
is resolved by the explicit release archive normalization boundary and unpacked
behavioral acceptance. Direct Cabal source archives retain their upstream ordinary
modes; the documented release wrapper preserves the declared helpers.

Durable ownership, reporting and packaging decisions are distilled into ADRs
[6](../adr/6-managed-service-process-group-lifecycle.md),
[7](../adr/7-suite-preflight-safety-and-report-isolation.md) and
[8](../adr/8-self-contained-multi-package-release-builds.md). No required work remains.


## Context and Orientation


`schema/Workspace.dhall` currently has no checks category; `schema/RunReference.dhall` permits only workflows, recipes, and matrices. `hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs` defines their typed names and records. `hurl-workbench-core/src/HurlWorkbench/Workspace/Context/Internal.hs` holds the validated indexes, while `hurl-workbench-core/src/HurlWorkbench/Workspace/Context.hs` exposes safe typed lookups. `hurl-workbench-core/src/HurlWorkbench/Workspace/Validate.hs` accumulates deterministic validation errors and resolves fragment/working-directory containment. Adding checks requires all these surfaces together.

`hurl-workbench-core/src/HurlWorkbench/Service/Resolve.hs` contains `ResolvedCommand`, environment binding resolution, and readiness-template parsing. Its current resolver copies literal argv; checks require a separate explicit plain-placeholder path. `hurl-workbench-core/src/HurlWorkbench/Service/Run.hs` provides existing group/timeout patterns. Do not turn an assertion into a readiness probe: readiness retries, while a check executes once and compares its final status.

`hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs` currently flattens every run into nonempty Hurl cases and prepares Hurl-specific reports. `hurl-workbench-core/src/HurlWorkbench/Suite/Run.hs` calls `runBatchObserved` once and writes a summary containing only case/service status. IR-1 replaces flattening with Hurl batches separated by lifecycle barriers. Extend that ordered representation with checks; do not manufacture a fake Hurl request or insert checks into the parallel queue.

`hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Suite.hs` displays suite results. `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/List.hs`, `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Validate.hs`, `hurl-workbench-cli/src/HurlWorkbench/Cli/Options.hs`, and `hurl-workbench-cli/src/HurlWorkbench/Cli/Help.hs` own category listing, validation counts, parsing, help, and completion. Extend these with checks while leaving standalone run/test selectors as workflows/recipes.

Relevant decisions consulted are [ADR 1](../adr/1-versioned-dhall-workspace-schema.md), preserving schema compatibility; [ADR 2](../adr/2-validated-workspace-boundary.md), requiring validated typed categories and canonical paths; [ADR 4](../adr/4-secure-hurl-process-boundary.md), separating secret channels and sensitive artifacts; [ADR 5](../adr/5-bounded-isolated-batch-execution.md), preserving fail-fast and stable result order; [ADR 6](../adr/6-managed-service-process-group-lifecycle.md), requiring process-group ownership; [ADR 7](../adr/7-suite-preflight-safety-and-report-isolation.md), preflighting every step before side effects; and [ADR 8](../adr/8-self-contained-multi-package-release-builds.md), requiring self-contained package resources. The prior exclusion of arbitrary hooks remains; update ADRs 6 and 7 to explain the narrow explicit check contract.

The production-consumer amendment is owned by `mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract`; the originating request is from `mori://tan/notification-hub`. These are adoption evidence sources, not repositories to modify as incidental implementation here.


## Plan of Work


### Milestone 1: Add a validated check category


Create `schema/Check.dhall` with `name : Text`, `command : CommandSpec.Type`, `expectedStatus : Natural` default 0, `timeoutSeconds : Optional Natural` default None, and `description : Optional Text` default None. Export it from `schema/package.dhall`, add `Workspace.checks : List Check.Type` default empty, and add `RunReference.Check : Text`. Mirror this in `Workspace.Types` with `CheckName`, `Check`, and `CheckRun`, using explicit Dhall constructor mapping where needed.

Extend the shared schema-version-1 compatibility conversion in `Workspace.Decode` to add the absent checks list and widen legacy run-reference unions, including empty typed list annotations and IR-1's Service alternative if already present. Preserve explicit values and reject malformed types after conversion. Keep old frozen fixtures unchanged. First prove an old suite and a recipe/check/recipe manifest decode through the same validated boundary before expanding cases.

Add check indexes, lookup accessors, and canonical executable paths to the validated workspace. Reject duplicate check names, missing check references, empty or absolute executable paths, directories, non-executable files, parent traversal, and symlink escape after canonicalization. A symlink whose canonical target stays inside the workspace may be accepted. Reuse contained-path validation rather than joining unchecked text at execution time. Keep name uniqueness per category; prevent cross-kind artifact collisions with typed namespaced report paths. Reject duplicate artifact identities across repeated occurrences as current suite reports do, rather than silently overwriting a prior check.

Validate `expectedStatus` in 0..255 and positive explicit timeouts with checked conversion to runtime units. Parse `{{parameter}}` in each argv element using the same exact-placeholder syntax as readiness URLs. Literal surrounding text is allowed, but unknown names, malformed braces, Secret, and Generated references fail static validation. Substitute strings as one argv element without shell splitting. Environment bindings retain existing Plain/Secret behavior. Working directories remain workspace-contained. Apply IR-6 policy validation to check commands through shared `commandIssues`.

Add list/validate/check-completion output and deterministic located error tests in workspace and CLI suites. A malformed late check must reject the entire suite before a service or earlier Hurl run starts. Acceptance includes unchanged old manifests, valid category introspection, and all requested path/name/channel refusals.


### Milestone 2: Implement a bounded single-check runner


Add `hurl-workbench-core/src/HurlWorkbench/Check/Resolve.hs` to discover the check's parameter subset, resolve suite-level bindings, substitute argv, and construct a redacted `ResolvedCheck` with its canonical executable, working directory, final environment, expected status, and deadline. Use only runtime/default/environment layers; do not import a neighboring recipe's bindings. Parse all check templates and prepare final environments during whole-suite preflight. With IR-6 present, use its environment selector and invocation snapshot; missing required allowlist names fail before any child is started.

Add `hurl-workbench-core/src/HurlWorkbench/Check/Run.hs` and register it with the Cabal package. Execute exactly once, with no shell, closed stdin, a new process group, and stdout/stderr directed to separate owner-only files under the prepared check directory. Allocate files before spawn and avoid unbounded in-memory capture. Reuse IR-1's `HurlWorkbench.Process.Run` acquisition/termination primitive once landed; if developed earlier, keep the interface compatible and consolidate before integration.

Start the execution deadline when spawning begins. Expected-status comparison applies only to normal process exit; timeout, signal/cancellation, spawn failure, and inability to clean the group remain distinct typed outcomes. A configured expected nonzero status is a success when matched. On any terminal path, terminate and reap remaining group descendants even when the leader already exited. Use the bounded termination policy in the decision log and keep cleanup diagnostics separate from the primary check result. An asynchronous exception is rethrown only after cleanup and after the enclosing suite has a chance to retain partial results.

A `CheckResult` carries logical name, primary outcome, optional actual child status, duration, relative stdout/stderr paths, and cleanup diagnostics. Neither its Show instance nor normal CLI error rendering may include resolved argv, environment values, or captured output. The private output files can contain credentials echoed by an application; document that they have the same sensitivity as Hurl reports and are not redacted response data.

Add `hurl-workbench-core/test/HurlWorkbench/Check/RunTest.hs`, registering it in the test driver and Cabal file. Use a workspace-local executable fixture to test matched zero/nonzero status, mismatch, timeout, cancellation, spawn race/failure, and a leader that exits while a descendant ignores TERM. Verify file permissions, bounded cleanup, absent survivor PIDs, original failure retention, and separate stdout/stderr. An injected cleanup failure must not overwrite an expected-status mismatch.


### Milestone 3: Integrate ordered barriers and truthful reporting


Require IR-1's prepared-step scheduler and process ownership milestones first. Add a prepared Check step and result alongside Hurl batches and Service steps. Resolve every check and all report paths before any setup/service/Hurl process starts. Require a report root for check-bearing suites; use `REPORT_ROOT/SUITE/checks/CHECK/` for private stdout/stderr and stable relative summary paths, and collision-check this namespace against all Hurl/artifact paths. Checks-only suites are valid: the Hurl case collection may be empty, but the ordered step collection remains nonempty. Update code that currently assumes a `NonEmpty BatchCase` rather than inventing dummy cases.

Drain the previous Hurl batch, run the check alone while managed-service monitors remain active, and only then schedule later Hurl work. Fail-fast closes scheduling across barriers, and later steps become explicit skips. With keep-going, an ordinary status mismatch or timeout can allow later steps after successful cleanup; an unavailable service or cleanup failure aborts dependent execution. The next step never overlaps a timed-out check's descendants. A service dying during a check cancels its group, performs IR-1 cleanup/teardown, and retains both the service failure and the interrupted check.

Keep legacy Hurl `cases` and aggregate service fields, and extend the common ordered `steps` summary with check kind, name, status, elapsed seconds, actual/expected exit status where appropriate, and relative artifact paths. Use separate primary failure and cleanup diagnostics. Preserve service-lifecycle exit 4 priority and report-write/pre-spawn exit 3 behavior. In the absence of those failures, an expected-status mismatch returns the actual nonzero status or 1 when the unexpected actual status is zero; timeout selects 124. Cancellation records cancelled and then preserves the existing interrupt/exception behavior after finalization. Cleanup-only check failure selects 3. Ordinary Hurl failures and check failures are selected in declaration order, independent of completion time.

Update `Cli.Command.Suite` to render these named outcomes and paths without replaying check output into normal diagnostics. Add public CLI tests for recipe/check/recipe ordering at jobs=2, keep-going/fail-fast, checks-only suites, a service death during a check, report overwrite refusal, sensitive sentinels, and check failures followed by teardown. Use read-only recipes in parallel barrier tests so they also pass IR-5; keep mutating shared-state scenarios serial and authorized.

Acceptance requires event logs showing both sides of the check barrier, a named failure in `summary.json`, no later starts after fail-fast, and process/report evidence for timeout and cancellation. Integrate IR-1's failure-during-check teardown acceptance here.


### Milestone 4: Demonstrate semantic CLI/API parity


Add `examples/executable-checks/hurl-workbench.dhall`, Hurl fragments, an executable check helper, and a README. The local helper compares normalized command outcomes and persisted observations from two independently provisioned fixture targets identified by declared Plain inputs, with credentials supplied only through environment bindings. The initial in-repository fixture can use workspace-local executable fixtures and the CLI test server to validate ordering, mismatch failure, and reporting through the real workbench CLI.

For AC-6, add `scripts/check-command-parity.sh` as an opt-in driver taking `HURL_WORKBENCH_CONSUMER_WORKSPACE` and `HURL_WORKBENCH_CONSUMER_SUITE` for a real consumer manifest. Run it within the caller's independently provisioned CLI and HTTP fixture scopes. Use Mori to inspect the actual application's supported commands/domain/store APIs, and implement the assertion in an application-owned executable rather than reading framework-internal tables. Compare changed/no-op, refusal, persisted domain facts, or semantic event counts as required by that consumer. Deliberately introduce a mismatch and prove the check fails and is named in the summary.

The driver must require distinct logical fixture identities and accept endpoints through declared runtime parameters. It must not log credentials, place secrets in argv, provision shared state as a substitute for independent fixtures, or claim that framework schema/package gates have moved into workbench. With IR-6 available, prove clean environment selection using a secret sentinel and irrelevant ambient settings. Discover and record the exact real invocation through `mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract` or another actual requesting application. The local fake parity helper alone does not satisfy AC-6; leave this milestone open until real supported application API evidence exists.

Update `docs/reference/workspace.md`, `docs/reference/cli.md`, `docs/guides/integration-testing.md`, `docs/security.md`, and relevant ADRs. Synchronize schema/example copies and add executable helper resources to `hurl-workbench-cli/hurl-workbench-cli.cabal` distribution globs explicitly if the existing globs omit them. Preserve executable permissions in source archives and test an unpacked example. Run platform and release checks.


## Concrete Steps


Run from the repository root after each implementation milestone:

```bash
nix develop -c cabal test hurl-workbench-core-test --test-show-details=direct
nix develop -c cabal test hurl-workbench-cli-test --test-show-details=direct
nix develop -c just sync-check schema-check
```

After creating the example, the static public check is:

```bash
nix develop -c cabal run hurl-workbench -- --workspace examples/executable-checks/hurl-workbench.dhall validate
nix develop -c cabal run hurl-workbench -- --workspace examples/executable-checks/hurl-workbench.dhall list checks
```

Extend `just examples` to create fresh fixture and report directories and run its recipe/check/recipe suite at jobs=2. It must observe a passed check and a deliberately failing variant with the expected nonzero exit and named summary entry. Then run:

```bash
nix develop -c just examples
nix develop -c just check
just linux-check
```

Expect all test suites and release-copy/schema checks to pass. Run the local Apple-container Linux gate from macOS outside the Nix shell. After exporting the verified real consumer workspace/suite and private runtime inputs inside independently provisioned fixture scopes, run:

```bash
bash scripts/check-command-parity.sh
```

Record the actual provider/consumer invocation and sanitized observations in the plan when known. The script must prove both a match and a mismatch; no invented external command syntax is an acceptance substitute.

Actual provider/consumer acceptance (2026-11-12) uses the existing matching Rei
8.0.0.0 API, CLI and live schema-hook cohort, discovered through Mori. The CLI
reports `rei 8.0.0.0 (8c5e112)` from
`mori://shinzui/rei/commits/8c5e11258f97b66600ce53269bd9675d9459db52`.
The helper is the application-specific executable in
`examples/executable-checks/rei/parity.py`; it uses supported CLI category JSON and
bounded paged category HTTP reads, with no framework-table reads. The caller uses
two separate Hinagata leases with different database names and endpoint origins.

```bash
export hinagata_postgres_datadir="$(mori path mori://shinzui/hinagata)/hinagata-postgres"
nix develop -c python3 scripts/check-rei-command-parity.py \
  --api "$REI_API_EXECUTABLE" --rei "$REI_CLI_EXECUTABLE" \
  --schema-hook "$REI_LIVE_TEST_EXECUTABLE" --hinagata "$HINAGATA_EXECUTABLE" \
  --workbench "$HURL_WORKBENCH_EXECUTABLE" --evidence-root /tmp/new-rei-parity-evidence
```

The final private evidence at `/tmp/hurl-plan13-rei-parity-final` records a matching
check status 0 with one category on each side. A supported HTTP POST creates one
extra category only on the HTTP twin, producing named `parity` status 1 and the
private diagnostic `persisted category parity differs: CLI 1, HTTP 2`. Both summaries
retain relative stdout/stderr paths and durations; token sentinels are absent from
summaries and ordinary driver logs. Caller evidence confirms both owned process
groups absent before the two `Released` inspections, at ordered timestamps
1794493944942716000 < 1794493945248583000 < 1794493945385697000.

The verified executable SHA-256 values are API
`ab17dca4bbcaffba3c208ea15a71f5e64702ff006651a89006eefeced3cb228f`, CLI
`1ed16aea8704564f790728df158418623080f4485f64e61acf7917805fee2ea5`, live schema hook
`2ff95770918cd6a2b905719ba01092a13cdb7ce6103ff48b750d8f30e8219b19`, Hinagata
`6286db4cc911c94d6054d77e71f5e1315c8899ca27e9126bbb1852edf7d1cf1a`, and workbench
`6e2bb6629ac7f1953c40f9687f6b260ccb8ae37922aa509e2d0246159276f421`.
The example's matching recipe/check/recipe suite uses jobs=2; the mismatch mutation
is authorized and serial. No Rei source, production service or production database
was modified. These are persisted-fact parity observations, not an event-count or
newer Rei-cohort acceptance claim.



## Validation and Acceptance


AC-1 is recipe/check/recipe execution order and a failed suite with a named check on status mismatch; also test explicit expected nonzero success. AC-2 proves plain argv substitution as one element and secrets only through environment, with secret sentinels absent from captured argv, ordinary diagnostics, and summary metadata. AC-3 rejects executable escape including symlinks and duplicate check names before execution.

AC-4 records both barrier edges at jobs=2 and proves fail-fast prevents later dependent steps. AC-5 spawns a descendant, times out or interrupts the check, and verifies bounded group cleanup, retained primary failure, separate cleanup diagnostics, duration, and relative artifacts. AC-6 runs a real supported application-owned parity/event assertion using independent fixture inputs and demonstrates a meaningful mismatch failure without credential disclosure.

Compatibility includes old fully specified manifests, existing Hurl statuses, bounded parallel batches between barriers, checks-only suites, service-monitor cancellation, report overwrite/permissions, IR-1 teardown after a check failure, and IR-6 policy reuse. New Hurl/Check/Service result kinds must never share a report writer or be mistaken for one another in exit selection.


## Idempotence and Recovery


Checks execute once; the workbench never retries a side-effecting assertion implicitly. Use fresh report roots and caller-owned disposable fixtures for acceptance. Preserve private diagnostics after failures, stop all owned groups before caller fixture release, and require explicit overwrite for an existing suite report tree. A report-write error remains visible separately from the check result. After interruption, verify owned processes are gone before retrying; never kill unrelated PIDs or alter framework-owned database tables to manufacture a passing parity check.


## Interfaces and Dependencies


Public additions are `Check`, `CheckName`, `Workspace.checks`, `RunReference.Check`, and `list checks`. The core `ResolvedCheck`/`CheckResult` interfaces keep expected/actual status, timing, process outcome, and cleanup diagnostics separate. `PreparedSuite.cases`, `SuiteResult.cases` and `SuiteMetadata.scenarios` are now lists so they can represent checks-only suites; individual prepared Hurl batches remain nonempty. The ordered suite scheduler introduced by IR-1 is the sole owner of barriers and global fail-fast. The common process-group primitive owns bounded termination; IR-6 owns final environment selection. IR-2 generation and IR-3 file roots remain Hurl execution inputs and are not implicitly inherited by checks.

Use existing process, concurrency, filesystem, and time dependencies; no new version bounds are selected. Before unfamiliar API use, retry `mori registry list`, relevant package searches, owning-project `show --full` and `docs`, and read the returned local sources. Confirm any proposed library version change against its authoritative package registry and upstream tags. Keep cross-repository evidence linked with canonical Mori URIs, and preserve local references to these sibling plans without adding an unrelated MasterPlan.
