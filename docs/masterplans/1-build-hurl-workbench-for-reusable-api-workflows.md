---
id: 1
slug: build-hurl-workbench-for-reusable-api-workflows
title: "Build Hurl Workbench for Reusable API Workflows"
kind: master-plan
created_at: 2026-07-30T23:31:46Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
provenance:
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-18T18:29:32Z
      mode: "update"
      note: "Reviewed and cascaded pre-implementation API, dependency, security, and Haskell Jitsurei corrections across the initiative."
---

# Build Hurl Workbench for Reusable API Workflows


This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Vision & Scope


After this initiative, `hurl-workbench` is a Haskell command-line tool that lets a
developer keep each reusable Hurl entry once, combine entries into named workflows,
bind those workflows into repeatable recipes and matrices, and run them either as quick
API explorations or as integration tests. A user can discover a workspace, list its
contents, validate it, render the exact Hurl source that will run, execute it in Hurl's
normal client mode, or execute named suites in Hurl's test mode. Hurl remains the source
of truth for HTTP requests, captures, assertions, retries, cookie sessions, and reports.

The first target is the repeated OAuth-plus-OData pattern in
`mori://tan/constellation1-client-hs/repos/constellation1-client-hs`: one OAuth capture
fragment should feed many resource-query fragments, with MLS-specific values expressed
as data rather than copied files. The second target is the integration-test pattern in
`mori://shinzui/mori/repos/mori`, under `mori-api/test/hurl`: safe and mutating suites,
optional service startup, readiness checks, generated variable files, and Hurl report
output.

Included scope is:

- a versioned Dhall workspace schema and Haskell domain model;
- workspace discovery, listing, loading, and semantic validation;
- deterministic composition of complete Hurl entry fragments;
- inspectable rendering and `hurlfmt` syntax validation;
- secure parameter and secret resolution;
- faithful Hurl client-mode and test-mode execution;
- recipes, matrices, safety classifications, suites, reports, and managed services;
- example workspaces, migration guides, Nix development tooling, and release checks.

Explicitly excluded from the first release are a new HTTP/assertion DSL, parsing or
rewriting Hurl's grammar in Haskell, a GUI or TUI, remote workflow registries, typed
client generation, automatic conversion of external repositories, cross-run OAuth token
caching, arbitrary shell hooks, and transparent sharing of captured state between
independent matrix cases. External helpers may prepare standard Hurl variable or secret
files before invoking the workbench.

Before implementation begins, the jobs, feature acceptance statements, and shared public
contracts must pass the profile-governed review in `docs/use-cases/`. The initiative is
accepted when both bundled examples pass end to end with Hurl 8.x,
the vendor example demonstrates a single OAuth fragment reused by multiple parameterized
queries, the integration example manages a local service and emits a report, and
`nix flake check`, `nix fmt -- --check`, `cabal build all`, and `cabal test all` succeed.


## Decomposition Strategy


The work is divided by durable responsibility rather than by individual CLI command.
EP-7 first owns the use-case and acceptance-contract review that gates implementation.
EP-1 owns the configuration boundary and normalized types. EP-2 owns pure composition and
rendering. EP-3 owns one secure, faithful Hurl invocation. EP-4 builds higher-level
exploration and repetition on that single-run primitive. EP-5 adds lifecycle orchestration
and test suites. EP-6 performs cross-cutting hardening, examples, packaging, and release
acceptance. This sequence keeps the early work mostly pure and independently testable,
then adds processes and services only after their inputs are stable. EP-5 now has a hard
dependency on EP-4 because its final suite API consumes EP-4's selection, preparation,
batch-result, and safety types; partial overlap during implementation is not a substitute
for a child plan being independently implementable once its declared hard dependencies
are complete. EP-1 has a hard governance dependency on EP-7: this is not a compile
dependency, but it enforces the explicit entry criterion that the user scenarios validate
the proposed contracts before product code fixes them in place.

A single all-in-one ExecPlan was rejected because it would mix schema design, pure
composition, secret handling, process control, concurrency, service lifecycle, reports,
and documentation in one progress stream. Splitting by individual commands was also
rejected because `render`, `run`, `test`, and `matrix` share domain types and execution
primitives; command-by-command plans would create unclear ownership and repeated edits.

There is currently no `docs/adr/` corpus in this repository. Mori searches for `hurl`,
`API integration testing`, and `command line interface` returned no relevant indexed ADR,
so no local or cross-repository ADR governs this decomposition. The Dhall schema-evolution
approach was checked against the locally indexed `dhall-haskell` guidance. During
implementation, durable decisions about the opaque-fragment boundary, schema evolution,
secret transport, and service command safety must be distilled into `docs/adr/` rather
than left only in these plans.

Implementation must also follow the applicable current standards in
`mori://shinzui/haskell-jitsurei`: `docs/core-standards`, `docs/core-custom-prelude`,
`docs/core-record-patterns`, `docs/cli-option-groups`, `docs/cli-shell-completions`,
`docs/cli-version-git-sha`, and `docs/api-hurl-integration-testing`. Concretely, records
use strict fields and explicit deriving strategies, qualified imports are postpositive,
the custom prelude does not leak the generic-lens `IsLabel` orphan, large command parsers
group options by user intent, completions and version output follow the documented CLI
contracts, and example Hurl suites keep safe resource families explicit while isolating
mutations and special perimeter cases.


## Exec-Plan Registry


| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-7 | Document and Ratify Hurl Workbench Use Cases | `docs/plans/7-document-and-ratify-hurl-workbench-use-cases.md` | None | None | Complete |
| EP-1 | Define the Typed Hurl Workspace Contract | `docs/plans/1-define-the-typed-hurl-workspace-contract.md` | EP-7 | None | Not Started |
| EP-2 | Compose and Render Reusable Hurl Workflows | `docs/plans/2-compose-and-render-reusable-hurl-workflows.md` | EP-1 | None | Not Started |
| EP-3 | Execute Hurl Workflows Securely | `docs/plans/3-execute-hurl-workflows-securely.md` | EP-2 | None | Not Started |
| EP-4 | Add Recipes Matrices and Exploratory Runs | `docs/plans/4-add-recipes-matrices-and-exploratory-runs.md` | EP-3 | None | Not Started |
| EP-5 | Orchestrate Services and Integration Test Suites | `docs/plans/5-orchestrate-services-and-integration-test-suites.md` | EP-4 | None | Not Started |
| EP-6 | Harden Document and Package the Workbench | `docs/plans/6-harden-document-and-package-the-workbench.md` | EP-4, EP-5 | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Every child plan
inherits intention `intention_01kytnndmnef28f9ksadwfac7h` in its frontmatter.


## Dependency Graph


```mermaid
flowchart LR
    EP7[EP-7 Use-case contract gate] --> EP1[EP-1 Workspace contract]
    EP1[EP-1 Workspace contract] --> EP2[EP-2 Composition and rendering]
    EP2 --> EP3[EP-3 Secure execution]
    EP3 --> EP4[EP-4 Recipes and matrices]
    EP4 --> EP5[EP-5 Services and suites]
    EP4 --> EP6[EP-6 Hardening and release]
    EP5 --> EP6
```

EP-1 requires EP-7 as a governance entry criterion because the jobs and acceptance
statements must ratify its public types before implementation. EP-2 requires EP-1 because
fragment and workflow identities, paths, and parameter
contracts must be stable before composition can be implemented. EP-3 requires EP-2
because it executes a rendered workflow and must not duplicate rendering logic. EP-4
requires EP-3 because every recipe or matrix case reduces to the same tested single-run
request. EP-5 requires EP-4 because suites consume expanded selections, prepared runs,
typed skipped/failed outcomes, and safety metadata; EP-4 already carries EP-3 transitively.
EP-6 waits for both high-level feature streams so its examples and release acceptance cover
the actual product.


## Integration Points


| Plans | Shared artifact | Owner | Consumption rule |
|---|---|---|---|
| EP-7 and all implementation plans | `docs/use-cases/` jobs, features, and acceptance-contract maps | EP-7 | A shared API or acceptance change must still satisfy the mapped use cases, or update the affected use case and explain the changed user contract before implementation. A `validated` use case with `planned` features claims a ratified requirement, not delivery. |
| EP-1 through EP-6 | `schema/package.dhall`, `schema/*.dhall`, category-specific name newtypes, `WorkspaceContext`, and opaque `ValidatedWorkspace` | EP-1 | Later plans accept the validated value rather than loose `WorkspaceRoot`/`Workspace` pairs. Schema changes go through record completion defaults and compatibility fixtures. |
| EP-1 through EP-5 | Static entity and cross-reference validation | EP-1 | EP-1 validates every schema category and builds all indexes without importing later feature modules. EP-2 adds a separate syntax-validation pass; EP-4/EP-5 resolvers retain defense-in-depth checks but do not create a dependency cycle back into `validateWorkspace`. |
| EP-2 through EP-5 | `ResolvedWorkflow`, fragment line spans, and `RenderedWorkflow` | EP-2 | Only the composer constructs rendered Hurl. Executors treat it as immutable UTF-8 text plus workspace-root and source-fragment provenance. |
| EP-3 through EP-5 | `HurlRunner`, `RunRequest`, `RunOutputPolicy`, typed report targets, `RunResult`, binding resolution, and the Hurl process adapter | EP-3 | Recipes, matrices, and suites reduce their work to this single-run interface; they never construct raw Hurl argv. Concurrent callers use captured or file output, never inherited streams. |
| EP-4 and EP-5 | `RunSelection`, `ExpandedRun`, `PreparedRun`, `BatchCase`, `BatchResult`, and typed case outcomes | EP-4 | Suites reference workflows, recipes, or matrices through one resolved sum type. Each scheduled case carries its fully built `RunRequest`, including output/report policy; skipped and start-failed cases are not represented as invented Hurl exit codes. |
| EP-3, EP-5, EP-6 | Hurl 8.x capability and report flags | EP-3 | `doctor` owns capability detection; later plans request features through typed options and do not probe binaries themselves. |
| EP-5 and EP-6 | Example fixture service and integration workspace | EP-5 | EP-6 documents and packages the accepted fixture instead of creating a second demonstration stack. |
| All plans | CLI errors and exit behavior | EP-1 defines workspace errors; EP-3 defines preflight/start failures and child exit propagation; EP-5 defines orchestration failures | A single Hurl-started run returns Hurl's exact exit status. Batch/suite results retain each Hurl status plus explicit skipped/start-failed outcomes. Workbench discovery, validation, dependency, and orchestration failures remain distinguishable and tested. |

The opaque-fragment boundary, Dhall compatibility rules, secret redaction/transport,
non-shell service command representation, and exact Hurl exit propagation are intended to
be durable architecture constraints. The implementing plan that first makes each
constraint concrete must create or update the corresponding ADR.


## Progress


- [x] (2026-09-18 18:40Z) EP-7 documented and strictly validated the initial use-case
  contract set. No product implementation has started.
- [ ] EP-1 through EP-6 remain not started.


## Surprises & Discoveries


- Observation: `Dhall.inputFileWithSettings` accepts `EvaluateSettings`; the original EP-1
  text passed `defaultInputSettings`, which is the settings type for expression APIs.
  Evidence: `mori://dhall-lang/dhall-haskell/repos/dhall-haskell`,
  `dhall-haskell/dhall/src/Dhall.hs`.

- Observation: Hurl 8.0.1 reads every ambient `HURL_*` variable, including control flags,
  variables, and secrets. A controlled wrapper must remove that namespace from the child
  environment after resolving declared sources or an ambient `HURL_TEST`, `HURL_OUTPUT`,
  `HURL_VARIABLE_*`, or `HURL_SECRET_*` can bypass the workbench request model.
  Evidence: official Hurl tag `8.0.1` in `mori://orange-open-source/hurl`, project-relative
  path `packages/hurl/src/cli/options/context.rs`; artifact-level Mori coverage is pending.

- Observation: Hurl variable files trim each line, ignore blank/comment lines, split on the
  first `=`, and infer plain values such as `true`, `null`, and numbers, while secret files
  force strings. The binding API therefore needs a named Hurl value-literal contract and
  must reject line breaks and trimming-sensitive values instead of pretending it transports
  arbitrary `Text` losslessly.
  Evidence: official Hurl tag `8.0.1` in `mori://orange-open-source/hurl`, project-relative
  paths `packages/hurl/src/cli/options/variables_file.rs` and
  `packages/hurl/src/cli/options/variables.rs`; artifact-level Mori coverage is pending.

- Observation: EP-5's final milestones consume types owned by EP-4, so the former soft
  dependency made EP-5 non-implementable under the MasterPlan contract. It is now a hard
  dependency.

- Observation: The OKF use-case profile distinguishes scenario maturity from feature
  delivery, so the evidence-backed jobs can be `validated` while every implementation
  slice remains truthfully `planned`.
  Evidence: `mori://shinzui/okf-profiles/profiles/use-cases`, version 0.15.0.


## Decision Log


- Decision: Keep Hurl source authoritative and compose only complete entry fragments.
  Rationale: This removes checked-in repetition while preserving Hurl captures,
  assertions, comments, retry behavior, and raw-wire independence from typed API clients.
  Date: 2026-07-30

- Decision: Use a versioned Dhall workspace with record-completion defaults.
  Rationale: The surrounding Haskell projects already use Dhall, and normalized typed
  configuration supports imports and reuse without adding a workbench expression language.
  Completion defaults give future optional fields a compatibility path.
  Date: 2026-07-30

- Decision: Treat a single rendered-workflow invocation as the shared execution primitive.
  Rationale: Client runs, test runs, recipe cases, matrices, and suites can then share
  process, variable, secret, output, and exit-status behavior.
  Date: 2026-07-30

- Decision: Make mutating API scenarios opt-in at execution time.
  Rationale: Integration workspaces often mix read-only checks with destructive or
  state-changing requests. A committed suite definition must not silently authorize writes.
  Date: 2026-07-30

- Decision: Represent service commands as an executable plus argv, never as a shell string.
  Rationale: The workbench needs deterministic process control and must not introduce shell
  interpolation into a configuration that may contain paths or runtime values.
  Date: 2026-07-30

- Decision: Expose an opaque validated workspace with category-specific logical-name
  newtypes as the shared domain boundary.
  Rationale: Later plans should not repeatedly pair an unvalidated workspace with a root or
  accidentally pass a recipe name where a workflow name is required.
  Date: 2026-09-18

- Decision: Make child output policy, typed report targets, spawn failures, Hurl exits, and
  skipped batch cases explicit in the shared execution API.
  Rationale: Inherited output is correct for one interactive run but cannot provide stable,
  non-interleaved concurrent output, and skipped work has no truthful `ExitCode`.
  Date: 2026-09-18

- Decision: Remove ambient `HURL_*` variables from spawned Hurl environments after the
  workbench resolves its own declared inputs.
  Rationale: Hurl treats that namespace as an alternate configuration channel; leaving it
  inherited would bypass typed options, binding precedence, output control, and safety tests.
  Date: 2026-09-18

- Decision: Apply the relevant `mori://shinzui/haskell-jitsurei` core, CLI, and Hurl
  integration-testing patterns throughout implementation.
  Rationale: The repository scaffold already uses GHC2024 and generic-lens, while the
  planned CLI and live Hurl examples directly match those maintained standards.
  Date: 2026-09-18

- Decision: Make the profile-governed use-case bundle a hard governance dependency of EP-1.
  Rationale: Jobs, observable outcomes, and feature acceptance now exercise the proposed
  APIs before implementation; a compile-only dependency would not enforce that review gate.
  Date: 2026-09-18


## Outcomes & Retrospective


The pre-implementation contract review now has four structured, evidence-backed use cases
covering the initiative's primary workflows. Product implementation remains pending in
EP-1 through EP-6; their APIs must preserve the ratified acceptance contracts.


## Revision Note


2026-09-18: Reviewed every child plan against the current tree, Dhall/Hurl/process APIs,
the MasterPlan and ExecPlan contracts, and the applicable Haskell Jitsurei standards.
Tightened the shared workspace and execution APIs, made EP-4 a hard dependency of EP-5,
recorded Hurl environment/value semantics, and assigned previously implicit shared
artifacts to a single owning plan before implementation begins.

2026-09-18: Added EP-7 and the OKF use-case bundle as the initiative's pre-implementation
contract gate. Traced four evidence-backed jobs through planned features to the public APIs
and owning ExecPlans, then made EP-7 a governance dependency of EP-1.
