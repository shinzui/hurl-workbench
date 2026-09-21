# Vendor OData exploration example

This workspace mirrors a common third-party API investigation without containing vendor
credentials, hostnames, schemas, or response data. One OAuth client-credentials fragment feeds one
reusable OData-shaped query workflow. Recipes hold resource-family defaults, and the
`property-by-mls` matrix changes only market-specific data. The MLSPIN case intentionally uses a
sold-status filter instead of the generic closed-status filter.

The example targets the repository's local fixture server. From the repository root, start it:

```bash
cabal run hurl-workbench-fixture-server -- --port 18080
```

In another shell, inspect and execute the workspace:

```bash
cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall validate
cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall render recipe properties --explain
VENDOR_ODATA_CLIENT_SECRET=fixture-secret cabal run hurl-workbench -- \
  --workspace examples/vendor-odata/hurl-workbench.dhall \
  matrix property-by-mls --mode run --jobs 2 --output-dir build/vendor-odata \
  --variable baseUrl=http://127.0.0.1:18080
```

Responses are written beneath `build/vendor-odata/property-by-mls/` with owner-only permissions.
They are not guaranteed to be redacted; a remote service can echo secrets in a response body.
The matrix prints ordered summaries like:

```text
PASS  property-by-mls/northwest -> .../property-by-mls/northwest.response
PASS  property-by-mls/metro -> .../property-by-mls/metro.response
PASS  property-by-mls/mlspin-sold -> .../property-by-mls/mlspin-sold.response
```

`co-buyer-investigation` retains a custom capture/assertion chain, while
`raw-decoding-investigation` preserves an opaque response used to diagnose below a typed client.
They remain ordinary native Hurl workflows because turning one-off diagnostic semantics into schema
would make both the workbench and the investigation harder to review.

Run those special workflows directly against the same fixture service:

```bash
VENDOR_ODATA_CLIENT_SECRET=fixture-secret cabal run hurl-workbench -- \
  --workspace examples/vendor-odata/hurl-workbench.dhall \
  test workflow co-buyer-investigation \
  --variable baseUrl=http://127.0.0.1:18080 --variable clientId=fixture-client

cabal run hurl-workbench -- \
  --workspace examples/vendor-odata/hurl-workbench.dhall \
  test workflow raw-decoding-investigation \
  --variable baseUrl=http://127.0.0.1:18080
```
