# ADR 3: Compose opaque Hurl entry fragments without rewriting them


Status: Accepted

Date: 2026-09-20

Origin: [EP-2](../plans/2-compose-and-render-reusable-hurl-workflows.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


Hurl Workbench removes repetition by assembling one workflow from several reusable `.hurl`
files. Hurl already owns request syntax, captures, assertions, retries, comments, and template
semantics. Parsing those constructs into a second Haskell model would create a competing grammar
and could silently change source that users expect Hurl itself to execute.

Concatenating files without a boundary rule is still unsafe: a fragment without a final line feed
can run into the next request, while normalizing every file would alter comments, line endings, or
formatting. Parser diagnostics also refer to the combined file rather than the original fragment.


## Decision


A fragment is a non-empty, valid UTF-8 file containing one or more complete Hurl entries. The
workbench treats its text as opaque. It does not parse, format, interpolate, or otherwise rewrite
requests, responses, captures, assertions, comments, or `{{parameter}}` placeholders.

Composition preserves each fragment's bytes and declaration order. Between adjacent fragments it
adds only the line-feed bytes needed to leave at least one blank line: two when the preceding
fragment has no final line feed, one when it has exactly one, and none when it already has two or
more. It adds one final line feed only when the complete rendering lacks one. The rendered source
contains no generated comments, paths, timestamps, variables, or secrets.

`ResolvedWorkflow` pairs the workspace's `Workflow` definition with a non-empty ordered collection
of canonical `ResolvedFragment` paths obtained from `ValidatedWorkspace`. `RenderedWorkflow` keeps
that resolution, deterministic text, and inclusive rendered line spans for each fragment. Span
metadata is not inserted into Hurl source.

The workbench delegates syntax parsing to the detected Hurl 8.x `hurlfmt` executable by running
`hurlfmt --no-color --out json FILE` without a shell. This parses valid, differently formatted
input without imposing `hurlfmt --check` formatting policy. Workspace syntax validation processes
workflow names in stable order and accumulates independent errors. When Hurlfmt reports a rendered
line inside a fragment span, the diagnostic identifies that source fragment and its canonical path.


## Consequences


Hurl remains the only HTTP and assertion language, and a rendered workflow is reviewable and safe
to pipe directly into Hurl tooling. Captures work across fragment boundaries because execution sees
one Hurl file, while runtime values remain outside rendered source.

Adding workbench-specific syntax inside a fragment is deliberately unsupported. A fragment that is
empty, unreadable, or invalid UTF-8 fails before Hurlfmt runs. Hurl grammar compatibility follows the
installed Hurlfmt version, so dependency detection and version reporting are part of the product
boundary. Diagnostics on composer-inserted blank lines may name the workflow without a source
fragment because those lines do not belong to either input file.
