# Managed integration-service example


This workspace uses the repository fixture API to demonstrate the complete suite lifecycle. The
`default` suite contains only explicit read-only recipes, `writes` contains the opt-in mutating
recipe, and `perimeter` keeps a negative boundary check separate from ordinary functional tests.

From the repository root:

```bash
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite default --report junit --report json --report-dir build/reports
```

The workbench starts the fixture server through Cabal, waits for `/health`, runs both safe recipes,
writes isolated reports plus `summary.json`, and terminates the service process group. The write
suite is refused unless authorization is explicit:

The stderr result has this shape (durations and absolute paths vary):

```text
PASS  health
PASS  read-echo
SERVICE stopped
SUMMARY .../build/reports/default/summary.json
```

```bash
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall test suite writes

cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite writes --allow-mutating
```

To use an already-running fixture server, start `hurl-workbench-fixture-server` separately and add
`--external-service`. See [the integration-testing guide](../../docs/guides/integration-testing.md)
for report layout, generated variable files, and troubleshooting.

The `perimeter` suite is deliberately separate from normal functional checks:

```bash
cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall \
  test suite perimeter
```

The `clean` suite opts into explicit environment selection. Build the workbench and fixture,
then run:

```bash
export HURL_WORKBENCH_FIXTURE_EXECUTABLE="$(cabal list-bin hurl-workbench-fixture-server)"
export HURL_WORKBENCH_CURL_EXECUTABLE="$(command -v curl)"
PORT=1 cabal run hurl-workbench -- \
  --workspace examples/integration-service/hurl-workbench.dhall test suite clean
```

The service selects PORT and overrides it through the `service_port` binding; the fixture
asserts PORT is its only inherited variable. Readiness has its own empty clean policy. Neither
command implicitly receives PATH or HOME. Use absolute executable paths; select any additional
names explicitly. Missing selected names fail before service startup, even if overridden by a
binding. Other suites retain default inheritance. Child output and Hurl artifacts can still
contain data intentionally emitted by those programs.

For a caller-owned database lease, explicitly select its PG variables and protected PGPASSFILE
when needed; keep the password file until consumer cleanup and lease release finish.

## Independent scenarios

Shared-state writes use `--jobs 1 --allow-mutating`; requesting more jobs is refused even
with one expanded run. The read-only default suite can use `--jobs 2`.

`independent.dhall` declares an `IndependentState` suite with two mutating cases. A trusted
caller must provision one ready service and fixture per scenario, hold both until workbench
returns, and generate a private version-1 JSON handoff. Each assignment names `writes/first`
or `writes/second`, a distinct fixture ID, a distinct HTTP(S) endpoint origin, `baseUrl` as the
endpoint parameter, a plain `marker` binding, and a `token` secret-environment reference.
All channels are required, including empty lists when unused. See the
[integration guide](../../docs/guides/integration-testing.md#independent-scenario-handoff) for the full JSON contract.

After provisioning and generating `scenario-inputs.json` with mode `0600` in a private directory:

```bash
cabal run hurl-workbench -- \
  --workspace examples/integration-service/independent.dhall \
  test suite independent-writes --external-service \
  --scenario-inputs scenario-inputs.json --allow-mutating --jobs 2 \
  --report json --report-dir build/independent-reports
```

This fixture expects a POST/GET `/markers` service. The acceptance driver provisions two
fresh real Hinagata databases and one such service per database, then proves concurrent writes,
read isolation, refusal, fail-fast, cancellation, and caller-owned release:

```bash
bash scripts/check-scenario-isolation.sh
```

Run it in a development shell with PostgreSQL tools, built workbench and Hinagata executables,
and the provider's packaged SQL resources. The [integration guide](../../docs/guides/integration-testing.md#real-provider-acceptance)
gives the complete setup. Workbench never acquires or releases the databases.
