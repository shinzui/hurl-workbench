---
id: 6
slug: harden-document-and-package-the-workbench
title: "Harden Document and Package the Workbench"
kind: exec-plan
created_at: 2026-07-30T23:31:55Z
intention: "intention_01kytnndmnef28f9ksadwfac7h"
master_plan: "docs/masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md"
provenance:
  revisions:
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-18T18:29:32Z
      mode: "update"
      note: "Specified Haskell Jitsurei-aligned help, completion, version, Hurlfmt, and release contracts."
    - model: "gpt-5.6-sol"
      harness: "codex-cli"
      at: 2026-09-20T23:49:02Z
      mode: "implement"
      note: "Recorded the multi-package Nix default failure discovered during EP-2 acceptance."
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

- [x] (2026-09-20) Re-read all repository ADRs and the applicable Haskell Jitsurei CLI
  patterns; verified dependency APIs in the Mori corpus and current release metadata upstream.
- [x] (2026-09-20) Milestone 1 complete: terminal-aware help-on-error/help-on-empty,
  revision-aware version output, public Bash/Zsh/Fish completion generation, centralized CLI
  failure construction, dependency next actions, preflight labeling, and golden/protocol tests
  pass with 64 core and 33 CLI tests.
- [x] (2026-09-20) Milestone 2 complete: the executable quick start, workspace and CLI references,
  architecture and security guides, changelog, and both motivating example READMEs match live
  output. Hurlfmt accepted every checked-in Hurl file; the quick start, vendor matrix and special
  workflows, managed/external safe suite, mutating suite, and perimeter suite passed against the
  local fixture service.
- [ ] Milestone 3: reproducible Nix, Cabal, CI, source distributions, and release commands.
- [ ] Milestone 4: release acceptance, performance smoke, and initiative closure.


## Surprises & Discoveries


- Observation: optparse-applicative 0.19.0.0 exports the requested completion script functions,
  while its upstream release tag is `0.19.0`; the public generators accept both the executable
  invocation and completion function/program name. The implementation uses the stable
  `hurl-workbench` name for both.
  Evidence: local source at `mori://pcapriotti/optparse-applicative/packages/optparse-applicative`,
  the authoritative Hackage index, and upstream tag inspection on 2026-09-20.

- Observation: Cabal package version modules must be declared in both `autogen-modules` and
  `other-modules` for the library stanza under the current Cabal toolchain.
  Evidence: Cabal rejected the initial declaration as `autogen-not-exposed`; adding the generated
  module to `other-modules` made the library and all consumers build cleanly.


- Observation: `nix flake check` currently fails before building the application because the
  generated default package calls `callCabal2nix` on the repository root, where there is neither a
  `.cabal` file nor `package.yaml`. The actual Cabal packages live in `hurl-workbench-core/` and
  `hurl-workbench-cli/`. Milestone 3 must replace that single-root package assumption with a
  multi-package-aware default output before the initiative-wide Nix gate can pass.
  Evidence: EP-2's 2026-09-20 `nix flake check` failed in
  `cabal2nix-hurl-workbench.drv` with “Found neither a .cabal file nor package.yaml.”


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

- Decision: Expose completion generation as a first-class `completions SHELL` command and
  make `--version` revision-aware.
  Rationale: A stable public command avoids documenting optparse-applicative's hidden
  completion protocol, while a package version plus Git revision makes installed builds
  diagnosable. Both follow the applicable haskell-jitsurei CLI patterns.
  Date: 2026-09-18


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
source tree and will not work in sdists. The generated default Nix package also assumes one root
Cabal file and currently fails before evaluation can build either package. Resolve both packaging
issues here without editing the Seihou-managed module.

The repository has no CI workflow yet. `README.md` still describes the placeholder `hello`
command. `CHANGELOG.md` is a template. No release should be advertised until these are
consistent with the implemented CLI.

At this point, scan all local ADR filenames/headings and read every ADR created by EP-1
through EP-5. Update them when the actual interfaces differ from earlier decisions. No
cross-repository ADR was relevant when the MasterPlan was created.

Apply the CLI conventions in
`mori://shinzui/haskell-jitsurei/docs/cli-overview`,
`mori://shinzui/haskell-jitsurei/docs/cli-option-groups`,
`mori://shinzui/haskell-jitsurei/docs/cli-shell-completions`, and
`mori://shinzui/haskell-jitsurei/docs/cli-version-git-sha`. The example's hierarchical
Dhall CLI configuration is a legacy pattern and is not applicable: this program's Dhall
document is its domain workspace, not its command-line configuration.


## Plan of Work


### Milestone 1: Stabilize public CLI behavior and diagnostics


Review every command through `hurl-workbench-cli/src/HurlWorkbench/Cli/Options.hs` and the
command modules. Ensure top-level and subcommand help consistently use the terms fragment,
workflow, recipe, matrix, service, and suite. Build each command from a named
`ParserInfo`/option-group parser, and configure `customExecParser` with help-on-error,
help-on-empty, and terminal-width-aware output. Add `HurlWorkbench.Cli.Version`; render the
Cabal package version from `Paths_hurl_workbench_cli.version` plus a short Git revision.
Prefer the Nix-injected `GIT_HASH` CPP literal when defined; otherwise enable
`TemplateHaskell` only in the version module and use `$$(GitHash.tGitInfoCwdTry)` with
`GitHash.giHash`, falling back to `unknown` rather than failing a source build without
`.git` metadata.

Expose the stable public commands `hurl-workbench completions bash`, `... zsh`, and
`... fish`. Render them with the exported `bashCompletionScript`, `zshCompletionScript`,
and `fishCompletionScript` functions from `Options.Applicative.BashCompletion`, using the
stable command name `hurl-workbench`; the generated scripts call the hidden completion
query handled automatically by the same top-level parser. The hidden optparse-applicative
completion flags remain an implementation mechanism and compatibility smoke target, not
the documented API.

Create one `HurlWorkbench.Cli.Error` renderer that maps domain errors to concise stderr
messages and the established exit behavior. Errors must name the manifest and logical
entity, provide a next action when Hurl/Hurlfmt is missing, distinguish preflight from child
failure, and never print secret values or derived `Show` output. Add snapshot/golden tests
for help and representative errors after normalizing executable paths.

Exercise `doctor`, discovery from nested directories, unknown targets, malformed Dhall,
semantic failures, Hurlfmt failures, missing variables, mutation gates, readiness timeout,
Hurl failure, and interrupted service cleanup. Fix any cross-command inconsistency through
the owning interface rather than command-specific patches.

This milestone is complete when CLI help is internally consistent, the public completion
command works for all three shells, version output contains both package version and build
revision, every documented exit path is tested, and a secret-fixture scan finds no
credential in output.


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
  audited passthrough allowlist, artifacts, reports, and completion generation;
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
for project-specific tools. Extend the project module or package override to pass a stable
`GIT_HASH` CPP literal to the executable when `.git` is absent; keep the local `githash`
path as the development fallback and test both rendering paths.

Replace the generated single-root `packages.default` assumption through the supported project
customization mechanism so the default output builds the CLI package together with its local core
dependency. Prove the fix first with `nix build .#packages.aarch64-darwin.default` (or the current
host system's equivalent) and then with `nix flake check`; do not point `callCabal2nix` at the
repository root while it has no root Cabal package.

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

`just check` must run formatting checks, `hurlfmt --check` over every checked-in Hurl
fragment and example, `nix flake check`, Cabal build/tests, schema compatibility fixtures,
both local examples, and `cabal sdist all`. Inspect each tarball with `tar -tf` to prove it
contains required license/source/schema documentation and no secret fixtures, build
outputs, report outputs, or personal absolute paths.

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
   cabal run hurl-workbench -- completions bash
   cabal run hurl-workbench -- completions zsh
   cabal run hurl-workbench -- completions fish
   ```

   Also test the underlying optparse-applicative protocol directly so an upstream change
   cannot silently break the public wrapper.

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
- every CLI command has accurate help, grouped options, completion, revision-aware version
  output, redacted diagnostics, and tested exit behavior;
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

The required development-shell addition is `pkgs.hurl`; Hurl remains an external binary.
Use `githash >=0.1.7 && <0.2` and `terminal-size >=0.3.4 && <0.4` if the implementation
needs the terminal-width adapter described above. Mori has no registered source for either
package; these bounds and APIs were therefore checked against Hackage and their upstream
release tags after the required Mori search. Keep all Haskell bounds compatible with GHC
9.12.4 and perform the same verification for every direct dependency before finalizing
them. Do not add a documentation generator, installer framework, telemetry, networked CI
test service, or publishing credential.


## Revision Note


2026-09-18: Reviewed the release plan before implementation. The public CLI now has an
explicit completion subcommand, option-group and terminal-aware help requirements, and a
package-version-plus-Git-revision contract. Added the haskell-jitsurei CLI references,
Hurlfmt checks for checked-in resources, and Nix revision injection so the release surface
is specified rather than inferred from optparse-applicative internals.

2026-09-20: Recorded the existing multi-package Nix failure found during EP-2 acceptance and made
repairing the generated single-root default package assumption an explicit Milestone 3 obligation.
