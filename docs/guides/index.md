# Hurl Workbench guides

Start with the [quick start](../../README.md#five-minute-quick-start), then choose
the workflow you need. Commands in these guides assume the repository root and
the pinned `nix develop` environment.

| Task | Guide or runnable example |
|---|---|
| Reuse authentication and vary query defaults | [Vendor API exploration](vendor-api-exploration.md) |
| Run reviewed suites with safe concurrency and private reports | [Integration testing](integration-testing.md) |
| Start an API, stub, and worker in order; restart between batches | [Ordered services](integration-testing.md#ordered-services-and-lifecycle-barriers) and [example](../../examples/multi-service/README.md) |
| Select the environment passed to commands | [Clean environments](integration-testing.md#explicit-clean-command-environments) |
| Generate fresh IDs, timestamps, or random values | [Fresh inputs](integration-testing.md#fresh-scenario-identifiers) and [example](../../examples/generated-parameters/README.md) |
| Send caller-generated body files unchanged | [File roots](integration-testing.md#caller-generated-file-request-bodies) and [example](../../examples/file-body/README.md) |
| Assert facts through an application CLI or semantic API | [Executable checks](integration-testing.md#assertions-beyond-http) and [example](../../examples/executable-checks/README.md) |
| Run mutations against independent caller-owned fixtures | [Scenario handoff](integration-testing.md#independent-scenario-handoff) |
| Verify real lease ownership and release | [Provider acceptance](integration-testing.md#real-provider-acceptance) |

The [workspace reference](../reference/workspace.md) defines Dhall records and
binding precedence; the [CLI reference](../reference/cli.md) defines commands,
artifacts, and exit behavior. The [security model](../security.md) explains input
and output boundaries. The [capability catalog](../capabilities/index.md) connects
these public contracts to implementation and acceptance evidence.

Normal local examples run with `just examples` after `cabal build all`. Real
provider and application checks have separate prerequisites and callers; their
recorded acceptance applies to the documented executable cohort.
