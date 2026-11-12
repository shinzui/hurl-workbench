# Ordered services and worker restart

Run `nix develop -c just examples` from the repository root. The multi-service
check uses the built fixture executable, private temporary state, and three
available loopback ports. It starts a stub, API, and projection worker, waiting
for each readiness check before starting the next service.

The `command-read` suite runs at jobs=1 with `--allow-mutating`. It submits exactly
one POST, polls GET until the worker has made that command visible, restarts the
worker, then observes the second worker generation through GET. The POST has no
retry option. The separate `read-barriers` suite uses pre-existing accepted state
and jobs=2; its two read-only batches are separated by the restart barrier.
Parallel mutation is refused even with mutation permission.

`launch.py` passes suite-level environment bindings to the fixture executable;
it also implements setup/teardown markers. Teardown checks every recorded PID is
gone. The caller owns temporary state. Workbench owns child process groups and
stops services in reverse acquisition order before teardown. A restarted service
gets the latest acquisition position. Commands and readiness use explicit Clean
environments. The summary contains logical names, statuses, durations and relative
artifact references; phase stdout/stderr remain sensitive, owner-only files.

These roles prove orchestration without a database. They do not prove actual
application projection behavior or lease release. The lease provider is
`mori://shinzui/hinagata`; the production consumer requirement is
`mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract`.
Rei exposes `rei worker query-projections` for its production Note/assignment/
definition owners, alongside the production `rei-api` executable. Its live-test
executable has `--hinagata-schema` and `--hinagata-verify` hooks for isolated
baselines. This example makes no real-consumer acceptance claim.

The opt-in `scripts/check-multi-service-lease.sh` runs **inside an already active
caller lease**. Supply absolute `HURL_WORKBENCH_CONSUMER_WORKSPACE`, the
`HURL_WORKBENCH_CONSUMER_SUITE` name, built `HURL_WORKBENCH_EXECUTABLE`, and a new
absolute `HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT`. An optional
`HURL_WORKBENCH_CONSUMER_VARIABLES_FILE` carries ordinary runtime bindings; secret
bindings use declared environment channels. The driver never acquires or releases
a database.

The consumer manifest must consume `HURL_WORKBENCH_CONSUMER_VARIANT` (`success`,
`readiness-failure`, `unexpected-exit`, `cancellation`) and the private
`HURL_WORKBENCH_CONSUMER_EVIDENCE_DIR`. Each variant writes `pids.json` as an array
of all owned leader/descendant PIDs and appends complete JSON lines to
`events.jsonl`. Success records one `{"event":"mutation"}`, one or more
`{"event":"observation","owner":"LOGICAL-PRODUCTION-OWNER"}`, and a successful
worker restart in the workbench summary. Cancellation records
`{"event":"cancel-ready"}` only while execution is active. Teardown's last event
is `{"event":"consumers-stopped"}` after confirming the real API/stub/owner have
stopped. The driver checks every PID and preserves private reports. The caller
then releases its lease and records provider evidence proving release followed
consumer shutdown. Use fresh isolated fixtures for each retry; teardown must
handle partially completed setup.
