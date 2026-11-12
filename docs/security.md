# Security model

## Secret sources and transport

Secret parameters have no committed default. They come from a declared environment variable,
`--secret-env NAME=ENVIRONMENT_NAME`, or a Hurl secrets properties file. Plain and secret channels
are type-checked and cannot substitute for one another.

Resolved plain values and secrets are serialized to separate unique temporary files with mode
`0600`; secrets never enter argv. Rendered Hurl and generated variable files use the same mode and
are removed after success, failure, or interruption. Secret-bearing types and process requests have
redacted `Show` instances. Diagnostic summaries record logical names and statuses, not bindings.

Before starting Hurl, the adapter removes inherited `HURL_*` variables so ambient configuration
cannot override the validated request. Explicitly declared parameter environments are read first.
Unrelated proxy, certificate, locale, and tool variables remain inherited.

## Paths and artifacts

The manifest directory is the workspace root. Fragment files and service working directories must
be relative, exist with the expected kind, and remain inside that root after canonicalization and
symlink resolution. Generated response/report names derive from validated logical names and are
collision-checked. Output directories use `0700`; files use `0600`. Overwrite is opt-in and scoped
to the exact selected artifact or suite subtree; symbolic-link report subtrees are rejected.

## Execution and safety

Hurl, managed services, and readiness commands are started directly as executable plus argv—never
through a shell. Extra Hurl passthrough is a small allowlist of value-free flags. Managed service
environment overlays bind declared workspace parameters; HTTP readiness permits only plain
parameters and rejects secret placeholders.

Recipes declare `ReadOnly` or `Mutating`. Mutating recipes require `--allow-mutating`. Direct
workflows are unclassified and require the same gate when included in suites. Whole-suite preflight
checks bindings, safety, report paths, and service inputs before starting the managed service.

Managed services are owned as POSIX process groups. Cleanup sends `SIGTERM`, waits the configured
shutdown interval, escalates to `SIGKILL`, and reaps the leader after success, readiness failure,
test failure, or asynchronous interruption.

## Limits users must account for

Hurl can redact declared secrets from its own diagnostics, but it cannot make an untrusted server
safe. Response bodies, generated curl files, and Hurl's JUnit/HTML/JSON/TAP reports may contain
server-echoed credentials or other sensitive data. Treat response and report roots as sensitive,
restrict retention and sharing, and do not send real credentials to untrusted requests.

The permission and process-group guarantees currently target macOS and Linux/POSIX. A non-POSIX
port needs equally tested secure-file permissions and process-tree ownership before it can claim the
same model.

## Managed command environments

Managed service and command-readiness environments default to inheritance for compatibility.
Use `Schema.EnvironmentPolicy.Clean [ "NAME" ]` on each command to inherit only required,
explicitly named variables, or `Clean ([] : List Text)` for none. Explicit workspace parameter
bindings overlay the selection. Selected names must exist before startup, even when overridden;
errors include names and phase, never values. No PATH, HOME, or locale variables are added.
Use absolute executable paths, and select each command's dependencies independently.

Resolved environment values are redacted from workbench diagnostics and suite summaries.
Inherited child stdout and stderr, deliberately echoed values, and Hurl response/report
artifacts remain sensitive output; this policy does not sanitize them. Hurl filtering is a
separate boundary. A language runtime may alter its own environment after exec.

For PostgreSQL lease consumers, explicitly select PGHOST, PGPORT, PGUSER, PGDATABASE, and
PGPASSFILE when needed. The password file stays protected and owned by the caller until all
managed consumers stop and the lease is released. Password contents must never enter argv,
committed manifests, or report metadata. See [integration testing](guides/integration-testing.md).

## Application state and parallel runs

Suite isolation defaults to `SharedState`, including old manifests. A requested job count above
one permits only explicitly `ReadOnly` recipes; mutating and unclassified runs are refused before
capability probes, binding IO, report replacement, or service startup. Mutation authorization is
separate: `--allow-mutating` permits serial writes and does not bypass isolation. Standalone
mutating matrices require serial execution too. Distinct Hurl sessions isolate client captures
and cookies; they do not isolate server resources.

IndependentState requires caller-owned ready services, `--external-service`, and a verified private
scenario-inputs file. The entire scenario/fixture/endpoint assignment is checked before execution;
fixture IDs and normalized origins must be unique. IDs are trusted assertions, and different DNS
names can still reach the same state. The caller must verify real provider identity, hold leases
until Hurl cleanup completes, then stop services and release leases. Workbench never provisions,
stops, or releases these external resources. Handoff files and connection metadata are not copied
to reports or argv. Secret environment references resolve to protected secret files.

Success, safely reportable refusal/setup failure, and cancellation summaries contain only logical
isolation metadata. Refusal reports do not invent child exit statuses or report artifacts.
Cancellation writes its best-effort summary after cleanup and propagates the original signal.
Summary-write failure cannot replace a managed-service failure or swallow cancellation.
User-controlled report symlinks, including ancestor links, are rejected. macOS's fixed OS-owned
`/tmp` and `/var` aliases are accepted only when they resolve to `/private/tmp` and `/private/var`.
The [handoff guide](guides/integration-testing.md#independent-scenario-handoff) defines binding
conflicts, endpoint validation, and the provider trust boundary.

## Suite phases and lifecycle ownership

Setup and teardown use executable/argv commands, suite-level bindings and the same
Clean/Inherit selector as services. One invocation snapshot freezes inherited and
explicit parameter environments for every start, readiness retry, phase and
restart. Whole-suite preflight precedes setup, including late lifecycle references
and teardown inputs. External mode skips all managed phases and refuses barriers.

Captured phase output is sensitive: owner-only directories and files, relative
artifact references in summaries, and no automatic output replay. Without a report
root, bracketed private captures are removed after finalization. Summaries never
serialize command argv, environments, resolved fixture paths or captured text.
The reserved `phases` subtree cannot collide with case artifact names.

Every spawned group is registered before readiness. Cleanup addresses descendants
even after leader exit, uses bounded TERM/KILL escalation, and reaps leaders before
teardown. Restart atomically retires the previous monitor generation before its
intentional stop. Cleanup failures remain separate from the primary cause, and
cancellation propagates after finalization. Database leases remain caller-owned.

Generated parameters are ordinary scenario inputs delivered through the same
owner-only temporary variables files as Plain inputs. Entropy comes from the
operating system; generation fails on unavailable/short entropy and never falls
back to timestamps or process identifiers. Random sampling has a finite rejection
budget. Generation is cancellable. Values are excluded from explanations, debug
resolved-binding output, and suite summaries. Response bodies and private Hurl
reports can contain echoed inputs. These generators are not a secret/token API.
UUID7 and TypeID expose the current millisecond timestamp; no strict monotonic
ordering is promised. Timestamps and short random strings may coincide even
though each execution generates independently.
