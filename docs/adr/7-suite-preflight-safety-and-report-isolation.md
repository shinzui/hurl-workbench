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


Suite preparation resolves every referenced selection in declaration order, renders and validates
every workflow, resolves bindings, applies the mutation gate, checks generated artifact stems,
derives every report target, and resolves the optional service before execution. Direct workflows
are unclassified and require the same explicit authorization as mutating recipes. The service uses
only runtime/default/environment bindings and never sees recipe or matrix layers.

Within suite preflight, each consumer resolves only its selected names from the shared binding
input. Bindings for other suite consumers are ignored, while unknown selected names, channel
mismatches, missing values, and normal source precedence remain enforced. Standalone commands keep
the stricter unused-binding behavior.

Each expanded run receives its own `REPORT_ROOT/SUITE/RUN/` subtree and typed Hurl targets. An
existing suite subtree is rejected unless overwrite is explicit; overwrite removes only that
validated suite child after rejecting symbolic links. Directories are owner-only. The workbench
writes `summary.json` atomically and records only logical names, statuses, durations, and relative
report paths—never bindings, child environments, response bodies, or captured output.

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
lower-priority exit.
