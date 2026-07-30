---
id: 6
slug: harden-document-and-package-the-workbench
title: "Harden Document and Package the Workbench"
kind: exec-plan
created_at: 2026-07-30T23:31:55Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
---

# Harden Document and Package the Workbench


This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in `docs/adr/` in the same
change.


## Purpose / Big Picture


This plan turns the completed feature streams into a coherent first release. A new user can
enter the Nix shell, follow one quick start, understand the workspace schema and security
model, run both examples without external services, generate shell completion, and build
clean source distributions. CI exercises formatting, compilation, unit tests, real Hurl
integration, both examples, schema compatibility, and package contents.


## Progress


(No implementation work has started.)


## Surprises & Discoveries


(None yet.)


## Decision Log


- Decision: Ship Hurl/Hurlfmt in the Nix development shell but keep Hurl an external runtime
  dependency of the Cabal packages.
  Rationale: The workbench delegates execution to the official binary and should neither
  embed nor reimplement it; the Nix shell still makes the supported toolchain reproducible.
  Date: 2026-07-30

- Decision: Treat the vendor and managed-service examples as release acceptance fixtures.
  Rationale: They directly represent the two motivating use cases and catch integration
  gaps that isolated unit tests cannot.
  Date: 2026-07-30

- Decision: Prepare release artifacts but do not publish them in this plan.
  Rationale: Publishing to Hackage or creating a remote release is an external state change
  that requires separate explicit authorization.
  Date: 2026-07-30


## Outcomes & Retrospective


(To be filled during and after implementation.)


## Context and Orientation


This plan depends on completed EP-4 and EP-5. By then the repository should contain the
typed workspace, deterministic composition, secure Hurl execution, recipes/matrices,
managed services/suites, and two examples. EP-6 does not redesign those interfaces; it
finds inconsistencies, improves user-facing behavior, documents the final product, and
establishes repeatable release checks.

The current template pins GHC 9.12.4 through `nix/haskell.nix`. That file is managed by
Seihou and explicitly directs project customizations to a new `flake.module.nix` using
`haskellProject.extraDevPackages`. The initial two Cabal packages refer to `../LICENSE` and
`../CHANGELOG.md`, which makes `cabal build` warn that those files are outside each package
source tree and will not work in sdists. Resolve that packaging issue here.

The repository has no CI workflow yet. `README.md` still describes the placeholder `hello`
command. `CHANGELOG.md` is a template. No release should be advertised until these are
consistent with the implemented CLI.

At this point, scan all local ADR filenames/headings and read every ADR created by EP-1
through EP-5. Update them when the actual interfaces differ from earlier decisions. No
cross-repository ADR was relevant when the MasterPlan was created.


## Plan of Work


### Milestone 1: Stabilize public CLI behavior and diagnostics


Review every command through `hurl-workbench-cli/src/HurlWorkbench/Cli/Options.hs` and the
command modules. Ensure top-level and subcommand help consistently use the terms fragment,
workflow, recipe, matrix, service, and suite. Add `--version` using the Cabal package
version. Retain optparse-applicative's generated Bash, Zsh, and Fish completion hooks and
document the exact commands.

Create one `HurlWorkbench.Cli.Error` renderer that maps domain errors to concise stderr
messages and the established exit behavior. Errors must name the manifest and logical
entity, provide a next action when Hurl/Hurlfmt is missing, distinguish preflight from child
failure, and never print secret values or derived `Show` output. Add snapshot/golden tests
for help and representative errors after normalizing executable paths.

Exercise `doctor`, discovery from nested directories, unknown targets, malformed Dhall,
semantic failures, Hurlfmt failures, missing variables, mutation gates, readiness timeout,
Hurl failure, and interrupted service cleanup. Fix any cross-command inconsistency through
the owning interface rather than command-specific patches.

This milestone is complete when CLI help is internally consistent, completion generation
works for all three shells, every documented exit path is tested, and a secret-fixture scan
finds no credential in output.


### Milestone 2: Write reference documentation and complete examples


Rewrite `README.md` around a five-minute quick start:

1. enter `nix develop`;
2. inspect `hurl-workbench --help` and `doctor`;
3. define one fragment/workflow with the bundled Dhall schema;
4. validate and render it;
5. run it with an environment-backed secret;
6. point to the two complete examples.

Create:

- `docs/reference/workspace.md` with every schema field, completion pattern, discovery rule,
  name/path restriction, reference rule, binding precedence, safety marker, and compatible
  evolution rule;
- `docs/reference/cli.md` with command synopsis, input/output channels, exit behavior,
  passthrough denylist, artifacts, reports, and completion generation;
- `docs/architecture.md` with the opaque-fragment boundary and the flow from workspace to
  expanded run to rendered Hurl to external process;
- `docs/security.md` with secret sources, temp permissions, cleanup, process argv, Hurl's
  response-body/report caveat, mutating gates, service execution, and workspace path model;
- the vendor and integration guides begun in EP-4 and EP-5, updated against actual output.

Finish both example READMEs with copy/paste commands and expected output shapes. Examples
must use only fixture values and local endpoints, contain no personal path, credential,
vendor hostname, or production response, and be syntax-checked by Hurlfmt in tests. Include
a compatibility fixture authored with only the original completion fields so schema changes
cannot silently break old workspaces.

Update `CHANGELOG.md` with an `0.1.0.0` unreleased section summarizing the workspace,
composition, execution, matrix, suite, security, and supported Hurl version. Do not claim a
release date or publication.

This milestone is complete when a clean-shell user can follow each README verbatim and all
documented snippets are exercised by a test or a release-check command.


### Milestone 3: Make Nix, Cabal, CI, and source distributions reproducible


Create `flake.module.nix` rather than editing Seihou-managed `nix/haskell.nix`. Set:

```nix
{ ... }:
{
  perSystem = { pkgs, ... }: {
    haskellProject.extraDevPackages = [ pkgs.hurl ];
  };
}
```

Confirm the pinned nixpkgs Hurl is at least 8.0.0 and that both `hurl` and `hurlfmt` appear
in `nix develop`. If nixpkgs has a later major, let `doctor` display the untested-major
warning and pin only if an actual compatibility test fails. Do not edit generated Nix files
for project-specific tools.

Fix the Cabal sdist warnings by giving each package source tree its own included license and
changelog file, or by another Cabal-supported layout proven by `cabal sdist all`. Keep the
canonical root files synchronized through an explicit release check; do not leave
outside-tree references. Review exposed versus internal modules and ensure test fixtures,
Dhall schema, examples, and required docs appear in the appropriate `extra-source-files` or
`data-files` lists.

Add a root `Justfile` with non-destructive convenience recipes that directly run the
canonical commands: `build`, `test`, `fmt`, `check`, `examples`, and `sdist`. The recipes
must not hide arguments needed for debugging. Add `.github/workflows/ci.yml` using the
repository's Nix toolchain and cache settings to run the same `just check` on Linux. Do not
put credentials in the workflow; real external-vendor tests are not part of CI.

`just check` must run formatting check, `nix flake check`, Cabal build/tests, schema
compatibility fixtures, both local examples, and `cabal sdist all`. Inspect each tarball
with `tar -tf` to prove it contains required license/source/schema documentation and no
secret fixtures, build outputs, report outputs, or personal absolute paths.

This milestone is complete when a clean checkout passes the same local and CI command and
both source distributions can be unpacked and built without reaching outside their source
trees except for declared package dependencies.


### Milestone 4: Run release acceptance and close the initiative records


Run the complete acceptance matrix on macOS locally and Linux in CI:

- minimal and completion-compat workspace load;
- OAuth-plus-OData render and matrix execution;
- bespoke capture/assert and raw exploration recipes;
- safe, mutating, perimeter, managed-service, and external-service suites;
- JUnit, HTML, JSON, and TAP reports;
- missing dependency, syntax failure, binding failure, child failure, timeout, interruption,
  cleanup, concurrency, and redaction tests;
- source distributions and Nix package build.

Measure a synthetic workspace with 100 fragments/cases to catch accidental quadratic
lookup or unbounded process scheduling. This is a smoke threshold rather than a public
performance promise: validation/rendering should complete promptly and peak active Hurl
processes must remain at the requested job limit.

Review every child plan's living sections and update the MasterPlan registry/status. Distill
durable decisions and implementation surprises into `docs/adr/`; keep command transcripts
and task-local details in the plans. Do not mark plans complete until their commands and
acceptance statements match the tree. Prepare a conventional commit with `ExecPlan:`,
`MasterPlan:`, and `Intention: intention_01kytnndmnef28f9ksadwfac7h` trailers if the user
asks for a commit. Do not publish packages or create remote releases without a separate
request.


## Concrete Steps


Run commands from `/Users/shinzui/Keikaku/bokuno/hurl-workbench`.

1. Verify toolchain and final help:

   ```bash
   nix develop -c hurl --version
   nix develop -c hurlfmt --version
   nix develop -c cabal run hurl-workbench -- --version
   nix develop -c cabal run hurl-workbench -- doctor
   ```

2. Generate completion smoke tests:

   ```bash
   cabal run hurl-workbench -- --bash-completion-script hurl-workbench
   cabal run hurl-workbench -- --zsh-completion-script hurl-workbench
   cabal run hurl-workbench -- --fish-completion-script hurl-workbench
   ```

3. Run the canonical full check:

   ```bash
   nix develop -c just check
   ```

   Expected final shape:

   ```text
   formatting: PASS
   build: PASS
   tests: PASS
   vendor example: PASS
   integration example: PASS
   source distributions: PASS
   ```

4. Inspect repository state and generated artifacts before any commit:

   ```bash
   git status --short
   git diff --check
   cabal sdist all
   ```

5. If and only if the user requests a commit, format first and use a Conventional Commit
   with plan linkage, for example:

   ```text
   feat: deliver reusable Hurl workflow workbench

   ExecPlan: docs/plans/6-harden-document-and-package-the-workbench.md
   MasterPlan: docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md
   Intention: intention_01kytnndmnef28f9ksadwfac7h
   ```


## Validation and Acceptance


- a clean Nix shell contains GHC 9.12.4, Hurl/Hurlfmt 8.x or a tested compatible later
  version, and all developer tools;
- every CLI command has accurate help, completion, redacted diagnostics, and tested exit
  behavior;
- both motivating examples run entirely against local fixture services;
- docs specify the opaque-Hurl architecture, workspace schema, precedence, safety, and
  security limitations without relying on these plans;
- compatibility fixtures prove completion-based schema evolution;
- `just check`, `nix flake check`, `cabal build all`, `cabal test all`, and
  `cabal sdist all` succeed;
- sdists contain required source/schema/docs/licenses and no build/report/secret artifacts;
- CI runs the same acceptance path without external credentials;
- all child plans, ADRs, and the MasterPlan reflect the implemented state;
- no package or remote release is published by this plan.


## Idempotence and Recovery


Formatting, checks, docs generation, example tests, and sdists are safe to repeat. Release
checks write only to ignored build/report/dist locations and exact completion output files.
If an example fails, preserve its report directory for diagnosis but terminate its service.
If a source distribution omits a file, update Cabal metadata and regenerate rather than
editing the archive. Do not delete user workspaces or external reports. Publishing remains
outside scope, so recovery never requires reverting a remote package or release.


## Interfaces and Dependencies


EP-6 does not introduce a new domain layer. It owns the final CLI error/help surface,
documentation set, Nix customization, Justfile, CI workflow, package metadata, and release
acceptance. All functional behavior must flow through EP-1 through EP-5 interfaces.

The only required development-shell addition is `pkgs.hurl`; Hurl remains an external
binary. Keep Haskell bounds compatible with GHC 9.12.4 and verify every direct dependency
against Mori-located source, the current Hackage registry, and upstream release tags before
finalizing them. Do not add a documentation generator, installer framework, telemetry,
networked CI test service, or publishing credential.
