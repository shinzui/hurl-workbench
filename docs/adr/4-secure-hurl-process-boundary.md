# ADR 4: Keep secrets and ambient Hurl controls outside the process boundary


Status: Accepted

Date: 2026-09-20

Origin: [EP-3](../plans/3-execute-hurl-workflows-securely.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


Hurl accepts runtime variables and secrets through command-line arguments, files, and environment
variables. Command-line secrets are observable in process listings and command traces. Hurl 8 also
interprets every inherited `HURL_*` variable as configuration, so ambient values can silently alter
test mode, output paths, variables, secrets, and other options after the workbench has validated a
typed request.

Interactive client runs need Hurl's stdout and stderr unchanged, while recipes, matrices, and suites
need isolated output that can be emitted later in declaration order. A process that cannot start is
also different from Hurl starting and returning a non-zero exit status.


## Decision


The workbench resolves every declared parameter before spawning Hurl and transports the final plain
and secret maps through separate, unique, owner-readable and owner-writable (`0600`) files in a
bracketed temporary directory. Secrets never enter argv. `SecretValue` is abstract, its `Show`
instance is redacted, and only the Hurl process adapter can read its text for serialization. The
generated rendered workflow and variable files use the same owner-only permissions and are removed
after success, failure, or interruption.

The child environment begins with the current environment and removes every key beginning with
`HURL_`. The resolver reads explicitly declared environment sources before this filter. Unrelated
proxy, certificate, locale, and tool settings remain inherited.

`RunRequest` is the only input to execution. It owns client versus test mode, typed Hurl options,
output policy, and typed report targets. The adapter constructs argv without a shell and permits
extra Hurl flags only through a versioned allowlist of zero-argument, non-sensitive long options.
Options which take values require typed fields. Response, curl, JUnit, and TAP files are prepared as
`0600`; HTML and JSON report directories are prepared as `0700`.

An interactive run inherits all three standard streams. Orchestrated runs close stdin and capture
stdout and stderr separately, or direct the response to one owner-only file while capturing
diagnostics. Hurl 8 client responses use stdout, while test-mode progress and summaries use stderr;
the workbench preserves those channel choices. Failure before process creation is `RunStartError`.
After Hurl starts, `RunResult` retains its exact `ExitCode`, including non-zero statuses.


## Consequences


Process listings and reconstructed argv cannot reveal secrets, and ambient `HURL_*` state cannot
bypass the workbench's validated request. Callers can distinguish dependency/setup failures from
real Hurl results and can preserve deterministic batch output without inventing exit codes for work
that never started.

The workbench deliberately does not sanitize response bodies: a server can echo a supplied secret
to stdout, and Hurl documents that its secret redaction does not cover response bodies. Users must
not run untrusted requests with credentials. The initial adapter supports macOS and Linux because
it enforces POSIX permissions; another platform needs an equally tested secure-file abstraction
before it can be supported.
