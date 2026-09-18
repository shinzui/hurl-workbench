---
id: 7
slug: document-and-ratify-hurl-workbench-use-cases
title: "Document and Ratify Hurl Workbench Use Cases"
kind: exec-plan
created_at: 2026-09-18T18:38:26Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
provenance:
  created_by:
    model: "gpt-5.6-sol"
    harness: "codex-cli"
    at: 2026-09-18T18:38:26Z
---

# Document and Ratify Hurl Workbench Use Cases

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Purpose / Big Picture

Before implementation starts, this plan turns the motivating API-workflow scenarios into
a profile-governed OKF use-case bundle. A reviewer can follow each job-to-be-done through
an observable feature acceptance statement to the Haskell contract and ExecPlan that owns
it. This makes the use cases a validation gate for the API rather than explanatory prose
added after implementation.

The result is visible by reading `docs/use-cases/index.md` and by running strict OKF
validation. The four initial use cases cover authenticated workflow reuse, parameterized
API cases, repeatable integration suites, and raw-wire diagnosis when a typed client fails.


## Progress

- [x] (2026-09-18 18:44Z) Registered and pinned the use-case profile and bundle metadata.
- [x] (2026-09-18 18:44Z) Wrote four evidence-backed use cases and their contract
  traceability maps.
- [x] (2026-09-18 18:44Z) Made this review a MasterPlan entry gate and cascaded it to EP-1.
- [x] (2026-09-18 18:45Z) Typechecked the Dhall metadata, strictly validated five OKF
  concepts, resolved all four graph edges, and passed `git diff --check`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence.

- Observation: The use-case profile separates use-case maturity from feature delivery.
  A scenario may be `validated` because its actor, job, and acceptance contract are
  evidence-backed while every implementing feature remains `planned`.
  Evidence: `mori://shinzui/okf-profiles/profiles/use-cases`, version 0.15.0.


## Decision Log

Record every decision made while working on the plan.

- Decision: Use the OKF `jtbd-use-cases` profile at the released `okf-profiles` v0.15.0
  tag and freeze its import hash.
  Rationale: The profile requires structured jobs, owned features, and observable
  acceptance while the tag and semantic hash make validation reproducible.
  Date: 2026-09-18

- Decision: Treat this plan as a governance dependency of EP-1.
  Rationale: The user explicitly wants the scenarios to test the public APIs and contracts
  before code fixes them in place; this dependency is an initiative entry criterion, not a
  Haskell compile dependency.
  Date: 2026-09-18

- Decision: Mark the four scenarios `validated` and their feature slices `planned`.
  Rationale: Existing repositories demonstrate all four jobs, while this repository has
  not implemented their workbench capabilities yet.
  Date: 2026-09-18


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

The repository now has a pinned, Mori-registered OKF 0.2 use-case bundle containing four
validated scenarios and one reviewed theme. Strict profile and log enforcement accepted
all five concepts, and the graph resolved each use case to the theme. Each feature remains
`planned`, so no product delivery is implied.

The contract maps confirmed that the proposed boundaries cover the observed jobs without
adding another product abstraction: EP-1 owns validated configuration, EP-2 owns faithful
composition, EP-3 owns secure single-run process behavior, EP-4 owns prepared batch cases,
and EP-5 owns service and suite orchestration. EP-1 through EP-6 remain the outstanding
product work.


## Context and Orientation

The product is still pre-implementation. The initiative is coordinated by
`docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md`; EP-1 through EP-6
own the workspace, composition, execution, repetition, service, and release contracts.
There is no existing `docs/use-cases/` bundle and no local `docs/adr/` corpus.

The profile is `mori://shinzui/okf-profiles/profiles/use-cases`. Its `Use Case` records
require one or more jobs-to-be-done and features. A *job* states the actor, situation,
motivation, and observable outcome. A *feature* names an owned capability, delivery state,
acceptance evidence, and the jobs it advances. The bundle uses OKF 0.2 and is registered in
`mori.dhall` so Mori can discover it.

Two existing repositories provide concrete evidence. The OAuth and OData experiments in
`mori://tan/constellation1-client-hs/repos/constellation1-client-hs`, project-relative path
`playground/`, repeat authentication and resource requests and include typed-decoder failure
investigations. The suite in `mori://shinzui/mori/repos/mori`, project-relative path
`mori-api/test/hurl/`, explicitly separates safe, mutating, signed, and perimeter tests and
supports an already-running service. These references motivate jobs; they do not make this
repository depend on either codebase.

No ADR is needed for this plan because it records product requirements and traceability,
not a runtime architecture choice. EP-1 and later plans still create ADRs when their durable
architecture constraints become concrete.


## Plan of Work

### Milestone 1: Establish the governed bundle

Add `docs/use-cases/profile.dhall`, pinned to `okf-profiles` v0.15.0 and frozen with a
semantic hash. Add `docs/use-cases/index.md`, `log.md`, and
`themes/developer-tooling.md`. Register the bundle in `mori.dhall` with OKF version 0.2.
This milestone is accepted when both Dhall files typecheck and OKF recognizes the bundle.

### Milestone 2: Ratify jobs and acceptance contracts

Add four `Use Case` concepts under `docs/use-cases/`. Each concept records real actors and
jobs, keeps feature delivery at `planned`, cites canonical Mori evidence, and maps feature
acceptance to the exact public contracts and local ExecPlans that own delivery. This
milestone is accepted when a reviewer can trace every feature to at least one job and one
implementation owner without inferring a new API.

### Milestone 3: Integrate and validate the initiative gate

Update the MasterPlan registry and graph so EP-7 precedes EP-1, add the OKF bundle to the
integration map, and update EP-1 context with the ratified inputs. Run strict, enforced OKF
validation and the repository's documentation checks. This milestone is accepted when the
MasterPlan is internally consistent and all available checks pass.


## Concrete Steps

Run from `/Users/shinzui/Keikaku/bokuno/hurl-workbench`:

    dhall freeze --all --inplace docs/use-cases/profile.dhall
    dhall type --file docs/use-cases/profile.dhall
    dhall type --file mori.dhall
    okf validate docs/use-cases --strict \
      --profile docs/use-cases/profile.dhall --profile-enforce --log-enforce
    okf graph docs/use-cases
    git diff --check

Expected validation includes a success result for four use cases and one theme with no
profile or log-enforcement errors. `okf graph` must resolve all body links.


## Validation and Acceptance

Acceptance requires all of the following:

- strict profile-enforced validation accepts the complete bundle;
- UC-1 through UC-4 each contain jobs with observable outcomes and feature slices with
  explicit acceptance, project ownership, and `planned` delivery state;
- each use case names the local ExecPlan and public contracts that must satisfy it;
- the MasterPlan dependency graph prevents EP-1 implementation from preceding this gate;
- `mori.dhall` advertises `docs/use-cases` as an OKF 0.2 bundle; and
- the update log explains that validation of a scenario does not claim implementation.


## Idempotence and Recovery

All edits are documentation or declarative metadata and can be reapplied safely. `dhall
freeze --all --inplace` is idempotent once the import is frozen. If validation fails, keep
the profile pinned, correct the reported concept locally, and rerun the exact command; do
not relax `--strict`, `--profile-enforce`, or `--log-enforce` to obtain a green result.


## Interfaces and Dependencies

This plan adds no Haskell library or runtime dependency. It depends on OKF 0.2, the
`jtbd-use-cases` profile exported by
`mori://shinzui/okf-profiles/profiles/use-cases` at v0.15.0, the repository's existing
Mori project schema, and the `okf`, `dhall`, and `mori` command-line tools.

The use cases validate, but do not redefine, the interfaces owned by EP-1 through EP-5:
`ValidatedWorkspace`, category-specific logical-name newtypes, `HurlValueLiteral`,
`ResolvedWorkflow`, `RenderedWorkflow`, `HurlRunner`, `RunRequest`, `RunResult`,
`RunSelection`, `PreparedRun`, `BatchResult`, typed case outcomes, and the managed-service
suite boundary. If a use case cannot be satisfied by these contracts, the owning ExecPlan
must be revised before implementation rather than adding an undocumented escape hatch.
