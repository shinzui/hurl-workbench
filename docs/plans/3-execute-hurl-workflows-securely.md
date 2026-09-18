---
id: 3
slug: execute-hurl-workflows-securely
title: "Execute Hurl Workflows Securely"
kind: exec-plan
created_at: 2026-07-30T23:31:53Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
provenance:
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-18T18:29:32Z
      mode: "update"
      note: "Defined typed execution, output, report, environment, value transport, and start-failure boundaries."
---

# Execute Hurl Workflows Securely


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture


After this plan, a rendered workflow is directly useful: `hurl-workbench run workflow
NAME` behaves like running the composed file with Hurl, while `hurl-workbench test workflow
NAME` uses Hurl's test mode. Values are resolved predictably, secrets never appear in the
spawned process argv, Hurl receives a workspace-root file boundary, stdout/stderr remain
faithful to Hurl, and the CLI returns Hurl's exact exit status after Hurl starts.

The same library-level `HurlRunner` operation from `RunRequest` to either a start error or
a `RunResult` becomes the only execution primitive for recipes, matrices, and suites in
later plans.


## Progress


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


## Decision Log


- Decision: Send resolved values through mode-0600 Hurl variable and secret files, never
  through `--secret NAME=VALUE` or secret-bearing environment names in diagnostics.
  Rationale: Process listings and command traces must not expose credentials, while Hurl's
  secret channel still supplies redaction for stderr and reports.
  Date: 2026-07-30

- Decision: Stream Hurl stdout and stderr unchanged for single runs.
  Rationale: Client mode is an exploration tool whose primary output is the final response;
  buffering, parsing, or decorating it would make the workbench less transparent.
  Date: 2026-07-30

- Decision: Pass through Hurl's exit code after a child process starts.
  Rationale: Shell scripts and CI already understand Hurl failures; a wrapper must not
  collapse or reinterpret them.
  Date: 2026-07-30

- Decision: Make stream handling and report/output targets part of `RunRequest`, and
  represent spawn failure separately from a started child's `ExitCode`.
  Rationale: Interactive runs should inherit streams, while parallel batches must capture
  diagnostics or write responses to isolated files. A process that never started did not
  emit a truthful Hurl exit code.
  Date: 2026-09-18

- Decision: Remove every ambient `HURL_*` variable from the child environment after the
  workbench resolves declared sources.
  Rationale: Hurl 8 treats that namespace as an alternate configuration channel for test
  mode, jobs, output, options, variables, and secrets; inheriting it would bypass the typed
  request and precedence model.
  Date: 2026-09-18


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


This plan depends on `docs/plans/2-compose-and-render-reusable-hurl-workflows.md`, which
owns `RenderedWorkflow`, `HurlfmtCapabilities`, and the non-shell `typed-process`
foundation. EP-1 defines `ValidatedWorkspace`, `HurlValueLiteral`, plain and secret
parameters, optional declared environment sources, and workflow parameter contracts. EP-3
must resolve values but must never substitute them into Hurl source.

Hurl 8.x supports `--variables-file`, `--secrets-file`, `--file-root`, client mode, and
`--test`. The official manual notes an important limit: secret values are redacted from
stderr logs and reports, but not from response bodies written to stdout. The workbench must
document that limit and must not claim it can sanitize a third-party response. Hurl also
rejects duplicate variable definitions, so the workbench resolves all supported sources
to one variable map and one secret map before spawning.

The reviewed Hurl 8.0.1 source is authoritative for the initial adapter. Its variable-file
reader trims whole lines, ignores empty lines and lines beginning with `#`, splits on the
first `=`, infers ordinary values, and forces secrets to strings. It also reads all ambient
`HURL_*` variables. Compatibility tests pin those behaviors so a later supported Hurl
major cannot silently alter value or environment semantics.

The supported platform for the first release is macOS and Linux. That permits an explicit
POSIX owner-only permission check for temporary secret material. Windows portability can
be added later behind a tested abstraction; it must not weaken the Unix implementation.

No existing ADR governs process or secret behavior. Create an ADR for secret transport,
child output, and exit propagation when this plan lands.


## Plan of Work


### Milestone 1: Resolve plain and secret bindings without rendering them


Add `hurl-workbench-core/src/HurlWorkbench/Parameter/Properties.hs` for the exact supported
Hurl 8 properties-file subset: UTF-8 lines are trimmed as complete lines; blank lines and
trimmed lines beginning with `#` are ignored; remaining lines split on the first `=`. Reject
a line without `=`, an invalid/reserved parameter name, duplicate names in one file,
invalid UTF-8, CR/LF/NUL within a programmatic value, and leading/trailing value whitespace
that would be lost by Hurl. Preserve additional `=` characters. Plain values become
`HurlValueLiteral`; secret values remain opaque strings. Do not include a secret line or
value in any error.

Add `hurl-workbench-core/src/HurlWorkbench/Parameter/Resolve.hs` with:

```haskell
data BindingInput = BindingInput
  { plainOverrides :: !(Map ParameterName HurlValueLiteral)
  , secretEnvironmentOverrides :: !(Map ParameterName Text)
  , variableFiles :: ![FilePath]
  , secretFiles :: ![FilePath]
  }
  deriving stock (Generic, Eq, Show)

data SecretValue

data ResolvedBindings = ResolvedBindings
  { variables :: !(Map ParameterName HurlValueLiteral)
  , secrets :: !(Map ParameterName SecretValue)
  }

instance Show ResolvedBindings where
  show _ = "ResolvedBindings <redacted>"

mkSecretValue :: Text -> Either SecretValueError SecretValue

resolveParameters
  :: ValidatedWorkspace
  -> Set ParameterName
  -> BindingInput
  -> IO (Either BindingError ResolvedBindings)

resolveWorkflowBindings
  :: ValidatedWorkspace
  -> Workflow
  -> BindingInput
  -> IO (Either BindingError ResolvedBindings)
```

Keep the `SecretValue` constructor and accessor internal. Its smart constructor enforces
the same lossless line-transport restrictions as `HurlValueLiteral` (no CR, LF, NUL, or
leading/trailing whitespace), but every failure reports only the parameter and source, not
the candidate value. Additional `=` characters remain valid.

For plain parameters, precedence from highest to lowest is explicit `--variable`, later
`--variables-file`, earlier `--variables-file`, the parameter's declared environment, then
its default. For secret parameters it is explicit `--secret-env NAME=ENVIRONMENT_NAME`,
later `--secrets-file`, earlier `--secrets-file`, then the declared environment. A name
defined more than once in the same precedence layer is an error; a higher layer may
intentionally override a lower layer. Missing required workflow parameters are reported
together in sorted name order. Overrides for parameters not declared by the selected
workflow are errors, preventing misspellings from becoming unused values.

`resolveWorkflowBindings` is a thin wrapper that supplies the workflow's declared parameter
set. The set-based primitive lets EP-5 resolve the union of suite-run and service parameters
without weakening unexpected-name checks.

The `--secret-env` argument carries only a parameter name and environment-variable name;
the actual secret is read after parsing. Error renderers may mention those names and the
source file path, never the value. Add tests for precedence, missing values, plain/secret
kind mismatch, malformed properties, duplicate sources, and error redaction. Keep a later
extension point for EP-4's recipe and matrix binding layers rather than baking CLI concepts
into the resolver.

This milestone is complete when the same declared inputs always resolve to the same maps,
secret errors do not contain fixture secret values, and no Hurl source has changed.


### Milestone 2: Build a secure, bracketed Hurl process adapter


Add `hurl-workbench-core/src/HurlWorkbench/Hurl/Capabilities.hs`:

```haskell
data HurlCapabilities = HurlCapabilities
  { hurlExecutable :: !FilePath
  , hurlVersion :: !Version
  , hurlfmt :: !HurlfmtCapabilities
  }
  deriving stock (Generic, Eq, Show)

detectHurlCapabilities :: IO (Either DependencyError HurlCapabilities)
```

Locate both binaries through `PATH`, invoke `--version` with `proc`, and parse the first
semantic version. Require at least Hurl 8.0.0. Accept a later major with a visible
"untested major version" warning rather than an unconditional failure. Unit-test parsing
with recorded version strings; do not make most tests depend on the developer's PATH.

Add `hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs`:

```haskell
data HurlRunMode = ClientMode | TestMode
  deriving stock (Generic, Eq, Show)

data RunOutputPolicy
  = InheritRunOutput
  | CaptureRunOutput
  | ResponseFile FilePath
  deriving stock (Generic, Eq, Show)

data HurlReportTarget
  = JUnitReport FilePath
  | HtmlReport FilePath
  | JsonReport FilePath
  | TapReport FilePath
  deriving stock (Generic, Eq, Show)

data RunRequest = RunRequest
  { renderedWorkflow :: !RenderedWorkflow
  , mode :: !HurlRunMode
  , bindings :: !ResolvedBindings
  , options :: !HurlOptions
  , outputPolicy :: !RunOutputPolicy
  , reportTargets :: ![HurlReportTarget]
  }

data CapturedRunOutput = CapturedRunOutput
  { stdout :: !ByteString
  , stderr :: !ByteString
  }
  deriving stock (Generic, Eq, Show)

data RunResult = RunResult
  { exitCode :: !ExitCode
  , elapsed :: !NominalDiffTime
  , capturedOutput :: !(Maybe CapturedRunOutput)
  }
  deriving stock (Generic, Eq, Show)

newtype HurlRunner = HurlRunner
  { runHurl :: RunRequest -> IO (Either RunStartError RunResult)
  }

mkHurlRunner :: HurlCapabilities -> HurlRunner
```

For each invocation, create one bracketed temporary directory containing the rendered
`.hurl` file and, when non-empty, `variables.env` and `secrets.env`. Use
`System.IO.Temp.openBinaryTempFile`, whose POSIX contract creates mode `0600`, write through
the returned handle, verify the resulting mode, and remove the directory after the child
exits or an exception is raised. Serialize `HurlValueLiteral` exactly once and emit one
unique name per generated file. Spawn Hurl with `--file-root WORKSPACE_ROOT`, the generated
input files, `--test` only in `TestMode`, typed safe options, typed report targets, then the
rendered file. Never use a shell.

`InheritRunOutput` inherits stdin/stdout/stderr and is reserved for one interactive CLI
run. `CaptureRunOutput` closes stdin and captures stdout/stderr for an orchestrator to emit
in declaration order. `ResponseFile` closes stdin, pre-creates that exact response file as
`0600`, passes it with `--output`, and captures diagnostics. Report targets likewise create
only their exact validated files/directories and permit at most one target per format.
`RunStartError` covers argument rejection, secure-file creation, and spawn failure before a
child starts; any started child, including one that exits non-zero, returns `RunResult`.

Define typed `HurlOptions` for common exploration controls: connect timeout, max time,
retry count, retry interval, insecure TLS, include headers, JSON output, verbose level,
curl export path. Response files and reports belong to the typed request fields rather than
`HurlOptions`. A repeatable `--hurl-arg ARG` extension may expose only an audited,
versioned allowlist of zero-argument, non-sensitive long flags not owned by the workbench.
Its smart constructor rejects unknown flags, every `--name=value` token, short flags,
positionals, and workbench-owned controls including secrets, variables, file root, mode,
jobs/parallelism, globs, output, and reports. Options that carry a value must gain a typed
field before use. This prevents an option from consuming the generated input path and
prevents credential-like values from entering argv. Never print a reconstructed command
containing runtime values.

Build the child environment from the current environment after removing every key whose
name begins with `HURL_`. Values explicitly named as parameter sources are read by the
workbench before that filtering and transported through the generated files. Preserve
unrelated settings such as proxy and certificate environment variables. Tests set hostile
`HURL_TEST`, `HURL_OUTPUT`, `HURL_VARIABLE_*`, and `HURL_SECRET_*` values and prove they do
not affect the child.

Use `typed-process` 0.2.13.x, `temporary`, `time`, and `unix` after verifying their current
registry releases and upstream tags. The executable already uses `-threaded`, as recommended
by `typed-process`.

Create a fake-Hurl test executable or script in a test temporary directory that records
argv paths and returns a requested exit code. Tests must prove secrets are absent from argv,
all temp files and typed output files are `0600`, `--file-root` is the manifest directory,
mode and report flags are correct, inherited versus captured output follows policy,
ambient `HURL_*` variables are absent, spawn failure is not represented as a child exit,
the child exit code is retained, and temp files disappear afterward. Add a development/test
executable named `hurl-workbench-fixture-server` under
`hurl-workbench-cli/test/fixture-server/Main.hs`, backed by WAI/Warp. It exposes local-only
health, OAuth-token, OData-echo, bespoke-capture, raw-response, and mutating endpoints and
accepts a port argument or `PORT` environment value. Use it for one real-Hurl integration test on an ephemeral port;
skip with an explicit message only when Hurl 8.x is not installed. EP-4 and EP-5 reuse this
same fixture executable in their examples instead of creating another server.

This milestone is complete when a real Hurl client run receives the fixture response, test
mode suppresses that response and prints Hurl's summary, and every cleanup/redaction test
passes.


### Milestone 3: Expose `run`, `test`, and `doctor`


Add `HurlWorkbench.Cli.Command.Run` and `HurlWorkbench.Cli.Command.Doctor`. The surface is:

```text
hurl-workbench [--workspace FILE] run workflow NAME [BINDING_OPTIONS] [HURL_OPTIONS]
hurl-workbench [--workspace FILE] test workflow NAME [BINDING_OPTIONS] [HURL_OPTIONS]
hurl-workbench doctor
```

Binding options are repeatable `--variable NAME=VALUE`, `--variables-file FILE`,
`--secret-env NAME=ENVIRONMENT_NAME`, and `--secrets-file FILE`. Parse secret files only
inside the resolver and never include values in `Show` instances for option or error types.
`doctor` prints paths, parsed versions, and support status for Hurl/Hurlfmt without loading a
workspace.

Both execution commands discover, decode, semantically validate, resolve and render the
workflow, syntax-check it, resolve bindings, and then call `runHurl`. Errors before Hurl
starts use workbench exit codes: `2` for workspace/binding/argument errors and `3` for a
missing or unsupported dependency. Once Hurl starts, call `exitWith` using its exact
`ExitCode`. Do not print a success banner over client-mode stdout.

Group parser sections with `parserOptionGroup` from `optparse-applicative` 0.19 under
`Bindings`, `HTTP and retry`, `Output and diagnostics`, and `Advanced Hurl arguments`, as
specified by `mori://shinzui/haskell-jitsurei/docs/cli-option-groups`. The grouping changes
help layout only; it must not create separate precedence behavior.

This milestone is complete when CLI tests cover the entire preflight order and a shell sees
the same non-zero status emitted by the fake or real Hurl process.


## Concrete Steps


Run commands from `/Users/shinzui/Keikaku/bokuno/hurl-workbench`.

1. Verify dependencies and local tools:

   ```bash
   hurl --version
   hurlfmt --version
   cabal info typed-process temporary time unix wai warp
   ```

2. Implement binding resolution, capabilities, process execution, CLI commands, and tests,
   then run:

   ```bash
   nix fmt
   cabal test hurl-workbench-core-test hurl-workbench-cli-test
   ```

3. Start the fixture server, then exercise it in client and test modes:

   ```bash
   cabal run hurl-workbench-fixture-server -- --port 18080
   ```

   In another shell:

   ```bash
   cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/execution/hurl-workbench.dhall run workflow health --variable baseUrl=http://127.0.0.1:18080
   cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/execution/hurl-workbench.dhall test workflow health --variable baseUrl=http://127.0.0.1:18080
   ```

   Client mode prints the response; test mode prints Hurl's per-file result and summary.

4. Verify exact exit propagation with the fake Hurl fixture and run the full build:

   ```bash
   cabal build all
   cabal test all
   cabal run hurl-workbench -- doctor
   ```


## Validation and Acceptance


- every declared workflow parameter resolves according to the documented precedence;
- missing and unexpected bindings are reported together before any HTTP request;
- secret values never appear in argv, diagnostic rendering, exception text, or test logs;
- generated Hurl, variable, and secret files are owner-only and are removed on every path;
- ambient `HURL_*` values cannot alter mode, jobs, output, options, variables, or secrets;
- Hurl receives the workspace root through `--file-root`;
- the workbench does not decorate or parse single-run stdout/stderr;
- concurrent callers can select capture or response-file output without inheriting
  interleaved child streams;
- client and test modes match direct Hurl behavior;
- unknown, value-bearing, sensitive, and workbench-owned passthrough arguments are rejected
  before spawn;
- `doctor` reports actual executable paths and versions;
- Hurl's exact non-zero exit status reaches the parent shell;
- real-Hurl integration and fake-process edge-case tests pass on macOS and Linux.


## Idempotence and Recovery


Preflight and execution are safe to retry subject to the API operation represented by the
workflow; the workbench must not imply that a mutating Hurl request is idempotent. Temp
resources and child processes are bracketed. If interrupted before spawn, no HTTP request
occurs. If interrupted after spawn, forward termination and wait for Hurl before cleanup.
On a permission-setting failure, abort before writing secrets. If Hurl is missing or too
old, `doctor` provides the actionable path/version failure and no workspace is changed.


## Interfaces and Dependencies


EP-3 owns `BindingInput`, `SecretValue`, `ResolvedBindings`, `resolveParameters`,
`resolveWorkflowBindings`, `HurlCapabilities`, `HurlOptions`, `HurlRunMode`,
`RunOutputPolicy`, `HurlReportTarget`, `RunRequest`, `RunStartError`, `CapturedRunOutput`,
`RunResult`, `HurlRunner`, `mkHurlRunner`, and the shared local fixture-server contract. Secret
constructors and unredacted renderers remain internal. EP-4 and EP-5 may add binding layers
or orchestrate multiple requests, but they must reduce every case to these interfaces and
must not construct child argv independently.

Use `typed-process` for non-shell process control, `temporary` for bracketed directories,
`unix` for POSIX permission enforcement, and `time` for elapsed duration. Use WAI/Warp only
as test dependencies for the local integration server. Continue using Hurl/Hurlfmt 8.x as
external runtime dependencies; do not add an HTTP implementation, response decoder, secret
store, or logging framework to the production library.


## Revision Note


2026-09-18: Reworked the execution boundary around typed output/report policies, explicit
spawn errors, injectable `HurlRunner`, lossless Hurl value literals, owner-only files, and
filtered `HURL_*` child environments; also aligned command help with the Haskell Jitsurei
option-group pattern.
