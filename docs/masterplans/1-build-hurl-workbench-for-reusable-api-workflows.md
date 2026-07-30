---
id: 1
slug: build-hurl-workbench-for-reusable-api-workflows
title: "Build Hurl Workbench for Reusable API Workflows"
kind: master-plan
created_at: 2026-07-30T23:31:46Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
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

The first target is the repeated OAuth-plus-OData pattern seen in
`/Users/shinzui/Keikaku/work/clients/haskell/constellation1-client`: one OAuth capture
fragment should feed many resource-query fragments, with MLS-specific values expressed
as data rather than copied files. The second target is the integration-test pattern in
`/Users/shinzui/Keikaku/bokuno/mori-project/mori/mori-api/test/hurl`: safe and mutating
suites, optional service startup, readiness checks, generated variable files, and Hurl
report output.

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

The initiative is accepted when both bundled examples pass end to end with Hurl 8.x,
the vendor example demonstrates a single OAuth fragment reused by multiple parameterized
queries, the integration example manages a local service and emits a report, and
`nix flake check`, `nix fmt -- --check`, `cabal build all`, and `cabal test all` succeed.


## Decomposition Strategy


The work is divided by durable responsibility rather than by individual CLI command.
EP-1 owns the configuration boundary and normalized types. EP-2 owns pure composition and
rendering. EP-3 owns one secure, faithful Hurl invocation. EP-4 builds higher-level
exploration and repetition on that single-run primitive. EP-5 adds lifecycle orchestration
and test suites. EP-6 performs cross-cutting hardening, examples, packaging, and release
acceptance. This sequence keeps the early work mostly pure and independently testable,
then adds processes and services only after their inputs are stable.

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


## Exec-Plan Registry


| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| EP-1 | Define the Typed Hurl Workspace Contract | `docs/plans/1-define-the-typed-hurl-workspace-contract.md` | None | None | Not Started |
| EP-2 | Compose and Render Reusable Hurl Workflows | `docs/plans/2-compose-and-render-reusable-hurl-workflows.md` | EP-1 | None | Not Started |
| EP-3 | Execute Hurl Workflows Securely | `docs/plans/3-execute-hurl-workflows-securely.md` | EP-2 | None | Not Started |
| EP-4 | Add Recipes Matrices and Exploratory Runs | `docs/plans/4-add-recipes-matrices-and-exploratory-runs.md` | EP-3 | None | Not Started |
| EP-5 | Orchestrate Services and Integration Test Suites | `docs/plans/5-orchestrate-services-and-integration-test-suites.md` | EP-3 | EP-4 | Not Started |
| EP-6 | Harden Document and Package the Workbench | `docs/plans/6-harden-document-and-package-the-workbench.md` | EP-4, EP-5 | None | Not Started |

Status values are Not Started, In Progress, Complete, and Cancelled. Every child plan
inherits intention `intention_01kytnndmnef28f9ksadwfac7h` in its frontmatter.


## Dependency Graph


```mermaid
flowchart LR
    EP1[EP-1 Workspace contract] --> EP2[EP-2 Composition and rendering]
    EP2 --> EP3[EP-3 Secure execution]
    EP3 --> EP4[EP-4 Recipes and matrices]
    EP3 --> EP5[EP-5 Services and suites]
    EP4 -. shared run selection .-> EP5
    EP4 --> EP6[EP-6 Hardening and release]
    EP5 --> EP6
```

EP-2 requires EP-1 because fragment and workflow identities, paths, and parameter
contracts must be stable before composition can be implemented. EP-3 requires EP-2
because it executes a rendered workflow and must not duplicate rendering logic. EP-4
requires EP-3 because every recipe or matrix case reduces to the same tested single-run
request. EP-5 also requires EP-3 because suites and managed services ultimately bracket
one or more single-run requests. EP-5 should consume EP-4's final `RunSelection` model if
available, but service lifecycle can be developed against workflows and recipes while
EP-4 is finishing. EP-6 waits for both high-level feature streams so its examples and
release acceptance cover the actual product.

Once EP-3 is complete, EP-4 and the service-lifecycle portion of EP-5 may proceed in
parallel. EP-5's suite selector integration should wait until EP-4 has stabilized the
matrix and recipe interfaces.


## Integration Points


| Plans | Shared artifact | Owner | Consumption rule |
|---|---|---|---|
| EP-1 through EP-6 | `schema/package.dhall`, `schema/*.dhall`, and `HurlWorkbench.Workspace.Types` | EP-1 | Later plans extend behavior around the normalized model; schema changes go through record completion defaults and compatibility fixtures. |
| EP-1, EP-2, EP-4, EP-5 | Entity names and cross-reference validation | EP-1 | Each feature exports a validator for its own entities; `validateWorkspace` composes all validators without duplicating name lookup. |
| EP-2 through EP-5 | `RenderedWorkflow` | EP-2 | Only the composer constructs rendered Hurl. Executors treat it as immutable UTF-8 text plus workspace-root provenance. |
| EP-3 through EP-5 | `RunRequest`, `RunResult`, binding resolution, and Hurl process adapter | EP-3 | Recipes, matrices, and suites reduce their work to this single-run interface; they never construct raw Hurl argv independently. |
| EP-4 and EP-5 | `RunSelection` and expanded cases | EP-4 | Suites reference workflows, recipes, or matrices through one resolved sum type. EP-5 brackets resolved runs with services. |
| EP-3, EP-5, EP-6 | Hurl 8.x capability and report flags | EP-3 | `doctor` owns capability detection; later plans request features through typed options and do not probe binaries themselves. |
| EP-5 and EP-6 | Example fixture service and integration workspace | EP-5 | EP-6 documents and packages the accepted fixture instead of creating a second demonstration stack. |
| All plans | CLI errors and exit behavior | EP-1 defines domain errors; EP-3 defines child exit propagation | A Hurl-started run returns Hurl's exact exit status. Workbench discovery, validation, dependency, and orchestration failures remain distinguishable and tested. |

The opaque-fragment boundary, Dhall compatibility rules, secret redaction/transport,
non-shell service command representation, and exact Hurl exit propagation are intended to
be durable architecture constraints. The implementing plan that first makes each
constraint concrete must create or update the corresponding ADR.


## Progress


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


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


## Outcomes & Retrospective


(To be filled during and after implementation.)
