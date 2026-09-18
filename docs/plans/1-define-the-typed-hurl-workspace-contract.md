---
id: 1
slug: define-the-typed-hurl-workspace-contract
title: "Define the Typed Hurl Workspace Contract"
kind: exec-plan
created_at: 2026-07-30T23:31:53Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
provenance:
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-18T18:29:32Z
      mode: "update"
      note: "Tightened workspace decoding, validation, name, value, and Haskell Jitsurei contracts before implementation."
---

# Define the Typed Hurl Workspace Contract


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture


This plan establishes the stable input boundary for every later feature. After it is
complete, a user can place `hurl-workbench.dhall` beside Hurl fragments, run
`hurl-workbench validate`, and get either a success message or contextual errors for
duplicate names, unsafe paths, invalid parameter contracts, or broken references. The
user can also run `hurl-workbench list` to inspect the named objects in the workspace.

The workspace describes existing Hurl source; it does not describe HTTP methods, URLs,
bodies, captures, or assertions. Those remain in `.hurl` files.


## Progress


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


## Decision Log


- Decision: Decode a fully normalized, versioned Dhall record into Haskell and publish
  record-completion defaults for user-authored values.
  Rationale: Dhall imports give workspaces typed reuse while the completion pattern lets
  later optional fields acquire defaults without requiring every existing workspace to
  spell them out.
  Date: 2026-07-30

- Decision: Use named lists in Dhall and build maps only after decoding.
  Rationale: Lists are straightforward to author and decode, while the semantic validator
  can report duplicate names instead of silently overwriting them.
  Date: 2026-07-30

- Decision: Discover only `hurl-workbench.dhall` in the current directory or its parents
  unless `--workspace` is supplied.
  Rationale: This mirrors project-root discovery without introducing implicit user-global
  configuration or surprising remote lookup.
  Date: 2026-07-30

- Decision: Make `ValidatedWorkspace` opaque and give every entity category its own name
  newtype.
  Rationale: Later libraries should not be able to skip semantic validation accidentally or
  pass a recipe, matrix, service, or suite name where a workflow name is required merely
  because all names happen to contain `Text`.
  Date: 2026-09-18

- Decision: Model committed and runtime plain values as `HurlValueLiteral`, not arbitrary
  `Text`.
  Rationale: Hurl 8 variable files infer booleans, nulls, integers, and floats, trim whole
  lines, and split at the first `=`. Naming this contract and rejecting CR, LF, NUL, and
  leading/trailing whitespace prevents a value from silently changing during secure file
  transport.
  Date: 2026-09-18


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


The repository currently has two Cabal packages. `hurl-workbench-core` exposes only
`HurlWorkbench.Prelude`; it is the correct home for normalized domain values, loading,
discovery, and validation. `hurl-workbench-cli` exposes `HurlWorkbench.Cli` and has one
placeholder `hello` command. `cabal.project` enables tests, but neither package has a test
suite. The clean baseline is `cabal build all` with GHC 9.12.4; Cabal currently warns that
package-local `license-file` and `extra-doc-files` paths point outside the package roots.
Those packaging warnings are recorded for EP-6 and are not part of this plan.

There is no local `docs/adr/` directory, and Mori returned no relevant cross-repository ADR
for Hurl, API integration testing, or CLI architecture. The Dhall dependency is
`mori://dhall-lang/dhall-haskell/packages/dhall`; its schema-evolution guidance is
`mori://dhall-lang/dhall-haskell/docs/dhall-schema-evolution-pattern`. That guidance
explains why adding record fields is breaking unless user input is normalized through
defaults. Hackage publishes `dhall` 1.42.3, and the Mori-located 1.42 source confirms that
`inputFileWithSettings` accepts `EvaluateSettings`, not `InputSettings`.

Implementation follows `mori://shinzui/haskell-jitsurei/docs/core-standards`,
`mori://shinzui/haskell-jitsurei/docs/core-custom-prelude`, and
`mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. The existing Cabal common
stanzas already select GHC2024 and the baseline extensions. EP-1 must correct
`HurlWorkbench.Prelude` into the documented small package-qualified re-export module,
enable `PackageImports` only in that module, keep `Data.Generics.Labels ()` out of the
prelude, use strict record fields and explicit deriving strategies, and use postpositive
`qualified` imports. Modules that actually use `#field` import `Data.Generics.Labels ()`
themselves.

In this plan, a *fragment* is a file containing one or more complete Hurl entries. A
*workflow* is an ordered list of fragment names. A *parameter* declares an externally
injected Hurl variable and whether it is secret. A *recipe* binds non-secret defaults to a
workflow. A *matrix* applies a recipe to multiple binding sets. A *service* describes one
managed process. A *suite* is a named collection of workflow, recipe, or matrix runs.
Later plans implement the behavior of these higher-level values, but this plan defines and
validates their shared representation once.


## Plan of Work


### Milestone 1: Publish the versioned Dhall schema and Haskell domain model


Add `schema/package.dhall` and one module per public value under `schema/`: `Workspace.dhall`,
`Parameter.dhall`, `Fragment.dhall`, `Workflow.dhall`, `Binding.dhall`, `Recipe.dhall`,
`Matrix.dhall`, `Service.dhall`, and `Suite.dhall`. Every record module exports `Type`,
`default`, and a completion-compatible value so examples can use expressions such as
`Schema.Fragment::{ name = "oauth", path = "hurl/oauth.hurl" }`. Keep the schema in this
repository and import it by a relative path; do not require network imports.

The normalized `Workspace.Type` has these fields:

```dhall
{ schemaVersion : Natural
, parameters : List Parameter.Type
, fragments : List Fragment.Type
, workflows : List Workflow.Type
, recipes : List Recipe.Type
, matrices : List Matrix.Type
, services : List Service.Type
, suites : List Suite.Type
}
```

Use these value contracts:

- `Parameter` has `name`, optional `description`, `kind` (`Plain` or `Secret`), optional
  non-secret `default`, and optional `environment` source name. A secret may have an
  environment source but may never have a literal default.
- `Fragment` has `name`, `path`, and optional `description`.
- `Workflow` has `name`, an ordered non-empty list of fragment names, a list of parameter
  names, and optional `description`.
- `Binding` has `parameter` and `value`; it is valid only for a plain parameter.
- `Recipe` has `name`, `workflow`, `bindings`, `safety` (`ReadOnly` or `Mutating`), and
  optional `description`.
- `MatrixCase` has `name` and `bindings`. `Matrix` has `name`, `recipe`, a non-empty list
  of cases, `failFast`, and optional `description`.
- `CommandSpec` has `executable`, `arguments`, optional `workingDirectory`, and a list of
  environment bindings from child environment name to workspace parameter name. No field
  accepts a shell command string.
- `Readiness` is either `Http` with URL, expected status, interval milliseconds, and
  timeout seconds, or `Command` with a `CommandSpec`, interval, and timeout.
- `Service` has `name`, a `CommandSpec`, `readiness`, and `shutdownTimeoutSeconds`.
- `RunReference` is a Dhall union of `Workflow Text`, `Recipe Text`, or `Matrix Text`.
  `Suite` has `name`, non-empty `runs`, optional `service`, `failFast`, and optional
  `description`.

Add corresponding strict records with `Generic` and explicit deriving strategies to
`hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs`. Use distinct newtypes for
`ParameterName`, `FragmentName`, `WorkflowName`, `RecipeName`, `MatrixName`,
`MatrixCaseName`, `ServiceName`, `SuiteName`, and `WorkspaceRoot`. Do not use one generic
`EntityName`; category-specific types make cross-category mistakes unrepresentable. Define
`HurlValueLiteral` for plain binding values. Its smart constructor rejects embedded CR,
LF, or NUL and leading or trailing whitespace, while permitting the first-`=` split used
by Hurl. Document that the remaining text uses Hurl 8 inference (`true`, `false`, `null`,
integer, float, quoted string, or ordinary string). Secret values remain opaque runtime
values and never inhabit the Dhall model.

First bring `hurl-workbench-core/src/HurlWorkbench/Prelude.hs` into conformance with the
Haskell Jitsurei custom-prelude pattern. Re-export only genuinely common types/functions
and `Control.Lens`; remove blanket `Data.Generics.Product`/`Data.Generics.Sum` re-exports,
use package-qualified imports in that module, and never import `Data.Generics.Labels` from
it. Add `HurlWorkbench.Workspace.Decode` with `FromDhall` instances and:

```haskell
decodeWorkspaceFile
  :: FilePath
  -> IO (Either WorkspaceError Workspace)
```

Decode with `Dhall.inputFile Dhall.auto`; in Dhall 1.42 this delegates to
`inputFileWithSettings defaultEvaluateSettings` and sets the import root to the manifest's
directory. If custom evaluation settings become necessary, pass
`Dhall.defaultEvaluateSettings`, never `defaultInputSettings`. Do not add a fallback
JSON/YAML parser. Normalize parse, import, type, and decode failures into
`WorkspaceError`; do not catch asynchronous exceptions.

Add `HurlWorkbench.Workspace.Context` with:

```haskell
data WorkspaceContext = WorkspaceContext
  { manifestPath :: !FilePath
  , workspaceRoot :: !WorkspaceRoot
  , workspace :: !Workspace
  }
  deriving stock (Generic, Eq, Show)

data ValidatedWorkspace

loadWorkspaceContext
  :: WorkspaceSource
  -> IO (Either WorkspaceError WorkspaceContext)
```

Keep the `ValidatedWorkspace` constructor internal. It contains the context plus indexed
maps for every category, so later plans perform typed lookup without rebuilding maps or
carrying a root separately.
Expose the new modules from `hurl-workbench-core/hurl-workbench-core.cabal` and add bounded
dependencies on `containers`, `directory`, `filepath`, and `dhall`.

This milestone is complete when a minimal completion-based fixture and a fully specified
fixture decode to the same normalized Haskell value, and an incompatible schema version is
reported before any command tries to use the workspace.


### Milestone 2: Implement deterministic discovery and semantic validation


Add `HurlWorkbench.Workspace.Discover` with:

```haskell
data WorkspaceSource
  = ExplicitWorkspace FilePath
  | DiscoveredWorkspace FilePath

discoverWorkspace
  :: Maybe FilePath
  -> FilePath
  -> IO (Either WorkspaceError WorkspaceSource)
```

If `--workspace FILE` is present, resolve that exact path and fail if it does not exist.
Otherwise start at the supplied current directory and walk parents until
`hurl-workbench.dhall` is found. Stop at the filesystem root. Never inspect `$HOME`, a
global config directory, or the network. The workspace root is the canonical directory
containing the manifest.

Add `HurlWorkbench.Workspace.Validate` with an accumulating validator:

```haskell
data ValidationIssue = ValidationIssue
  { location :: !Text
  , message :: !Text
  }
  deriving stock (Generic, Eq, Show)

validateWorkspace
  :: WorkspaceContext
  -> IO (Either (NonEmpty ValidationIssue) ValidatedWorkspace)
```

Validation rules are observable product behavior:

- fragment, workflow, recipe, matrix, service, suite, and matrix-case names match
  `[A-Za-z][A-Za-z0-9._-]*` and are unique within their category or parent;
- parameter names match the Hurl-template-safe `[A-Za-z_][A-Za-z0-9_-]*` subset and reject
  Hurl 8's reserved `getEnv`, `newDate`, and `newUuid` names;
- `schemaVersion` is exactly `1`;
- fragment paths are relative `.hurl` paths, exist as regular files, canonicalize inside
  the workspace root, and cannot escape through `..` or symlinks;
- command working directories are relative existing directories inside the workspace;
- workflow fragment and parameter references resolve, and each workflow has at least one
  fragment;
- secret parameters have no literal defaults;
- every binding references a parameter declared by the selected workflow, plain
  parameters only, and a parameter appears at most once in a binding set;
- recipes reference workflows; matrices reference recipes and have unique, non-empty
  cases; service environment bindings reference declared parameters;
- suites have at least one run, and every workflow, recipe, matrix, and service reference
  resolves;
- positive interval and timeout fields are non-zero, and HTTP readiness status is between
  100 and 599;
- every `HurlValueLiteral` satisfies the lossless single-line transport rule;

Return all independent issues in stable category/name order so one validation run is
actionable. Define `WorkspaceError` separately for discovery/Dhall/IO failures. Render
both error families with manifest paths and entity locations, never raw call stacks.

Add fixtures under `hurl-workbench-core/test/fixtures/workspaces/` for minimal, duplicate,
missing-reference, escaping-path, secret-default, and schema-version cases. Add a Tasty
test suite in `hurl-workbench-core/test/Main.hs`; use `tasty` and `tasty-hunit`, with bounds
verified against Hackage and upstream tags when the Cabal file is edited.

This milestone is complete when tests prove parent discovery, explicit-path precedence,
symlink/path escape rejection, error accumulation, stable ordering, and successful loading.


### Milestone 3: Replace the placeholder CLI with `validate` and `list`


Split `hurl-workbench-cli/src/HurlWorkbench/Cli.hs` into a small dispatcher plus
`HurlWorkbench.Cli.Options`, `HurlWorkbench.Cli.Command.Validate`, and
`HurlWorkbench.Cli.Command.List`. Remove `hello`. Define one global
`--workspace FILE` option before subcommands.

The initial CLI surface is:

```text
hurl-workbench [--workspace FILE] validate
hurl-workbench [--workspace FILE] list [all|parameters|fragments|workflows|recipes|matrices|services|suites]
```

`validate` prints the manifest path and counts on success. On semantic failure it prints
every issue to stderr and exits non-zero. `list` validates first, then prints a stable,
line-oriented table suitable for a human; `list all` groups categories under headings.
Do not expose secrets or read parameter environments during either command.

Add `hurl-workbench-cli/test/Main.hs` for parser tests and command-level tests against the
fixture workspaces. Change the executable entry point only enough to preserve
`HurlWorkbench.Cli.runCli :: IO ()`.

Use `optparse-applicative` 0.19.x, whose `parserOptionGroup` API is required by later
commands. Parser modules use postpositive qualified imports. Shared command runners load
and validate once, then pass `ValidatedWorkspace`; handlers must not accept an unvalidated
`Workspace` plus an unrelated `WorkspaceRoot`.

This milestone is complete when the executable discovers a parent workspace, lists the
fixture entities, reports every invalid reference, and its help no longer mentions
`hello`.


## Concrete Steps


Run all commands from the repository root. Locate dependency sources through Mori first:

```bash
mori registry show dhall-lang/dhall-haskell --full
mori registry docs dhall-lang/dhall-haskell
mori registry show pcapriotti/optparse-applicative --full
```

1. Recheck released versions before editing bounds:

   ```bash
   cabal info dhall optparse-applicative tasty tasty-hunit
   git ls-remote --tags https://github.com/dhall-lang/dhall-haskell.git
   git ls-remote --tags https://github.com/pcapriotti/optparse-applicative.git
   ```

2. Add schema, source modules, fixtures, Cabal test suites, and CLI commands described
   above. Format after each coherent milestone:

   ```bash
   nix fmt
   ```

3. Build and run focused tests:

   ```bash
   cabal build all
   cabal test hurl-workbench-core-test hurl-workbench-cli-test
   ```

   Expected tail:

   ```text
   Test suite hurl-workbench-core-test: PASS
   Test suite hurl-workbench-cli-test: PASS
   ```

4. Exercise the CLI against the valid fixture:

   ```bash
   cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/minimal/hurl-workbench.dhall validate
   cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/minimal/hurl-workbench.dhall list all
   ```

   Expected validation shape:

   ```text
   Valid workspace: .../minimal/hurl-workbench.dhall
   1 fragment, 1 workflow, 0 recipes, 0 matrices, 0 services, 0 suites
   ```

5. Exercise one invalid fixture and verify multiple errors appear in one run:

   ```bash
   cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/missing-reference/hurl-workbench.dhall validate
   ```

   Expected result: a non-zero exit and messages naming each unresolved reference.


## Validation and Acceptance


Acceptance is behavioral, not just compilation:

- a workspace may import sibling Dhall modules relative to its manifest;
- an explicit manifest always wins over discovery;
- discovery works from a nested child directory and stops at the root;
- old minimal fixtures using completion still normalize when every defaulted field is
  omitted;
- a secret literal default, duplicate entity, missing reference, `../` fragment, and
  symlink escape each produce a specific error;
- independent semantic issues are reported together in stable order;
- later modules can only receive the opaque `ValidatedWorkspace`, and compile-time tests
  demonstrate that category-specific names cannot be interchanged;
- plain values that would change when serialized through Hurl's line-oriented variable
  file are rejected with the parameter location before any process starts;
- `list` output contains names and relationships but never environment-derived values;
- `cabal build all` and both package tests pass under GHC 9.12.4.


## Idempotence and Recovery


Dhall decoding, discovery, validation, and listing are read-only and safe to repeat. Tests
must create symlinks and temporary directories under their own temporary root and remove
them through bracketed cleanup. If a schema edit makes fixtures fail, restore compatibility
by adding a completion default; do not rewrite fixtures until the diff demonstrates an
intentional schema-version change. If a dependency bound fails with the pinned GHC, inspect
the Mori-located source and current Hackage release before choosing a workaround.


## Interfaces and Dependencies


At completion, these modules are public from `hurl-workbench-core`:

```haskell
module HurlWorkbench.Workspace.Types
module HurlWorkbench.Workspace.Decode
module HurlWorkbench.Workspace.Discover
module HurlWorkbench.Workspace.Context
module HurlWorkbench.Workspace.Validate
```

The central interfaces are:

```haskell
decodeWorkspaceFile
  :: FilePath
  -> IO (Either WorkspaceError Workspace)
discoverWorkspace
  :: Maybe FilePath
  -> FilePath
  -> IO (Either WorkspaceError WorkspaceSource)
loadWorkspaceContext
  :: WorkspaceSource
  -> IO (Either WorkspaceError WorkspaceContext)
validateWorkspace
  :: WorkspaceContext
  -> IO (Either (NonEmpty ValidationIssue) ValidatedWorkspace)
```

`Workspace` and `WorkspaceContext` are decoded/pre-validation values; only EP-1 loading and
validation code plus focused tests use them directly. `ValidatedWorkspace` is the shared
input to EP-2 through EP-6 and exports typed lookup functions without exporting its
constructor.

Use `dhall` 1.42.x for typed decoding, `containers` for indexed lookup and duplicate
detection, and `directory`/`filepath` for canonical path checks. Use the existing
`optparse-applicative` dependency at `>=0.19 && <0.20` for the CLI and Tasty plus
`tasty-hunit` for tests. Verify final bounds against Hackage and upstream release tags at
implementation time. Do not add YAML, JSON, an HTTP client, a Hurl parser, or a process
library in this plan.


## Revision Note


2026-09-18: Corrected the Dhall decoding API, replaced the generic logical name and loose
workspace/root pair with category-specific names and an opaque validated workspace,
specified Hurl value-literal semantics, and incorporated the applicable Haskell Jitsurei
core and CLI conventions before implementation.
