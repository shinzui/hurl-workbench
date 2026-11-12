---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Mori registry unavailable during dependency and lease discovery](1-mori-registry-unavailable-during-dependency-and-lease-discovery.md) - The registry requires an unavailable local PostgreSQL socket, preventing source and Hinagata discovery.
- [Lifecycle fixture publishes readiness before logging readiness](10-lifecycle-fixture-publishes-readiness-before-logging-readiness.md) - The existing suite fixture allows Hurl and cancellation to race its readiness event, making release checks fail intermittently.
- [Mori registry unavailable during file-root implementation](11-mori-registry-unavailable-during-file-root-implementation.md) - The local registry PostgreSQL socket refused connections, preventing dependency source discovery.
- [Clean Linux release driver defaults to an ASCII filesystem locale](12-clean-linux-release-driver-defaults-to-an-ascii-filesystem-locale.md) - The Apple-container release gate could not construct required Unicode path fixtures because its inherited locale used ASCII.
- [Inherited Mori endpoint uses retired PostgreSQL socket](13-inherited-mori-endpoint-uses-retired-postgresql-socket.md) - Mori registry discovery failed until a command-local override selected the endpoint already declared in the shell profile.
- [Parallel tests race process-global environment mutation](2-parallel-tests-race-process-global-environment-mutation.md) - Existing binding tests mutate libc environ while unrelated tests spawn children, intermittently causing posix_spawnp Bad address.
- [Disposable Linux validation compiles a cold development toolchain](3-disposable-linux-validation-compiles-a-cold-development-toolchain.md) - The Apple-container release gate has no persistent Nix store, making its first development-shell realization compile many dependencies before project validation.
- [Mori registry unavailable through PostgreSQL tunnel](4-mori-registry-unavailable-through-postgresql-tunnel.md) - Registry discovery and provider source lookup cannot proceed while the Sungkyung PostgreSQL tunnel refuses connections.
- [Linux release gate realizes editor-only HLS dependencies](5-linux-release-gate-realizes-editor-only-hls-dependencies.md) - The Linux release script enters the full editor development shell and spends validation time building HLS dependencies unrelated to the release checks.
- [Mori registry unavailable during multi-service implementation](6-mori-registry-unavailable-during-multi-service-implementation.md) - The configured Mori PostgreSQL socket refuses connections, blocking dependency-source and real-consumer discovery.
- [Rei 9 live fixture fails to link its generated Note owner](7-rei-9-live-fixture-fails-to-link-its-generated-note-owner.md) - The current Rei checkout compiles its core but the live schema-hook executable fails to link generated Note hole symbols, requiring the existing matching Rei 8 consumer cohort for acceptance.
- [Linux checks overwrite the macOS Cabal package database](8-linux-checks-overwrite-the-macos-cabal-package-database.md) - The Apple-container gate mounted the developer checkout for builds, allowing Linux Cabal registrations and Git hooks to overwrite macOS state.
- [Mori dependency discovery requires unavailable PostgreSQL](9-mori-dependency-discovery-requires-unavailable-postgresql.md) - The Mori registry fails before dependency discovery because its local PostgreSQL socket refuses connections.
