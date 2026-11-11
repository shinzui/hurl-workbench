# Integration testing with managed suites


A suite is a reviewed list of workflows, recipes, and matrices. `test suite` resolves every run,
binding, safety classification, report path, and service input before it starts a process. This
makes suites suitable for unattended checks while keeping state-changing and perimeter scenarios
deliberately separate.


## Safe defaults and explicit writes


Put only `ReadOnly` recipes in the default suite. A `Mutating` recipe and a direct workflow both
require `--allow-mutating`; direct workflows are unclassified because they have no recipe safety
declaration. Keep auth, CORS, network-perimeter, and other environment-sensitive checks in named
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
statuses, durations, and relative report paths. Existing suite report trees are rejected; add
`--overwrite` to replace exactly that suite subtree.

Report metadata and summaries omit bindings, child environments, captured diagnostics, and
response bodies. Hurl reports and client response artifacts can still contain data returned by the
server, including echoed credentials, so store and retain the report root as sensitive output.


## Generated variables


Arbitrary pre/post hooks are intentionally outside the workbench. When a request needs an external
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
separate contracts. Lifecycle hooks and executable checks are not currently implemented.

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
a fake psql executable. This covers driver control flow and shutdown without allocating a
database; it cannot establish real lease access or release.

Real Hinagata acceptance remains pending: `mori registry search hinagata` currently fails
because the registry's local PostgreSQL socket refuses connections. No supported provider
wrapper invocation or observed provider release is claimed here. Once registry access is
restored, discover the interface using `mori registry show shinzui/hinagata --full` and
`mori registry docs shinzui/hinagata`, run the driver inside that supported lease scope, and
record the exact invocation and release evidence in plan 8.
