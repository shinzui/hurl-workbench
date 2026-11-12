# Real Rei CLI/API category parity

This consumer-specific assertion exercises the supported category CLI and paged
HTTP interfaces from `mori://shinzui/rei`, as requested by
`mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract`.
`parity.py` compares slug, name, status, description and context, omitting generated
identities, timestamps and stream metadata. It neither reads internal tables nor
implements framework persistence. The helper belongs to this application fixture
workspace; workbench knows only its declared executable and process result.

`scripts/check-rei-command-parity.py` is the separate caller. It starts a disposable
SCRAM-authenticated PostgreSQL cluster, uses Hinagata's supported prepare/acquire
commands to obtain two distinct clones, and starts one Rei API per clone. It
creates equivalent categories through the real CLI and HTTP POST, then invokes
`scripts/check-command-parity.sh` inside those independently provisioned scopes.
The mismatch suite creates one extra category only through the HTTP twin's API.
The named `parity` check must then fail with status 1. Two API processes stop before
either caller-owned lease is released. No production configuration or database is
used or modified.

Discover the consumer and provider with Mori and build a matching API/CLI/schema
hook cohort in their repositories. From this repository, with absolute executable
paths in the named variables, run:

```bash
export hinagata_postgres_datadir="$(mori path mori://shinzui/hinagata)/hinagata-postgres"
nix develop -c python3 scripts/check-rei-command-parity.py \
  --api "$REI_API_EXECUTABLE" --rei "$REI_CLI_EXECUTABLE" \
  --schema-hook "$REI_LIVE_TEST_EXECUTABLE" --hinagata "$HINAGATA_EXECUTABLE" \
  --workbench "$HURL_WORKBENCH_EXECUTABLE" --evidence-root /tmp/new-rei-parity-evidence
```

The evidence directory must be new. It contains private logs, binary SHA-256
identities, match/mismatch summaries and caller release observations. Acceptance
used Rei 8.0.0.0, CLI revision
`mori://shinzui/rei/commits/8c5e11258f97b66600ce53269bd9675d9459db52`, with the
same built cohort as the existing multi-service consumer. This is no claim about
a newer consumer cohort. API tokens and database connection inputs use declared
Secret environment bindings; argv and ordinary summaries contain none of them.

The generic driver takes `HURL_WORKBENCH_CONSUMER_WORKSPACE` and
`HURL_WORKBENCH_CONSUMER_SUITE`, plus distinct `HURL_WORKBENCH_CLI_FIXTURE_ID` /
`HURL_WORKBENCH_API_FIXTURE_ID`, `HURL_WORKBENCH_CLI_FIXTURE`,
`HURL_WORKBENCH_API_URL`, and a new `HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT`.
It runs the named matching suite with jobs=2 and the `SUITE-mismatch` suite with
jobs=1 and explicit mutation authorization. Set
`HURL_WORKBENCH_CONSUMER_MISMATCH_SUITE` to override that name. The application
owns the mismatch operation; the driver provisions or releases no fixtures.
