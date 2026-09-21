# hurl-workbench

`hurl-workbench` composes complete Hurl entries into reusable workflows, supplies plain and secret
parameters securely, and executes recipes, matrices, and integration suites through the official
Hurl binary. Hurl remains responsible for HTTP, captures, assertions, cookies, retries, and reports.

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
  lifecycle, safe and mutating suites, and isolated JUnit/JSON reports.

## Core model

A `hurl-workbench.dhall` manifest imports [`schema/package.dhall`](schema/package.dhall). Fragments
are ordinary `.hurl` files containing one or more complete entries. A workflow names fragments in
order; rendering preserves their bytes and inserts only the line feeds needed between them.
Recipes add committed plain bindings and an explicit safety class. Matrices layer named cases over
a recipe. Suites flatten workflows, recipes, and matrices and can own a managed service.

Without `--workspace`, discovery starts at the current directory and walks upward looking for
`hurl-workbench.dhall`. See the [workspace reference](docs/reference/workspace.md), [CLI
reference](docs/reference/cli.md), [architecture](docs/architecture.md), and [security
model](docs/security.md).

## Development

The repository contains `hurl-workbench-core` and `hurl-workbench-cli`, targets GHC 9.12.4, and
uses a Nix flake for the complete toolchain.

```bash
nix develop
cabal build all
cabal test all
nix fmt -- --ci
```

## License

[BSD-3-Clause](LICENSE) — © 2026 Nadeem Bitar.
