# ADR 2: The validated workspace is the only input to workbench features


Status: Accepted

Date: 2026-09-19

Origin: [EP-1](../plans/1-define-the-typed-hurl-workspace-contract.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


Rendering, execution, recipes, matrices, and suites all read the same workspace. If each
feature accepted a decoded `Workspace` plus a separately passed root directory, a feature
could skip validation, resolve a fragment against the wrong root, or pass a recipe name
where a workflow name is required, because every name is ultimately `Text`. Plain values
are also transported to Hurl through line-oriented variable files, which trim lines, split
at the first `=`, and infer booleans, nulls, and numbers.


## Decision


`HurlWorkbench.Workspace.Context.ValidatedWorkspace` is abstract. It can only be produced
by `HurlWorkbench.Workspace.Validate.validateWorkspace`; its constructor lives in the
non-exposed module `HurlWorkbench.Workspace.Context.Internal`. It carries the manifest path,
the canonical workspace root, the decoded workspace, typed indexes for every category, and
the canonical absolute path of every fragment file. Every feature after loading accepts
this value, never a loose workspace/root pair.

Each entity category has its own name newtype (`ParameterName`, `FragmentName`,
`WorkflowName`, `RecipeName`, `MatrixName`, `MatrixCaseName`, `ServiceName`, `SuiteName`),
and lookups are typed by them. A test compiled with deferred type errors proves that
cross-category lookups do not type-check.

Plain values are `HurlValueLiteral`, whose smart constructor rejects CR, LF, NUL, and
leading or trailing whitespace; the remaining text follows Hurl 8's own type inference.
Committed values are checked by validation with their entity location, and runtime values
must go through `mkHurlValueLiteral`. Secret values are never part of the Dhall model.

Validation accumulates every independent issue and reports them in a fixed category order,
then by entity name, with locations such as `workflows/list-properties/fragments`. Paths
(fragment files and command working directories) must be relative and canonicalize inside
the workspace root, so `..` and symlink escapes are rejected.


## Consequences


Later features cannot forget to validate or mix up names, and fragment paths are already
proven safe when a feature reads them. Validation is intentionally static: it checks the
workspace's own consistency but does not parse Hurl syntax (a separate pass owned by the
composition work) or read environments and secrets. Adding a category means extending the
internal record, the validator, and the accessors together.
