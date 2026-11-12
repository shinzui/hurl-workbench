---
name: release
description: Release hurl-workbench-core and hurl-workbench-cli to Hackage following PVP
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# hurl-workbench Release Skill

Release this repository's two packages to [Hackage](https://hackage.haskell.org/)
using the Haskell **PVP** version format (`A.B.C.D`).

## Versioning Strategy

`hurl-workbench-core` and `hurl-workbench-cli` **share one version number** and
are released together. A single annotated git tag `v<version>` marks each
release. This shared-version invariant is enforced by the repo itself: `just
sync-check` requires `LICENSE`, `CHANGELOG.md`, `README.md`, and `schema/` to be
byte-identical in both package directories (and `examples/` copied into the cli
package), so the two cabal versions must never diverge.

PVP (`A.B.C.D`):
- `A.B` — **major**: breaking API changes (removed/renamed exports, changed
  types, changed semantics, incompatible CLI/Dhall-schema changes).
- `C` — **minor**: backwards-compatible API additions (new exports, new modules,
  new instances, new CLI flags/commands).
- `D` — **patch**: bug fixes, documentation, performance, internal-only changes.

> Note: the root `CHANGELOG.md` header mentions SemVer and "Keep a Changelog",
> but Hackage ordering is PVP — a four-component version where **`A.B`** together
> is the breaking-change axis. Apply the PVP rules above when choosing the bump.

## Packages (in dependency order)

Publish in this order because of the inter-package dependency:

1. **hurl-workbench-core** (`hurl-workbench-core/`) — core library, no internal
   deps.
2. **hurl-workbench-cli** (`hurl-workbench-cli/`) — library + the
   `hurl-workbench` executable; depends on `hurl-workbench-core`.

The following are **NOT** separately released to Hackage — they are internal
components of the two packages above, not standalone packages:

- the `hurl-workbench-fixture-server` executable (test-only fixture HTTP
  server, in `hurl-workbench-cli`);
- the `hurl-workbench-core-test` and `hurl-workbench-cli-test` test-suites;
- the `examples/` workspaces (shipped *inside* the cli sdist, not as a package).

## Arguments

`$ARGUMENTS` is optional:
- `major`, `minor`, or `patch` — the bump level.
- If omitted, infer the bump from the changes (step 2).

## Steps

### 1. Determine what changed since the last release

- Read the current shared version from either cabal file (they match):
  `hurl-workbench-core/hurl-workbench-core.cabal` or
  `hurl-workbench-cli/hurl-workbench-cli.cabal` (the `version:` field).
- Find the latest release tag: `git tag --list 'v*' | sort -V | tail -1`.
  - **First release:** this repo currently has no tags. If there is no `v*`
    tag, treat this as the initial release — summarize all of `git log --oneline`
    and use the `## [Unreleased]` section of `CHANGELOG.md` as the change set.
  - Otherwise run `git log --oneline <last-tag>..HEAD`. If empty, tell the user
    there is nothing to release and stop.
- Present a summary: current version, last tag (or "none — first release"),
  commit count since, and which of `hurl-workbench-core/` or
  `hurl-workbench-cli/` have changes (`git diff --stat <last-tag>..HEAD -- <dir>`).

### 2. Determine the next version using PVP

- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use it.
- Otherwise analyze the commits (Conventional Commits are used in this repo —
  see the global `CLAUDE.md`):
  - `feat!:` / `BREAKING CHANGE:` / "remove"/"rename"/changed types → **major**.
  - `feat:` / new module / new export / new CLI flag → **minor**.
  - `fix:` / `docs:` / `refactor:` / `test:` / `chore:` / internal → **patch**.
- Increment:
  - **major**: bump `B`, reset `C` and `D` to 0 (`0.1.0.0` → `0.2.0.0`).
  - **minor**: bump `C`, reset `D` to 0 (`0.1.0.0` → `0.1.1.0`).
  - **patch**: bump `D` (`0.1.0.0` → `0.1.0.1`).
- **Present the proposed bump and wait for confirmation before editing anything.**

### 3. Update versions, internal bound, changelogs, and release copies

#### Version update
Set the new `version:` in **both** cabal files:
- `hurl-workbench-core/hurl-workbench-core.cabal`
- `hurl-workbench-cli/hurl-workbench-cli.cabal`

#### Internal dependency bound
`hurl-workbench-cli` depends on `hurl-workbench-core` in both its `library` and
`test-suite hurl-workbench-cli-test` `build-depends`. The current cabal declares
it **unbounded** (bare `hurl-workbench-core,`). Because the two packages share a
version, add/update a PVP bound so published metadata constrains it:
`hurl-workbench-core ^>=<new-version>` in both stanzas. (If a future cabal
already carries a bound, bump it to the new version instead.)

#### Hardcoded release versions in scripts
`scripts/check-sdist.sh` (run by the `sdist` / `just check` gate) **hardcodes the
current version**. Update every occurrence to the new version, or the gate in
step 4 will fail:
- the archive names `hurl-workbench-core-<old>.tar.gz` and
  `hurl-workbench-cli-<old>.tar.gz`;
- the two unpacked directory names `./hurl-workbench-core-<old>` and
  `./hurl-workbench-cli-<old>` written into the generated `cabal.project`;
- the expected `--version` fallback string `hurl-workbench <old> (unknown)`.

Grep first to catch them all: `rg -n '<old-version>' scripts/`.

#### Changelog update (root, then sync copies)
1. Edit the root `CHANGELOG.md`:
   - Keep the `## [Unreleased]` heading (leave it empty for future work).
   - Add a new `## [<new-version>] - <YYYY-MM-DD>` section (today's date) below
     it, moving the accumulated Unreleased entries into it.
   - This repo already has a `## [0.1.0.0] - Unreleased` placeholder — on the
     first release, replace `Unreleased` in that heading with today's date and
     the final version rather than adding a duplicate section.
   - Group entries under the Keep-a-Changelog headings already in use:
     `### Added`, `### Changed`, `### Fixed`, `### Security`, `### Compatibility`
     — include only the ones that have entries.
2. **Sync the release copies** so `just sync-check` passes — the per-package
   copies are real files, not symlinks, and there is no auto-sync script:
   ```bash
   cp CHANGELOG.md hurl-workbench-core/CHANGELOG.md
   cp CHANGELOG.md hurl-workbench-cli/CHANGELOG.md
   ```
   If you also changed `README.md`, `LICENSE`, `schema/`, or (cli only)
   `examples/` in this release, re-sync those too:
   ```bash
   cp README.md hurl-workbench-core/README.md && cp README.md hurl-workbench-cli/README.md
   cp LICENSE  hurl-workbench-core/LICENSE  && cp LICENSE  hurl-workbench-cli/LICENSE
   rsync -a --delete schema/   hurl-workbench-core/schema/
   rsync -a --delete schema/   hurl-workbench-cli/schema/
   rsync -a --delete examples/ hurl-workbench-cli/examples/
   ```

**Show the user every change** (both cabal versions, the internal bound, the
`scripts/check-sdist.sh` edits, the changelog section, and the synced copies)
and get approval before running the gates or committing.

### 4. Run the full release gate

From inside the dev shell (`nix develop`):

```bash
nix fmt            # format first; treefmt/fourmolu, must be clean
git add -A         # nix evaluates the git tree — new/changed files must be staged
just check         # the complete gate (see below)
```

`just check` runs, in order: `fmt-check`, `hurlfmt-check`, `sync-check`,
`build` (`cabal build all`), `test` (`cabal test all`), `schema-check`,
`performance`, `examples`, `sdist` (`scripts/check-sdist.sh`), and `nix-check`
(`nix flake check`). All must pass.

- `sync-check` is why step 3's copies matter; `sdist` is why the
  `scripts/check-sdist.sh` version edits matter.
- Optional cross-platform gate: on a Mac with Apple `container` running,
  `just linux-check` runs the same gate in a disposable ARM64 Linux VM.
- If any check fails, **fix it and re-run before proceeding** — never publish on
  a red gate.

### 5. Commit, tag, and push

- Stage the cabal files, `scripts/check-sdist.sh`, all `CHANGELOG.md` copies, and
  any other synced files.
- One commit, Conventional Commits style (repo convention — global `CLAUDE.md`):
  `chore(release): <new-version>`. Body: what's in the release and why this bump.
- One **annotated** tag: `git tag -a v<new-version> -m "Release <new-version>"`.
- Push: `git push && git push --tags`.

### 6. Publish to Hackage (core → cli)

Build canonical source archives with the repo's script (it normalizes the cli
archive's file modes so the executable `examples/**/*.py` helpers stay
executable):

```bash
sdist_dir="$(mktemp -d)"
bash scripts/build-sdist.sh "$sdist_dir"
# produces $sdist_dir/hurl-workbench-core-<v>.tar.gz and hurl-workbench-cli-<v>.tar.gz
```

Then, **for each package in order — `hurl-workbench-core` first, then
`hurl-workbench-cli`**:

1. `cd <pkg-dir>` and run `cabal check` (no packaging warnings).
2. Upload the source distribution and publish it:
   `cabal upload --publish "$sdist_dir/<pkg>-<v>.tar.gz"`.
3. Build and upload Haddock docs:
   ```bash
   cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump
   cabal upload --publish --documentation dist-newstyle/<pkg>-<v>-docs.tar.gz
   ```
   (use the exact docs tarball path cabal prints).
4. Report the Hackage URL: `https://hackage.haskell.org/package/<pkg>-<v>`.

**Stop immediately if the core upload fails — do not upload cli, which depends on
it.**

Final summary table:

| Package | Version | Hackage URL |
|---------|---------|-------------|
| hurl-workbench-core | <v> | https://hackage.haskell.org/package/hurl-workbench-core-<v> |
| hurl-workbench-cli  | <v> | https://hackage.haskell.org/package/hurl-workbench-cli-<v> |

### 7. Create the GitHub release

After both Hackage uploads succeed (`gh` is installed; `shinzui/hurl-workbench`
is public):

```bash
gh release create v<v> --title "v<v>" --notes "$(cat <<'EOF'
## Packages

| Package | Hackage |
|---------|---------|
| hurl-workbench-core | https://hackage.haskell.org/package/hurl-workbench-core-<v> |
| hurl-workbench-cli  | https://hackage.haskell.org/package/hurl-workbench-cli-<v> |

## What's Changed

<the root CHANGELOG.md section for this version>
EOF
)"
```

Report the GitHub release URL when done.

## Important

- Always confirm the version bump, bound, script edits, and changelog **before**
  committing (step 3) — the commit and tag are created only after approval.
- Both cabal versions must stay identical; keep the internal
  `hurl-workbench-core` bound and the per-package `CHANGELOG.md`/`README.md`/
  `LICENSE`/`schema`/`examples` copies in sync, and update the hardcoded versions
  in `scripts/check-sdist.sh`.
- Always publish in dependency order: `hurl-workbench-core` → `hurl-workbench-cli`.
- Never skip `nix fmt`, `cabal check`, or `just check` (`sync-check`, `sdist`,
  tests, and `nix flake check` included).
- If any step fails, **stop and report** rather than continuing.
- If the `hurl-workbench-core` Hackage upload fails, do **not** continue to
  `hurl-workbench-cli`.
