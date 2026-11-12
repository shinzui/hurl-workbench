# Production Rei consumer inside a Hinagata lease

This opt-in fixture uses the actual `rei-api` application and
`rei worker query-projections` Note owner from `mori://shinzui/rei`, with a local
HTTP stub/proxy for deterministic request recording. It implements the contract of
`scripts/check-multi-service-lease.sh`. The generic driver accepts an already
leased fixture and never allocates or releases a database.

The separate caller `scripts/check-rei-multi-service.py` starts its own disposable
SCRAM-authenticated PostgreSQL cluster, asks `mori://shinzui/hinagata` to prepare a
baseline using Rei's existing `rei-api-live-test --hinagata-schema` and
`--hinagata-verify` hooks, then acquires one clone. A static Topic read row is an
independent anchor fixture. The Note under observation is created only by one
production POST and appears only through the production asynchronous query owner;
no Note projection rows or runtime tables are seeded by this harness.

Success polls GET on the Note tag, restarts the production worker and observes it
again. Other variants fail worker readiness, terminate the worker during active
HTTP work, and interrupt a held request. Every adapter and child PID is recorded,
reverse cleanup precedes teardown, and the caller verifies Hinagata reports
`Released` only after all four consumer scopes have stopped. Private timestamps
corroborate that order. Parallel mutation is refused before setup, and every
adapter asserts Clean policy excluded ambient database/service configuration.

Build matching API, CLI and schema-hook executables from the same Rei cohort.
Discover repositories with Mori; do not point these hooks at a developer database.
From the workbench repository, after building the workbench and provider, run:

```bash
export hinagata_postgres_datadir="$(mori path mori://shinzui/hinagata)/hinagata-postgres"
nix develop -c python3 scripts/check-rei-multi-service.py \
  --api "$REI_API_EXECUTABLE" --rei "$REI_CLI_EXECUTABLE" \
  --schema-hook "$REI_LIVE_TEST_EXECUTABLE" --hinagata "$HINAGATA_EXECUTABLE" \
  --workbench "$HURL_WORKBENCH_EXECUTABLE" --evidence-root /tmp/new-rei-lifecycle-evidence
```

Each option is an absolute built executable path. `cabal list-bin` in the owning
repository's development shell supplies those paths (`rei-api:exe:rei-api`,
`rei-cli:exe:rei`, `rei-api:test:rei-api-live-test`, and `hinagata`). The evidence root
must be new. Reports, capture files and caller diagnostics are private; retain
only sanitized aggregate evidence in durable documents.

Acceptance was exercised with the Rei 8.0.0.0 binary cohort (CLI build revision
`8c5e112`), discovered under `mori://shinzui/rei`. The current 9.0.0.0 checkout's live
schema hook has a generated Note-symbol linker failure (FRIC-7 in the workbench
friction log); this fixture makes no Rei 9 acceptance claim. No consumer source,
production database or lease configuration is modified.
