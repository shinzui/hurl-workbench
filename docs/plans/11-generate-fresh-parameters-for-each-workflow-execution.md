---
id: 11
slug: generate-fresh-parameters-for-each-workflow-execution
title: "Generate fresh parameters for each workflow execution"
kind: exec-plan
created_at: 2026-11-11T20:51:21Z
intention: "intention_01m7663ac3ev3skznh7qza9d36"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-11-11T20:51:21Z
  revisions:
    - model: "gpt-6-astra"
      harness: "codex-cli"
      at: 2026-11-11T21:02:49Z
      mode: "other"
      note: "Complete initial IR plan, link created Mina intention, and check cross-plan acceptance contracts"
---

# Generate fresh parameters for each workflow execution


This ExecPlan is a living document. Keep the progress and decision sections current, record implementation friction through `agents/skills/exec-plan/FRICTION.md`, and distill lasting decisions into `docs/adr/` at completion.


## Purpose / Big Picture


A scenario will be able to declare a fresh recipient identifier, UUID, timestamp, or random string without a shell helper. Every fragment in one Hurl execution receives the same generated value, while separate executions receive independent generation. A developer can reproduce a failed scenario by supplying `--variable` explicitly. Rendering remains deterministic and explains that an input is generated without producing or printing its value.

This implements [IR-2](../improvement-requests/add-generated-parameter-kinds-so-re-runnable-scenarios-need-no-helper-script.md), including all three acceptance criteria and all five requested generator forms. A TypeID is a typed identifier consisting of a prefix and a compact encoding of a version-7 UUID; a UUID is a 128-bit identifier with explicit version and variant bits.


## Progress


- [ ] Milestone 1: Compatible generator declarations validate statically and rendering identifies generated inputs without generating them.
- [ ] Milestone 2: Protected binding resolution generates once per execution, honors runtime overrides, and passes deterministic format/error tests.
- [ ] Milestone 3: Real CLI workflows, matrices, and suites prove sharing within executions, freshness across executions, and release compatibility.

Planning handoff: implementation has not begun. A Mina intention is linked in frontmatter. Mori registry list/search failed on 2026-11-11 because its PostgreSQL socket refused connections. No new dependency version or API is assumed; source discovery must be retried before introducing unfamiliar dependency calls. The UUID and TypeID format specifications were consulted directly for the data contract below.


## Surprises & Discoveries


## Decision Log


2026-11-11: Treat generation as the final fallback in the plain runtime binding channel: explicit variable, later variable file, declared environment, then generator. Secret sources remain invalid. A declared environment that is missing remains an error unless a higher-priority value wins, matching existing precedence. Reject every committed value for Generated, including recipe bindings as well as the explicitly requested defaults and matrix bindings, so the declaration cannot silently become a fixed identifier.

2026-11-11: Generate at per-run binding resolution, including each expanded matrix case and suite Hurl run. Never cache generated bindings with the rendered-workflow cache or share them through a process-global map. Hurl retries within that invocation reuse its resolved bindings. Timestamps and very short random strings are not promised to differ on every call; independent generation is the guarantee, while UUID-based identifiers provide the freshness required by AC-2.

2026-11-11: Keep suite lifecycle commands and checks on stable declared Plain/Secret inputs. Generated values are per Hurl execution and are not implicit outputs passed between suite steps. Explicit runtime plain parameters remain the way to share a caller-created identity across different executions.

2026-11-11: Use injectable clock and entropy sources behind a small generator module and pure encoders. The default POSIX adapter reads a bounded number of bytes from the operating system entropy device; no shell generator or new library pin is required. Random strings have a documented 1..4096 character bound to keep allocation and conversion finite.


## Outcomes & Retrospective


## Context and Orientation


`schema/ParameterKind.dhall` is currently `< Plain | Secret >`, referenced by `schema/Parameter.dhall`. Its Haskell representation is in `hurl-workbench-core/src/HurlWorkbench/Workspace/Types.hs`. `hurl-workbench-core/src/HurlWorkbench/Workspace/Validate.hs` checks committed defaults, recipe/matrix binding kinds, and reserved Hurl names. `hurl-workbench-core/src/HurlWorkbench/Workspace/Decode.hs` expects an exact type; old explicitly annotated parameter unions require compatibility conversion when Generated is added.

`hurl-workbench-core/src/HurlWorkbench/Parameter/Resolve.hs` resolves selected parameter names in `resolveParametersWithMode`, verifies channel kinds in `kindMismatches`, and chooses values in `resolveOne`. `hurl-workbench-core/src/HurlWorkbench/Parameter/Resolve/Internal.hs` defines sources, issues, and redacted resolved bindings. `hurl-workbench-core/src/HurlWorkbench/Run/Prepare.hs` caches rendered source but already resolves bindings separately for each expanded run. Preserve that separation. `hurl-workbench-core/src/HurlWorkbench/Hurl/Run.hs` writes plain and secret maps to separate owner-only temporary files and removes them after execution.

`hurl-workbench-cli/src/HurlWorkbench/Cli/Command/Render.hs` currently explains only binding layers without resolving values. `hurl-workbench-cli/src/HurlWorkbench/Cli/Command/List.hs` displays kinds. Extend these inspection paths to understand Generated while keeping them free of clock/entropy/environment reads. Suite process inputs are resolved separately in `hurl-workbench-core/src/HurlWorkbench/Service/Resolve.hs` and `hurl-workbench-core/src/HurlWorkbench/Suite/Resolve.hs`.

Relevant decisions are [ADR 1](../adr/1-versioned-dhall-workspace-schema.md), preserving schema-version-1 compatibility; [ADR 2](../adr/2-validated-workspace-boundary.md), enforcing typed indexes and literal validation; [ADR 3](../adr/3-opaque-hurl-fragment-composition.md), leaving fragment bytes and Hurl syntax opaque; [ADR 4](../adr/4-secure-hurl-process-boundary.md), requiring protected binding files and redacted metadata; [ADR 5](../adr/5-bounded-isolated-batch-execution.md), isolating matrix execution state; [ADR 6](../adr/6-managed-service-process-group-lifecycle.md) and [ADR 7](../adr/7-suite-preflight-safety-and-report-isolation.md), keeping service inputs suite-scoped; and [ADR 8](../adr/8-self-contained-multi-package-release-builds.md), synchronizing packaged schemas and examples. No existing ADR specifies generated-parameter semantics; record that durable contract during implementation.

[IR-1's plan](10-support-ordered-multi-service-suite-lifecycles.md) and [Plan 8](8-support-explicit-clean-environments-for-managed-processes.md) also touch compatibility decoding. Extend their normalization if present; do not duplicate it or require their lifecycle features to implement this plan. IR-2 can otherwise be implemented independently of IR-1, IR-3, and IR-4.


## Plan of Work


### Milestone 1: Declare and explain generation without executing it


Add `schema/Generator.dhall` with the following closed union, export it from `schema/package.dhall`, and add `Generated : Generator` to `ParameterKind`:

```dhall
< Uuid4
| Uuid7
| TypeId : { prefix : Text }
| Rfc3339Now
| RandomAlphanumeric : { length : Natural }
>
```

Add Haskell generator types and constructor decoding in `Workspace.Types`. Widen legacy `< Plain | Secret >` parameter unions during schema-version-1 compatibility conversion, including empty typed lists. Re-typecheck before extraction and preserve explicit new values; malformed generator payloads remain errors. Keep the original minimal and minimal-explicit fixtures unchanged and add a frozen old manifest with both kinds. Extend an existing shared converter if other plans have landed.

In `Workspace.Validate`, reject defaults and all committed bindings for Generated, invalid TypeID prefixes, and random lengths outside 1..4096. Prefix rules are the TypeID v0.3 contract: empty is allowed; otherwise at most 63 lowercase ASCII letters/underscores, beginning and ending with a letter. Empty prefix emits no separator. Reserved Hurl function names remain rejected. Update all kind pattern matches, including list output and binding-error rendering.

Change the render explanation to inspect selected workflow declarations via the validated workspace and label each generated input `generated`, with its generator kind but no generated value. It must work even with no committed layers. Do not invoke the resolver or entropy source from render, validate, or list. Validate any service/readiness/phase-command/check references to Generated as unsupported suite-scoped inputs; standalone Hurl execution still accepts them.

Acceptance is passing workspace tests covering old/new unions, every generator payload, invalid prefixes and lengths, forbidden committed values, reserved names, and the inspection commands. A render test uses an entropy provider that fails if called, proving rendering does not consume generated state.


### Milestone 2: Generate and resolve through the protected channel


Add `hurl-workbench-core/src/HurlWorkbench/Parameter/Generate.hs`, with a generator environment providing UTC time and an operation to obtain exactly a requested bounded byte count. Keep pure UUID formatting, TypeID encoding, and alphanumeric sampling separately testable. Register production/test modules in `hurl-workbench-core/hurl-workbench-core.cabal` and `hurl-workbench-core/test/Main.hs`. Use existing bytestring/time/base facilities and a bracketed POSIX entropy-device reader; handle short reads, EOF, IO errors, and cancellation without looping forever or substituting weak randomness. Never use process IDs, shell commands, or timestamps alone as entropy.

UUID4 sets the RFC version-4 and variant bits on random bytes. UUID7 uses the current Unix millisecond timestamp in its leading 48 bits, version 7, variant bits, and independent randomness for remaining bits; reject timestamps outside the representable range. Return canonical lowercase hyphenated UUID text. Use the layouts and known vectors in [RFC 9562](https://www.rfc-editor.org/rfc/rfc9562.html), sections 5.4, 5.7, and Appendix A. No strict monotonic-order guarantee is added.

TypeId encodes the UUID7 bytes in big-endian order as 26 lowercase base32 characters using `0123456789abcdefghjkmnpqrstvwxyz`, with two leading zero bits; the first encoded character cannot exceed `7`. Prepend a nonempty prefix plus underscore. The upstream specification is `mori://jetify-com/typeid` with project-relative path `spec/README.md` (artifact-level URI and local registry ownership verification pending); the consulted version is 0.3.0. Preserve canonical Mori references when recording its test vectors or implementation context.

Rfc3339Now formats UTC as `YYYY-MM-DDTHH:MM:SS.sssZ`, using milliseconds, with a fixed clock in tests. RandomAlphanumeric uses ASCII letters and digits. Sample bytes without modulo bias by rejecting bytes at or above 248 before taking a remainder over 62; draw bounded chunks until the requested valid length is filled. Validate all produced text through `mkHurlValueLiteral` before delivery. These outputs are scenario inputs, not a new secret/token API.

Introduce typed generator failure in the binding error model that names only the parameter and generator kind, never entropy or generated bytes. Extend resolver entry points with an injectable generator environment while retaining default production wrappers. Generated uses the plain map and rejects secret bindings. Only invoke its generator if no higher-precedence source supplies a value; invalid supplied values fail rather than trigger generation. A generator failure returns a preparation error before any Hurl or managed process starts and uses execution preflight exit 2.

Resolve each selected generated name once, store the result in that run's `ResolvedBindings`, and reuse it across all fragments and Hurl retries. Never regenerate in `Hurl.Run`, report writers, or explanation output. Rendering cache entries must contain no resolved bindings. Document that preflight may generate for a case later skipped by fail-fast; the value belongs to the prepared execution and is not regenerated when scheduling begins.

Acceptance uses deterministic clock/entropy vectors to check UUID version and variant bits, timestamp packing, TypeID encoding and roundtrip decoding, empty/max prefixes, random rejection sampling, timestamp formatting, entropy errors, and literal safety. Resolver tests count generator calls, verify runtime precedence and zero calls for explicit overrides, and prove each independently prepared case has its own value. Keep expected bytes independent of the encoder under test.


### Milestone 3: Demonstrate actual Hurl and CLI behavior


Extend `hurl-workbench-core/test/HurlWorkbench/Parameter/ParameterTest.hs`, `hurl-workbench-core/test/HurlWorkbench/Hurl/RunTest.hs`, and `hurl-workbench-core/test/HurlWorkbench/Run/SelectionTest.hs`, adding a generator-specific test module where useful. Capture the delivered properties file through the existing runner fixture and assert permissions and lifetime. Add a real two-fragment fixture: the first request sends and captures an identifier, and the second compares that capture with the same parameter. Run it twice and compare identifiers. Decode the captured `rcp_...` suffix independently and require UUID version 7 and the correct variant, not just a regex match.

Add `examples/generated-parameters/hurl-workbench.dhall`, its fragments and README, backed by the existing CLI fixture server, and cover it in `hurl-workbench-cli/test/Main.hs`. Show all five declarations and a reproducible explicit override. Add matrix and suite tests at jobs=2 using read-only echo workflows to prove distinct per-case UUIDs and stable values within each execution without bypassing IR-5's shared-state mutation guard. Repeated selections must keep the existing artifact-collision rules; use distinct recipes/cases for tests.

Assert generated values never appear in rendered source, `render recipe --explain`, debug Show output, or `summary.json`. A server can echo values into private reports, just as with ordinary responses; do not promise report-body redaction. Ensure invalid defaults and matrix bindings make public validate fail and prevent execution. Exercise generator failure through an injected provider at the core boundary and ordinary generated execution through the real CLI.

Update `docs/reference/workspace.md`, `docs/guides/integration-testing.md`, `docs/reference/cli.md`, `docs/security.md`, and the relevant ADRs. Synchronize schemas and examples into package copies and mirror README/CHANGELOG changes when made. Run full tests, example, schema, and distribution gates before marking complete.


## Concrete Steps


All commands run from the repository root. During implementation use:

```bash
nix develop -c cabal test hurl-workbench-core-test --test-show-details=direct
nix develop -c cabal test hurl-workbench-cli-test --test-show-details=direct
nix develop -c just sync-check schema-check
```

After creating the example, use the public inspection path:

```bash
nix develop -c cabal run hurl-workbench -- --workspace examples/generated-parameters/hurl-workbench.dhall validate
nix develop -c cabal run hurl-workbench -- --workspace examples/generated-parameters/hurl-workbench.dhall render recipe recipient --explain
nix develop -c just examples
nix develop -c just check
```

Name the example recipe `recipient` so these commands remain executable. Its explanation must say `generated` without containing a minted ID; `just examples` must start its fixture and run the two-fragment recipe twice and once with `--variable recipientId=rcp_01h2xcejqtf2nbrexx3vqjhp41`. The latter is an explicit reproduction value, not an automatically generated result. Expect all tests and release/schema checks to pass. Run `just linux-check` outside the Nix shell on macOS for the POSIX entropy and protected-file path, preferring its local Apple-container runner.


## Validation and Acceptance


IR-2 AC-1 requires captured CLI properties containing an `rcp_` value whose suffix matches the requested alphabet and decodes to a version-7 UUID. AC-2 requires different UUID-based values in two executions and equality within both fragments of each execution. Extend that proof to matrix cases and suite Hurl runs; deterministic resolver tests make the lifetime invariant non-probabilistic. AC-3 requires an explicit CLI override delivered unchanged, validation errors for defaults and matrix-case bindings, and no generator call when an override wins.

All requested generators need tests, including UUID4, UUID7, TypeId, Rfc3339Now, and RandomAlphanumeric. Test invalid prefix/length and entropy failure before spawn, forbidden recipe bindings, generated-versus-secret channel errors, and no generation during inspection. Preserve legacy Plain/Secret precedence, reserved names, Hurl fragment composition, secret-file cleanup, report redaction, and old Dhall fixture equivalence. Tests must distinguish fresh per-run state from one workspace-global generated value.


## Idempotence and Recovery


Re-running a scenario normally generates new identifiers, so application assertions must use those inputs rather than fixed IDs. Reproduction uses explicit runtime overrides; do not commit generated values into defaults or binding layers. Tests use private temporary directories and controlled clocks/entropy. If generation fails, fix the entropy provider and prepare a new execution; never reuse a partially prepared map across invocations. On failed/cancelled Hurl execution, existing bracketed file cleanup remains responsible for temporary properties files.


## Interfaces and Dependencies


`Generator` is configuration, `ParameterKind.Generated Generator` marks the new kind, and the new generation environment is an execution dependency rather than manifest data. Resolver output remains `ResolvedBindings` with Generated in its plain map. Add a source label for generation only where source metadata is retained; no result value enters display or summary metadata. Rendering receives declarations, never generated bindings.

No dependency bounds change is preselected. Before adding unfamiliar calls to existing libraries, retry `mori registry list`, search the relevant package, inspect its owning project's full metadata/docs, and read its local source. If replacing the small encoder/entropy adapter with a library becomes desirable, first verify its released UUID7/TypeID support against Hackage and upstream release tags and update this decision and acceptance tests. Do not select a stale pin from the local corpus or invent an API while Mori is unavailable.
