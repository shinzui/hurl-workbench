# Map repeated vendor experiments to reusable Hurl workbench runs


The motivating vendor playground contains thirteen related Hurl files. Most repeat the same OAuth
client-credentials exchange and then vary an MLS identifier, resource family, query projection,
ordering, result limit, or status filter. Hurl Workbench factors only that demonstrated repetition:

- `oauth-client-credentials.hurl` owns the authentication request and `accessToken` capture once;
- `odata-query.hurl` owns the common resource-query entry once;
- recipes such as `properties`, `members`, and `offices` commit reviewable ordinary defaults;
- `property-by-mls` applies named case overrides in declaration order, including the MLSPIN-specific
  sold-status filter;
- runtime `baseUrl` and `clientSecret` values stay outside committed configuration.

The complete fixture-backed workspace is in the repository-local
[`examples/vendor-odata/`](../../examples/vendor-odata/) directory. It is structurally analogous to
the experiments under the project-relative `playground/` tree in
`mori://tan/constellation1-client-hs/repos/constellation1-client-hs`; it does not copy that project's
credentials, endpoints, response bodies, or proprietary model.

## Inspect and run the local workspace

From the repository root inside `nix develop`, inspect the declarations and
render without reading credentials or generating runtime inputs:

```bash
cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall list
cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall validate
cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall render recipe properties --explain
```

Start `cabal run hurl-workbench-fixture-server -- --port 18080` in another
terminal, then run against that local fixture:

```bash
VENDOR_ODATA_CLIENT_SECRET=fixture-secret cabal run hurl-workbench -- \
  --workspace examples/vendor-odata/hurl-workbench.dhall \
  run recipe properties --variable baseUrl=http://127.0.0.1:18080 --variable top=5

VENDOR_ODATA_CLIENT_SECRET=fixture-secret cabal run hurl-workbench -- \
  --workspace examples/vendor-odata/hurl-workbench.dhall \
  matrix property-by-mls --mode run --jobs 2 \
  --variable baseUrl=http://127.0.0.1:18080 --output-dir build/vendor-responses
```

The fixture secret is only for the bundled local service. For a real endpoint,
supply your own credential through the declared environment source,
`--secret-env`, or `--secrets-file`. Plain runtime overrides win over variable
files, case bindings, recipe bindings, declared environment values, and defaults.
For assertions and a test summary, use `test recipe properties` or matrix
`--mode test` with the same runtime inputs.


## Keep special investigations special


Parameterization is useful only where the request shape is genuinely repeated. A co-buyer
investigation with a custom capture/assert chain remains a native multi-entry Hurl fragment. A
broken-decoding reproduction remains a raw-response workflow. Both still use the same renderer,
binding boundary, and Hurl runner, but neither requires a new workbench HTTP or assertion schema.

Direct workflow execution is the low-level escape hatch and is deliberately unclassified. Recipes
and matrices carry `ReadOnly` or `Mutating` metadata; mutating selections require
`--allow-mutating` on every invocation, and standalone mutating matrices also require
`--jobs 1`. Matrix cases use separate Hurl processes, so OAuth captures and cookies
do not cross case boundaries. These sessions do not establish application-state
isolation. Shared mutating suites require serial execution; parallel mutations
belong in a caller-provisioned [independent suite](integration-testing.md#independent-scenario-handoff).


## Output and concurrency


Matrices default to one worker. Parallel client mode requires `--output-dir`, which prevents final
response bodies from interleaving on stdout. Artifact names derive from validated matrix and case
names, existing files stop the batch unless `--overwrite` is explicit, directories use mode `0700`,
and files use mode `0600`. Treat the directory as sensitive: Hurl can redact declared secrets from
diagnostics, but a server-controlled response body can still echo them.

## Fresh inputs, body files, and semantic checks

Declare a Generated parameter when each execution needs a fresh UUID, TypeID,
timestamp, or random string. All fragments in that execution share the resolved
value; separate matrix cases generate independently. Reproduce a run with an
explicit `--variable` or variable file. Use a Plain parameter if several runs or
helper commands must share one value. See the
[generated-input example](../../examples/generated-parameters/README.md).

For signatures or other application-specific data, prepare inputs in the caller.
Pass properties through the appropriate plain/secret channel, or send exact body
bytes from a private directory using `--file-root DIR`. Keep output trees outside
an explicit body root and retain the input directory until execution ends. The
[file-body example](../../examples/file-body/README.md) proves UTF-8 and CRLF
preservation; fragment source paths still resolve from the workspace.

If an investigation needs an application CLI/API comparison, declare a named
executable Check in a suite. It runs alone between drained Hurl batches and
requires `--report-dir`; captures remain private files. See
[assertions beyond HTTP](integration-testing.md#assertions-beyond-http) for
parameter restrictions, deadlines, and a matching/mismatch proof. Use the
[capability catalog](../capabilities/index.md) to find the evidence and limits
behind these interfaces.
