---
id: 5
slug: orchestrate-services-and-integration-test-suites
title: "Orchestrate Services and Integration Test Suites"
kind: exec-plan
created_at: 2026-07-30T23:31:54Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
---

# Orchestrate Services and Integration Test Suites


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture


After this plan, a repository can declare a safe default integration suite, separate
perimeter or mutating suites, and an optional service process that the workbench starts,
waits for, tests, and always stops. Test runs can emit per-run Hurl JUnit, HTML, JSON, or
TAP artifacts. This replaces handwritten runner scripts for the common lifecycle while
preserving an explicit path for externally generated Hurl variables such as signed request
bodies.


## Progress


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


## Decision Log


- Decision: A suite may manage at most one service in the first release.
  Rationale: One process covers the motivating API-server lifecycle and yields clear
  readiness and shutdown semantics. Multi-service dependency graphs belong in a later
  orchestration layer.
  Date: 2026-07-30

- Decision: Service readiness is either an HTTP status probe or a non-shell command probe.
  Rationale: These cover normal API health endpoints and specialized readiness without
  embedding a shell or a second test DSL.
  Date: 2026-07-30

- Decision: Emit one Hurl report per expanded run beneath a deterministic report root.
  Rationale: Recipes and matrix cases can have different bindings and therefore execute as
  separate Hurl processes; isolated reports avoid unsafe concurrent updates to one file.
  Date: 2026-07-30


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


This plan has a hard dependency on `docs/plans/3-execute-hurl-workflows-securely.md` and a
soft dependency on `docs/plans/4-add-recipes-matrices-and-exploratory-runs.md`. EP-3 owns
secure Hurl invocation. EP-4 owns `RunSelection`, expanded cases, bounded batches, and
safety metadata. Service lifecycle can be developed using one workflow before EP-4 ends,
but final suite selection must consume EP-4's types rather than duplicate them.

The Mori API Hurl runner demonstrates the target operational shape: a curated default
read-only list, opt-in writes, separate auth/CORS/perimeter checks, an already-running
server assumption, generated inputs for signed ingestion, and Hurl reports. The workbench
should add optional service ownership and naming without hiding those distinctions.

A service is a configured executable plus argv, working directory, environment bindings,
readiness probe, and shutdown timeout. It is not a shell command. A suite resolves each
`RunReference` to one or more EP-4 `ExpandedRun` values and runs them in test mode. A report
root contains one child directory per expanded run plus a workbench summary.

There is no relevant local or Mori-indexed ADR. The non-shell process boundary, readiness
semantics, termination guarantee, and report layout are durable and should be captured in
an ADR when implemented.


## Plan of Work


### Milestone 1: Resolve and bracket a managed service


Add `hurl-workbench-core/src/HurlWorkbench/Service/Resolve.hs`:

```haskell
data ResolvedService = ResolvedService
  { name :: EntityName
  , processConfig :: ResolvedCommand
  , readiness :: ResolvedReadiness
  , shutdownTimeout :: NominalDiffTime
  }

resolveService
  :: WorkspaceRoot
  -> Workspace
  -> ResolvedBindings
  -> Service
  -> Either ServiceError ResolvedService
```

Resolve environment bindings from the same plain/secret maps used by selected runs. Permit
`{{parameterName}}` placeholders only in HTTP readiness URLs; implement a small total
substitution function that accepts exactly declared names and errors on missing or malformed
placeholders. Do not apply it to Hurl source, executable names, arbitrary shell text, or
working-directory paths. Keep child environment values out of `Show` instances.

Add `HurlWorkbench.Service.Run`:

```haskell
data ServiceHandle

withService
  :: ResolvedService
  -> (ServiceHandle -> IO a)
  -> IO a
```

Start the executable with the configured argv, canonical workspace-contained working
directory, and an environment formed by overlaying declared bindings on the current
environment. Create a separate process group. Poll readiness until success, timeout, or
early service exit:

- an HTTP probe performs GET, accepts only its configured status, uses a short per-request
  timeout, and retries at the configured interval;
- a command probe runs its executable/argv directly with the service environment and treats
  exit zero as ready;
- DNS, connection refusal, and unexpected status remain retryable until the overall timeout;
  malformed URLs and a missing readiness executable fail immediately.

On normal return, exception, SIGINT, or readiness failure, send graceful termination to the
service process group, wait up to `shutdownTimeoutSeconds`, then force termination and reap
it. Never leave a zombie or background process. Add `http-client` 0.7.19.x for HTTP probes
after verifying Hackage and upstream tags. Use typed-process/process-group APIs already
chosen in EP-3.

Tests need controllable fixture processes for ready-after-delay, early exit, ignored TERM,
HTTP wrong-status-then-ready, and command readiness. Prove cleanup by checking process
liveness after every failure path.

This milestone is complete when `withService` brackets a fixture server through success,
timeout, child failure, and asynchronous cancellation without leaving it running.


### Milestone 2: Execute named suites with safety gates and reports


Add `hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs` and
`HurlWorkbench/Suite/Run.hs`:

```haskell
data ReportFormat = JUnit | Html | Json | Tap

data SuiteOptions = SuiteOptions
  { jobs :: PositiveInt
  , allowMutating :: Bool
  , manageService :: Bool
  , reportFormats :: Set ReportFormat
  , reportDirectory :: Maybe FilePath
  }

data SuiteResult = SuiteResult
  { cases :: NonEmpty CaseResult
  , serviceOutcome :: Maybe ServiceOutcome
  , summaryPath :: Maybe FilePath
  }

runSuite
  :: HurlCapabilities
  -> WorkspaceContext
  -> SuiteOptions
  -> Suite
  -> IO SuiteResult
```

Resolve run references in declaration order and flatten matrix cases without losing their
qualified names. If any selected recipe or matrix case is `Mutating`, fail before starting
the service unless `allowMutating` is true. The suite's `failFast` setting is the default;
an explicit CLI keep-going/fail-fast choice may override it.

When a service is declared and `manageService` is true, resolve all parameter values needed
by its environment/readiness, start it once, wait until ready, run the whole suite in
`TestMode`, then stop it. `--external-service` skips startup/readiness/shutdown for users who
already run the API. A missing service parameter is a preflight error before process start.

Reports require `--report-dir`. Create an owner-only directory
`REPORT_ROOT/SUITE/RUN/`. Pass one typed Hurl report option per requested format:
`junit.xml`, `html/`, `json/`, or `report.tap`. Never pass report flags through raw Hurl
arguments. Write `REPORT_ROOT/SUITE/summary.json` atomically after the suite, containing
logical names, statuses, durations, and relative report paths but no parameter values,
secrets, response bodies, or child environment. The summary is a workbench artifact; the
actual result details remain Hurl's reports.

Suite exit is zero only when service startup/shutdown and every selected run succeed. If
Hurl ran and failed, use the first non-zero Hurl exit code in declaration order. Use
workbench exit `4` for service orchestration failure. Preserve partial reports and summary
on test failure; cleanup only transient rendered/variable/secret files.

Test report argv with fake Hurl and run a real JUnit/JSON example against the fixture
service. Assert that mutating suites do not start the service without the flag.

This milestone is complete when a safe suite runs unattended, a write suite is blocked by
default, all requested per-run reports exist, and the managed service is gone afterward.


### Milestone 3: Add suite CLI and an integration-testing example


Extend the CLI with:

```text
hurl-workbench [--workspace FILE] test suite NAME
  [--jobs N] [--fail-fast|--keep-going] [--allow-mutating]
  [--external-service] [--report junit|html|json|tap] [--report-dir DIR]
  [BINDING_OPTIONS] [HURL_OPTIONS]
```

Update `list suites` to display run references, managed service, and whether any referenced
recipe is mutating. `validate` must render and syntax-check every workflow reachable from a
suite.

Create `examples/integration-service/` with a service definition for the repository's
fixture server, read-only health/read recipes, a mutating create recipe, a default safe
suite, a separate write suite, and a separate perimeter-style suite. The service command is
an executable plus argv; for development it may invoke Cabal with an explicit project-dir
argument, but it may not use `sh -c`. Use a declared port parameter in the child environment
and in the HTTP readiness URL.

Add `docs/guides/integration-testing.md` covering:

- default safe versus explicit mutating suites;
- `--external-service` for an already-running API;
- readiness, shutdown, and troubleshooting;
- report artifact locations and the response-body secret caveat;
- generating a standard Hurl variable file with an external signing helper, then supplying
  it through `--variables-file`; arbitrary pre/post hooks remain out of scope;
- keeping auth/CORS/perimeter scenarios separate from default functional checks.

This milestone is complete when a clean checkout can start the fixture service through the
workbench, pass the safe suite with JUnit and JSON reports, refuse the write suite without
authorization, run it with authorization, and leave no server process.


## Concrete Steps


First run the source lookup from `/Users/shinzui/Keikaku/bokuno/mori-project/mori`:

   ```bash
   just mori-global registry search http-client
   ```

Run the remaining commands from `/Users/shinzui/Keikaku/bokuno/hurl-workbench`.

1. Verify the released HTTP dependency before adding bounds:

   ```bash
   cabal info http-client
   ```

2. Implement service resolution/lifecycle, suites, reports, CLI, examples, and tests:

   ```bash
   nix fmt
   cabal test hurl-workbench-core-test hurl-workbench-cli-test
   ```

3. Run the safe integration example with reports:

   ```bash
   cabal run hurl-workbench -- --workspace examples/integration-service/hurl-workbench.dhall test suite default --report junit --report json --report-dir build/reports
   ```

   Expected result: the service becomes ready, all safe cases pass, report paths are listed,
   and the service exits.

4. Prove the mutation guard before opting in:

   ```bash
   cabal run hurl-workbench -- --workspace examples/integration-service/hurl-workbench.dhall test suite writes
   cabal run hurl-workbench -- --workspace examples/integration-service/hurl-workbench.dhall test suite writes --allow-mutating
   ```

   The first command exits before starting the service and names the mutating recipes. The
   second starts the service and executes them.

5. Run all checks:

   ```bash
   cabal build all
   cabal test all
   nix fmt -- --check
   ```


## Validation and Acceptance


- service commands are always executable-plus-argv and never shell strings;
- service cwd stays inside the workspace, environment values remain redacted, and only
  declared readiness placeholders are substituted;
- HTTP and command readiness honor interval/timeout and notice early service exit;
- service process groups terminate and are reaped on success, test failure, timeout, and
  interruption;
- a suite starts its service only after all binding/safety/report preflight succeeds;
- mutating suites require `--allow-mutating` and safe suites do not;
- `--external-service` performs no lifecycle actions;
- every expanded run gets isolated Hurl reports and the summary contains no runtime values;
- partial reports survive failures;
- the integration example demonstrates safe, write, perimeter, generated-variable, and
  managed/external-service workflows;
- all real-Hurl and process-lifecycle tests pass.


## Idempotence and Recovery


Workspace and suite resolution are read-only. Safe fixture suites are repeatable; mutating
suite idempotence depends on their Hurl requests and is never implied by the CLI. If service
startup times out, terminate and reap it before returning. If a run fails, stop according
to fail-fast policy, preserve completed report directories, write a partial summary, and
then stop the service. Existing report roots are rejected unless `--overwrite` is explicit;
overwrite removes or replaces only the resolved suite subtree after confirming it remains
inside the requested report root.


## Interfaces and Dependencies


EP-5 owns `ResolvedService`, `ServiceHandle`, `withService`, `ReportFormat`, `SuiteOptions`,
`SuiteResult`, and `runSuite`. It consumes EP-3 process/binding types and EP-4 selection and
batch types. EP-6 may package and document these interfaces but must not fork lifecycle or
report behavior.

Use `http-client` 0.7.19.x for readiness HTTP GETs, the existing typed process layer for
services and command probes, and `aeson` for the small redacted workbench summary. Verify
current versions and upstream release tags before setting bounds. Do not add Docker
orchestration, a general task runner, shell evaluation, multiple-service graphs, a signing
language, or a report merger.
