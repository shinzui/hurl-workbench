# Executable check barriers

`parity` runs a read-only Hurl recipe, the application-owned `parity.py` assertion,
and another read-only recipe. The assertion invokes the example application's
supported CLI and HTTP facts interfaces against separately provisioned fixtures.
Plain inputs identify the fixtures; a Secret parameter reaches the helper only as
`PARITY_TOKEN`. Its Clean policy selects PATH and excludes ambient database and
service settings. `parity-mismatch` changes only the HTTP fixture through its
supported API, then proves that the same assertion fails.

From the repository root, inside `nix develop`, run:

```bash
cabal build all
HURL_WORKBENCH_EXECUTABLE="$(cabal list-bin hurl-workbench)" \
  python3 scripts/check-command-parity-local.py
```

The caller creates two private fixture directories, starts their HTTP service,
runs the matching suite at jobs=2 and the mutating mismatch suite serially, verifies
named summary outcomes and a secret sentinel, then stops the service and removes
the fixtures. This also runs under `just examples`.

For manual use, provision separate CLI and HTTP fixture roots containing
`facts.json` arrays of `{ "key": "...", "value": "..." }` facts. Start the API
with `PARITY_TOKEN` supplied privately in its environment:

```bash
python3 examples/executable-checks/app.py serve /private/http-fixture 18081
hurl-workbench --workspace examples/executable-checks/hurl-workbench.dhall \
  test suite parity --jobs 2 --report-dir /private/new-reports \
  --variable cliFixture=/private/cli-fixture --variable apiUrl=http://127.0.0.1:18081 \
  --variable cliFixtureId=cli-scope --variable apiFixtureId=http-scope
```

The workbench invocation needs the same private `PARITY_TOKEN` environment source.
It refuses an existing suite report tree unless overwrite is explicit. Private
stdout/stderr live at `REPORT/SUITE/checks/parity/`; they may contain credentials
printed by a helper. Only logical status, timing, exit codes and relative paths
enter the summary. Checks-only suites are also supported.

The [Rei consumer](rei/README.md) supplies actual application evidence beyond this
small local example. Neither check replaces package/schema/client release gates.
