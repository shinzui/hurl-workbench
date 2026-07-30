---
id: 2
slug: compose-and-render-reusable-hurl-workflows
title: "Compose and Render Reusable Hurl Workflows"
kind: exec-plan
created_at: 2026-07-30T23:31:53Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
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


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


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


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


This plan depends on `docs/plans/1-define-the-typed-hurl-workspace-contract.md`. EP-1
creates `WorkspaceRoot`, `Fragment`, `Workflow`, decoded workspace lookup, path validation,
and the `validate`/`list` CLI. A workflow's `fragments` field is ordered and contains names,
not paths. A fragment file is contractually one or more complete Hurl entries; fragments
must not be header snippets, partial request bodies, or workbench-specific templates.

Hurl supports captures that remain available to later entries in the same file. That is
the mechanism that lets an OAuth response fragment capture `accessToken` and a later
request fragment use `{{accessToken}}`. Hurl's public grammar and current manual do not
provide an include or macro facility, so external whole-entry composition fills a real
gap. This is an inference from the official Hurl 8.x grammar and manual, not a claim that
future Hurl versions can never add includes.

The locally installed baseline is Hurl 8.0.1 and includes `hurlfmt`. Its `--check` option
means formatting check; `hurlfmt --out json FILE` is the suitable parse-only probe. This
plan introduces a narrow `hurlfmt` adapter but leaves HTTP execution to EP-3.

There is still no relevant local or Mori-indexed ADR. The opaque-fragment boundary is
durable architecture; create an ADR in this plan when the implementation confirms the
exact composition contract.


## Plan of Work


### Milestone 1: Implement pure, provenance-aware composition


Add `hurl-workbench-core/src/HurlWorkbench/Workflow/Resolve.hs` to resolve a workflow name
to ordered, already validated fragment records. It must report the workflow and missing
fragment name even though normal CLI paths validate first; library callers should not get
partial functions.

Add `hurl-workbench-core/src/HurlWorkbench/Workflow/Render.hs` with these public values:

```haskell
data RenderedWorkflow = RenderedWorkflow
  { workspaceRoot :: WorkspaceRoot
  , workflowName :: EntityName
  , sourceFragments :: NonEmpty ResolvedFragment
  , contents :: Text
  }

resolveWorkflow :: Workspace -> EntityName -> Either WorkflowError ResolvedWorkflow
renderWorkflow :: WorkspaceRoot -> ResolvedWorkflow -> IO RenderedWorkflow
```

Read every fragment strictly as UTF-8. Reject an invalid byte sequence with the fragment
path and byte-offset context. Do not normalize indentation, line endings inside a fragment,
comments, or templates. Between adjacent fragments, insert the minimum number of `\n`
bytes needed to leave at least one blank line: insert two if the prior content has no final
line feed, one if it has one, and none if it has two or more. Ensure the complete rendering
ends with one line feed by adding one only when absent. Never remove bytes from a fragment.

The result must not inject generated comments, timestamps, absolute paths, resolved
variables, or secrets. The same workspace bytes therefore produce the same `contents` on
every machine. Add unit tests for empty files, one/multiple trailing newlines, CRLF source,
Unicode comments, invalid UTF-8, missing fragments, and ordered capture/use examples. An
empty fragment is a validation error because it cannot contain a complete entry.

This milestone is complete when golden comparisons prove exact ordering and separator
behavior and no runtime values are consulted during rendering.


### Milestone 2: Validate rendered syntax through `hurlfmt`


Add `hurl-workbench-core/src/HurlWorkbench/Hurl/Format.hs` with:

```haskell
newtype HurlfmtExecutable = HurlfmtExecutable FilePath

data HurlfmtError
  = HurlfmtNotFound FilePath
  | InvalidHurl EntityName Text
  | HurlfmtFailed ExitCode Text

validateRenderedWorkflow
  :: HurlfmtExecutable
  -> RenderedWorkflow
  -> IO (Either HurlfmtError ())
```

Write the rendering to a bracketed temporary file and run
`hurlfmt --no-color --out json TEMP_FILE`, capturing and discarding stdout while preserving
stderr for diagnostics. Never use a shell string. A parse failure must be associated with
the workflow name; retain Hurlfmt's line/column diagnostic because it refers to the exact
rendered text available from `render`.

Add `validateWorkspaceSyntax` that renders every workflow in stable name order and returns
all parse errors rather than stopping at the first. Extend the EP-1 `validate` command to
run semantic validation first and syntax validation only when semantic validation succeeds.
If `hurlfmt` is absent, return one dependency error rather than one error per workflow.

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


First run the source lookup from `/Users/shinzui/Keikaku/bokuno/mori-project/mori`:

```bash
just mori-global registry search typed-process
```

Run the remaining implementation commands from
`/Users/shinzui/Keikaku/bokuno/hurl-workbench`.

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


EP-2 owns `ResolvedWorkflow`, `RenderedWorkflow`, `resolveWorkflow`, `renderWorkflow`, and
`validateRenderedWorkflow`. EP-3 and every higher-level plan must consume these interfaces
instead of reading or concatenating fragments itself.

Use `Data.Text.Encoding.decodeUtf8'` for strict UTF-8, `Data.List.NonEmpty` for ordered
non-empty fragments, `typed-process` with `proc` rather than `shell`, and a bracketed
temporary-file library. Hurlfmt 8.x is the syntax oracle. Do not add a Hurl grammar parser,
template substitution library, formatter, or HTTP client.
