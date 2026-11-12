# Integration testing with managed suites


A suite is a reviewed list of workflows, recipes, and matrices. `test suite` resolves every run,
binding, safety classification, report path, and service input before it starts a process. This
makes suites suitable for unattended checks while keeping state-changing and perimeter scenarios
deliberately separate.


## Safe defaults and explicit writes


Put only `ReadOnly` recipes in the default suite. A `Mutating` recipe and a direct workflow both
require `--allow-mutating`; direct workflows are unclassified because they have no recipe safety
declaration. Suites default to `Schema.IsolationPolicy.SharedState`. Shared-state writes and
direct workflows require `--jobs 1` as well as `--allow-mutating`, even when only one scenario
expands. Parallel shared-state suites must contain only `ReadOnly` recipes. The same rule applies
to standalone mutating matrices. Separate Hurl sessions do not establish separate application
state, and `--external-service` does not change the isolation check.

`Schema.IsolationPolicy.IndependentState` requires an explicit runtime handoff assigning one
caller-provisioned fixture and endpoint per scenario. It cannot declare a shared managed service;
use `--external-service`. Mutation still requires `--allow-mutating`.

Keep auth, CORS, network-perimeter, and other environment-sensitive checks in named
opt-in suites instead of broad filesystem globs.

The repository example has all three shapes:

```bash
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite default

# Refused before the service starts.
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite writes

# Explicitly authorized.
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite writes --allow-mutating
```

Every request block should assert its status. When a response has a body, also assert its media
type and at least one stable wire-level semantic. Keep capture-dependent request sequences in one
workflow; separate workflows are independent Hurl sessions.


## Managed and external services


By default, a suite with a service starts its executable and argv directly—never through a shell—
overlays declared environment bindings, polls readiness, and runs Hurl only after readiness
succeeds. Cleanup sends TERM to the service process group, escalates to KILL after the configured
timeout, and reaps the leader on success, failure, or interruption.

Use an existing server by skipping lifecycle ownership:

```bash
cabal run hurl-workbench-fixture-server -- --port 18080

cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite default --external-service
```

If a managed suite never becomes ready, run `list services` and check the executable, argv,
workspace-relative working directory, bound environment names, readiness URL/status, and port
availability. A connection refusal or wrong status is retried until the overall timeout; malformed
URLs and missing readiness executables fail immediately. If the service exits while tests run, the
workbench cancels active Hurl children and marks unfinished cases as prerequisite failures.


## Reports


Reports are opt-in and require `--report-dir`:

```bash
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite default --jobs 2 \
  --report junit --report json --report-dir build/reports
```

Each expanded run owns a directory such as
`build/reports/default/read-echo/`. JUnit uses `junit.xml`, HTML uses `html/`, JSON uses `json/`,
and TAP uses `report.tap`. `build/reports/default/summary.json` contains only logical names,
statuses, isolation policy, logical scenarios, durations, and relative report paths. Existing suite report trees are rejected; add
`--overwrite` to replace exactly that suite subtree.

Report metadata and summaries omit bindings, child environments, captured diagnostics, and
response bodies. Hurl reports and client response artifacts can still contain data returned by the
server, including echoed credentials, so store and retain the report root as sensitive output.


## Generated variables


Generated per-request inputs remain caller-prepared; suite setup and teardown are bounded lifecycle phases. When a request needs an external
signature or other generated input, run the dedicated helper first and have it write a standard
Hurl properties file:

```text
signed_body={"example":true}
signature=generated-value
```

Then pass it to the suite:

```bash
sign-request --output build/generated.env
cabal run hurl-workbench -- \
  --workspace path/to/hurl-workbench.dhall \
  test suite signed-ingestion --variables-file build/generated.env
```

Use `--secrets-file` or `--secret-env NAME=ENVIRONMENT_NAME` when a generated value is secret. Do
not place secret placeholders in readiness URLs; URLs accept declared plain parameters only.

## Explicit clean command environments

Service and readiness commands independently accept `environmentPolicy`. Omission and
`Schema.EnvironmentPolicy.Inherit` preserve the ambient environment. Opt into isolation with:

```dhall
environmentPolicy = Schema.EnvironmentPolicy.Clean [ "PGHOST", "PGPORT", "PGUSER", "PGDATABASE" ]
```

`Clean ([] : List Text)` selects no inherited variables. Explicit `environment` parameter
bindings are then added and override selected ambient values. Every selected inherited name
must exist, even if a binding overrides it; an empty value counts as present. Invalid or duplicate
names fail validation. Missing runtime names fail before either service or readiness starts,
identify only the command phase and variable names, and give suite exit 4. External-service mode
skips these unused managed-command policies.

There are no implicit PATH, HOME, locale, or platform variables. Select each needed name
explicitly. Resolve executable paths in the caller and use absolute paths for deterministic
startup. A child language runtime can add its own variables after launch; the policy controls
the environment passed to the executable. Command readiness uses its own policy and keeps the
same captured environment across retries. HTTP readiness and Hurl's environment filtering remain
separate contracts. Setup, teardown and named service lifecycle barriers use these same environment rules. Executable check steps remain separately planned.

The `clean` suite in `examples/integration-service/hurl-workbench.dhall` uses a selected PORT
that an explicit workspace binding overrides. Its readiness command starts with an empty
environment. Run it after building both executables:

```bash
export HURL_WORKBENCH_FIXTURE_EXECUTABLE="$(cabal list-bin hurl-workbench-fixture-server)"
export HURL_WORKBENCH_CURL_EXECUTABLE="$(command -v curl)"
PORT=1 cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall test suite clean
```

## Caller-owned PostgreSQL leases

`scripts/check-clean-environment-lease.sh` is an opt-in consumer driver. Run it inside an
already active lease with PGHOST, PGPORT, PGUSER, and PGDATABASE set, and with workbench,
Python, and psql available in the caller's PATH. Alternatively set
HURL_WORKBENCH_EXECUTABLE to the absolute built executable. If authentication requires a
password, supply a caller-owned protected PGPASSFILE; the driver explicitly selects its path
and never puts password bytes in arguments or reports. Keep that file until lease cleanup ends.
PGPASSWORD is not inherited by clean children.

```bash
export HURL_WORKBENCH_EXECUTABLE="$(cabal list-bin hurl-workbench)"
bash scripts/check-clean-environment-lease.sh
```

The service and readiness both query `current_database()` and `current_user` through psql and
privately check the supplied lease identity. The driver tests success, readiness failure, and
SIGINT cancellation, verifies consumer shutdown before returning, and prints three PASS lines.
The caller must then release the lease and independently verify that release. The driver does
not provision or release databases.

Normal example checks also run `scripts/check-clean-environment-lease-simulation.sh` with
a fake psql executable, both with and without a protected caller-owned PGPASSFILE. It
checks service and readiness PID shutdown and preserves that file for the caller.
This covers driver control flow and shutdown without allocating a database;
it cannot establish real lease access or release.

The supported wrapper from `mori://shinzui/hinagata/docs/user-documentation` is:

```bash
hinagata --config CONFIG db with --json -- bash scripts/check-clean-environment-lease.sh
```

For a reproducible real-provider check, `scripts/check-clean-environment-provider.py` starts
its own disposable PostgreSQL cluster with SCRAM password authentication. It runs three
separate `db with` leases, forwarding the workbench status to the owner after checking consumer
shutdown. Hinagata must return statuses 0, 4, and 130, report `LeaseReleased`, and expose
`Released` through `inspect`. The check independently verifies that each clone is absent from
`pg_database`, that the protected password file survives until the consumer returns, and that
Hinagata removes it on release. Password bytes never enter command arguments or printed output.
This opt-in check needs PostgreSQL tools, Hurl, a built workbench, and a built Hinagata executable.
Discover and build the provider first:

```bash
hinagata_root="$(mori path mori://shinzui/hinagata)"
(cd "$hinagata_root" && nix develop -c cabal build hinagata)
export HINAGATA_EXECUTABLE="$(cd "$hinagata_root" && nix develop -c cabal list-bin hinagata)"
# Source-tree builds need Hinagata's packaged SQL resources.
export hinagata_postgres_datadir="$hinagata_root/hinagata-postgres"
nix develop -c bash -c 'export HURL_WORKBENCH_EXECUTABLE="$(cabal list-bin hurl-workbench)"; python3 scripts/check-clean-environment-provider.py'
```

The provider harness internally invokes `hinagata --config CONFIG db with --json --` with a
Python callback that runs `bash scripts/check-clean-environment-lease.sh --mode MODE
--propagate-status`. The ordinary driver still runs all three modes and exits zero after
successful assertions; the optional flags select one mode and return its workbench status.

On 2026-11-12 UTC, this check passed on macOS with the provider at
`mori://shinzui/hinagata` commit `a0c1059743e5957e66e4b8cee9e485ad89471937`.
All three leases passed database access, consumer shutdown, release, database absence, and
password-file removal checks. Plan 8 records the acceptance evidence. Earlier registry failures
came from a stale inherited `MORI_PG_CONNECTION_STRING`; using the current endpoint from the
user's shell profile restored discovery without restarting PostgreSQL.

## Independent scenario handoff

A scenario is one expanded run: a direct workflow/recipe name or `matrix/case`. Declare
`isolation = Schema.IsolationPolicy.IndependentState` on the suite and omit `service`.
The caller provisions each fixture, starts its service, checks readiness and database identity,
and holds every lease until workbench returns after reaping Hurl children. It then stops its
services before releasing leases. Workbench only validates and consumes the handoff; it owns no
provider service or lease. Separate Hurl sessions alone do not establish application isolation.

Create the handoff once in a private temporary directory, with file mode `0600`. Pass its path
through `--scenario-inputs`, relative to the invocation directory or absolute. Version 1 requires
exactly these fields, including empty lists when unused; unknown fields and unsupported versions
are refused:

```json
{
  "version": 1,
  "scenarios": [
    {
      "scenario": "writes/first",
      "fixtureId": "caller-fixture-a",
      "endpoint": "http://127.0.0.1:18181",
      "endpointParameter": "baseUrl",
      "bindings": [{"parameter": "marker", "value": "first-marker"}],
      "secretEnvironment": [{"parameter": "token", "variable": "FIRST_TOKEN"}]
    },
    {
      "scenario": "writes/second",
      "fixtureId": "caller-fixture-b",
      "endpoint": "http://127.0.0.1:18182",
      "endpointParameter": "baseUrl",
      "bindings": [{"parameter": "marker", "value": "second-marker"}],
      "secretEnvironment": [{"parameter": "token", "variable": "SECOND_TOKEN"}]
    }
  ]
}
```

The example labels/identities/ports illustrate the shape; the provider must supply the actual
ready resources. Every expanded scenario must appear exactly once, with no extras, duplicate
fixture IDs, or duplicate endpoint origins. A fixture ID is opaque, nonempty private provider
metadata with no control characters. Endpoint origins compare lowercase scheme/host and effective
port: `http://EXAMPLE.test` and `http://example.test:80/` collide. Only root HTTP(S) endpoints are
accepted; userinfo, query, fragment, and non-root paths are refused. Distinct paths on one server
cannot establish independence.

The caller is trusted to describe real isolation truthfully. Workbench cannot prove that distinct
opaque IDs or DNS aliases lead to distinct databases. Verify provider database identity privately;
the acceptance driver corroborates HTTP observations with direct queries to both leased databases.
A failed or incomplete allocation must prevent invocation, and partial acquisition must release
all successfully acquired leases after consumers stop.

`endpointParameter` must name a declared Plain workflow parameter. `bindings` supplies additional
Plain literals; `secretEnvironment` names declared Secret parameters and environment variables,
resolved through the existing protected secret channel. Missing variables and invalid Hurl
literals fail preflight without printing values. A parameter may occur in only one handoff
channel. A handoff-supplied parameter cannot also occur in suite runtime overrides, variable or
secret files, or committed recipe/case bindings. Such conflicts fail rather than overriding the
provider. Valid explicit handoff values override declared defaults/environment fallback. Other
suite input retains ordinary precedence and per-workflow subset resolution.

All assignment and binding preparation finishes before scheduling Hurl. Cases use the ordinary
bounded worker pool, fail-fast, and declaration ordering. Standalone matrices have no independent
handoff; migrate shared writes to `--jobs 1 --allow-mutating`, or place independent cases in a
suite using this contract. See [the example](../../examples/integration-service/independent.dhall).

Workbench summaries contain isolation and logical scenario names, never fixture IDs, endpoint
URLs, binding/environment values or names, connection strings, provider errors, or captured output.
Safely reportable refusals have `status: refused`, stable `reasonCodes`, and `not-started` cases
with no invented Hurl exit or report artifacts. Missing runtime input uses `setup-failed`.
Unknown suites and unsafe/conflicting report destinations cannot receive a summary there.
Cancellation joins owned children, retains completed outcomes, writes a best-effort `cancelled`
summary with unfinished cases marked `cancelled`, then rethrows the interruption. It does not
release provider resources. Hurl-generated reports and response content remain sensitive.

## Real provider acceptance

Discover the provider with Mori, build its documented CLI, and provide its packaged SQL resources:

```bash
hinagata_root="$(mori path mori://shinzui/hinagata)"
(cd "$hinagata_root" && nix develop -c cabal build hinagata)
export HINAGATA_EXECUTABLE="$(cd "$hinagata_root" && nix develop -c cabal list-bin hinagata)"
export hinagata_postgres_datadir="$hinagata_root/hinagata-postgres"
nix develop -c bash -c 'export HURL_WORKBENCH_EXECUTABLE="$(cabal list-bin hurl-workbench)"; bash scripts/check-scenario-isolation.sh'
```

The driver requires `initdb`, `pg_ctl`, `psql`, Hurl, Python, and both built executables; missing
prerequisites fail clearly. It creates a private SCRAM-authenticated PostgreSQL cluster and invokes
`hinagata --config CONFIG db acquire --json` twice for each execution mode. Each returned
application connection goes only to its provider-owned service through explicit PG variables and
a protected password file. `/health` readiness follows private `current_database()` and
`current_user` checks. Both POSTs rendezvous after committing their different markers; a serial
implementation cannot pass the barrier. GET observations and independent database queries require
exactly one own marker in each database. POSTs are never retried.

After workbench returns and execution PID checks confirm Hurl children stopped, the driver stops
both services, then invokes `db release LEASE_ID --json` exactly once per acquired lease. It
checks `inspect LEASE_ID --json` for `Released` and corroborates database absence through
`pg_database`. A second-allocation failure (`db acquire --fixture absent --json`) never starts
consumers and still releases the first lease. The driver also checks duplicate/incomplete
handoffs, missing secret input, fail-fast, cancellation, and summary redaction. Every retry uses
fresh leases and services; it never touches application databases or substitutes an in-memory
service for a real database test.

On 2026-11-12 UTC, the early two-lease check passed against provider commit
`a0c1059743e5957e66e4b8cee9e485ad89471937` of `mori://shinzui/hinagata`. The complete driver
also passed success, Hurl failure, cancellation, and partial acquisition cleanup. Normal CI uses
`scripts/check-scenario-isolation-local.py` with two explicitly selected in-memory fixture servers,
plus public CLI/core tests; it requires no developer database credentials and does not replace
this real-provider evidence.

## Ordered services and lifecycle barriers

Use the [multi-service example](../../examples/multi-service/README.md) for an
API/stub/worker suite with setup, teardown and a named restart. Consecutive Hurl
runs form bounded batches; Stop/Start/Restart drain the preceding batch and finish
before the next begins. A worker restart repeats readiness and moves that service
to the newest cleanup position. All active leaders are monitored, including during
later startup. Unexpected death cancels active Hurl process groups and retains
completed case outcomes.

The example submits one mutation and polls only GET observations. Use jobs=1
for a shared mutating fixture. A separate read-only example proves jobs=2 barriers;
a barrier does not establish scenario isolation. Explicit Clean policies apply to
service/readiness/setup/teardown commands, using one preflight environment snapshot.

For real adoption use `scripts/check-multi-service-lease.sh` inside the caller's
existing lease and follow its [consumer evidence contract](../../examples/multi-service/README.md).
The driver checks success, readiness failure, unexpected exit and cancellation,
and confirms consumer PIDs have stopped. The caller releases the database only
after the driver returns and records that provider-side release evidence.
