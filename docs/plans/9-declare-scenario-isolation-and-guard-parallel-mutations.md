---
id: 9
slug: declare-scenario-isolation-and-guard-parallel-mutations
title: "Declare scenario isolation and guard parallel mutations"
kind: exec-plan
intention: "intention_01m76636k9enysm8fxs71dah6z"
created_at: 2026-11-11T20:49:52Z
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-11-11T20:49:52Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-12T03:27:06Z
      mode: "implement"
      note: "Begin implementation of scenario isolation and early parallel mutation guards"
---

# Declare scenario isolation and guard parallel mutations

This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current. Follow `agents/skills/exec-plan/PLANS.md`, record implementation friction through the bundled friction tooling, and distill durable decisions into `docs/adr/` before completion.


## Purpose / Big Picture


A suite author will be able to declare whether scenarios share application state. Parallel runs that might mutate shared state will fail before a service or Hurl execution starts, even when mutation is authorized. Parallel mutation will require a verified runtime handoff assigning each scenario its own caller-provisioned fixture and service endpoint. Serial shared-state mutation and parallel shared-state read-only suites will continue working.

This implements [IR-5](../improvement-requests/declare-scenario-isolation-and-guard-parallel-mutations.md). Demonstrate the result with two concurrent writes to independently leased databases: each scenario reads only its own write, duplicate fixture or endpoint identities are refused, and workbench summaries contain only logical isolation metadata.


## Progress


- [x] (2026-11-12) Milestone 1: Compatible isolation declarations and early core/CLI guards are implemented. Core tests (83) and CLI tests (35) pass, including frozen populated/empty old schemas, invalid policies, requested parallelism for a single unsafe run, ordered mixed-suite refusals, external mode, opt-in independence, zero capability/syntax hooks, and service/readiness start markers. `just sync-check schema-check` passes. Serial opted-in writes and parallel reads remain supported.
- [x] (2026-11-12) Milestone 2: Private version-1 handoffs, full assignment/origin/channel/conflict validation, and cached per-expanded-run preparation are implemented. Core/CLI tests and the public local two-server driver pass. The early real Hinagata two-lease invocation passed concurrent independent writes, direct database corroboration, duplicate/incomplete refusal, and release inspection before report variants were expanded.
- [x] (2026-11-12) Milestone 3: Safe metadata is separate from executable requests. Parsed success/refusal/setup/cancellation summaries identify policy and scenarios without runtime sentinels. Deterministic cancellation/fail-fast tests retain ordered completed results, join workers, preserve service exit 4 on summary failure, and rethrow cancellation even on write failure. Core (91) and CLI (37) tests pass on macOS.
- [x] (2026-11-12) Milestone 4: Shared/independent examples, documentation, ADRs 1/5/7/8, schema/release copies, and the complete real-provider driver are verified. The full macOS and local ARM64 Apple-container Linux `just check` gates each pass all 91 core and 37 CLI tests, examples, compatibility, formatting, distribution builds, and Nix checks. The public independent manifest also validates. Both gates used the same tracked source tree (`81afcb9668a2054c4796514601070aac78f7c24a`); macOS ran in an isolated detached validation worktree.

Completion (2026-11-12): all four milestones and IR-5 AC-1 through AC-5 are satisfied. The full real-provider driver passes success, Hurl failure/fail-fast, cancellation, and partial allocation failure, checking Hurl shutdown before services stop and exactly one release per acquired lease with Released inspections and database absence. Final macOS and local Apple-container ARM64 Linux release gates both exit zero with `all checks: PASS`; both run 91 core and 37 CLI tests. The tracked source tree is identical across those platform checks. [FRIC-4](../friction-log/4-mori-registry-unavailable-through-postgresql-tunnel.md) and [FRIC-5](../friction-log/5-linux-release-gate-realizes-editor-only-hls-dependencies.md) are resolved and strict friction validation passes. No dependency pins or runtime bounds changed. This plan is standalone, with no parent MasterPlan.


## Surprises & Discoveries


2026-11-12: plan 8 has landed. Its in-tree command-policy compatibility pass already supplies the exact Dhall expression traversal needed for suite records and empty-list annotations; suite normalization extends that approach without changing dependency versions or introducing new external APIs. Mori source discovery initially failed ([FRIC-4](../friction-log/4-mori-registry-unavailable-through-postgresql-tunnel.md)), then succeeded with a command-local override from the current shell profile, following the completed plan 8 recovery note. No service restart was needed.

2026-11-12: macOS exposes `/tmp` and `/var` as OS-owned aliases to `/private`. Rejecting every ancestor symlink also rejected ordinary provider temporary paths. Report checks now permit only these fixed standard destinations on macOS, while rejecting user-controlled ancestor symlinks.

2026-11-12: a real Hurl failure can finish and be observed while SIGINT is delivered. A cancelled summary retains that completed failure alongside unfinished cancelled cases. The real driver checks those truthful outcomes; deterministic core barriers separately prove completed success retention and queued unfinished cases.

2026-11-12: the default editor shell again built unrelated HLS dependencies before Linux release checks ([FRIC-5](../friction-log/5-linux-release-gate-realizes-editor-only-hls-dependencies.md)). A dedicated check shell preserves the pinned compiler and complete gate while excluding HLS; no dependency pins or runtime bounds changed.


## Decision Log


2026-11-11: Default to SharedState and retain schema version 1 by normalizing missing suite fields during decoding. Completion defaults alone do not preserve old fully specified Dhall records, including empty lists with old element annotations.

2026-11-11: Mutation permission and state isolation are separate checks. Any requested jobs count greater than one with a mutating or unclassified shared-state run is refused, even if expansion contains only one run. Apply the same conservative rule to standalone mutating matrices, which otherwise offer the same unsafe scheduling path. Single workflow and recipe commands remain serial.

2026-11-11: Use caller-owned, already provisioned and ready services for independent scenarios. Add a native suite runtime handoff file and a corresponding core API; workbench validates the whole assignment before scheduling. It does not acquire databases, start per-scenario services, release leases, or infer independence from separate Hurl sessions. Independent suites must use external-service mode and may not declare a shared managed service.

2026-11-11: Treat the provider's fixture identity as an assertion by a trusted caller, checked for uniqueness and completeness alongside endpoint assignments. Workbench cannot prove that two different URLs or opaque identifiers reach different databases. The integration test establishes the real provider's correctness; documentation must state this trust boundary.


## Outcomes & Retrospective


All five IR-5 criteria are verified. Old populated and empty suite shapes decode with SharedState; unsafe requested parallelism fails before probes or children; verified independent inputs isolate actual concurrent writes across two real leased databases; existing authorization, bounded scheduling, fail-fast, report isolation, exit selection, and process cleanup remain intact; parsed success/refusal/setup/cancellation summaries expose only logical isolation metadata.

The early producer/consumer check validated the proposed handoff without a contract change before report variants were expanded. The real provider fixture checks both database identity and own-marker-only observations, then independently verifies release. Normal core/CLI/local tests require no real database credentials. Public shared and independent examples and the versioned JSON contract are documented; provider ownership and the trusted-identity boundary are explicit. ADRs 1, 5, 7, and 8 retain the compatible schema, state-versus-session distinction, verified preparation and reporting boundary, cancellation publication, and the release check shell. ADR 6's managed process ownership remains unchanged.

[FRIC-4](../friction-log/4-mori-registry-unavailable-through-postgresql-tunnel.md) in docs/friction-log/ is resolved: the current shell-profile endpoint restores Mori discovery through a command-local override. [FRIC-5](../friction-log/5-linux-release-gate-realizes-editor-only-hls-dependencies.md) in docs/friction-log/ is resolved: the dedicated check shell removes editor-only HLS from Linux release validation while retaining the same pinned compiler and complete gate. Both entries were triaged through the bundled script; no entries remain logged for this plan.

An initial Linux empty-category assertion failed without showing stderr; the assertion now compares the complete CommandResult. The steady-candidate Linux gate passes that case and all remaining checks. No runtime cause was established, and no decoding fallback was added. macOS validation used a temporary detached worktree to avoid sharing Cabal's inplace registration cache with Linux. Future cross-platform checks should keep build directories separate when run concurrently.


## Context and Orientation


A workspace is a Dhall manifest decoded into Haskell values and validated before use. A suite lists workflows, recipes, or matrices. A matrix expands a recipe into one run per case. In this plan a scenario is one expanded run, identified by its existing logical artifact stem, such as `property-page-sizes/small`. Shared state means scenarios can observe or change the same application resources. Independent state means a caller has separately provisioned the resources and service for every scenario. A lease is the provider's temporary allocation of a fixture, held until every consumer has stopped. A handoff is runtime metadata and bindings supplied by that provider; it is not committed workspace configuration.

`schema/Suite.dhall` defines name, runs, optional service, isolation (default SharedState), failFast, and description. `schema/package.dhall` exports the schema. `hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs` defines the corresponding Suite and generic decoder; `hurl-workbench-core/src/HurlWorkbench/Workspace/Decode.hs` evaluates, version-checks, and type-checks the full workspace. `hurl-workbench-core/src/HurlWorkbench/Workspace/Validate.hs` validates suite references. Schema copies in `hurl-workbench-core/schema/` and `hurl-workbench-cli/schema/` must match the root.

`hurl-workbench-core/src/HurlWorkbench/Run/Selection.hs` produces ExpandedRun with Classified ReadOnly, Classified Mutating, or UnclassifiedWorkflow safety. Direct workflows are always unclassified; Hurl source is deliberately opaque. `hurl-workbench-core/src/HurlWorkbench/Run/Prepare.hs` renders, checks syntax, and resolves bindings into PreparedRun. It retains the common selection API and adds prepareExpandedForSuiteWith for individual expanded runs and runtime inputs, sharing one rendered-workflow cache.

`hurl-workbench-core/src/HurlWorkbench/Suite/Isolation.hs` provides the pure early isolation guard, shared by the core suite path and CLI suite/matrix commands. `hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs` verifies scenario inputs and applies this guard before run preparation, checks mutation permission, prepares report directories, and returns executable PreparedSuite requests alongside separate safe SuiteMetadata, with one optional ResolvedService for shared state. `hurl-workbench-core/src/HurlWorkbench/Suite/Run.hs` runs the batch inside that service's lifetime and writes summary.json. Safely reportable preflight errors now reserve only the suite root for a refusal/setup summary. Cancellation retains observed completed cases, joins child cleanup, writes a best-effort cancelled summary, and rethrows the original interruption.

`hurl-workbench-core/src/HurlWorkbench/Run/Batch.hs` uses a fixed worker count and a queue. Active cases finish after fail-fast; queued cases become skipped. Observers retain completed results if a service failure interrupts execution. This bounds Hurl concurrency and keeps declaration-ordered results, but does not establish independent server state. `hurl-workbench-core/src/HurlWorkbench/Service/Run.hs` owns only managed service process groups. `hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs` owns Hurl children and temporary secure binding files.

CLI integration lives in `hurl-workbench-cli/src/HurlWorkbench/Cli/Options.hs`, `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Suite.hs`, and `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Matrix.hs`. Tests belong in `hurl-workbench-core/test/HurlWorkbench/Workspace/WorkspaceTest.hs`, `hurl-workbench-core/test/HurlWorkbench/Run/SelectionTest.hs`, `hurl-workbench-core/test/HurlWorkbench/Suite/RunTest.hs`, and `hurl-workbench-cli/test/Main.hs`. The CLI fixture server is `hurl-workbench-cli/test/fixture-server/FixtureServer.hs`. `Justfile` defines release-copy, schema, example, full-test, and distribution checks.

Relevant ADRs consulted are [ADR 1](../adr/1-versioned-dhall-workspace-schema.md), requiring versioned schema compatibility; [ADR 2](../adr/2-validated-workspace-boundary.md), requiring validated inputs; [ADR 4](../adr/4-secure-hurl-process-boundary.md), requiring redacted metadata and protected variable files; [ADR 5](../adr/5-bounded-isolated-batch-execution.md), defining bounded workers and truthful ordered outcomes; [ADR 6](../adr/6-managed-service-process-group-lifecycle.md), defining process ownership and cancellation cleanup; [ADR 7](../adr/7-suite-preflight-safety-and-report-isolation.md), requiring whole-suite preflight and isolated report trees; and [ADR 8](../adr/8-self-contained-multi-package-release-builds.md), requiring synchronized release resources. No existing ADR establishes independent database fixtures. The ADR directory currently uses plain Markdown, with no profiled ADR bundle in mori.dhall; preserve that convention.

The originating consumer is `mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract`, and fixture ownership remains with `mori://shinzui/hinagata`. Neither becomes a production dependency here. [Plan 8](8-support-explicit-clean-environments-for-managed-processes.md) has landed clean child environments. This implementation extends its existing compatibility-normalization approach for suite isolation; the independent runtime handoff remains separate from managed child environment policy.


## Plan of Work


### Milestone 1: Compatible declarations and an early concurrency guard


Add `schema/IsolationPolicy.dhall` as `< SharedState | IndependentState >`, export it, and add `isolation : IsolationPolicy` with default SharedState to Suite.dhall. Add the matching Haskell type and field. Normalize only missing suite isolation fields in schema-version-1 evaluated input before typed extraction; preserve explicit values and reject malformed types. Handle the element type of an empty suites list as well as populated records. Do not rewrite old fixtures or convert arbitrary decode errors to a shared-state fallback. Consult Mori-located Dhall sources before choosing the normalization API.

Keep minimal and minimal-explicit fixtures unchanged. Add a frozen old-shape populated suite fixture without importing the new schema, and an equivalent new fixture. Prove omitted and explicit SharedState decode identically, IndependentState round-trips, invalid union choices fail, and unsupported schema versions retain their current diagnostics. Static validation rejects IndependentState with a nonempty service field: independent execution uses caller-owned services only.

Introduce a pure isolation check in new `hurl-workbench-core/src/HurlWorkbench/Suite/Isolation.hs`. Expand references first and check each safety disposition before formatting, binding resolution, capability probes, report preparation, or service resolution. For SharedState and jobs > 1, return typed issues naming all mutating or unclassified logical runs in declaration order. The guard is independent of allowMutating; jobs = 1 retains the existing mutation opt-in. ReadOnly runs are allowed at higher jobs counts. Until milestone 2 supplies verified assignments, IndependentState is refused with a missing-handoff issue, even with jobs = 1.

Call the same check from the core suite path and the CLI before detectCapabilities, so refused CLI cases start neither service/readiness/Hurl children nor Hurl version probes. Standalone matrix execution has no independent handoff in this change: treat it as SharedState and reject a mutating matrix with jobs > 1. Keep parallel read-only matrix behavior. Do not infer safety by parsing HTTP verbs or Hurl text.

Extend core and CLI tests with mutating recipes, matrix-expanded mutations, mixed suites, and direct workflows, using allowMutating = True to prove that permission does not bypass isolation. Inject a capability detector and syntax validator that fail if invoked, plus service and Hurl start markers. Refusal must produce exit 2 and zero starts. Also cover requested jobs > 1 with a single unsafe expanded run, external-service mode, serial opted-in mutation, and parallel read-only execution. Adjust old suite tests that used parallel unclassified runs to exercise valid serial behavior, preserving their original report assertions and adding explicit refusal regressions. Run the core/CLI test commands and schema checks below; those observable outcomes complete this milestone.


### Milestone 2: Validate a per-scenario handoff before scheduling


Add a core runtime module `hurl-workbench-core/src/HurlWorkbench/Suite/Scenario.hs` for decoding and verifying the contract in Interfaces and Dependencies. Add `--scenario-inputs FILE` to suite CLI options, resolved relative to the invocation directory, and carry optional decoded inputs in SuiteRequest. Export the new modules from the core Cabal package. Read the file once into immutable values; reject malformed input with logical error codes and no raw values. The provider writes it in a private temporary directory with owner-only file permissions. Reject symbolic links, non-regular files, and group/other permission bits. Keep runtime values out of Show instances and decoding error text.

An IndependentState suite requires --external-service and a complete handoff. SharedState rejects a handoff rather than silently ignoring it. Match each entry to exactly one expanded artifact stem, rejecting missing, duplicate, and extra scenarios, duplicate fixture identities, and duplicate normalized endpoint identities. Scenario labels must obey the existing logical path/name rules. A fixture identity is opaque provider metadata, never a report identifier. Compare endpoint origins using lowercase scheme/host and effective port; reject userinfo, query, fragment, non-HTTP(S) schemes, and non-root paths. Different paths on the same server do not establish independence. DNS aliases reaching the same server remain the trusted provider's responsibility.

For each run, verify endpointParameter names a declared Plain parameter in that workflow, then inject the endpoint and generated bindings only into that scenario's BindingInput. Resolve secrets through declared environment names into the existing SecretValue channel. Reject a parameter occurring in multiple handoff channels. For every parameter supplied by the handoff, reject conflicting suite runtime inputs or recipe/case committed bindings; do not silently let common overrides replace the provider's endpoint. Declared defaults and environment fallback are lower priority than a valid explicit handoff. Other ordinary suite inputs retain existing precedence and subset resolution. Missing secret environment variables, wrong parameter kinds, undeclared names, and invalid plain Hurl literals fail preflight without echoing values.

Refactor Run.Prepare so an already expanded run can be prepared with its scenario input, reusing rendered workflow validation where appropriate. Complete assignment verification and all binding preparation for the entire suite before any Hurl execution or report-tree replacement. Build the same BatchCase values and reuse the existing bounded scheduler; no per-scenario service lifecycle is added. No handoff file or fixture handle is copied into reports or Hurl argv.

First prove this path through two local caller-owned fixture servers using the public CLI and distinct generated endpoint bindings. Then perform an early real producer/consumer check before expanding error/report variants: discover the supported Hinagata lease interface with Mori, acquire two disposable leases, start one application fixture per lease, verify each service's database identity privately, and pass the generated assignments to one suite invocation. The provider must retain both leases until workbench returns and its Hurl children are reaped. Record the exact verified provider invocation in the plan and integration guide. If this check exposes a contract mismatch, revise the handoff now; simulated servers alone do not satisfy the real-lease criterion.

A missing or failed provider allocation must prevent invocation for an incomplete assignment; also deliberately submit an incomplete file and assert workbench refusal. Inject duplicate fixture IDs and identical endpoint origins with different case/default-port spelling and prove zero execution starts. Distinct valid assignments must overlap in execution while never exceeding jobs. These integration checks, plus focused core/CLI tests, complete milestone 2. Broken provider infrastructure leaves its real-lease acceptance open.


### Milestone 3: Report isolation on every observable outcome


Separate safe summary metadata from PreparedSuite's executable requests in Suite.Resolve and Suite.Run. Add a top-level isolation field with `shared-state` or `independent-state`, and a scenario field on each case using its logical artifact stem. Retain existing names, relative report paths, and successful/failed case semantics. Never serialize fixture IDs, endpoint URLs, binding values, environment names or values, connection strings, provider exceptions, or captured output into workbench summaries. Hurl-generated response/report content remains subject to the established sensitive-artifact boundary in ADR 4.

For a known suite with valid logical run names and a safely reservable report directory, an isolation or handoff refusal must write a minimal atomic summary with status `refused`, logical cases marked `not-started`, and stable reason codes. Missing runtime inputs are setup failures with status `setup-failed`; neither gets an invented Hurl exit status. Preserve exit 2 for invalid invocation/preflight, 3 for file/start/summary-write failures, and 4 for managed service lifecycle failures. A missing/invalid suite or unsafe/conflicting report path cannot safely produce a summary there: return the diagnostic without overwriting an existing tree or inventing a destination. Tests must distinguish this legitimate absence from a lost refusal summary.

Reuse existing owner-only report permissions, symbolic-link checks, overwrite scope, and atomic summary writes. Preflight reporting must never call a service or Hurl runner. Summaries for refused runs must not claim nonexistent Hurl report artifacts. A reporting failure must not replace an existing higher-priority service failure or swallow cancellation.

Extend the completion observer/finalization path to retain completed outcomes on asynchronous cancellation, wait for child cleanup, write a best-effort summary marked `cancelled` with unfinished cases explicitly distinguished from completed failures, and rethrow the original cancellation. Do not turn cancellation into a successful SuiteResult. Provider-owned services and leases remain alive for the provider's outer cleanup; workbench must neither kill nor release them. Managed shared-state services retain their existing process-group cleanup.

Use deterministic synchronization barriers in cancellation and fail-fast tests rather than timing guesses. Assert completed results remain in declaration order, active workers are reaped, and queued cases do not start after fail-fast. Seed distinct sensitive values in fixture IDs, endpoints, plain/secret bindings, and setup failures; verify their absence from workbench diagnostics and summaries for success, refusal, setup failure, and cancellation. Parse JSON structure as well as checking byte sentinels. If adding Aeson to test build-depends, reuse the existing project bound and source lookup; no version upgrade is planned. These assertions complete milestone 3.


### Milestone 4: Demonstrate real isolation and publish the contract


Add a reproducible acceptance driver `scripts/check-scenario-isolation.sh` and disposable fixture support under `hurl-workbench-cli/test/fixtures/scenario-isolation/`. Use the verified provider interface from milestone 2 to acquire two fresh Hinagata leases and run a minimal database-backed HTTP service per lease. The fixture may use Python plus an installed psql client, following the repository's existing Python process-test pattern; it must not place database passwords in argv. The driver owns services, leases, and protected credential files. Add prerequisite checks and fail clearly rather than silently substituting an in-memory fixture for the database test.

Exercise two mutating matrix cases concurrently through one IndependentState suite. Each performs one POST containing a different marker, then bounded GET observation of its own marker and absence of the other's marker. A barrier must demonstrate overlap, so two accidentally serial runs cannot pass the concurrency assertion. Query both databases through the provider to corroborate the HTTP observations without printing connection details. Each retry of the acceptance test acquires fresh fixtures; POST requests are not automatically retried.

Exercise allocation failure, duplicate lease identity, duplicate endpoint, a Hurl failure with fail-fast, and cancellation. Require provider cleanup evidence: workbench Hurl children stop before provider services stop, and services stop before leases are released. Assert the provider releases every successfully acquired lease exactly once, including partial acquisition failure. Workbench never performs lease release. Record real acceptance commands and concise observations in Progress. The driver must be repeatable without touching application databases or reusing mutated fixtures.

Document the schema, CLI handoff, provider trust boundary, runtime binding precedence, serial migration path, and summary behavior in `docs/guides/integration-testing.md`, `docs/reference/cli.md`, and `docs/security.md`. Add ordinary shared-state and independent handoff examples under `examples/integration-service/` and synchronize `hurl-workbench-cli/examples/`. Include any new fixture/script file types in Cabal distribution manifests when they are needed by packaged tests or examples. Synchronize all schema, README, and changelog copies affected by the change. Update ADRs 1, 5, and 7 with the compatible policy, state-versus-session distinction, preflight/report behavior, and caller ownership boundary; preserve ADR 6's managed-process guarantees.

Run the repository release gate and local Apple-container Linux check. The normal tests must exercise the handoff using local fixtures without requiring a developer's real database credentials; the opt-in real lease driver is additional required acceptance evidence. Triaging implementation friction and the ADR distillation pass finish the plan after all five IR-5 criteria pass.


## Concrete Steps


Run from the repository root, `/Users/shinzui/Keikaku/bokuno/hurl-workbench` in the authoring environment. Reproduction commands follow; Progress records the actual acceptance evidence:

```bash
nix develop -c cabal test hurl-workbench-core-test --test-show-details=direct
nix develop -c cabal test hurl-workbench-cli-test --test-show-details=direct
nix develop -c just sync-check schema-check
```

Expect passing tests, `release copies: PASS`, and `schema compatibility: PASS`. At the final coherent boundary run the required release checks, including distribution builds:

```bash
nix develop -c just check
git diff --check
```

Expect `all checks: PASS` and a zero exit from the diff check. Run Linux acceptance from macOS outside the development shell:

```bash
just linux-check
```

The existing read-only integration example should still pass with jobs 2. The existing writes suite should pass serially with opt-in and fail with exit 2 at jobs 2, before its service starts:

```bash
nix develop -c cabal run hurl-workbench -- --workspace examples/integration-service/hurl-workbench.dhall test suite writes --allow-mutating --jobs 1
nix develop -c cabal run hurl-workbench -- --workspace examples/integration-service/hurl-workbench.dhall test suite writes --allow-mutating --jobs 2
```

The new independent example, written during implementation, uses provider-generated runtime input. Within the acceptance driver's temporary workspace its command is:

```bash
hurl-workbench --workspace hurl-workbench.dhall test suite independent-writes --external-service --scenario-inputs scenario-inputs.json --allow-mutating --jobs 2 --report json --report-dir reports
```

The driver resolves the built executable before changing directories. Run it from the repository root after provider discovery:

```bash
bash scripts/check-scenario-isolation.sh
```

Require `independent writes: PASS`, `duplicate assignments refused: PASS`, and `provider cleanup: PASS` only after the corresponding assertions succeed. Record the actual provider invocation, service readiness check, database identity check, and cleanup evidence when milestone 2 establishes them. The script does not exist at plan creation.

Dependency discovery is mandatory before new library API assumptions or provider integration:

```bash
mori registry list
mori registry search hinagata
mori registry show shinzui/hinagata --full
mori registry docs shinzui/hinagata
mori registry search dhall
mori registry search aeson
mori registry search http-client
```

Use returned qualified project names for show/docs and read the located source files. Registry discovery initially failed because the inherited endpoint was stale; a command-local override from the current shell profile restored list/search/show/docs. Sources for Dhall expression traversal, Aeson object decoding, http-client origin parsing, async cancellation/publication, and the toolchain check-shell API were inspected through Mori-located checkouts. No dependency upgrade or pin change was needed; test Aeson uses the existing project bound.

The actual provider at `mori://shinzui/hinagata` commit `a0c1059743e5957e66e4b8cee9e485ad89471937` exposes `db acquire --json`, `db release LEASE_ID --json`, and `inspect LEASE_ID --json`. The driver creates its own SCRAM-authenticated cluster, acquires two detached caller-owned leases per execution mode, passes their application PG variables and a private PGPASSFILE only to its own services, checks `/health` after private `current_database()`/`current_user` assertions, and calls one suite invocation. Reproduce from the repository root after building workbench and the discovered provider:

```bash
hinagata_root="$(mori path mori://shinzui/hinagata)"
(cd "$hinagata_root" && nix develop -c cabal build hinagata)
export HINAGATA_EXECUTABLE="$(cd "$hinagata_root" && nix develop -c cabal list-bin hinagata)"
export hinagata_postgres_datadir="$hinagata_root/hinagata-postgres"
nix develop .#check -c bash -c 'export HURL_WORKBENCH_EXECUTABLE="$(cabal list-bin hurl-workbench)"; bash scripts/check-scenario-isolation.sh'
```

The early `--early` run proved the real two-lease boundary before summary variants. The final complete run passed:

```text
duplicate assignments refused: PASS
independent writes: PASS
provider cleanup (success): PASS
provider cleanup (failure): PASS
provider cleanup (cancellation): PASS
partial allocation refused before consumers: PASS
provider cleanup (allocation-failure): PASS
```

Success requires both POSTs to commit and reach a rendezvous before either responds, then each GET and a direct database query sees only its own marker. The failure run uses jobs 1 and fail-fast and proves the queued second POST never starts. Cancellation waits for both active POSTs, signals workbench, checks its shell-equivalent status 130 and a cancelled summary, then proves all recorded Hurl PIDs are gone while provider services remain alive. Only then does the driver stop services, release every acquired lease once, inspect Released, and verify clone absence through pg_database. The partial-allocation variant fails the second `db acquire --fixture absent --json` before any consumer starts and releases the first lease. Normal tests/local acceptance use explicit in-memory fixtures and do not substitute for this real database evidence.


## Validation and Acceptance


IR-5 AC-1 requires unchanged old manifests, including fully specified populated and empty suite records, to decode with SharedState. Explicit IndependentState must decode without making a bare declaration sufficient to run. Existing read-only execution remains valid.

AC-2 requires zero service, readiness, and Hurl execution starts for shared-state jobs > 1 containing a mutating recipe, mutating matrix case, or direct workflow. Test both opt-in values, external-service mode, mixed safety, and a single unsafe run. CLI capability and format hooks must also remain uncalled for this early refusal. Standalone parallel mutation matrices receive the same protection.

AC-3 requires the real two-lease concurrency test, unique fixture and endpoint assignments, separately resolved runtime bindings, observable overlap, and proof that each scenario sees only its own writes. Missing, duplicate, malformed, mismatched, or failed provisioning assignments must prevent execution. Valid identifier strings alone do not prove database isolation; the real provider integration is mandatory evidence.

AC-4 requires serial shared-state mutations to retain --allow-mutating, parallel shared-state read-only suites to succeed, and existing fail-fast, active-child cleanup, report isolation, exact Hurl exit selection, and declaration-order semantics to remain intact. Include zero-child refusal tests alongside actual process execution tests.

AC-5 requires parsed workbench summary JSON to identify isolation and logical scenarios on success, safely reportable refusal, setup failure, and cancellation, with sensitive sentinels absent. Invalid report destinations must remain untouched. Cancellation must propagate after child cleanup, and provider-owned resources must only be released by the provider. Hurl response artifacts are not claimed to be redacted.


## Idempotence and Recovery


Use unique private temporary directories, report roots, ports, and freshly acquired leases for every acceptance run. Keep provider services and credential files alive until all consumers stop. Wrap partial acquisition in provider cleanup so cancellation or a second allocation failure releases the first lease. Never retry POST automatically or reuse a mutated database to make a failed test pass.

Decode compatibility happens in memory and never rewrites user manifests. Report refusal must not remove an existing tree without the established explicit overwrite option, nor follow a symbolic link. Retry failed checks using new report roots after verifying owned children have stopped. Do not terminate unrelated local processes or change a developer's database configuration.

Mina successfully created `intention_01m76636k9enysm8fxs71dah6z`; do not create another intention when resuming. Commits made during implementation use Conventional Commits and include both `ExecPlan: docs/plans/9-declare-scenario-isolation-and-guard-parallel-mutations.md` and the linked `Intention:` trailer.


## Interfaces and Dependencies


The workspace field is `Suite.isolation :: IsolationPolicy`, with Haskell constructors SharedState and IndependentState and Dhall spelling `Schema.IsolationPolicy.SharedState` or `Schema.IsolationPolicy.IndependentState`. The runtime file is separate from Dhall and has a versioned JSON envelope. This is the implemented version-1 shape, using harmless example values:

```json
{
  "version": 1,
  "scenarios": [
    {
      "scenario": "writes/first",
      "fixtureId": "opaque-lease-a",
      "endpoint": "http://127.0.0.1:18181",
      "endpointParameter": "baseUrl",
      "bindings": [{"parameter": "marker", "value": "first"}],
      "secretEnvironment": [{"parameter": "token", "variable": "FIRST_TOKEN"}]
    },
    {
      "scenario": "writes/second",
      "fixtureId": "opaque-lease-b",
      "endpoint": "http://127.0.0.1:18182",
      "endpointParameter": "baseUrl",
      "bindings": [{"parameter": "marker", "value": "second"}],
      "secretEnvironment": [{"parameter": "token", "variable": "SECOND_TOKEN"}]
    }
  ]
}
```

Each entry requires all shown fields; empty binding lists are valid. Reject unknown envelope/entry fields and unsupported versions. Use list entries so duplicate parameter assignments can be diagnosed rather than lost through map conversion. Fixture IDs must be nonempty and contain no control characters; their text remains private even on duplicate errors. Plain values pass through mkHurlValueLiteral and secret environment references use declared Secret parameters. No connection string is required in this file: the provider passes database credentials directly to its own services.

Suite.Scenario should expose a redacted ScenarioInputs type, an abstract VerifiedScenarioInputs type, a decoder/file loader, and a verifier accepting the expanded scenario definitions. Only verification constructs the latter. SuiteRequest carries optional unverified inputs; successful preflight produces requests whose endpoint/binding assignments cannot change during execution. The core verifier is also available to caller-owned Haskell runners, so the CLI is not the sole protection. Tests may construct raw inputs to prove invalid values cannot become verified execution requests.

Keep the batch runner's worker pool and observer interface. Independent execution uses no ResolvedService; the caller is responsible for provisioning, readiness, truthful identities, lifetime, and release. The core's existing Dhall, Aeson, containers, http-client, async, STM, typed-process, and POSIX facilities cover the intended implementation. Confirm APIs through Mori before use. The provider-specific adapter belongs to the acceptance driver, not production workbench code. Pools of mutated fixtures, automatic PostgreSQL provisioning, distributed locking, per-scenario managed service orchestration, and inference of HTTP mutation safety are outside this plan.
