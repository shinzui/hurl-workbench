---
id: 10
slug: support-ordered-multi-service-suite-lifecycles
title: "Support ordered multi-service suite lifecycles"
kind: exec-plan
created_at: 2026-11-11T20:51:21Z
intention: "intention_01m76638egeeqa9pyrp8p3f3q5"
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
---

# Support ordered multi-service suite lifecycles


This ExecPlan is a living document. Keep Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective current during implementation. Record implementation friction using `agents/skills/exec-plan/FRICTION.md`, and distill durable decisions into `docs/adr/` before completion.


## Purpose / Big Picture


A developer will be able to run an integration suite that prepares its fixture, starts several services in readiness order, stops or restarts a named worker between HTTP scenarios, and reliably shuts everything down before fixture release. The observable proof is a three-service command/read scenario: submit one mutation, poll its read result, restart a worker at an explicit boundary, and inspect the ordered summary and cleanup event log.

This implements [IR-1](../improvement-requests/support-several-managed-services-per-suite-with-ordered-readiness-and-setup-commands.md), including its 2026-10-11 amendment and AC-1 through AC-7. Workbench owns child processes; a caller still owns any disposable database lease, meaning the temporary allocation and its eventual release.


## Progress


- [ ] Milestone 1: Old manifests remain compatible and multi-service suites are fully validated and prepared before execution.
- [ ] Milestone 2: Ordered startup, bounded setup/teardown, and reverse process-group cleanup pass success, failure, and cancellation tests.
- [ ] Milestone 3: Named lifecycle steps form barriers between parallel Hurl batches and produce ordered, redacted results.
- [ ] Milestone 4: Public CLI examples and real leased-fixture command/read acceptance prove ownership, safety, and release ordering.

Planning handoff: no implementation is claimed. Intention creation succeeded through `mina ci --json`. Mori registry discovery failed on 2026-11-11 because the configured local PostgreSQL socket refused connections. Re-run dependency and consumer discovery before implementing new dependency API calls or the real adoption driver; do not substitute guessed provider commands for acceptance evidence.


## Surprises & Discoveries


## Decision Log


2026-11-11: Keep schema version 1 and preserve `Suite.service` as single-service sugar. Reject simultaneous nonempty `services` and `service`, and normalize legacy evaluated records and union annotations before typed extraction. Completion defaults alone do not preserve explicitly typed old manifests.

2026-11-11: Execute consecutive Hurl runs as bounded batches separated by lifecycle barriers. A barrier waits for all earlier cases, executes alone, and finishes before later cases start. The same scheduler boundary will support [the IR-4 plan](13-run-executable-checks-as-ordered-suite-barriers.md).

2026-11-11: Setup runs in declaration order before services; teardown runs in declaration order after reverse service cleanup, even after partial setup failure. Commands have finite phase budgets. Cleanup records secondary failures without replacing the original failure record; service lifecycle failures continue selecting exit 4.

2026-11-11: External-service mode bypasses setup, managed startup/shutdown, and teardown. Refuse suites with lifecycle steps in that mode, since silently skipping a requested restart would change the test. State this behavior in CLI help.


## Outcomes & Retrospective


## Context and Orientation


A workspace is the Dhall manifest plus fragment files beneath its directory. `schema/Suite.dhall` currently has one optional `service`, a list of runs, and fail-fast configuration. `schema/RunReference.dhall` permits workflows, recipes, and matrices. `hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs` mirrors these declarations; `hurl-workbench-core/src/HurlWorkbench/Workspace/Decode.hs` performs version checking and exact typed decoding. `hurl-workbench-core/src/HurlWorkbench/Workspace/Validate.hs` validates references and contained working directories.

`hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs` flattens every run into `PreparedSuite.cases`, resolves one `managedService`, and prepares report directories. `hurl-workbench-core/src/HurlWorkbench/Suite/Run.hs` runs one `runBatchObserved` callback inside `withService` and writes an atomic summary. This flattening loses lifecycle boundaries, so it must become an ordered execution sequence while retaining stable case identities and partial results.

`hurl-workbench-core/src/HurlWorkbench/Service/Resolve.hs` resolves explicit environment bindings and readiness URLs from suite-level values. `hurl-workbench-core/src/HurlWorkbench/Service/Run.hs` owns one POSIX process group, the service leader and its descendants signalled together, through `withService`. Its callback races leader exit. It is insufficient to nest this interface for restarts: an intentional stop would look like unexpected death, and cleanup can currently replace the earlier error. `hurl-workbench-core/src/HurlWorkbench/Run/Batch.hs` supplies bounded workers and observed case completion.

Extend the existing tests in `hurl-workbench-core/test/HurlWorkbench/Workspace/WorkspaceTest.hs`, `hurl-workbench-core/test/HurlWorkbench/Service/RunTest.hs`, `hurl-workbench-core/test/HurlWorkbench/Suite/RunTest.hs`, and `hurl-workbench-cli/test/Main.hs`. The CLI fixture implementation is `hurl-workbench-cli/test/fixture-server/FixtureServer.hs`, with its executable entry point in `hurl-workbench-cli/test/fixture-server/Main.hs`.

Relevant ADRs are [ADR 1](../adr/1-versioned-dhall-workspace-schema.md), requiring versioned schemas and unchanged compatibility fixtures; [ADR 2](../adr/2-validated-workspace-boundary.md), requiring validated typed references; [ADR 4](../adr/4-secure-hurl-process-boundary.md), preserving private files and secret channels; [ADR 5](../adr/5-bounded-isolated-batch-execution.md), preserving bounded scheduling and declaration-order results; [ADR 6](../adr/6-managed-service-process-group-lifecycle.md), requiring group ownership and cleanup before exception propagation; [ADR 7](../adr/7-suite-preflight-safety-and-report-isolation.md), requiring whole-suite preflight and summaries without values; and [ADR 8](../adr/8-self-contained-multi-package-release-builds.md), requiring synchronized schema/example package copies. Extend the one-service decisions in ADRs 6 and 7 without weakening their ownership and confidentiality guarantees.

[Plan 8](8-support-explicit-clean-environments-for-managed-processes.md) specifies a shared environment selector for IR-6. Reuse it for every command introduced here when available, including readiness, setup, teardown, and later restarts. IR-5 is [the scenario-isolation request](../improvement-requests/declare-scenario-isolation-and-guard-parallel-mutations.md); its independently tracked implementation must still reject shared-state parallel mutations. Barriers do not prove fixture isolation. The real consumer requirement originates in `mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract` and `mori://tan/notification-hub`.


## Plan of Work


### Milestone 1: Prepare a compatible ordered suite


Add `services : List Text`, `setup : List CommandSpec.Type`, `teardown : List CommandSpec.Type`, and positive `commandTimeoutSeconds` (default 60) and `cleanupTimeoutSeconds` (default 30) fields to `schema/Suite.dhall`. New list defaults are empty. Retain `service`; normalize it to a singleton when `services` is empty, and reject duplicates and ambiguous declarations. Add `schema/ServiceStep.dhall` as `< Stop : Text | Start : Text | Restart : Text >`, export it from `schema/package.dhall`, and extend `RunReference` with `Service : ServiceStep`. Add corresponding Haskell constructors with explicit Dhall constructor mapping.

Extend `Workspace.Decode` with a narrow schema-version-1 compatibility conversion. Preserve all explicitly supplied values, add only missing supported fields, and widen old run unions consistently, including empty-list type annotations. Re-typecheck the converted expression before extraction. Coordinate with Plan 8's command normalization and later IR-2/IR-4 union changes; keep one conversion path. First prove one frozen old service manifest and one new multi-service manifest decode and prepare successfully before expanding tests. Never accept an arbitrary malformed record by dropping fields or catching all decoder errors.

Validate all service references, setup/teardown command bindings and directories, positive finite budgets, and lifecycle transitions before any managed process starts. Simulate named service state from the initially started list: Stop requires running, Start requires stopped, Restart requires running, and every name must belong to the suite. Checks do not change this state. A failed runtime transition aborts the sequence because later steps no longer have valid prerequisites.

Replace the flat prepared shape with an ordered list of prepared steps: nonempty Hurl batches and lifecycle operations. Keep global case indices and report stems stable across batches. Preflight all batches, all commands, safety gates, environment policies, and all artifact paths before setup. Snapshot ambient environment once for the invocation and freeze final command environments, so restarts do not reread mutable ambient state. Services and phase commands use suite-level bindings, never recipe or matrix layers. Extend existing workspace and suite tests; the milestone passes when old manifests still decode identically and malformed later steps prevent setup/start markers.


### Milestone 2: Own the entire process lifetime


Factor process-group acquisition and bounded termination from `Service.Run` into a new internal `hurl-workbench-core/src/HurlWorkbench/Process/Run.hs`. Maintain `withService` as a compatibility wrapper. Register the new module in `hurl-workbench-core/hurl-workbench-core.cabal`. Add `hurl-workbench-core/src/HurlWorkbench/Service/Group.hs` to hold service states and successful acquisition order. Register a group for cleanup immediately after spawning, before readiness; a service that never becomes ready still needs cleanup.

Run setup commands sequentially with expected exit zero and the suite command budget. They use executable plus argv, closed stdin, resolved environment, a dedicated process group, and private captured diagnostics. On setup failure, start no services, skip remaining setup, and attempt all teardown commands. Start services in declaration order, waiting for each readiness result before acquiring the next. Monitor every running leader throughout subsequent startup, Hurl execution, and lifecycle operations. Any unexpected exit cancels active execution and proceeds to cleanup.

When a report root is selected, allocate phase output under private, collision-checked `phases/setup/INDEX/` and `phases/teardown/INDEX/` suite subdirectories and reference only those relative paths in summaries. Otherwise capture into a bracketed owner-only temporary directory, remove it after finalization, and report typed phase outcomes without replaying raw command output. Do not make setup/teardown output a route around the existing sensitive-artifact rules.

On every exit path, cancel and reap active Hurl or phase-command children, then stop active service groups in reverse acquisition order, then attempt teardown in declaration order. Restarted services acquire a new position at the end of the ownership stack. Clean the group whose readiness failed before earlier acquired groups. Descendants must be terminated even when the leader has already exited; leader exit alone is not proof of group cleanup. Use TERM, a bounded grace period, KILL, and reaping. Bound each service by its configured shutdown timeout and bound teardown collectively by `cleanupTimeoutSeconds`; mark remaining teardown entries skipped if that budget expires. Mask asynchronous interruption only around ownership transitions and bounded finalization, never with an uninterruptible wait.

Retain a primary failure plus ordered cleanup diagnostics. Setup/start/readiness/unexpected-death/lifecycle/teardown failures select suite exit 4, including cleanup-only failure, while an earlier Hurl failure remains recorded as the primary cause when cleanup also fails. On interruption, attempt the summary within bounded finalization and then propagate cancellation after cleanup. Extend `Service.RunTest.hs` and `Suite.RunTest.hs` under their existing full paths to cover failures at each acquisition position, cleanup errors, hanging descendants, and cancellation. Acceptance requires zero surviving owned children and exact phase order, not just a passing return code.


### Milestone 3: Execute lifecycle barriers and retain results


In `Suite.Run`, execute each prepared Hurl batch through `runBatchObserved`, drain it, and then execute the next lifecycle step. Preserve whole-suite fail-fast: when enabled, an unsuccessful batch or step prevents later execution and records explicit skips. With keep-going, ordinary Hurl failures permit later steps, but a failed lifecycle operation or dead prerequisite always aborts later execution. Record partial active-batch outcomes before cancellation and keep original declaration order across batches.

Before intentional Stop or Restart, atomically mark the service as stopping and retire its current monitor generation. The monitor must still recognize an exit that happened before this state transition as unexpected. Stop terminates and reaps the group; Start creates a new group and rechecks readiness; Restart completes both. A monitor event for an old generation must not cancel a replacement process. An already running Start or stopped Stop is a preflight error under milestone 1's transition simulation.

Extend `SuiteResult` with named lifecycle and phase outcomes and separate cleanup diagnostics. Keep existing `cases` and aggregate `service` summary fields for old clients; add ordered `steps` and named `services` details. Include action, logical name, status, duration, and relative artifact references for start, readiness, stop, restart, and cleanup. Never serialize commands, resolved argv, environments, paths to caller fixtures, or captured output. Update `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Suite.hs` to display named outcomes without inventing Hurl statuses for lifecycle work.

Acceptance records begin/end events around two read-only Hurl batches at jobs=2 and a restart: neither batch overlaps the barrier, readiness is repeated, and the intentional stop does not produce exit 4. Add a service-death test during an active parallel batch and retain completed cases while active children are cancelled. Keep IR-4's eventual Check barrier on this same prepared-step/result boundary.


### Milestone 4: Prove the public command/read scenario


Extend `hurl-workbench-cli/test/fixture-server/FixtureServer.hs` and `Main.hs` with deterministic fixture roles and event recording, and add `examples/multi-service/hurl-workbench.dhall`, Hurl fragments, and a README. The roles are an API accepting a command, a stub provider, and a projection owner (the worker that makes accepted state visible to reads). Record exactly one mutation request, then bounded GET polling of owner-backed visibility. Never use mutation retries as readiness polling. Include worker restart and observable pre/post state. Use jobs=1 for the mutating shared-fixture scenario and jobs=2 for the separate read-only barrier proof.

Add `scripts/check-multi-service-lease.sh` as an opt-in driver accepting an absolute consumer workspace through `HURL_WORKBENCH_CONSUMER_WORKSPACE` and a suite name through `HURL_WORKBENCH_CONSUMER_SUITE`. It runs inside an already active caller lease, uses runtime bindings/private environment channels supplied by that caller, and invokes the built CLI in success, readiness-failure, unexpected-exit, and cancellation variants. Its consumer manifest must start the actual application API/stub/projection owner and expose private event/PID evidence to the harness. The driver neither acquires nor releases a database. Caller-side evidence must show release happens only after all consumers exit.

Discover the actual supported provider and consumer entry points through Mori before wiring the real run. Use `mori://shinzui/hinagata` for lease ownership and the exact Rei masterplan URI above for the production consumer. Record the verified invocation and evidence in this plan and the example README. Local fixture roles validate orchestration but do not satisfy AC-7 alone; leave this milestone open until a real API command is observed through its actual projection owner on an externally leased fixture. Joint acceptance must also exercise the IR-5 isolation guard and IR-6 environment policy once implemented.

Update `docs/reference/workspace.md`, `docs/reference/cli.md`, `docs/guides/integration-testing.md`, `docs/security.md`, and relevant ADRs. Copy canonical schemas into both package schema directories and examples into `hurl-workbench-cli/examples/`; mirror any README/CHANGELOG edits according to `Justfile`. Run the release checks and supported-platform lifecycle tests.


## Concrete Steps


Run from the repository root. After each milestone run the relevant core tests; add the CLI tests once the public surface exists:

```bash
nix develop -c cabal test hurl-workbench-core-test --test-show-details=direct
nix develop -c cabal test hurl-workbench-cli-test --test-show-details=direct
nix develop -c just sync-check schema-check
nix develop -c just examples
```

The tests must pass; synchronization and schema checks print `release copies: PASS` and `schema compatibility: PASS`. The existing examples need loopback port 18080 available. Add the new fixture example to `just examples` so the same command covers its actual process orchestration. Before final acceptance run:

```bash
nix develop -c just check
just linux-check
```

Run the Linux command from macOS outside the Nix shell using Apple containers, falling back to a remote Linux builder only when local containers cannot satisfy the requirements. In the verified caller lease wrapper, after exporting the consumer workspace/suite and required runtime bindings, run:

```bash
bash scripts/check-multi-service-lease.sh
```

Expect one accepted mutation, successful bounded read observation, reverse shutdown, and caller release after the last consumer exit. Do not mark the real-lease check passed merely because a fake service example passes.


## Validation and Acceptance


AC-1 is a three-service fixture log proving readiness-before-next-start. AC-2 is setup-before-start and teardown-after-stop on success, setup/readiness/Hurl/check failure, and cancellation; repeat the check-failure variant once IR-4 exists. AC-3 is Stop/Start/Restart between Hurl runs with named outcomes and changed observed state. AC-4 is unexpected death of any of several services cancelling active Hurl groups, returning exit 4, and preserving completed results.

AC-5 fails the second and third service, fails cleanup after a primary failure, and interrupts a live suite. Assert reverse acquisition cleanup, bounded duration, retained primary cause, secondary diagnostics, and no remaining process groups. AC-6 proves jobs=2 barriers and monitor-generation correctness with intentional stops. AC-7 requires the actual command/read consumer and leased fixture described above, including single mutation submission and owner-backed polling. Use secret sentinels to verify summaries and ordinary diagnostics contain no resolved inputs; private command output remains sensitive.

Compatibility requires unchanged single-service and fully specified old manifests, old summary fields, external-service behavior as documented, and IR-5/IR-6 integration. Whole-suite preflight must reject a malformed late command or lifecycle reference before setup starts.


## Idempotence and Recovery


Fixtures use unique temporary workspaces, ports, marker files, and report roots. Teardown commands must tolerate partial setup and absent resources; document that requirement for users. Do not retry setup, lifecycle steps, or mutations automatically. On failure, retain private reports, confirm all owned groups have stopped, and retry with a fresh fixture. Existing report roots require explicit overwrite, scoped to the selected suite subtree. Never release the caller's lease or terminate unrelated processes from workbench cleanup.


## Interfaces and Dependencies


The public contract is additive Suite fields plus `RunReference.Service`. Internally, `PreparedSuite` owns an ordered sequence and resolved phase commands; `Service.Group` owns live process handles and monitor generations; `SuiteResult` separates primary execution failure from cleanup diagnostics. IR-4 extends this sequence with checks rather than re-flattening it. IR-2 generated parameters remain per Hurl execution and cannot become shared service configuration. IR-3 contributes one validated body-file root to each prepared Hurl request without changing fragment resolution.

Use existing `async`, `stm`, `typed-process`, `unix`, and HTTP readiness dependencies; this plan chooses no new package bounds. Before using unfamiliar APIs, run `mori registry list`, `mori registry search typed-process`, and `mori registry search dhall`, then `mori registry show <qualified-project> --full` and `mori registry docs <qualified-project>` using discovered owners. Read the source paths returned. If a dependency change becomes necessary, verify released versions in its authoritative registry and upstream tags before changing Cabal/Nix bounds. Registry failure is a recorded research prerequisite, not evidence of API compatibility.
