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

- `Parameter`: `name`; `kind` (`Plain` by default or `Secret`); optional `defaultValue`; optional
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
- `RunReference`: `Workflow Text`, `Recipe Text`, or `Matrix Text`.
- `Suite`: `name`, non-empty `runs`, optional `service`, `failFast` (default `False`), and
  description.

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
