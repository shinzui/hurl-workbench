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


## Keep special investigations special


Parameterization is useful only where the request shape is genuinely repeated. A co-buyer
investigation with a custom capture/assert chain remains a native multi-entry Hurl fragment. A
broken-decoding reproduction remains a raw-response workflow. Both still use the same renderer,
binding boundary, and Hurl runner, but neither requires a new workbench HTTP or assertion schema.

Direct workflow execution is the low-level escape hatch and is deliberately unclassified. Recipes
and matrices carry `ReadOnly` or `Mutating` metadata; mutating selections require
`--allow-mutating` on every invocation. Matrix cases are independent Hurl processes, so OAuth
captures and cookies do not cross case boundaries.


## Output and concurrency


Matrices default to one worker. Parallel client mode requires `--output-dir`, which prevents final
response bodies from interleaving on stdout. Artifact names derive from validated matrix and case
names, existing files stop the batch unless `--overwrite` is explicit, directories use mode `0700`,
and files use mode `0600`. Treat the directory as sensitive: Hurl can redact declared secrets from
diagnostics, but a server-controlled response body can still echo them.
