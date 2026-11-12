# CLI reference

```text
hurl-workbench [--workspace FILE] COMMAND
```

`--workspace` selects a manifest explicitly; otherwise discovery walks from the current directory
upward. `--version` prints the Cabal package version and short build revision. `--help`, empty
invocations, and parse errors show contextual help.

## Commands

| Command | Purpose | Primary output |
|---|---|---|
| `validate` | Decode, semantically validate, and Hurlfmt-check every workflow. | Counts on stdout; diagnostics on stderr. |
| `list [CATEGORY]` | List `all`, `parameters`, `fragments`, `workflows`, `recipes`, `matrices`, `checks`, `services`, or `suites`. | Stable tables on stdout. |
| `render workflow NAME` | Compose and Hurlfmt-check a workflow. | Hurl on stdout or atomically to `--output FILE`. |
| `render recipe NAME` | Render a recipe's selected workflow; `--explain` lists binding sources without values. | Hurl on stdout; explanation/path on stderr. |
| `run workflow|recipe NAME` | Execute in Hurl client mode. | Hurl streams directly to the terminal. |
| `test workflow|recipe NAME` | Execute in Hurl test mode. | Hurl streams directly to the terminal. |
| `matrix NAME` | Expand and execute every recipe case. | Ordered diagnostics and case summaries on stderr. |
| `test suite NAME` | Preflight and execute a suite, optionally managing its service. | Ordered diagnostics, summaries, and artifact paths on stderr. |
| `doctor` | Probe Hurl and Hurlfmt paths, versions, and support status. | Tool report on stdout. |
| `completions bash|zsh|fish` | Generate a shell script that delegates to this parser. | Script on stdout. |

Run any command with `--help` for its complete grouped options.

## Bindings and execution controls

Execution commands accept repeatable `--variable NAME=VALUE`, `--variables-file FILE`,
`--secret-env NAME=ENVIRONMENT_NAME`, and `--secrets-file FILE`. `--allow-mutating` is required for
mutating recipes/matrix cases and for unclassified direct workflows inside suites.

Typed Hurl controls are `--connect-timeout`, `--max-time`, `--retry`, `--retry-interval`,
`--insecure`, `--include`, `--json`, `--verbose` or `--very-verbose`, `--file-root DIR`, and `--curl FILE`. The only
accepted repeatable `--hurl-arg` values are:

```text
--compressed  --location  --location-trusted  --no-color  --path-as-is
```

Options taking values are never accepted through passthrough.

Matrices add `--mode run|test`, `--jobs N`, `--fail-fast`/`--keep-going`, `--output-dir DIR`, and
`--overwrite`. Parallel client mode requires an output directory. Suites add `--jobs`, safety and
fail-fast controls, `--external-service`, repeatable `--report junit|html|json|tap`, `--report-dir`,
and `--overwrite`, plus `--scenario-inputs FILE` for independent suites.

Suites default to `isolation = Schema.IsolationPolicy.SharedState`, including manifests written
before the field existed. With `--jobs` greater than one, every expanded run must be a `ReadOnly`
recipe. Mutating recipes, matrix cases, and unclassified direct workflows fail before capability
probes, binding resolution, or child starts, even with `--allow-mutating` or `--external-service`.
Use `--jobs 1 --allow-mutating` for shared-state writes. Standalone mutating matrices also require
`--jobs 1`. The requested job count controls this check even for one expanded run.

`IndependentState` requires `--external-service` and a complete `--scenario-inputs FILE`; it
cannot declare a shared managed service. The file resolves relative to the invocation directory,
is read once, and must be a regular non-symlink file with no group/other permissions. SharedState
rejects scenario inputs. The [handoff contract](../guides/integration-testing.md#independent-scenario-handoff)
defines version 1, origin uniqueness, parameter channels, and binding precedence.

## Artifacts and reports

Client matrix responses use `OUTPUT/MATRIX/CASE.response`. Suite reports use
`REPORT/SUITE/RUN/`: `junit.xml`, `html/`, `json/`, or `report.tap`. Every suite writes a redacted
`summary.json` when a report directory is selected. It identifies `isolation` (`shared-state` or
`independent-state`) and each logical `scenario`. Safely reportable preflight refusals use status
`refused`; missing runtime input uses `setup-failed`. Both list `not-started` cases, stable
`reasonCodes`, and empty report lists. Cancellation preserves completed outcomes, marks unfinished
cases `cancelled`, writes a best-effort `cancelled` summary after child cleanup, and propagates the
original interruption. Unknown suites or unsafe/conflicting report destinations receive no new
summary and leave existing trees untouched. Output directories are owner-only (`0700`) and
files are owner-readable/writable (`0600`). Existing targets fail preflight unless overwrite is
explicit; suite overwrite removes only the validated selected suite subtree.

## Exit behavior

- `0`: workbench success and every started Hurl process succeeded;
- `1`: ordinary discovery, decoding, validation, or selection failure for inspection commands;
- `2`: execution preflight, binding, safety-gate, or artifact-layout failure;
- `3`: missing dependency, secure-file/start failure, or report-summary write failure;
- `4`: managed-service lifecycle failure;
- another non-zero status: for a started single run, Hurl's exact status; batches select the first
  Hurl failure in declaration order unless a higher-priority workbench/service failure applies.

Parse failures are emitted by optparse-applicative with contextual usage. Failures before a child
starts are labeled as workbench/preflight errors; Hurl failures remain child results.

## Completion installation

```bash
hurl-workbench completions bash > ~/.local/share/bash-completion/completions/hurl-workbench
hurl-workbench completions zsh > ~/.zfunc/_hurl-workbench
hurl-workbench completions fish > ~/.config/fish/completions/hurl-workbench.fish
```

The generated scripts require `hurl-workbench` on `PATH` and query its hidden completion protocol
at tab-completion time.

## Multi-service suites

`test suite NAME` prepares every Hurl batch, service, setup command, teardown
command, environment policy and report path before setup starts. The environment
is frozen for all managed commands and later restarts. Named lifecycle actions
appear as `SERVICE NAME ACTION STATUS`; phase outcomes appear as `PHASE` lines.
Lifecycle and phase work have their own statuses, independent of Hurl cases.

`--external-service` bypasses setup, managed services/readiness/shutdown and
teardown. It refuses a suite containing lifecycle steps. `--fail-fast` also skips
later batches and barriers after a failed Hurl batch. With keep-going, only ordinary
Hurl failures permit later execution; service/lifecycle failures stop the sequence.
Setup, service and cleanup failures select exit 4. An earlier Hurl failure remains
recorded as the primary cause if cleanup also fails.

`summary.json` retains `cases` and aggregate `service` for existing clients, and
adds ordered `steps`, named `services`, `phases`, `primaryFailure`, and separate
`cleanupDiagnostics`. Phase output lives under private
`phases/setup/INDEX/` and `phases/teardown/INDEX/` directories when a report root is
selected. Without reports, captures are temporary and removed at finalization.

Generated inputs appear as `generated (TypeId)` (or their other generator kind)
in `render ... --explain`. Validate, list, and render inspect declarations without
reading the clock or entropy. Run/test resolve fresh inputs per Hurl execution;
`--variable name=value` and `--variables-file` support reproducible overrides.
Generation failures identify only the parameter and generator kind and fail
execution preflight with exit status 2.

## Request body file roots

`run workflow`, `test workflow`, `run recipe`, `test recipe`, `matrix`, and `test suite`
accept `--file-root DIR`. Relative CLI paths use the invocation directory. Without an override,
Hurl reads file request bodies relative to the canonical workspace root. Only execution accepts
the option; render and validate continue without runtime body files.

A suite can instead declare `fileRootParameter = Some "payloadRoot"`. The named declared Plain
parameter resolves once from suite-level runtime inputs, environment, or defaults; a relative
value uses the workspace root. CLI `--file-root` wins and requires no shadowed parameter value.
Secret, Generated, unknown, and malformed references fail workspace validation.

Missing, regular-file, unreadable, or unsearchable roots fail with exit 2 before subprocesses,
including version probes. Explicit body roots and output/report/curl trees must be disjoint,
including symlink aliases and overwrite ancestors. Explicitly selecting the workspace applies
this rule too; the default allows the existing workspace-local report layout.
The caller keeps the directory alive and readable until execution finishes and owns its cleanup.
See [the byte-preserving example](../../examples/file-body/README.md).

## Executable check results

`list checks` displays logical check names, expected status, timeout and description.
Validation counts checks. `test suite` requires `--report-dir` for a check-bearing
suite, even without a Hurl report format. It emits named `CHECK` status/path lines
on stderr; captured check stdout/stderr are kept private and are never replayed.

The ordered `steps` summary adds `kind: "check"`, `name`, `status`, `expectedStatus`,
`actualStatus`, `elapsedSeconds`, suite-relative `stdout` and `stderr`, and separate
`cleanupDiagnostics`. Skips identify fail-fast, prerequisite failure or cancellation.
Legacy Hurl `cases` and service fields remain; checks-only suites have empty cases.

Fail-fast spans all batches and barriers. Keep-going permits later work after an
ordinary mismatch or timeout with successful group cleanup. Service death or
uncertain cleanup aborts later work. A mismatched nonzero status is preserved;
unexpected zero selects 1, timeout selects 124, signal selects 128 plus the signal
number, and launch or cleanup-only failure selects 3. Ordinary Hurl/check failures
are chosen in declaration order. Service lifecycle failure retains exit 4 priority,
and summary-write failure selects 3 unless a service failure already selects 4.
Cancellation preserves partial observations and rethrows after finalization.
