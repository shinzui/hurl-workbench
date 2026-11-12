# Caller-owned request body files

`request.hurl` reads `file,request.json;` without generating files in the workspace.
Start the repository fixture server on loopback port 18080, then run from the repository root:

```bash
payload_root="$(mktemp -d)"
trap 'rm -rf "$payload_root"' EXIT
printf '{"message":"雪"}\r\n' > "$payload_root/request.json"
hurl-workbench --workspace examples/file-body/hurl-workbench.dhall \
  run workflow send-body --file-root "$payload_root" > "$payload_root.response"
cmp "$payload_root/request.json" "$payload_root.response"
hurl-workbench --workspace examples/file-body/hurl-workbench.dhall \
  test workflow send-body --file-root "$payload_root"
rm "$payload_root.response"
```

The echo endpoint returns the raw bytes, so `cmp` verifies UTF-8, CRLF, and the final newline.
`nix develop -c just examples` starts the fixture automatically and runs this comparison.

The caller creates, keeps readable/searchable, and eventually deletes the body directory.
Keep it alive until workbench and its Hurl children exit. Workbench never creates, changes
permissions on, or removes these inputs, including after failure or interruption. Separate
invocations can use the same filename with different bytes in separate roots.

`--file-root DIR` is relative to the invocation directory and overrides any suite setting.
For a suite alternative, run `test suite parameter --allow-mutating --variable
payloadRoot=/absolute/payload/directory`. Its `fileRootParameter = Some "payloadRoot"`
resolves a declared Plain parameter once from suite-wide CLI values, variable files,
environment, or defaults. Relative parameter values use the workspace directory.
Inspection requires no runtime value. The CLI override also works without supplying the
shadowed parameter.

Explicit roots and response/report/curl output trees must be disjoint, including aliases.
Keep reports outside the body root. Explicitly selecting the workspace itself applies this
stronger rule; omitting the option preserves ordinary workspace-local reports.
Fragment sources still resolve inside the workspace. This option changes Hurl's body-file
base and does not confine arbitrary paths authored in Hurl.
