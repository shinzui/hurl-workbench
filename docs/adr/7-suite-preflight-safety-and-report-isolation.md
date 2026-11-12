# ADR 7: Preflight whole suites and isolate every report tree


Status: Accepted

Date: 2026-09-20

Origin: [EP-5](../plans/5-orchestrate-services-and-integration-test-suites.md) under
[MasterPlan 1](../masterplans/1-build-hurl-workbench-for-reusable-api-workflows.md)


## Context


A suite can combine direct workflows, recipes, and matrices, then optionally run them against one
managed service. Starting that service before discovering a missing binding, unsafe run, duplicate
artifact name, or invalid report path would create avoidable local or remote side effects.

Runtime binding options are suite-wide, but each workflow and the service consume different
subsets. Strict single-workflow resolution correctly rejects accidental unused bindings; applying
that rule independently to each suite member would incorrectly reject values intended for another
member. Report formats also write incompatible file and directory shapes, and concurrent cases
must never update one shared report.


## Decision


Suite preparation first expands selections and checks application-state isolation in declaration
order. SharedState is the compatible default. With requested jobs greater than one, mutating or
unclassified expanded runs fail before formatting, binding resolution, report replacement, or
service resolution. The CLI repeats this pure guard before Hurl capability probes. Authorization
does not bypass it. IndependentState cannot declare a shared managed service. It requires external-service mode
and a private version-1 scenario handoff, verified in full before preparation or capability probes.
Every logical scenario has one unique fixture ID and endpoint origin. HTTP(S) origins use
lowercase scheme/host and effective port; userinfo, query, fragment, and non-root paths are
refused. Distinct paths cannot establish independence. Provider identity and actual database
separation remain caller assertions; workbench cannot prove DNS aliases are distinct state. This boundary is separate from the
existing batch scheduler and managed service ownership.

After isolation permits execution, suite preparation resolves every referenced selection, renders and validates
every workflow, resolves bindings, applies the mutation gate, checks generated artifact stems,
derives every report target, and resolves the optional service before execution. Direct workflows
are unclassified and require the same explicit authorization as mutating recipes. The service uses
only runtime/default/environment bindings and never sees recipe or matrix layers.

Within suite preflight, each consumer resolves only its selected names from the shared binding
input. Independent scenarios inject only their own validated provider binding input. Handoff
channels must name declared parameters of the proper kind, cannot overlap, and cannot conflict
with runtime files/overrides or committed recipe/case values. Defaults and declared environment
fallback remain lower priority. The caller owns fixture allocation, service readiness and lifetime,
password files, and release after all consumers stop. Workbench starts or releases none of them.
Bindings for other suite consumers are ignored, while unknown selected names, channel
mismatches, missing values, and normal source precedence remain enforced. Standalone commands keep
the stricter unused-binding behavior.

Each expanded run receives its own `REPORT_ROOT/SUITE/RUN/` subtree and typed Hurl targets. An
existing suite subtree is rejected unless overwrite is explicit; overwrite removes only that
validated suite child after rejecting symbolic links. Directories are owner-only. The workbench
writes `summary.json` atomically and records only logical names, statuses, durations, and relative
report paths—never bindings, child environments, response bodies, or captured output.

Safe SuiteMetadata is separate from executable PreparedSuite requests. Summaries identify isolation
and logical scenario stems. Safely reportable preflight refusals reserve only the selected suite
directory and write an atomic `refused` summary with `not-started` cases, stable reason codes, and
empty report lists; missing runtime inputs use `setup-failed`. Unknown selections and unsafe or
conflicting destinations produce no summary there and preserve existing trees. User-controlled
symlink ancestors are rejected. macOS's OS-owned `/tmp` and `/var` aliases are accepted only for
their standard `/private` destinations.

All cases run through EP-4's bounded worker pool. A completion observer retains finished outcomes
if service failure cancels the batch. Unfinished cases become explicit prerequisite skips, service
lifecycle failure selects exit 4, a Hurl start or summary-write failure selects exit 3, and an
ordinary Hurl failure preserves the first child exit in declaration order.


## Consequences


Once a suite starts its service, configuration, safety, and report-layout failures have already
been excluded. Default-safe automation cannot silently include a direct workflow or mutating
recipe. Concurrent report writers never share a target, and failed runs preserve partial reports
plus a redacted summary whenever summary writing succeeds.

Suite report overwrite is intentionally subtree-scoped and destructive only when explicitly
requested. Repeating a run without overwrite fails before the service starts. A summary-write
failure is retained separately in `SuiteResult` and cannot turn a service lifecycle failure into a
lower-priority exit. On asynchronous cancellation, the batch and service brackets first join
owned children; finalization retains completed outcomes, marks unfinished cases `cancelled`, and
writes a best-effort `cancelled` summary before rethrowing the original interruption. A reporting
failure never swallows cancellation. Provider-owned services and leases remain with the caller.
Hurl response artifacts retain the sensitive-output boundary in ADR 4.
