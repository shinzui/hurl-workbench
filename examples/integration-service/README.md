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
