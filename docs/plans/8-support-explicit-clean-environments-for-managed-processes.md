---
id: 8
slug: support-explicit-clean-environments-for-managed-processes
title: "Support explicit clean environments for managed processes"
kind: exec-plan
intention: intention_01m76ccvkkewgr1s6jdtbzmzna
created_at: 2026-11-11T20:36:28Z
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-11-11T20:36:28Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-11-11T22:41:59Z
      mode: "implement"
      note: "Implement compatible command policies and process environment isolation"
---

# Support explicit clean environments for managed processes

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture


Managed services and readiness commands will be able to start with only deliberately selected environment variables. A developer can keep ordinary Rei and Mori configuration in their shell while a fixture receives only its test database connection and explicit workspace bindings. Existing manifests continue inheriting the environment unless they opt in.

This implements [IR-6](../improvement-requests/support-explicit-clean-environments-for-managed-processes.md). Demonstrate it with child processes that record variable names, assert selected values privately, and prove that REI_PG_CONNECTION_STRING, REI_CONFIG, and MORI_API_URL are absent unless selected. A real caller-owned PostgreSQL lease must also survive the handoff and be released after managed consumers stop.


## Progress


- [x] (2026-11-11) Milestone 1: Old manifests decode unchanged; clean policies decode and reject invalid or duplicate names. Workspace tests and all four CLI compatibility fixtures pass; schema copies agree.
- [x] (2026-11-11) Milestone 2: Service and readiness share one selector and parent snapshot, reject missing names before startup, and preserve cleanup and redaction. All 78 core and 33 CLI tests pass, including private-parent selected empty values and overrides, native exact-environment, mixed old/new decoding-to-exec, missing-name startup markers, clean cancellation/readiness cleanup, failure redaction, and external-service bypass.
- [ ] Milestone 3: Public clean example, summary sentinel checks, consumer driver, documentation, and release copies are implemented. macOS examples and schema/release checks pass. Real Hinagata lease access and provider release evidence remain blocked by registry access; Linux validation is running in an Apple container.

Implementation handoff (2026-11-11): Mina created intention_01m76ccvkkewgr1s6jdtbzmzna successfully; it is authoritative in frontmatter. Required local commands already passed: `nix develop -c cabal build all`, `nix develop -c cabal test all --test-show-details=direct` (78 core, 33 CLI), `nix develop -c just sync-check schema-check`, `nix develop -c just examples`, `nix fmt -- --ci`, `git diff --check`, and `nix develop -c bash scripts/check-sdist.sh` (unpacked source distributions build successfully). `scripts/check-clean-environment-lease-simulation.sh` exercised all three driver paths and consumer shutdown; it is explicitly simulation evidence, not AC-5. `bash scripts/check-clean-environment-lease.sh` with incomplete PG inputs exited 2 before launch. `just linux-check` is still building its development environment. Mori discovery still fails with the same refused local PostgreSQL socket (FRIC-1). No provider wrapper syntax or real lease release is inferred.


## Surprises & Discoveries


2026-11-11: A Haskell child on macOS adds `__CF_USER_TEXT_ENCODING` after exec, so language-level environment inspection cannot establish the exact launch boundary. Native `test/fixtures/processes/environment.c` inspects envp and proves empty and explicit-only environments. The public Haskell fixture allows that known runtime addition while verifying that PORT is its only selected input.

2026-11-11: Existing parallel tests mutate libc environ while unrelated process launches use it, intermittently producing `posix_spawnp: failed (Bad address)`. Core tests now run sequentially, and helper compilation uses an explicit environment snapshot; internal batch-concurrency tests still exercise their own workers. See FRIC-2.

2026-11-11: Cancellation of the public driver sends SIGINT to the workbench session group, matching terminal interruption. The managed service is in its separate owned group and must be stopped by workbench cleanup before the driver returns. Simulated success, readiness failure, and cancellation all pass.


## Decision Log


2026-11-11: Keep inherited behavior as the schema-version-1 default. Add an explicit policy on the common command record and normalize omitted policy fields in old evaluated manifests before typed decoding. Completion defaults alone cannot preserve fully specified old command records.

2026-11-11: A clean allowlist contains required inherited names. Every selected name must exist in the captured parent environment, including when an explicit binding overrides its final value. Users who only want a declared binding must omit that name from the allowlist. Empty values count as present; there is no optional-name syntax in this change.

2026-11-11: Resolve both service and command-readiness environments from one snapshot before starting the service. A missing readiness variable must not start a service that immediately needs cleanup. Keep HTTP readiness and the separate Hurl environment filtering contract unchanged.

2026-11-11: Cover the command phases present in the checkout, currently service startup and command readiness. Share the policy resolver with future lifecycle setup, teardown, and executable checks; do not implement those separate feature requests here. If those extensions land before this plan completes, their common-command paths and joint tests become part of this plan's existing consistency criterion.


## Outcomes & Retrospective


The command policy feature and local adoption path are implemented. ADRs 1 and 6 record version-1 normalization and shared environment ownership. Common-command consumers were inspected again: only service startup and command readiness exist; no setup/teardown or executable-check phases were added.

FRIC-1 remains logged because the real provider interface and release evidence cannot yet be obtained. FRIC-2 is resolved by serializing core test cases around existing global environment mutations. Milestone 3 and AC-5 remain open until a real Hinagata-owned lease run records the supported outer invocation and observed release after consumers stop.


## Context and Orientation


A workspace is a Dhall configuration file decoded into Haskell records and then validated before execution. A managed service is a child process owned for the duration of a suite. A readiness command is a repeatedly executed child whose successful exit permits the suite to run. The ambient environment means the name/value pairs inherited by workbench from its parent. An allowlist is the explicit set of names permitted to cross into a clean child environment. A lease is a caller-owned temporary database allocation that must remain alive until all consumers stop.

`schema/CommandSpec.dhall` defines executable, arguments, workingDirectory, and environment. The last field holds bindings from workspace parameter names to child variable names, not literal secrets. `schema/package.dhall` exports these types. Both `hurl-workbench-core/schema/` and `hurl-workbench-cli/schema/` contain release copies.

`hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs` defines `CommandSpec` and its generic Dhall decoder. `hurl-workbench-core/src/HurlWorkbench/Workspace/Decode.hs` evaluates a manifest, checks schemaVersion, then checks and extracts the typed workspace. `hurl-workbench-core/src/HurlWorkbench/Workspace/Validate.hs` validates both service and readiness commands in `commandIssues`, including names, duplicate explicit targets, and working directories. Static validation must not read runtime environment values.

`hurl-workbench-core/src/HurlWorkbench/Service/Resolve.hs` resolves declared parameter bindings into `ResolvedCommand.environment`, whose `Show` instance is redacted. `hurl-workbench-core/src/HurlWorkbench/Service/Run.hs` reads `getEnvironment` once in `withService`; `serviceProcessConfig` and `readinessProcessConfig` currently apply `overlayEnvironment`. Its `prepareReadiness` currently ignores the ambient argument. `hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs` prepares the suite; `hurl-workbench-core/src/HurlWorkbench/Suite/Run.hs` executes it and writes summaries without environment values. `hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs` has a separate Hurl-specific environment boundary.

Tests live in `hurl-workbench-core/test/HurlWorkbench/Workspace/WorkspaceTest.hs`, `hurl-workbench-core/test/HurlWorkbench/Service/RunTest.hs`, and `hurl-workbench-core/test/HurlWorkbench/Suite/RunTest.hs`; public command tests live in `hurl-workbench-cli/test/Main.hs`. Service tests already exercise Python fixtures, readiness deadlines, cancellation, and process termination. `Justfile` owns schema, release-copy, example, and distribution checks.

Relevant decisions consulted are [ADR 1](../adr/1-versioned-dhall-workspace-schema.md), which requires version-1 defaults and compatibility fixtures; [ADR 2](../adr/2-validated-workspace-boundary.md), which requires static validation before execution; [ADR 4](../adr/4-secure-hurl-process-boundary.md), which preserves secret channels and Hurl filtering; [ADR 6](../adr/6-managed-service-process-group-lifecycle.md), which owns service groups and cleanup; [ADR 7](../adr/7-suite-preflight-safety-and-report-isolation.md), which requires preflight and redacted summaries; and [ADR 8](../adr/8-self-contained-multi-package-release-builds.md), which requires synchronized package resources. Update ADRs 1 and 6 when implementing the compatibility and policy decisions, preserving the other guarantees.

The originating consumer is `mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract`. PostgreSQL lease ownership remains with `mori://shinzui/hinagata`. Neither is a new Haskell runtime dependency. No parent MasterPlan is assigned to this plan.


## Plan of Work


### Milestone 1: Decode and validate a compatible policy


Add `schema/EnvironmentPolicy.dhall` as the union `< Inherit | Clean : List Text >` and export it from `schema/package.dhall`. Add `environmentPolicy : EnvironmentPolicy` to CommandSpec with default `EnvironmentPolicy.Inherit`. Add the corresponding Haskell `EnvironmentPolicy` type (`Inherit` and `Clean [Text]`) and field in Workspace.Types. Existing environment bindings retain their meaning and precedence.

In Workspace.Decode, add a narrowly scoped compatibility normalization after evaluation and schema-version checking: for service command records and command-readiness records only, insert Inherit when environmentPolicy is absent. Type-check and extract the resulting expression. Preserve explicitly supplied policies and reject malformed types; never catch arbitrary decode failures and silently fall back to inheritance. Cover empty service lists, HTTP readiness, and mixed old/new command records, including Dhall union type annotations that must remain consistent after normalization. Consult Mori-located Dhall source before using new decoding APIs. Do not change schemaVersion or rewrite old manifests to hide incompatibility.

Extend commandIssues to validate clean names with the existing environment-name predicate, rejecting empty names, equals signs, NUL, whitespace, invalid initial characters, and duplicates in deterministic order with command-specific locations. A name shared between allowlist and explicit bindings is valid. Runtime absence is not a static validation issue.

Add frozen old-shape service and readiness fixtures under `hurl-workbench-core/test/fixtures/workspaces/`, in addition to preserving minimal and minimal-explicit fixtures unchanged. Add tests for omitted/default/explicit Inherit equivalence, clean-empty decoding, both readiness forms, malformed policy types, invalid names, and duplicate names. Update Haskell constructor call sites and synchronize all three schema trees. Milestone acceptance is passing workspace tests and both compatibility CLI checks, with a regression fixture that would fail if the new field were simply made mandatory.


### Milestone 2: Enforce the policy at the process boundary


Carry policy through ResolvedCommand. Factor environment selection into a shared pure function in a new `hurl-workbench-core/src/HurlWorkbench/Service/Environment.hs` module, registering it in `hurl-workbench-core/hurl-workbench-core.cabal`. Given policy, ambient pairs, and resolved explicit bindings, it either returns missing names or the final pairs. Inherit preserves the current left-biased explicit-over-ambient map union. Clean first checks that every selected name exists, takes only selected pairs, and then overlays explicit bindings. Clean [] with no bindings produces an empty list. Never add PATH, HOME, locale, or platform defaults.

In withService, snapshot once and prepare final environments for both commands before startProcess. Prepared readiness must retain its final environment across retries; process-config constructors consume those final pairs without another ambient overlay. Preserve existing process groups, deadlines, and exception cleanup. Missing names produce a typed ServiceError naming the service/command phase and missing variable names, never values. Keep error classification compatible with existing service failures and suite exit 4. Preserve the external-service bypass: a service not being launched must not require its clean inherited names.

First exercise one old manifest and one clean manifest through decode, validation, resolution, and real child execution. This checks the schema-to-process connection before expanding the test matrix. Resolve fixture executables to absolute paths in the test parent so tests of an absent PATH do not depend on executable search behavior. Avoid a shell or interpreter that adds environment variables when proving exact environment contents; use a small native helper if necessary. Child assertions should emit only names and success/failure, not secret values.

Extend Service.RunTest with inheritance compatibility; clean-empty; selected/unselected sentinels; explicit override precedence; present-empty values; independently different policies on service and readiness; no implicit PATH/HOME; and missing names in either phase. A startup marker must remain absent when either required-name check fails. Use private per-test environments or a subprocess wrapper rather than racing process-global setEnv across parallel tests. Exercise readiness retries and failure/cancellation cleanup under clean mode. Extend Suite.RunTest to assert missing-environment failures prevent Hurl execution and that external-service mode does not inspect unused managed-command policies.

Do not expose new resolved values in Show, diagnostics, list output, summaries, or exception text. Assert distinct secret sentinels are absent from workbench-owned metadata for success, spawn failure, readiness failure, and missing-name failure. Existing inherited child stdout and Hurl response artifacts are not sanitized by this feature; document that established boundary instead of promising suppression of secrets deliberately echoed by a child. Milestone acceptance is the core and CLI suites passing with the new process-level assertions and all existing lifecycle tests intact.


### Milestone 3: Demonstrate adoption and the database handoff


Add a clean-policy suite to `examples/integration-service/hurl-workbench.dhall` while retaining a default-inheritance example. Demonstrate a service binding overriding a selected non-secret variable and a readiness command with its own selection. Extend `hurl-workbench-cli/test/Main.hs` or a focused fixture to run the public command with REI_PG_CONNECTION_STRING, REI_CONFIG, and MORI_API_URL set to harmless sentinel strings, prove their exclusion, and inspect summary.json for secret absence. Add the new example to the existing Justfile example gate and synchronize `hurl-workbench-cli/examples/`.

Add `scripts/check-clean-environment-lease.sh` as an opt-in integration driver for an already active caller-owned PostgreSQL lease. Its contract is to require PGHOST, PGPORT, PGUSER, and PGDATABASE, admit PGPASSFILE only when the caller supplies it, resolve workbench/fixture/psql executable paths before launching clean children, and keep password bytes out of argv and artifacts. Use a unique temporary workspace and an application fixture that connects using these values and verifies current_database() and current_user without logging credentials. The readiness command must verify the same lease. Reuse the existing service fixture patterns; the workbench must not acquire or release the lease itself.

The driver must exercise success, an intentional callback/readiness failure, and cancellation. Prove consumer PIDs stop before returning control to the lease owner, then prove the owner releases the allocation. A fake environment handoff test is useful for normal CI but does not satisfy the real-lease criterion. Run the driver inside the supported Hinagata lease callback/command wrapper after discovering its actual interface with Mori; record the exact runnable invocation and observed release evidence in this plan and `docs/guides/integration-testing.md`. Registry unavailability must leave this acceptance item open rather than substitute guessed Hinagata syntax or claim a simulated lease is real evidence.

Update `docs/guides/integration-testing.md`, `docs/security.md`, and the example README to explain policy syntax, missing-name behavior, explicit-binding precedence, independent command policies, explicit PATH/HOME selection, absolute executable paths for deterministic startup, and the protected PGPASSFILE handoff. Synchronize distributed README/example copies if changed. Update root/package changelogs together. Inspect common-command consumers again before completion: if setup/teardown or executable checks now exist, wire them through the shared resolver and extend sentinel and cleanup integration tests to those phases. Record this conditional scope explicitly in the acceptance evidence.

Run focused acceptance, release-copy/schema/example checks, and the ordinary full test suites. Validate macOS and Linux behavior; on macOS prefer the existing Apple-container `just linux-check` path. Finish with the ADR distillation pass and friction triage prescribed by the exec-plan skill. Milestone 3 remains incomplete until real lease cleanup evidence exists.


## Concrete Steps


Run from the repository root. These commands are planned implementation checks, not checks already performed during planning:

```bash
nix develop -c cabal test hurl-workbench-core-test --test-show-details=direct
nix develop -c cabal test hurl-workbench-cli-test --test-show-details=direct
nix develop -c just sync-check schema-check
nix develop -c cabal build all
nix develop -c just examples
nix fmt -- --ci
git diff --check
```

Expect all tests to pass, `release copies: PASS`, `schema compatibility: PASS`, and `examples: PASS`. Formatting and diff checks must exit zero. The existing example runner needs its loopback port 18080 free. Run the real lease driver from within the provider's supported lease scope:

```bash
bash scripts/check-clean-environment-lease.sh
```

The driver must refuse missing PG variables before starting children and print only `clean lease success: PASS`, `clean lease failure cleanup: PASS`, and `clean lease cancellation cleanup: PASS` after its checks succeed. Provider release evidence is recorded by the outer lease owner, not inferred from these three lines. Discover that outer invocation before claiming this check complete:

```bash
mori registry list
mori registry search hinagata
mori registry show shinzui/hinagata --full
mori registry docs shinzui/hinagata
```

For new library API work, similarly search `dhall` and `typed-process`, then show/docs the qualified projects returned and read their sources. Never search the Nix store. No dependency version changes are planned; if one becomes necessary, verify the authoritative package registry and upstream release tags before selecting bounds.

On macOS, Linux acceptance is run outside the development shell:

```bash
just linux-check
```

Record actual commands and concise outcomes in Progress as milestones pass. Infrastructure failures are not passing results.


## Validation and Acceptance


IR-6 AC-1 is satisfied when unchanged old completion and fully specified manifests decode to inherited behavior and a newly selected Clean policy changes real child observations. AC-2 requires exact selected-plus-explicit names at the process boundary, explicit override precedence, no implicit PATH/HOME, exclusion of the three Rei/Mori sentinels, and startup-marker absence for missing required service or readiness names.

AC-3 requires independent policies to work consistently in service and readiness execution using the same resolver. If lifecycle or executable-check extensions exist by completion, exercise the same sentinels in each and in a joint suite; otherwise state their absence and retain the reusable contract without adding new phases.

AC-4 requires deterministic static rejection of malformed/duplicate names and no secret values in workbench-owned reports and diagnostics on successful and failed runs. Tests must assert a secret really reached an explicitly bound child as well as remaining absent from metadata; mere absence everywhere would not prove the handoff works.

AC-5 requires a real Hinagata-owned lease, actual database access from clean service and readiness children, and observed consumer shutdown before lease release on success, failure, and cancellation. PGPASSFILE is explicitly selected when needed, remains a protected file owned by the caller, and its contents never enter reports. A missing provider or broken registry leaves this criterion open. Existing cleanup, Hurl filtering, external-service behavior, and release-copy checks must still pass.


## Idempotence and Recovery


All tests use disposable workspaces, unique report roots, and per-run marker paths. Restore parent environment changes with a bracket if unavoidable. Retry failed tests with fresh temporary roots after confirming fixture processes have stopped; never kill unrelated processes or reuse a real application database. Cancellation must complete service cleanup before the provider releases its lease. Preserve protected password files until their lease owner finishes cleanup.

Compatibility normalization is in memory and never rewrites user manifests. Do not delete fixtures or change old expected behavior to obtain a green test. Keep dependency locks unchanged unless separately justified. Planning created this document only; retry intention creation once the requested parent is configured, and attach the returned ID without inventing one or creating duplicate intentions after a successful response.


## Interfaces and Dependencies


The public policy contract is `EnvironmentPolicy = Inherit | Clean [Text]` on CommandSpec, represented in Dhall as `< Inherit | Clean : List Text >`. For example, a command completion record can contain:

```dhall
environmentPolicy = Schema.EnvironmentPolicy.Clean [ "PGHOST", "PGPORT", "PGUSER", "PGDATABASE" ]
```

Existing `environment : List EnvironmentBinding` remains the explicit-binding channel. ResolvedCommand carries the selected policy while keeping resolved values redacted. The shared environment selector takes policy, an ambient snapshot, and explicit bindings and returns either missing names or final pairs; its callers own contextual ServiceError rendering. New consumers must use that selector rather than reimplement overlays.

Reuse existing Dhall, containers, typed-process, and POSIX process APIs, with source lookup before new API assumptions. Add no shell-string command form, automatic ambient defaults, Hurl-wide policy switch, database provisioning layer, or inferred application-variable list. The external provider contract is an active lease, explicitly passed PG names, optional protected password-file path, and caller-owned release after workbench returns. The real provider invocation is the one outstanding external interface discovery; its acceptance cannot be waived by completion of local unit tests.
