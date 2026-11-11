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
