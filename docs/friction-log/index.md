---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Mori registry unavailable during dependency and lease discovery](1-mori-registry-unavailable-during-dependency-and-lease-discovery.md) - The registry requires an unavailable local PostgreSQL socket, preventing source and Hinagata discovery.
- [Parallel tests race process-global environment mutation](2-parallel-tests-race-process-global-environment-mutation.md) - Existing binding tests mutate libc environ while unrelated tests spawn children, intermittently causing posix_spawnp Bad address.
- [Disposable Linux validation compiles a cold development toolchain](3-disposable-linux-validation-compiles-a-cold-development-toolchain.md) - The Apple-container release gate has no persistent Nix store, making its first development-shell realization compile many dependencies before project validation.
- [Mori registry unavailable through PostgreSQL tunnel](4-mori-registry-unavailable-through-postgresql-tunnel.md) - Registry discovery and provider source lookup cannot proceed while the Sungkyung PostgreSQL tunnel refuses connections.
- [Linux release gate realizes editor-only HLS dependencies](5-linux-release-gate-realizes-editor-only-hls-dependencies.md) - The Linux release script enters the full editor development shell and spends validation time building HLS dependencies unrelated to the release checks.
- [Mori registry unavailable during multi-service implementation](6-mori-registry-unavailable-during-multi-service-implementation.md) - The configured Mori PostgreSQL socket refuses connections, blocking dependency-source and real-consumer discovery.
