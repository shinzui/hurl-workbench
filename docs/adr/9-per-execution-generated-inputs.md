# ADR 9: Resolve generated inputs once per prepared Hurl execution

Status: Accepted

Date: 2026-11-12

Origin: [Plan 11](../plans/11-generate-fresh-parameters-for-each-workflow-execution.md)

## Context

Reusable scenarios need fresh identities without helper scripts, while reproduction
needs explicit values. Rendered workflows are cached across matrix and suite runs;
caching their runtime bindings would accidentally reuse identities.

## Decision

Generated is a declaration with one of five closed generator configurations. It
uses the plain binding channel, after explicit variables, later variable files,
and declared environments. Defaults and committed recipe/matrix bindings are
invalid. Missing declared environments remain errors. Each prepared Hurl run
resolves a name once; fragments and Hurl retries reuse the map. Render caches
contain source only. Preflight can generate for cases later skipped by fail-fast.

Suite commands and readiness checks use stable Plain/Secret inputs. Generated
inputs are not outputs exchanged between executions. Validation, listing, and
rendering consume no generated state. Legacy version-1 Plain/Secret unions are
widened before typed extraction; original and converted Dhall are typechecked.

The generator environment injects clock and entropy. Production reads bounded
bytes from `/dev/urandom`, checks exact lengths, propagates cancellation, and
redacts failure causes. Random strings reject biased bytes and have a finite
rejection budget. UUID layouts follow RFC 9562; TypeID follows v0.3 in
`mori://jetify-com/typeid` with project-relative path `spec/README.md`
(artifact-level URI pending). No new dependency is required.

## Consequences

Explicit runtime overrides reproduce a scenario without consuming its generator.
UUID-based IDs provide collision resistance; timestamps and short random strings
can repeat. No monotonic UUID guarantee or secret-token API is added. Generated
values use protected variables files and never appear in summary metadata, though
responses and private reports can echo them.
