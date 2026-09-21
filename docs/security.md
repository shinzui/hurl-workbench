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
