---
id: 2
slug: compose-and-render-reusable-hurl-workflows
title: "Compose and Render Reusable Hurl Workflows"
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
      note: "Made rendering failures explicit and added source-span and Hurlfmt capability contracts."
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-20T23:28:53Z
      mode: "implement"
      note: "Started EP-2 composition, syntax validation, and render-command implementation."
---

# Compose and Render Reusable Hurl Workflows


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture


After this change, a user can define an OAuth entry once, define resource requests in
separate files, and render any ordered combination as one valid Hurl session. Captures made
by an earlier fragment remain visible to later entries because the rendered result is one
Hurl file. `hurl-workbench render workflow NAME` writes inspectable Hurl source with all
template placeholders intact, and workspace validation asks `hurlfmt` to parse every
workflow without implementing Hurl's grammar in Haskell.


## Progress


- [x] (2026-09-20 23:39Z) Milestone 1: implemented workflow resolution, exact UTF-8
  composition, inclusive fragment line spans, and focused core tests.
- [x] (2026-09-20 23:41Z) Milestone 2: implemented Hurlfmt capability detection,
  accumulated stable-order workspace syntax validation, and the extended `validate` command.
- [x] (2026-09-20 23:44Z) Milestone 3: implemented exact-output `render workflow`, atomic file
  replacement, source-fragment overwrite protection, the composition fixture, and CLI tests.
- [x] (2026-09-20 23:48Z) Ran focused, end-to-end, and EP-2 repository acceptance checks and
  distilled the durable composition contract into ADR 3. `cabal build all`, all 49 tests,
  `nix fmt -- --ci`, and live Hurlfmt 8.0.1 file/stdout validation pass. The attempted
  initiative-wide `nix flake check` exposed a pre-existing multi-package packaging failure now
  assigned explicitly to EP-6; it does not invalidate EP-2's behavior.


## Surprises & Discoveries


- Observation: Mori has no registered source project for `typed-process` or `temporary`, so
  dependency research had to continue through the authoritative Hackage index and released source.
  Hackage currently exposes `typed-process-0.2.13.0` and `temporary-1.3` as the latest releases;
  their source confirms that `readProcess` captures complete stdout/stderr without lazy I/O and
  `withSystemTempDirectory` brackets recursive cleanup. The `temporary` repository carries the
  matching `v1.3` tag; `typed-process` upstream tags currently stop at `0.2.11.1`, so the
  `0.2.13.0` bound is grounded in Hackage's released source rather than an inferred tag.
  Evidence: `mori registry search typed-process`, `mori registry search temporary`, `cabal list
  --simple-output typed-process temporary`, and the released package sources acquired with `cabal
  get`.

- Observation: `Data.Text.Encoding.decodeUtf8'` reports invalid UTF-8 but its public
  `UnicodeException` does not expose the byte position. Rendering therefore lets `decodeUtf8'`
  decide validity and uses a small RFC 3629 byte scanner only to locate the first invalid byte for
  diagnostics.
  Evidence: `mori://haskell/text/repos/text`, project-relative path
  `text/src/Data/Text/Encoding.hs`, and the invalid-byte-offset test in
  `hurl-workbench-core/test/HurlWorkbench/Workflow/WorkflowTest.hs`.

- Observation: Hurlfmt 8.0.1 emits parse locations as `--> FILE:LINE:COLUMN`. Mapping the reported
  line through inclusive fragment spans identifies the owning source fragment; blank separator
  lines intentionally have no owner.
  Evidence: the recorded-diagnostic adapter test and the installed Hurlfmt 8.0.1 probe.

- Observation: The pinned treefmt CLI rejects the MasterPlan's former `nix fmt -- --check`
  acceptance command because `--check` is not a supported flag; `nix fmt -- --ci` is the current
  fail-on-change CI mode. The MasterPlan and affected EP-4/EP-5 validation steps were corrected
  before final acceptance.
  Evidence: the formatter CLI's `unknown flag: --check` output and its documented `--ci` flag.


## Decision Log


- Decision: Treat fragment text as opaque UTF-8 and insert only missing line-feed
  separators between fragments.
  Rationale: The workbench must preserve Hurl comments, captures, assertions, and formatting
  while ensuring adjacent entries cannot run together syntactically.
  Date: 2026-07-30

- Decision: Render Hurl placeholders rather than resolving parameters into source text.
  Rationale: Values belong in Hurl variable/secret channels at execution time; rendered
  source should be deterministic, reviewable, and safe to share.
  Date: 2026-07-30

- Decision: Use `hurlfmt --out json` as a parser oracle, not `hurlfmt --check`.
  Rationale: `--check` also enforces formatter output and would reject valid but differently
  formatted fragments. JSON conversion parses the file without making formatting policy.
  Date: 2026-07-30

- Decision: Return expected resolution, UTF-8, filesystem, and Hurlfmt failures explicitly
  and preserve a line-span map from rendered lines to source fragments.
  Rationale: A public library boundary should not turn invalid source into an unclassified
  exception, and Hurlfmt's combined-file line number is actionable only when it can be
  mapped back to the owning fragment.
  Date: 2026-09-18

- Decision: Keep the selected `Workflow` definition and canonical `ResolvedFragment` values in
  `ResolvedWorkflow`, then carry those fragments into `RenderedWorkflow` beside the generated
  source and line spans.
  Rationale: EP-3 needs the workflow's declared parameters and workspace root, while all later
  execution paths must reuse the already validated canonical files and provenance instead of
  resolving names or paths again.
  Date: 2026-09-20

- Decision: Detect Hurlfmt once before validating a workspace and process workflow names in sorted
  order, while treating a disappeared executable as one dependency failure rather than repeating it
  for every workflow.
  Rationale: Dependency availability is workspace-wide, but syntax failures are independent and
  should accumulate deterministically.
  Date: 2026-09-20


## Outcomes & Retrospective


The implementation now resolves validated workflow names to canonical fragment files, preserves
valid UTF-8 source exactly, inserts only the required line-feed boundaries, and records inclusive
source spans without leaking provenance into Hurl text. Hurlfmt capability detection and syntax
validation use `typed-process` without a shell, clean temporary input on every tested path, and
accumulate independent workflow failures in stable order.

The CLI now validates Hurl syntax after semantic validation and renders one named workflow either as
stdout-only Hurl source or through atomic same-directory replacement. It rejects output paths that
canonicalize to any input fragment. The checked-in `composition` fixture demonstrates an OAuth
capture reused by a parameterized property request, and both direct piping and file-based validation
pass with Hurlfmt 8.0.1.

The durable composition boundary is recorded in
`docs/adr/3-opaque-hurl-fragment-composition.md`. `cabal build all`, all 49 tests, the treefmt CI
gate, and both live Hurlfmt 8.0.1 render paths pass. The MasterPlan's broader `nix flake check`
remains blocked by the pre-existing root-package assumption now documented in EP-6, not by an
EP-2 source, test, or dependency failure.


## Context and Orientation


This plan depends on `docs/plans/1-define-the-typed-hurl-workspace-contract.md`. EP-1
creates category-specific names, the opaque `ValidatedWorkspace`, path validation, and the
`validate`/`list` CLI. A workflow's `fragments` field is ordered and contains
`FragmentName` values, not paths. A fragment file is contractually one or more complete
Hurl entries; fragments must not be header snippets, partial request bodies, or
workbench-specific templates.

Hurl supports captures that remain available to later entries in the same file. That is
the mechanism that lets an OAuth response fragment capture `accessToken` and a later
request fragment use `{{accessToken}}`. Hurl's public grammar and current manual do not
provide an include or macro facility, so external whole-entry composition fills a real
gap. This is an inference from the official Hurl 8.x grammar and manual, not a claim that
future Hurl versions can never add includes.

The locally installed baseline is Hurl 8.0.1 and includes `hurlfmt`. Its `--check` option
means formatting check; `hurlfmt --out json FILE` is the suitable parse-only probe. This
plan introduces a narrow `hurlfmt` adapter but leaves HTTP execution to EP-3.

No relevant ADR existed when this plan began. The implemented opaque-fragment boundary is now
recorded in `docs/adr/3-opaque-hurl-fragment-composition.md`: it requires whole-entry, non-empty,
valid UTF-8 fragments; byte-preserving minimum-separator composition; unresolved placeholders; and
Hurlfmt as the non-shell syntax oracle.


## Plan of Work


### Milestone 1: Implement pure, provenance-aware composition


Add `hurl-workbench-core/src/HurlWorkbench/Workflow/Resolve.hs` to resolve a workflow name
to ordered, already validated fragment records. It must report the workflow and missing
fragment name even though normal CLI paths validate first; library callers should not get
partial functions.

The implemented resolution records are:

```haskell
data ResolvedFragment = ResolvedFragment
  { fragment :: !Fragment
  , fragmentPath :: !FilePath
  }
  deriving stock (Generic, Eq, Show)

data ResolvedWorkflow = ResolvedWorkflow
  { workspaceRoot :: !WorkspaceRoot
  , workflow :: !Workflow
  , sourceFragments :: !(NonEmpty ResolvedFragment)
  }
  deriving stock (Generic, Eq, Show)
```

Add `hurl-workbench-core/src/HurlWorkbench/Workflow/Render.hs` with these public values.
Every record uses strict fields, `Generic`, and explicit deriving strategies per
`mori://shinzui/haskell-jitsurei/docs/core-record-patterns`:

```haskell
data RenderedFragmentSpan = RenderedFragmentSpan
  { fragmentName :: !FragmentName
  , fragmentPath :: !FilePath
  , firstLine :: !Int
  , lastLine :: !Int
  }
  deriving stock (Generic, Eq, Show)

data RenderedWorkflow = RenderedWorkflow
  { workspaceRoot :: !WorkspaceRoot
  , workflowName :: !WorkflowName
  , sourceFragments :: !(NonEmpty ResolvedFragment)
  , fragmentSpans :: !(NonEmpty RenderedFragmentSpan)
  , contents :: !Text
  }
  deriving stock (Generic, Eq, Show)

resolveWorkflow
  :: ValidatedWorkspace
  -> WorkflowName
  -> Either WorkflowError ResolvedWorkflow

renderWorkflow
  :: ResolvedWorkflow
  -> IO (Either RenderError RenderedWorkflow)
```

Read every fragment strictly as UTF-8. Reject an invalid byte sequence with the fragment
path and byte-offset context. Do not normalize indentation, line endings inside a fragment,
comments, or templates. Between adjacent fragments, insert the minimum number of `\n`
bytes needed to leave at least one blank line: insert two if the prior content has no final
line feed, one if it has one, and none if it has two or more. Ensure the complete rendering
ends with one line feed by adding one only when absent. Never remove bytes from a fragment.

The result must not inject generated comments, timestamps, absolute paths, resolved
variables, or secrets. The same workspace bytes therefore produce the same `contents` on
every machine. `fragmentSpans` is metadata and is not rendered into `contents`. Add unit
tests for empty files, one/multiple trailing newlines, CRLF source, Unicode comments,
invalid UTF-8, missing fragments, span boundaries, and ordered capture/use examples. An
empty fragment is a validation error because it cannot contain a complete entry.

This milestone is complete when golden comparisons prove exact ordering and separator
behavior and no runtime values are consulted during rendering.


### Milestone 2: Validate rendered syntax through `hurlfmt`


Add `hurl-workbench-core/src/HurlWorkbench/Hurl/Format.hs` with:

```haskell
newtype HurlfmtExecutable = HurlfmtExecutable FilePath

data HurlfmtCapabilities = HurlfmtCapabilities
  { executable :: !HurlfmtExecutable
  , version :: !Version
  }
  deriving stock (Generic, Eq, Show)

data HurlfmtError
  = HurlfmtNotFound FilePath
  | InvalidHurl WorkflowName (Maybe RenderedFragmentSpan) Text
  | HurlfmtFailed ExitCode Text
  deriving stock (Generic, Eq, Show)

detectHurlfmtCapabilities
  :: IO (Either DependencyError HurlfmtCapabilities)

validateRenderedWorkflow
  :: HurlfmtCapabilities
  -> RenderedWorkflow
  -> IO (Either HurlfmtError ())
```

Write the rendering to a bracketed temporary file and run
`hurlfmt --no-color --out json TEMP_FILE`, capturing and discarding stdout while preserving
stderr for diagnostics. Never use a shell string. A parse failure must be associated with
the workflow name; retain Hurlfmt's line/column diagnostic because it refers to the exact
rendered text available from `render`.

Map parse line/column diagnostics through `fragmentSpans` when possible. Add
`validateWorkspaceSyntax` that renders every workflow in stable name order and returns all
parse errors rather than stopping at the first. Extend the EP-1 `validate` command to run
semantic validation first and syntax validation only when semantic validation succeeds.
If `hurlfmt` is absent, return one dependency error rather than one error per workflow.

The implemented workspace boundary is:

```haskell
validateWorkspaceSyntax
  :: HurlfmtCapabilities
  -> ValidatedWorkspace
  -> IO (Either DependencyError [WorkflowSyntaxError])
```

Use `typed-process` 0.2.13.x for this adapter after checking its Mori/upstream source and
Hackage release. `temporary` or the GHC/platform equivalent must provide bracketed cleanup;
verify the current release before adding bounds. This is the same process foundation EP-3
will use.

This milestone is complete when a malformed response/assert section fails with Hurlfmt's
line number, a valid OAuth-plus-request workflow passes, and no temporary files remain
after success, parse failure, or exception.


### Milestone 3: Add an exact-output `render` command


Add `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Render.hs` and extend the parser with:

```text
hurl-workbench [--workspace FILE] render workflow NAME [--output FILE]
```

Without `--output`, stdout contains only the rendered Hurl bytes so it can be piped to
`hurl`, `hurlfmt`, or a diff. Send discovery and diagnostic messages to stderr. With
`--output`, create or replace that exact file after successful composition, then print its
path to stderr. Do not infer a `.hurl` extension and do not overwrite an input fragment;
compare canonical output and fragment paths before opening the output.

The command validates the workspace semantically, composes the selected workflow, and asks
Hurlfmt to parse it before producing output. Add CLI tests that capture stdout/stderr,
verify `render` has no banner, verify unknown-name diagnostics, and reject an output path
that aliases a source fragment.

This milestone is complete when the following pipeline succeeds for a valid fixture and
the two rendered entries appear in declared order:

```bash
cabal run hurl-workbench -- --workspace PATH render workflow oauth-property | hurlfmt --out json
```


## Concrete Steps


Run commands from the repository root. Mori does not currently index `typed-process`; record
that lookup result before falling back to Hackage and the upstream repository:

```bash
mori registry search typed-process
cabal info typed-process temporary
git ls-remote --tags https://github.com/fpco/typed-process.git
git ls-remote --tags https://github.com/feuerbach/temporary.git
```

1. Confirm the pinned external tools and released process dependencies:

   ```bash
   hurl --version
   hurlfmt --version
   cabal info typed-process temporary
   ```

   The local expected Hurl version begins with:

   ```text
   hurl 8.0.1
   ```

2. Implement the resolver, renderer, Hurlfmt adapter, command, and tests; then format and
   run focused checks:

   ```bash
   nix fmt
   cabal test hurl-workbench-core-test hurl-workbench-cli-test
   ```

3. Render the ordered OAuth fixture and parse it independently:

   ```bash
   cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/composition/hurl-workbench.dhall render workflow oauth-property --output /tmp/hurl-workbench-oauth-property.hurl
   hurlfmt --no-color --out json /tmp/hurl-workbench-oauth-property.hurl
   ```

   Expected result: both commands exit zero, and Hurlfmt emits a JSON document containing
   the authentication entry before the property entry.

4. Validate all repository targets:

   ```bash
   cabal build all
   cabal test all
   ```


## Validation and Acceptance


- composition preserves every fragment's original text and ordering, adding only required
  boundary/final line feeds;
- captures from an authentication entry can be referenced by a later entry in the rendered
  Hurl session;
- `render` output is deterministic and contains unresolved `{{parameter}}` placeholders;
- no environment variable or secret value is read during validation or rendering;
- malformed Hurl is rejected by Hurlfmt with useful workflow and line context;
- a combined-file Hurlfmt line is mapped to its fragment name/path whenever it falls inside
  a recorded fragment span;
- a missing Hurlfmt binary produces a dependency error rather than a Haskell exception;
- temporary files are cleaned in every exit path;
- rendering to a source fragment path is rejected before any file is changed;
- all core and CLI tests pass.


## Idempotence and Recovery


Resolving, rendering, and syntax validation are safe to repeat. Temporary files are
bracketed and must be cleaned even on asynchronous exceptions. `--output` is the only
persistent write; compose and validate fully before opening it, then use an atomic
same-directory temporary file and rename so interruption cannot leave a truncated result.
If an output aliases a fragment, abort without writing. Golden fixtures should be updated
only after reviewing the textual diff and recording any changed separator contract in the
Decision Log and ADR.


## Interfaces and Dependencies


EP-2 owns `ResolvedFragment`, `ResolvedWorkflow`, `RenderedFragmentSpan`, `RenderedWorkflow`,
`HurlfmtExecutable`, `HurlfmtCapabilities`, `DependencyError`, `WorkflowSyntaxError`,
`resolveWorkflow`, `renderWorkflow`, `detectHurlfmtCapabilities`, `validateRenderedWorkflow`, and
`validateWorkspaceSyntax`. EP-3 and every higher-level plan must consume these interfaces instead
of reading or concatenating fragments itself or probing Hurlfmt again. Expected resolution,
rendering, dependency, and parser failures remain in `Either`; asynchronous exceptions are never
converted to domain errors.

Use `Data.Text.Encoding.decodeUtf8'` for strict UTF-8, `Data.List.NonEmpty` for ordered
non-empty fragments, `typed-process` with `proc` rather than `shell`, and a bracketed
temporary-file library. Hurlfmt 8.x is the syntax oracle. Do not add a Hurl grammar parser,
template substitution library, formatter, or HTTP client.


## Revision Note


2026-09-18: Updated composition to consume the opaque validated workspace and typed
workflow names, made render failures explicit, assigned Hurlfmt capability ownership to
EP-2, and added fragment line-span provenance so parse diagnostics identify their source.

2026-09-20: Implemented all three milestones, added the accepted opaque-fragment ADR and
composition fixture, and recorded dependency/version, UTF-8-offset, and Hurlfmt-diagnostic
discoveries. Final repository-wide acceptance checks remain before the plan is marked complete.

2026-09-20: Completed EP-2 acceptance with 49 passing tests, a clean Cabal build and treefmt CI
gate, and live Hurlfmt file/stdout pipelines. Routed the separately discovered multi-package Nix
default failure to EP-6 and corrected obsolete treefmt commands in future plans.
