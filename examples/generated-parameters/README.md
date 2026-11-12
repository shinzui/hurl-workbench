# Generated parameters

With the fixture server on port 18080, run from the repository root:

```bash
hurl-workbench --workspace examples/generated-parameters/hurl-workbench.dhall test recipe recipient
hurl-workbench --workspace examples/generated-parameters/hurl-workbench.dhall test recipe recipient --variable recipientId=rcp_01h2xcejqtf2nbrexx3vqjhp41
hurl-workbench --workspace examples/generated-parameters/hurl-workbench.dhall render recipe recipient --explain
```

The manifest shows all five generators. Each execution resolves its own values;
its two fragments share the same recipient ID. Runtime variables and variable
files override generation. Generated inputs cannot have committed defaults,
recipe bindings, or matrix bindings. Matrix `recipients` and suite `recipients`
can run with `--jobs 2` against the read-only echo endpoint.
