# ADR 5: Bound batch execution and isolate every case result


Status: Accepted

Date: 2026-09-20

Origin: [EP-4](../plans/4-add-recipes-matrices-and-exploratory-runs.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


A matrix expands one recipe into separate Hurl invocations. Starting one thread for every case
can exhaust local resources or exceed a third-party API's concurrency limits. A semaphore around an
already-started thread also makes fail-fast misleading: every case has been scheduled even when most
threads are only waiting for a permit.

Concurrent Hurl processes cannot safely inherit a shared terminal because response bodies and
diagnostics would interleave. Completion order is nondeterministic, but users need summaries,
diagnostics, exit selection, and artifact names to remain stable in declaration order. A Hurl
failure, a failure before spawn, and a case skipped after fail-fast are distinct events.


## Decision


`runBatch` uses a fixed number of workers over an STM queue. The positive worker count is an opaque
validated value and defaults to one at the CLI boundary. A worker removes a case only when it can
start that case. With fail-fast enabled, the first observed unsuccessful result closes scheduling;
already-active workers finish and are reaped, while untouched queue entries become explicit skipped
results. Failure state and completed results are published under masking before observers run,
so cancellation cannot lose a completed result between child return and publication, and a
failure observer cannot allow another worker to schedule queued work before fail-fast closes.

Every case invokes the EP-3 `HurlRunner` independently. Batch execution retains a four-way outcome:
passed, Hurl-failed with the exact child status, start-failed with the typed EP-3 error, or skipped
with a reason. Results are restored to declaration order after all active workers finish. The batch
selects the first non-zero Hurl status in declaration order, or workbench status 3 when the first
actual failure is pre-spawn; skipped cases never receive an invented child status.

Concurrent requests use captured diagnostics or a typed response file, never inherited streams.
Client response artifacts derive only from validated logical names, are collision-checked before
execution, and are prepared beneath the requested output root as `0700` directories and `0600`
files. Existing artifacts stop the whole batch unless overwrite was explicit. Response artifacts
are not described as redacted because a server may echo credentials in its body.


## Consequences


The configured concurrency bound applies to processes actually in flight, and fail-fast can leave
untouched work truthfully unstarted. Completion timing does not change user-visible ordering or exit
selection. EP-5 can reuse the same case and result model for suites without flattening orchestration
events into Hurl exits.

Separate Hurl processes isolate client session state, not application state. SharedState suites
permit requested concurrency greater than one only when every expanded run is explicitly
ReadOnly. Mutating and unclassified runs are refused before preparation or process probes,
including when just one run expands. Standalone mutating matrices use the same serial guard.
Mutation permission remains a separate opt-in; external-service mode does not bypass isolation.
IndependentState suites require a complete verified handoff assigning a unique caller-owned
fixture identity and endpoint origin per logical scenario, with separately resolved binding input.
The configured jobs bound still applies to active Hurl processes; workbench acquires no leases or
per-scenario services. Separate origins and opaque IDs are trusted provider assertions, not proof
that two databases differ. Real two-lease acceptance corroborates HTTP observations through direct
database queries. Standalone matrices retain the shared-state serial mutation guard.

Each case performs a complete independent Hurl session, including authentication. This spends more
requests than shared-session execution but avoids cross-case capture, cookie, and token state. Users
must opt into higher concurrency and must treat response directories as sensitive output.
