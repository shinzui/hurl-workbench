---
id: 5
slug: orchestrate-services-and-integration-test-suites
title: "Orchestrate Services and Integration Test Suites"
kind: exec-plan
created_at: 2026-07-30T23:31:54Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
provenance:
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-18T18:29:32Z
      mode: "update"
      note: "Made EP-4 a hard dependency and specified suite preflight, safety, reports, and process-group cleanup."
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-20T23:47:35Z
      mode: "implement"
      note: "Corrected the formatter acceptance command after EP-2 exercised the pinned treefmt CLI."
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


- Observation: The repository's pinned treefmt CLI uses `--ci`, not the obsolete `--check`
  flag, for a no-cache fail-on-change validation run. The final acceptance command in this plan
  has been corrected to `nix fmt -- --ci`.
  Evidence: EP-2's repository acceptance run on 2026-09-20.


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

- Decision: Resolve all runs, service inputs, safety gates, output paths, and report targets
  before starting the managed service.
  Rationale: No HTTP or service side effect should occur when any later suite case is known
  to be invalid, and one managed service cannot depend ambiguously on case-specific matrix
  values.
  Date: 2026-09-18


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


This plan has a hard dependency on
`docs/plans/4-add-recipes-matrices-and-exploratory-runs.md`, which transitively depends on
EP-3. EP-3 owns secure Hurl invocation. EP-4 owns `RunSelection`, expanded/prepared cases,
bounded batches, explicit case outcomes, and safety metadata. Final suite selection must
consume those types rather than duplicate them; therefore EP-4 is a hard dependency even
though isolated service-lifecycle code could theoretically be drafted earlier.

The Hurl runner in `mori://shinzui/mori/repos/mori`, under `mori-api/test/hurl`,
demonstrates the target operational shape: a curated default
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

The example suites follow
`mori://shinzui/haskell-jitsurei/docs/api-hurl-integration-testing`: the default is an
explicit list of independent safe families, writes and perimeter/auth variants are opt-in,
every request asserts status, and body-bearing responses assert media type plus stable wire
semantics. `--external-service` preserves the standard already-running-server workflow;
managed service mode is the higher-level orchestration alternative.


## Plan of Work


### Milestone 1: Resolve and bracket a managed service


Add `hurl-workbench-core/src/HurlWorkbench/Service/Resolve.hs`:

```haskell
data ResolvedService = ResolvedService
  { name :: !ServiceName
  , processConfig :: !ResolvedCommand
  , readiness :: !ResolvedReadiness
  , shutdownTimeout :: !NominalDiffTime
  }
  deriving stock (Generic, Eq, Show)

resolveService
  :: ValidatedWorkspace
  -> ResolvedBindings
  -> Service
  -> Either ServiceError ResolvedService
```

Resolve environment bindings from the same plain/secret maps used by selected runs. Permit
`{{parameterName}}` placeholders only in HTTP readiness URLs; implement a small total
substitution function that accepts exactly declared plain names and errors on missing,
malformed, or secret placeholders. A secret must never enter a URL. Do not apply
substitution to Hurl source, executable names, arbitrary shell text, or working-directory
paths. Keep child environment values out of `Show` instances.

A service is started once for the whole suite, so service parameters resolve only from the
suite's runtime `BindingInput`, declared parameter environment sources, and defaults. Recipe
or matrix-case layers are per-run and must not supply service environment/readiness values.
If a service parameter is available only from a committed case layer, preflight fails with
an explanation before any process starts.

Add `HurlWorkbench.Service.Run`:

```haskell
data ServiceHandle

withService
  :: ResolvedService
  -> (ServiceHandle -> IO a)
  -> IO (Either ServiceError a)
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

After readiness succeeds, monitor the service leader while the callback runs. If the
service exits first, cancel and reap active Hurl children, record the unexpected exit in
`ServiceOutcome`, and mark work that never started as `BatchPrerequisiteFailed`; do not
allow the callback to continue against a dead prerequisite.

On POSIX, launch with `typed-process` `setCreateGroup True`, retain the typed `Process`, and
obtain its PID with `getPid`; that PID is the new process-group ID. On normal return,
callback exception, SIGINT, or readiness failure, call
`System.Posix.Signals.signalProcessGroup` with `sigTERM`, wait up to
`shutdownTimeoutSeconds`, then signal the group with `sigKILL` and reap the leader with
`waitExitCode`. The generic `typed-process` `stopProcess` cleanup only terminates the
immediate process, so it is not the service-group shutdown implementation. Re-throw
asynchronous exceptions only after cleanup; return expected spawn/readiness/shutdown
failures as `ServiceError`. Never leave a zombie or background descendant. Add
`http-client` 0.7.19.x for HTTP probes after verifying Hackage and upstream tags.

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
  deriving stock (Generic, Eq, Ord, Show)

data SuiteOptions = SuiteOptions
  { jobs :: !PositiveInt
  , failFastOverride :: !(Maybe Bool)
  , allowMutating :: !Bool
  , manageService :: !Bool
  , reportFormats :: !(Set ReportFormat)
  , reportDirectory :: !(Maybe FilePath)
  }
  deriving stock (Generic, Eq, Show)

data SuiteRequest = SuiteRequest
  { suiteName :: !SuiteName
  , bindingInput :: !BindingInput
  , hurlOptions :: !HurlOptions
  , suiteOptions :: !SuiteOptions
  }

newtype SuitePreflightError = SuitePreflightError
  { issues :: !(NonEmpty SuitePreflightIssue)
  }
  deriving stock (Generic, Eq, Show)

data SuiteResult = SuiteResult
  { cases :: !(NonEmpty CaseResult)
  , serviceOutcome :: !(Maybe ServiceOutcome)
  , summaryPath :: !(Maybe FilePath)
  , selectedExitCode :: !ExitCode
  }
  deriving stock (Generic, Eq, Show)

runSuite
  :: HurlRunner
  -> HurlfmtCapabilities
  -> ValidatedWorkspace
  -> SuiteRequest
  -> IO (Either SuitePreflightError SuiteResult)
```

Resolve run references in declaration order and flatten matrix cases without losing their
qualified names. If any selected recipe or matrix case is `Mutating`, or a direct workflow
is `UnclassifiedWorkflow`, fail before starting the service unless `allowMutating` is true.
An unclassified workflow is not assumed safe merely because it bypasses a recipe. The
suite's `failFast` setting is the default; an explicit CLI keep-going/fail-fast choice may
override it.

Before starting anything, expand and prepare every referenced run, derive every typed report
target, validate all output paths, build every EP-4 `BatchCase` with its complete
`RunRequest`, resolve the service's runtime-only parameters, and apply the mutation gate.
When a service is declared and `manageService` is true, start it once, wait until ready,
run the whole prepared suite in `TestMode`, then stop it.
`--external-service` skips startup/readiness/shutdown for users who already run the API. A
missing service parameter is a preflight error before process start.

Accumulate independent preflight issues in declaration order. Once preflight succeeds,
`runSuite` always returns a `SuiteResult`: if service spawn or readiness fails, set the
`ServiceOutcome`, mark every prepared case `CaseSkipped BatchPrerequisiteFailed`, and
select workbench exit `4` rather than returning a preflight error.

Reports require `--report-dir`. Create an owner-only directory
`REPORT_ROOT/SUITE/RUN/`. Pass one typed Hurl report option per requested format:
`junit.xml`, `html/`, `json/`, or `report.tap`. Never pass report flags through raw Hurl
arguments. Write `REPORT_ROOT/SUITE/summary.json` atomically after the suite, containing
logical names, statuses, durations, and relative report paths but no parameter values,
secrets, response bodies, or child environment. The summary is a workbench artifact; the
actual result details remain Hurl's reports.

Suite exit is zero only when service startup/shutdown and every selected run succeed. If
Hurl ran and failed and service shutdown succeeded, use the first non-zero Hurl exit code in
declaration order. Use workbench exit `3` for a pre-spawn Hurl failure and exit `4` for
service start/readiness/shutdown failure. A shutdown failure takes precedence over a Hurl
failure while the summary retains both outcomes. Preserve partial reports and summary on
test failure; cleanup only transient rendered/variable/secret files.

Test report argv with fake Hurl and run a real JUnit/JSON example against the fixture
service. Assert that mutating suites do not start the service without the flag.

This milestone is complete when a safe suite runs unattended, a write suite is blocked by
default, all requested per-run reports exist, and the managed service is gone afterward.


### Milestone 3: Add suite CLI and an integration-testing example


Extend the CLI with:

```text
hurl-workbench [--workspace FILE] test suite NAME
  [--jobs N] [--fail-fast|--keep-going] [--allow-mutating]
  [--external-service] [--report junit|html|json|tap] [--report-dir DIR] [--overwrite]
  [BINDING_OPTIONS] [HURL_OPTIONS]
```

Group suite flags with `parserOptionGroup` under `Suite control`, `Service lifecycle`,
`Reports`, `Bindings`, and `Advanced Hurl arguments`, following
`mori://shinzui/haskell-jitsurei/docs/cli-option-groups`. Reuse EP-3/EP-4 parsers and types
so help organization does not create a second request model.

Update `list suites` to display run references, managed service, and whether any referenced
run is mutating or unclassified. `validate` must render and syntax-check every workflow
reachable from a suite.

Create `examples/integration-service/` with a service definition for the repository's
fixture server, read-only health/read recipes, a mutating create recipe, a default safe
suite, a separate write suite, and a separate perimeter-style suite. The service command is
an executable plus argv; for development it may invoke Cabal with an explicit project-dir
argument, but it may not use `sh -c`. Use a declared port parameter in the child environment
and in the HTTP readiness URL.

Keep safe resource families as explicit suite references rather than a broad filesystem
glob. Every example request block asserts its status; every response with a body also
asserts media type and stable semantics. Different Hurl files are independent because Hurl
test mode may run files in parallel, while capture-dependent sequences stay within one
rendered workflow.

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


Run commands from the repository root and locate the dependency through Mori first:

```bash
mori registry show snoyberg/http-client --full
```

1. Verify the released HTTP dependency before adding bounds:

   ```bash
   cabal info http-client
   git ls-remote --tags https://github.com/snoyberg/http-client.git
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
   nix fmt -- --ci
   ```


## Validation and Acceptance


- service commands are always executable-plus-argv and never shell strings;
- service cwd stays inside the workspace, environment values remain redacted, and only
  declared readiness placeholders are substituted;
- HTTP and command readiness honor interval/timeout and notice early service exit;
- service process groups terminate and are reaped on success, test failure, timeout, and
  interruption;
- a suite starts its service only after all binding/safety/report preflight succeeds;
- case-specific recipe/matrix values cannot ambiguously configure a once-per-suite service;
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
`SuiteRequest`, `ServiceOutcome`, `SuiteResult`, `SuitePreflightError`, and `runSuite`. It
consumes EP-3 process/binding types and EP-4 selection, preparation, `BatchCase`, and
batch-result types. EP-6 may package and document these interfaces but must not fork
lifecycle or report behavior.

Use `http-client` 0.7.19.x for readiness HTTP GETs, the existing typed process layer for
services and command probes, and `aeson` for the small redacted workbench summary. Verify
current versions and upstream release tags before setting bounds. Do not add Docker
orchestration, a general task runner, shell evaluation, multiple-service graphs, a signing
language, or a report merger.


## Revision Note


2026-09-18: Made EP-4 a hard dependency, specified POSIX process-group shutdown instead of
relying on immediate-child cleanup, separated suite preflight from execution, defined the
missing runtime input API and exit precedence, and aligned suite layout/help with the
Haskell Jitsurei Hurl and CLI patterns.

2026-09-20: Replaced the unsupported treefmt `--check` flag with the pinned CLI's `--ci`
fail-on-change mode after EP-2 exercised the repository acceptance commands.
