---
okf_version: "0.2"
---

# What hurl-workbench provides today

This catalog records the consumer-facing capabilities implemented by
`hurl-workbench-core` and the `hurl-workbench` executable in `hurl-workbench-cli`.
Each stable `CAP-N` handle names an independently verifiable provision claim,
with public entry points, repository-relative evidence, and limits.

All records use `status: shipped` to mean available in this source tree,
`since: unreleased` because no release tag establishes availability, and
`stability: experimental` because the pre-1.0 interfaces may change. The package
version `0.1.0.0` alone is not release evidence. No independent review is claimed.

## Capabilities

| Handle | Capability |
|---|---|
| [CAP-1](typed-workspaces.md) | Typed and validated workspaces |
| [CAP-2](reusable-hurl-composition.md) | Reusable Hurl fragment composition |
| [CAP-3](secure-hurl-execution.md) | Secure parameter binding and Hurl execution |
| [CAP-4](recipes-and-bounded-matrices.md) | Recipes and bounded scenario matrices |
| [CAP-5](safe-integration-suites.md) | Preflighted integration suites and reports |
| [CAP-6](ordered-service-lifecycles.md) | Ordered managed service lifecycles |
| [CAP-7](explicit-command-environments.md) | Explicit inherited and clean command environments |
| [CAP-8](generated-execution-inputs.md) | Fresh generated inputs per Hurl execution |
| [CAP-9](caller-owned-body-file-roots.md) | Caller-owned request body file roots |
| [CAP-10](independent-scenario-handoffs.md) | Caller-provisioned independent scenario handoffs |
| [CAP-11](executable-check-barriers.md) | Executable assertions as ordered suite barriers |

## Adoption and maintenance

Start with the [README](../../README.md) and [task guides](../guides/index.md).
The [workspace](../reference/workspace.md) and [CLI](../reference/cli.md)
references define fields and options. [Use cases](../use-cases/index.md) record
consumer outcomes; [improvement requests](../improvement-requests/index.md)
record gaps. Fixtures, lease provisioning, and application assertion semantics
remain caller responsibilities.

The descriptor selects `coordination.capabilities` from
`mori://shinzui/okf-profiles` at published tag `v0.25.0`, frozen with a Dhall
semantic hash by `okf profile init`. Handles are bundle-scoped and preserved when
claims evolve. Cross-repository consumers can refer to, for example,
`mori://shinzui/hurl-workbench/okf/capabilities/concepts/CAP-11`.

```bash
mori validate
okf validate docs/capabilities --profile docs/capabilities/profile.dhall \
  --profile-enforce --log-enforce
okf graph docs/capabilities
```

Verify repository-relative evidence resources and mirror each `requires` entry
as a Markdown body link when updating a record. `--strict` additionally reports
missing independent review metadata; add provenance only for reviews that occurred.
