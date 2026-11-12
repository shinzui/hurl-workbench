# ADR 6: Own managed services through a POSIX process group


Status: Accepted

Date: 2026-09-20

Origin: [EP-5](../plans/5-orchestrate-services-and-integration-test-suites.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


An integration suite may start an API server that creates descendants of its own. Stopping only
the immediate child can leave listeners, workers, or zombies behind. Readiness also has to finish
before Hurl runs, while malformed configuration must fail before the service starts and transient
HTTP failures must remain retryable.

Service commands can carry secrets in their environment. A shell command or arbitrary template
expansion would create quoting and injection hazards, and placing a secret in a readiness URL would
leak it through ordinary HTTP diagnostics and infrastructure logs.


## Decision


Service commands and command readiness probes are an executable plus argv, never shell text. Their
environment policy defaults to Inherit, preserving explicit bindings over ambient values.
Clean selects required inherited names and then overlays explicit bindings, without implicit
PATH, HOME, or locale defaults. Both commands are prepared from one parent snapshot before
service startup; absent selected names fail even if explicitly overridden. Readiness retries
retain that prepared environment. The shared Service.Environment selector owns this contract
for future common-command consumers. Resolved command values have a redacted `Show` instance.
The policy controls the environment passed to exec; a language runtime may subsequently add
variables. A native helper checks launch environments because the Haskell runtime on
macOS adds `__CF_USER_TEXT_ENCODING`.

HTTP readiness supports only exact `{{parameter}}`
substitution from declared plain suite-level bindings; unknown, missing, malformed, and secret
placeholders are errors.

The service starts in a new POSIX process group. The leader PID is retained as the group ID. One
masked bracket covers readiness and the suite callback: expected lifecycle failures are returned as
typed errors, while synchronous and asynchronous callback exceptions are rethrown only after
cleanup. Readiness observes early leader exit and applies the overall deadline to each HTTP or
command probe, so even a hanging command cannot defeat the configured timeout.

Cleanup sends `SIGTERM` to the process group, waits for the configured shutdown interval, escalates
to group `SIGKILL`, and reaps the typed process. The same cleanup runs after success, readiness
failure, callback failure, and cancellation. Once ready, the service leader races the callback; an
unexpected service exit cancels the callback before returning a lifecycle failure.

HTTP probing uses `mori://snoyberg/http-client/packages/http-client` 0.7.19.x. Connection failures
and wrong statuses retry until the overall deadline, while URL parsing and probe-process spawn
failures are immediate errors.


## Consequences


Suites get one deterministic ownership boundary for an optional managed service and do not leave
its descendants running after cancellation or failure. Callback cancellation composes with the
structured EP-4 worker pool and EP-3 Hurl cleanup, so active Hurl children are also reaped when the
service dies.

The implementation is intentionally POSIX-specific. A future non-POSIX port needs an equivalent
job/process-tree ownership mechanism rather than silently weakening cleanup to leader-only
termination. Service configuration cannot derive readiness or environment values from recipe or
matrix-case binding layers because those values are not stable for the suite-wide process.

## Ordered group ownership (2026-11-12)

[Plan 10](../plans/10-support-ordered-multi-service-suite-lifecycles.md) extends
ownership to ordered service acquisitions and named Stop/Start/Restart barriers.
Process.Run owns group spawn/termination; Service.Group holds newest-first
acquisitions, registered before readiness. The STM membership list is also the
monitor generation: intentional stop checks already-observed leader exits and
retires that member atomically. Old monitor transactions cannot target a restart.
The group monitor covers subsequent acquisitions, batches and lifecycle work.

Cleanup signals the whole group even after leader exit, waits a bounded TERM
grace period, escalates remaining groups with KILL and reaps leaders. macOS can
report EPERM for signalling an already-disappeared group, so no escalation is
attempted once disappearance is observed. Ownership is retained if stop fails.
Restarted members get a new acquisition position. Setup precedes acquisitions;
reverse cleanup precedes bounded teardown, including failure and cancellation.
All managed consumers freeze the environment and parameter-environment channels
from one preflight snapshot. Resolved commands redact argv and paths as well as
environment values. withService remains a compatibility wrapper.

Linux fast-child acceptance exposed a PID acquisition race in typed-process: its
waiter can reap a child before `getPid` reads the handle. Process.Run now uses the
public acquisition API from `mori://haskell/process/packages/process`, captures the group ID before starting its one
reaper, and publishes completion through STM. No detached waiter can remove the
identity before ownership registration. The direct process dependency uses stable
public APIs; Hackage and upstream tags were checked through 1.6.30.0 before
selecting the inclusive 1.6 range. Other adapters retain typed-process where no
ownership transfer is required.

## Bounded executable assertions (2026-11-12)

[Plan 13](../plans/13-run-executable-checks-as-ordered-suite-barriers.md) adds named
workspace-owned checks as explicit suite barriers. They execute once, without a
shell, from a canonical executable file inside the workspace. Only Plain
suite-level parameters may substitute argv templates; Secret inputs use explicit
environment bindings. Generated, recipe and matrix inputs are not shared check
state. The shared environment selector freezes check commands during preflight.

Checks use Process.Run ownership with a finite execution deadline (default 60
seconds), then a separate five-second TERM grace and five-second KILL/reap budget.
Cleanup addresses descendants even after leader exit and runs before cancellation
is rethrown. Normal exits alone compare expected status; mismatch, timeout,
signal, cancellation and launch failure retain distinct outcomes. Cleanup diagnostics
never replace the primary assertion outcome. Service monitors remain active during
checks and cancel the group before service cleanup and teardown.

A check can also be cancelled during descendant cleanup after its leader has
already exited. Its cleanup runs in an independently bounded task; the parent
joins that task before reporting cancellation and propagating the exception.
The cleanup task retains its own timeout even when the parent must wait without
accepting another interruption. No child ownership is abandoned during TERM grace.
