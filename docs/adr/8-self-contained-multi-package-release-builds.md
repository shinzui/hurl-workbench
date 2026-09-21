# ADR 8: Keep release packages self-contained and wire them explicitly in Nix


Status: Accepted

Date: 2026-09-20

Origin: [EP-6](../plans/6-harden-document-and-package-the-workbench.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


The repository contains two Cabal packages below the root. A generated default Nix output assumed
one root Cabal package and failed before either real package could build. Cabal source
distributions also cannot depend on license, changelog, schema, fixture, or example files outside
their package source trees.

The pinned GHC 9.12.4 Nix package set lags several direct bounds used by the packages. Bringing
Warp forward also requires a coherent HTTP/2, HTTP Semantics, time-manager, recv, and network
cohort; upgrading only the direct dependency fails during Cabal configuration. Aeson has the
opposite constraint: Dhall 1.42.3 requires Aeson below 2.3.


## Decision


The Seihou-managed built-in root package is disabled through its supported
`nix.builtin-package = false` variable. The unmanaged `flake.module.nix` constructs the core and
CLI packages independently with `callCabal2nix`, makes the CLI the default output, and passes the
flake revision as the `GIT_HASH` compile-time definition. A source build outside Git retains the
runtime `unknown` fallback.

Until the shared package registry supplies the complete cohort, the project module uses
fixed-output Hackage archives for the exact compatible releases. The upstream work is tracked as
`mori://shinzui/haskell-nix/okf/improvement-requests/concepts/IR-2`; once that request is delivered,
the local dependency replacements should be deleted in favor of the shared extension.

Each Cabal package owns package-local copies of the root license, changelog, README, and Dhall
schema. The CLI package additionally owns the examples it distributes. `just sync-check` proves
those copies remain byte-identical to their canonical root counterparts, while the sdist check
unpacks both archives, rejects generated/secret-shaped artifacts and personal paths, builds the
unpacked project, and proves the revision fallback.

Nix package derivations skip the repository test suites because those tests intentionally reach
across package boundaries for shared fixtures. The release gate does not skip them: `just check`
runs Cabal's complete test suites, live local examples, schema compatibility, performance smoke,
sdist builds, and `nix flake check` before accepting the package derivations.


## Consequences


The default Nix output and both source archives build from their declared source trees instead of
accidentally depending on repository layout. Package metadata is duplicated deliberately, with an
executable synchronization invariant rather than an unenforced convention. The Nix graph is
larger than a plain locked nixpkgs graph until IR-2 centralizes the compatibility cohort, but every
replacement is content-addressed and the Cabal and Nix dependency contracts agree.

The generated single-root assumption belongs to the `nix-haskell-flake` template in
`mori://shinzui/seihou-modules`; artifact-level URI coverage for its template source is pending.
This repository uses the template's supported escape hatch rather than modifying generated Nix
files by hand.
