# Workspace reference

A workspace is a Dhall record stored in `hurl-workbench.dhall`. Import the versioned package with a
path appropriate to the manifest and use record completion so future optional fields receive
defaults:

```dhall
let Schema = ../../schema/package.dhall

in  Schema.Workspace::{
    , schemaVersion = Schema.schemaVersion
    , fragments = [ Schema.Fragment::{ name = "health", path = "health.hurl" } ]
    , workflows = [ Schema.Workflow::{ name = "health", fragments = [ "health" ] } ]
    }
```

Every record module exports `Type` and `default`; union modules are used directly. The supported
schema version is `1`.

## Top-level fields

| Field | Type | Default | Meaning |
|---|---|---:|---|
| `schemaVersion` | `Natural` | required | Must equal `Schema.schemaVersion`. |
| `parameters` | `List Parameter.Type` | `[]` | External Hurl variables. |
| `fragments` | `List Fragment.Type` | `[]` | Named `.hurl` source files. |
| `workflows` | `List Workflow.Type` | `[]` | Ordered fragment compositions. |
| `recipes` | `List Recipe.Type` | `[]` | Workflow, committed bindings, and safety. |
| `matrices` | `List Matrix.Type` | `[]` | Named case layers over one recipe. |
| `services` | `List Service.Type` | `[]` | Managed processes and readiness checks. |
| `suites` | `List Suite.Type` | `[]` | Non-empty run collections and optional service. |

## Record fields

All `description` fields are `Optional Text` and default to `None Text`.

- `Parameter`: `name`; `kind` (`Plain` by default, `Secret`, or `Generated`); optional `defaultValue`; optional
  `environment`. Secrets cannot have committed defaults.
- `Fragment`: `name`, workspace-relative `path`, optional `description`. The path must end in
  `.hurl`, resolve to a regular file, and remain inside the workspace root after symlinks are
  resolved.
- `Workflow`: `name`, non-empty ordered `fragments`, `parameters` (default `[]`), and description.
  References must exist and cannot repeat within their list.
- `Binding`: `parameter`, `value`. Committed bindings are plain only.
- `Recipe`: `name`, `workflow`, `bindings` (default `[]`), required `safety` (`ReadOnly` or
  `Mutating`), and description.
- `MatrixCase`: `name`, `bindings` (default `[]`).
- `Matrix`: `name`, `recipe`, non-empty `cases`, `failFast` (default `False`), and description.
- `EnvironmentBinding`: child-process `variable` and workspace `parameter`.
- `CommandSpec`: `executable`, `arguments` (default `[]`), optional workspace-relative
  `workingDirectory`, and `environment` bindings (default `[]`). Commands are executable plus argv;
  there is no shell-string form.
- `HttpReadiness`: `url`, `expectedStatus` (default `200`), `intervalMilliseconds` (default `500`),
  `timeoutSeconds` (default `30`). Only plain `{{parameter}}` substitutions are accepted in URLs.
- `CommandReadiness`: `command`, `intervalMilliseconds` (default `500`), `timeoutSeconds` (default
  `30`).
- `Service`: `name`, `command`, `readiness` (`Http` or `Command`), `shutdownTimeoutSeconds`
  (default `10`), and description.
- `ServiceStep`: `Stop Text`, `Start Text`, or `Restart Text`.
- `RunReference`: `Workflow Text`, `Recipe Text`, `Matrix Text`, or `Service ServiceStep`.
- `IsolationPolicy`: `SharedState` or `IndependentState`.
- `Suite`: optional `fileRootParameter` (default `None Text`), `name`, non-empty Hurl `runs` (with optional lifecycle steps), optional `service`, ordered `services` (default `[]`), `setup` and `teardown` command lists (default `[]`), positive `commandTimeoutSeconds` (default `60`) and `cleanupTimeoutSeconds` (default `30`), `isolation` (default `SharedState`),
  `failFast` (default `False`), and description. IndependentState cannot declare a managed service
  and requires a verified runtime handoff at execution.

## Names, paths, and references

Fragment, workflow, recipe, matrix, case, service, and suite names match
`[A-Za-z][A-Za-z0-9._-]*`. Parameter names match `[A-Za-z_][A-Za-z0-9_-]*` and cannot be Hurl's
reserved template functions `getEnv`, `newDate`, or `newUuid`. Environment variable names match
`[A-Za-z_][A-Za-z0-9_]*`. Names are unique within their category.

All references are category-specific: a recipe name cannot stand in for a workflow name. The
validator reports every unresolved reference in stable order. Fragment and command working paths
are relative to the directory containing the manifest, cannot escape that root, and are checked
after canonicalizing symlinks.

## Binding precedence

Plain values use the first available source in this order:

1. repeated `--variable NAME=VALUE` overrides;
2. `--variables-file` values, with later files winning;
3. matrix-case binding, then recipe binding;
4. the parameter's declared environment variable;
5. `defaultValue`.

Secrets use `--secret-env`, then `--secrets-file` (later files win), then the parameter's declared
environment. Plain values cannot enter a secret channel and secret values cannot enter a plain
channel. A selected workflow must receive every declared parameter, and standalone commands reject
bindings not used by that selection. Suite preflight permits a shared runtime input to contain
values for different suite members, while each member still resolves only its own parameters.

Values transported in Hurl properties files cannot contain a line break or NUL and cannot have
leading or trailing whitespace that Hurl would trim.

## Compatible evolution

Use `Schema.Workspace::{ ... }` and the per-record `Schema.X::{ ... }` completion forms. Lists and
optional descriptive fields have defaults so adding compatible optional categories or fields does
not break older manifests. `schemaVersion` remains explicit and unsupported versions are rejected
before typed decoding. The repository tests an original-field-only completion fixture against an
equivalent fully specified manifest.

Missing suite isolation fields in schema-version-1 evaluated records and empty suite-list types
are normalized to SharedState. Explicit invalid policies still fail typed decoding. Independent
handoff bindings have their own conflict rules, documented in the
[integration guide](../guides/integration-testing.md#independent-scenario-handoff).

## Ordered suite lifecycles

Use `services = [ "stub", "api", "worker" ]` for ordered acquisition. Each
service must become ready before the next starts. `service = Some "api"` remains
single-service sugar; supplying both forms is an error. Duplicate service names
and references outside the suite are rejected.

`RunReference.Service (ServiceStep.Restart "worker")` is a barrier: every earlier
Hurl case finishes before restart, readiness repeats, and later cases start only
after it finishes. Stop requires a running member; Start requires a stopped
member; Restart requires a running member. The entire transition sequence is
validated before setup. Ordinary Hurl failures allow later batches under
keep-going; a lifecycle failure always aborts the remaining sequence.

Setup runs in declaration order before acquisition. Teardown runs in declaration
order after reverse process-group cleanup, including setup failure and
cancellation. A timed-out collective cleanup budget skips the remaining teardown
commands. Phase commands require exit zero, have closed stdin, and share the
suite-level binding and environment rules. Teardown must tolerate partial setup.
No lifecycle operation or mutating request is retried automatically.

The version-1 compatibility conversion adds only missing fields and widens the
known old Hurl union, including explicit empty-list type annotations. Both the
original and converted expressions are typechecked; explicit malformed values or
unknown fields remain errors. Frozen compatibility manifests are unchanged.

## Generated inputs

Use `Schema.ParameterKind.Generated` with `Schema.Generator.Uuid4`, `Uuid7`,
`TypeId { prefix = "rcp" }`, `Rfc3339Now`, or `RandomAlphanumeric { length = 24 }`.
See [the complete example](../../examples/generated-parameters/hurl-workbench.dhall).
TypeID prefixes may be empty, or contain up to 63 lowercase ASCII letters and
underscores with a letter at each end. Random string length is 1..4096.

Generated inputs reject committed defaults, recipe bindings, and matrix bindings.
Runtime resolution uses explicit `--variable`, then later variable files, then a
declared environment variable, then generation. A missing declared environment
is an error unless a higher-priority binding wins. Secret channels are invalid.
Each prepared Hurl execution resolves a name once, shared by all its fragments and
retries. Matrix cases and suite Hurl runs generate independently. Suite commands
and readiness URLs cannot consume Generated inputs; use Plain inputs to share an
identity across executions. Schema version 1 still accepts legacy Plain/Secret
unions, including empty typed parameter lists.

## Suite body directory parameter

`Suite.fileRootParameter : Optional Text` names a declared Plain parameter. It selects Hurl's
file request-body base once for every Hurl run in the suite, using suite-wide bindings only.
Recipe and matrix-case values cannot select it. Relative values use the workspace root;
CLI `--file-root` overrides the parameter, resolving relative to the invocation directory.
Static validation checks the reference and kind without reading the directory or requiring a
runtime value. Secret and Generated parameters cannot select paths exposed to Hurl argv.
Old schema-version-1 records, including empty suite list annotations, decode with `None`.
Fragment paths and rendered source are unaffected.
