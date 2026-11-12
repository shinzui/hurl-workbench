# hurl-workbench

`hurl-workbench` composes complete Hurl entries into reusable workflows, supplies plain and secret
parameters securely, and executes recipes, matrices, and integration suites through the official
Hurl binary. Suites can manage several services, generate fresh scenario inputs, read caller-owned
body files, and run application-owned executable assertions between Hurl batches. Hurl remains
responsible for HTTP, captures, assertions, cookies, retries, and reports.

Suites default to shared application state: parallel Hurl runs require ReadOnly recipes, and shared
writes require `--jobs 1 --allow-mutating`. Independent suites validate caller-provisioned
fixture/endpoint assignments through `--scenario-inputs`; the caller establishes actual isolation.
See the [integration guide](docs/guides/integration-testing.md).

## Five-minute quick start

Enter the pinned development environment and inspect the interface:

```bash
nix develop
cabal run hurl-workbench -- --help
cabal run hurl-workbench -- doctor
```

The small workspace in [`examples/quick-start/`](examples/quick-start/) defines one `health`
fragment and workflow against the bundled Dhall schema. Its token is a secret parameter sourced
from `QUICKSTART_TOKEN`; no credential is committed. Inspect, validate, and render it:

```bash
sed -n '1,240p' examples/quick-start/hurl-workbench.dhall
cabal run hurl-workbench -- --workspace examples/quick-start/hurl-workbench.dhall validate
cabal run hurl-workbench -- --workspace examples/quick-start/hurl-workbench.dhall render workflow health
```

Start the local fixture API in one terminal:

```bash
cabal run hurl-workbench-fixture-server -- --port 18080
```

Run the workflow from another terminal with an environment-backed fixture secret:

```bash
QUICKSTART_TOKEN=fixture-secret cabal run hurl-workbench -- \
  --workspace examples/quick-start/hurl-workbench.dhall \
  test workflow health
```

The expected result is a passing Hurl test summary. For full workflows, continue with:

- [`examples/vendor-odata/`](examples/vendor-odata/) — one OAuth capture reused by OData-shaped
  recipes and a bounded matrix, plus bespoke capture and raw-response investigations;
- [`examples/integration-service/`](examples/integration-service/) — managed fixture-service
  lifecycle, safe and mutating suites, clean command environments, and isolated reports;
- [`examples/multi-service/`](examples/multi-service/) — ordered stub/API/worker startup,
  setup/teardown, and worker restart barriers;
- [`examples/generated-parameters/`](examples/generated-parameters/) — fresh UUID, TypeID,
  timestamp, and random inputs with reproducible overrides;
- [`examples/file-body/`](examples/file-body/) — caller-generated UTF-8/CRLF request bodies
  passed unchanged through `--file-root`;
- [`examples/executable-checks/`](examples/executable-checks/) — CLI/API parity assertions
  between Hurl runs, including a deliberately failing comparison.

## Core model

A `hurl-workbench.dhall` manifest imports [`schema/package.dhall`](schema/package.dhall). Fragments
are ordinary `.hurl` files containing one or more complete entries. A workflow names fragments in
order; rendering preserves their bytes and inserts only the line feeds needed between them.
Recipes add committed plain bindings and an explicit safety class. Matrices layer named cases over
a recipe. Suites execute bounded Hurl batches separated by executable checks or named service
Stop/Start/Restart barriers. Services become ready in declaration order and stop in reverse
acquisition order before bounded teardown, including on failure and cancellation.

Plain, Secret, and Generated parameters have separate binding rules. Generated values resolve
once per prepared Hurl execution; explicit runtime values reproduce a prior run. Use Plain inputs
when setup, checks, and several Hurl runs must share an identity. Command environments can inherit
ambient variables or explicitly select names through `EnvironmentPolicy.Clean`.

Execution commands accept `--file-root DIR`; suites can also name a Plain `fileRootParameter`.
The caller keeps body files alive until execution ends. Keep report and output trees outside an
explicit body root. A suite with executable checks requires `--report-dir`; captured check output
stays in private files while the summary records named outcomes and relative paths.

Without `--workspace`, discovery starts at the current directory and walks upward looking for
`hurl-workbench.dhall`. See the [workspace reference](docs/reference/workspace.md), [CLI
reference](docs/reference/cli.md), [architecture](docs/architecture.md), and [security
model](docs/security.md). The [guide index](docs/guides/index.md) maps tasks to examples, and the
[OKF capability catalog](docs/capabilities/index.md) records implemented contracts, evidence, and
limits with stable `CAP-N` handles. These capabilities are currently unreleased and experimental.

## Development

The repository contains `hurl-workbench-core` and `hurl-workbench-cli`, targets GHC 9.12.4, and
uses a Nix flake for the complete toolchain.

```bash
nix develop
just check
```

`just check` initializes Cabal's Hackage index, whose solver view is pinned by
`cabal.project`, then runs formatting, builds, tests, local examples, source-distribution
checks, and the Nix flake gate. On a Mac with Apple `container` installed and its system
service running, `just linux-check` runs that same gate in a disposable ARM64 Linux VM.
Local examples include multi-service orchestration, file-body byte preservation, generated-input
overrides, and matching/failing executable checks. Real application and database lease acceptance
uses opt-in caller harnesses documented in the integration guide.

Release source archives use `bash scripts/build-sdist.sh`; this wrapper preserves executable modes
for the declared check helpers. `just sdist` verifies the unpacked archives and their examples.

## License

[BSD-3-Clause](LICENSE) — © 2026 Nadeem Bitar.
