# Architecture

The workbench is a coordinator around Hurl, not a replacement HTTP language.

```text
hurl-workbench.dhall
        │ decode + validate + index
        ▼
ValidatedWorkspace ── selection ──► workflow / recipe / matrix / suite
        │                                  │ expand + resolve bindings
        │                                  ▼
        └── fragment paths ───────► ResolvedWorkflow
                                           │ byte-preserving composition
                                           ▼
                                    RenderedWorkflow
                                           │ hurlfmt syntax check
                                           ▼
                              secure files + typed Hurl argv
                                           │
                                           ▼
                                   official Hurl process
```

## Opaque fragment boundary

A fragment is a file containing one or more complete Hurl entries. The workbench never parses,
formats, interpolates, or rewrites Hurl grammar. It validates paths, reads UTF-8, preserves every
input byte, and inserts only the line feeds required to separate adjacent fragments. That keeps
Hurl authoritative for requests, captures, assertions, sessions, and future syntax.

Rendering records source spans so a Hurlfmt line diagnostic can identify its originating fragment.
Composer-inserted separator lines belong only to the workflow. `render` exposes the exact source
that execution receives.

## Validated domain boundary

Discovery and Dhall decoding produce an untrusted workspace context. Semantic validation checks
schema version, names, references, binding channels, non-empty selections, path containment,
service commands, readiness, and suite members, then builds category-specific indexes. Downstream
code accepts the opaque `ValidatedWorkspace`; it cannot accidentally operate on a partially
validated record or confuse one name category with another.

Recipes and matrices reduce to prepared independent runs. Suites flatten those same selections,
preflight the complete set, optionally acquire one managed service, and delegate cases to the same
bounded batch runner. Every final invocation passes through the single Hurl process adapter.

## Process ownership

Single runs construct typed argv and secure temporary inputs. Batch execution uses a fixed worker
pool and restores results to declaration order. A managed service runs in its own POSIX process
group; readiness and the suite callback share one bracket, and cleanup terminates and reaps the
group after success, failure, or interruption.

The core package owns workspace, rendering, binding, execution, batching, and service/suite domain
logic. The CLI package owns parsing, human output, discovery-facing commands, and exit mapping.
