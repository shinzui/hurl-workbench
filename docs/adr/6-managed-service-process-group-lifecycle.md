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
environment overlays explicit workspace bindings on the current environment, and resolved command
values have a redacted `Show` instance. HTTP readiness supports only exact `{{parameter}}`
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
