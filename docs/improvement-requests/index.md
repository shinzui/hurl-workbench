---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Add generated parameter kinds so re-runnable scenarios need no helper script](add-generated-parameter-kinds-so-re-runnable-scenarios-need-no-helper-script.md) - Parameters are plain or secret and come from bindings, files, or the environment; a scenario that must be re-runnable against a persistent database needs a fresh identifier of a specific shape on every run, which neither the workspace nor Hurl's newUuid and newDate can produce.
- [Admit executable checks as ordered suite runs for assertions Hurl cannot make](admit-executable-checks-as-ordered-suite-runs-for-assertions-hurl-cannot-make.md) - Integration suites often need one assertion that is not an HTTP response, such as a row count in the service's database or a message on a broker; because the workbench deliberately excludes arbitrary hooks, such suites keep a shell harness around the workbench and lose its single ordered report.
- [Allow a run-scoped file root for file request bodies](allow-a-run-scoped-file-root-for-file-request-bodies.md) - The workbench always passes the workspace root as Hurl's file root, so a fragment that sends a file body resolves under the workspace root; integration runs that write request files per run, with per-run keys or signatures, have nowhere the workbench will read them from.
- [Declare scenario isolation and guard parallel mutations](declare-scenario-isolation-and-guard-parallel-mutations.md) - Make suite state sharing explicit and reject parallel mutating or unclassified runs against shared state, while permitting bounded concurrency for independently provisioned fixtures.
- [Support explicit clean environments for managed processes](support-explicit-clean-environments-for-managed-processes.md) - Allow managed services, readiness commands, and future lifecycle or check commands to receive only explicitly selected inherited environment variables plus declared bindings.
- [Support several managed services per suite with ordered readiness and setup commands](support-several-managed-services-per-suite-with-ordered-readiness-and-setup-commands.md) - A suite can own one managed service and no setup or teardown commands, so an integration test that needs a database cluster, migrations, a stub provider, an HTTP server, and a background worker cannot be a workbench suite without a shell wrapper around it.

