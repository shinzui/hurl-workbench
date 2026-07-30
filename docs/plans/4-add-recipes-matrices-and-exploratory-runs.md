---
id: 4
slug: add-recipes-matrices-and-exploratory-runs
title: "Add Recipes Matrices and Exploratory Runs"
kind: exec-plan
created_at: 2026-07-30T23:31:53Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
---

# Add Recipes Matrices and Exploratory Runs


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture


This plan turns a reusable workflow into a practical third-party API workbench. A developer
can give a workflow a named set of ordinary bindings, apply it to many named cases, run
those cases sequentially or with bounded concurrency, and keep each response in a stable
artifact path. The repeated OAuth entry and OData query structure live once; only the MLS,
resource, query, or special status differs as data.

The plan also preserves the value of bespoke Hurl scenarios. An unusual capture/assertion
workflow or a raw-wire decoding reproduction remains an ordinary fragment/recipe instead
of being forced into a generic abstraction.


## Progress


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


## Decision Log


- Decision: Recipes and matrix cases bind only plain parameters; secrets remain runtime
  inputs.
  Rationale: Named API explorations should be commit-safe and reviewable. Credential values
  do not belong in Dhall, even when they are convenient defaults.
  Date: 2026-07-30

- Decision: Execute each matrix case as an independent Hurl process in the first release.
  Rationale: Per-case bindings, isolation, artifacts, and failures remain simple and
  deterministic. Sharing an OAuth capture across cases would require a new state/cache
  protocol and is outside this initiative.
  Date: 2026-07-30

- Decision: Default matrices to one job and require explicit bounded concurrency.
  Rationale: Third-party vendors often impose rate limits, and exploration output is most
  readable sequentially.
  Date: 2026-07-30


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


This plan depends on `docs/plans/3-execute-hurl-workflows-securely.md`. EP-3 owns rendering,
binding resolution, Hurl capability detection, secure temp files, `RunRequest`, and exact
single-run execution. EP-1 already defines `Recipe`, `Matrix`, `MatrixCase`, `Binding`, and
the `ReadOnly`/`Mutating` safety marker. This plan supplies their runtime semantics.

The motivating Constellation client repository has thirteen Hurl files. Every file repeats
the same OAuth client-credentials exchange and most differ only by MLS, OData resource, and
`$filter`/`$select`/`$orderby`/`$top` values. One MLSPIN case uses a vendor-specific sold
status; one co-buyer check has a custom capture/assert chain; one broken-decoding scenario
is deliberately raw. The desired design factors only the actual repetition and leaves the
special scenarios explicit.

A recipe is one workflow plus committed plain bindings. A matrix is one recipe plus ordered
case-specific plain bindings. An *expanded run* is the fully resolved target name,
workflow, safety marker, binding layers, and artifact stem consumed by the EP-3 primitive.

There is no relevant local or Mori-indexed ADR. If concurrency, safety, or artifact rules
become durable beyond the details already fixed in the master plan, record them in a local
ADR while implementing this plan.


## Plan of Work


### Milestone 1: Resolve recipes and matrix cases to single-run requests


Add `hurl-workbench-core/src/HurlWorkbench/Run/Selection.hs`:

```haskell
data RunSelection
  = SelectWorkflow EntityName
  | SelectRecipe EntityName
  | SelectMatrix EntityName

data ExpandedRun = ExpandedRun
  { displayName :: Text
  , workflow :: Workflow
  , safety :: Safety
  , bindingLayers :: NonEmpty BindingLayer
  , artifactStem :: FilePath
  }

resolveSelection
  :: Workspace
  -> RunSelection
  -> Either SelectionError (NonEmpty ExpandedRun)
```

A workflow expands to one read-only low-level run with no committed binding layer. A recipe
expands to one run with its recipe bindings. A matrix expands in declared case order; each
case adds a higher-precedence layer over recipe bindings. A case may override a recipe
value intentionally. The effective plain-binding precedence becomes explicit CLI value,
later variable file, earlier variable file, matrix case, recipe, declared environment,
then parameter default. Secret precedence remains unchanged from EP-3 because committed
layers cannot contain secrets.

Sanitize `artifactStem` from logical names using the same entity-name contract; join a
matrix and case as `MATRIX/CASE`, never an arbitrary configured path. Reject duplicate case
names and any binding not declared by the selected workflow even if EP-1 validation was
skipped by a library caller.

Extend EP-3's resolver to accept ordered `BindingLayer` values without importing recipe or
matrix types into `HurlWorkbench.Parameter.Resolve`. Add table-driven tests for all
precedence combinations and for stable case expansion.

This milestone is complete when every recipe/matrix case deterministically reduces to the
same `RunRequest` shape used by a workflow and the resolver never handles a secret value
from committed configuration.


### Milestone 2: Add bounded matrix execution and artifacts


Add `hurl-workbench-core/src/HurlWorkbench/Run/Batch.hs`:

```haskell
data BatchOptions = BatchOptions
  { jobs :: PositiveInt
  , failFast :: Bool
  , outputDirectory :: Maybe FilePath
  , mode :: HurlRunMode
  }

data CaseResult = CaseResult
  { name :: Text
  , exitCode :: ExitCode
  , elapsed :: NominalDiffTime
  , outputPath :: Maybe FilePath
  }

runBatch
  :: HurlCapabilities
  -> BatchOptions
  -> NonEmpty PreparedRun
  -> IO (NonEmpty CaseResult)
```

Use bounded concurrency with at most `jobs` active Hurl processes. Default to one job. With
`failFast`, stop scheduling new cases after the first observed failure, wait for active
children, and mark never-started cases as skipped in the summary. Without it, run every
case. Return results in declaration order regardless of completion order.

Client-mode output rules are deliberate:

- with one job and no output directory, inherit stdout and write case start/end labels to
  stderr, so each raw final response remains unmodified;
- with more than one job, require `--output-dir` to prevent interleaved response bodies;
- when an output directory is present, create it with owner-only permissions, pre-create
  each response file with mode `0600`, and pass that per-case path through EP-3's typed Hurl
  output option so Hurl truncates an already protected file;
- never claim response artifacts are redacted; Hurl documents that response bodies can
  contain secrets.

Test mode may use multiple jobs without response output because Hurl test mode suppresses
final bodies, but workbench case summaries still go to stderr in declaration order. A
batch exits zero only if every started case succeeds. Otherwise choose the first non-zero
Hurl exit code in declaration order, not completion order. This is deterministic and does
not alter EP-3's exact exit rule for a single run.

Add fake-Hurl tests that measure the concurrency bound, force out-of-order completion,
exercise fail-fast scheduling, inspect per-case output paths, and prove stable result
ordering. Add one real-Hurl matrix test against the in-process fixture server.

This milestone is complete when a three-case matrix runs with jobs one and two, produces
distinct response artifacts, and reports the same ordered summary in both modes.


### Milestone 3: Expose recipe and matrix UX plus a representative vendor example


Extend `render`, `run`, and `test` to accept `workflow NAME` or `recipe NAME`. Add:

```text
hurl-workbench [--workspace FILE] matrix NAME [--mode run|test] [--jobs N]
  [--fail-fast|--keep-going] [--output-dir DIR] [BINDING_OPTIONS] [HURL_OPTIONS]
```

For `render recipe`, stdout is still only the workflow Hurl text; print a redacted binding
source summary to stderr only when `--explain` is requested. Refuse a `Mutating` recipe or
any matrix containing one unless the command includes `--allow-mutating`. A direct workflow
selection is the low-level escape hatch and has no recipe safety metadata; document this
clearly in help.

Create `examples/vendor-odata/` with a local `hurl-workbench.dhall`, fragments, and a README.
The example must be runnable against the test fixture rather than a proprietary endpoint,
but mirror the real shape:

- `fragments/oauth-client-credentials.hurl` captures `accessToken`;
- `fragments/odata-query.hurl` uses `baseUrl`, `mls`, `resource`, `filter`, `select`,
  `orderby`, and `top` parameters plus the captured token;
- one workflow orders those two fragments;
- recipes provide common property/member/office defaults;
- a matrix varies MLS and OData query values, including a case whose sold-status filter
  differs from the generic closed-status filter;
- a separate bespoke workflow demonstrates a co-buyer-style capture/assert chain;
- a separate raw workflow demonstrates inspecting a response that a typed client cannot
  decode.

Do not copy vendor credentials, hostnames, response bodies, or proprietary schemas. Add
`docs/guides/vendor-api-exploration.md` mapping the thirteen-file repetition pattern to
fragments, recipes, and matrices and explaining which custom scenarios should remain
custom.

This milestone is complete when the example validates, renders one OAuth entry rather than
one per case in source control, runs its local matrix, and produces one artifact per case.


## Concrete Steps


Run commands from `/Users/shinzui/Keikaku/bokuno/hurl-workbench`.

1. Implement selection, binding layers, batches, CLI parsing, and tests:

   ```bash
   nix fmt
   cabal test hurl-workbench-core-test hurl-workbench-cli-test
   ```

2. Inspect the example without making requests:

   ```bash
   cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall validate
   cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall list matrices
   cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall render recipe properties
   ```

   Expected list output includes the declared MLS cases and does not include credential
   values.

3. Start the shared fixture service:

   ```bash
   cabal run hurl-workbench-fixture-server -- --port 18080
   ```

   In another shell, execute the example:

   ```bash
   cabal run hurl-workbench -- --workspace examples/vendor-odata/hurl-workbench.dhall matrix property-by-mls --mode run --jobs 2 --output-dir build/vendor-odata
   ```

   Expected result: a stable summary for every case and one response file beneath
   `build/vendor-odata/property-by-mls/` per case.

4. Run the full repository checks:

   ```bash
   cabal build all
   cabal test all
   nix fmt -- --check
   ```


## Validation and Acceptance


- recipe bindings override parameter defaults but are overridden by matrix and explicit
  runtime layers in the documented order;
- no committed recipe or matrix can bind a secret parameter;
- every matrix case becomes an isolated Hurl process and ordered result;
- concurrency never exceeds `--jobs`, and parallel client runs require separate outputs;
- fail-fast stops new scheduling and still reaps active children;
- mutating recipes require `--allow-mutating` every time;
- response artifact directories/files are owner-only and visibly documented as potentially
  containing secrets from response bodies;
- the vendor example uses one auth fragment, data-driven OData cases, and explicit custom
  scenarios;
- all unit, fake-process, and real-Hurl integration tests pass.


## Idempotence and Recovery


Selection and expansion are pure and safe to repeat. API execution has the semantics of the
underlying Hurl requests; read-only classification is descriptive, while mutating runs
require explicit authorization. Create batch output directories before starting cases and
write each response to a unique case path, so a retry cannot cross-contaminate another
case. If an artifact already exists, fail before starting unless `--overwrite` is supplied;
with `--overwrite`, replace only the exact resolved case files after validating that all
paths remain under the requested output root. Interrupted batches terminate active Hurl
children and report which cases completed, failed, or never started.


## Interfaces and Dependencies


EP-4 owns `RunSelection`, `ExpandedRun`, `BindingLayer`, `BatchOptions`, `CaseResult`, and
`runBatch`. EP-5 consumes expanded selections when suites are introduced. EP-3 continues
to own `runHurl`; batch code must call it rather than copy its temp-file or argv logic.

Use `async` plus STM/semaphores, or an equivalently small bounded-concurrency primitive,
after verifying the current Hackage release and upstream tag. Reuse `containers`,
`typed-process`, `temporary`, and `time` already introduced. Do not add a database,
persistent token cache, template engine, OData client, or response decoder.
