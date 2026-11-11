# Bundle Update Log

## 2026-11-11

* **Update**: FRIC-3 accepted: All Linux gate components passed through the temporary shell and a stable-source Nix retry.


* **Addition**: FRIC-3 records slowdown environment friction with mori://shinzui/hurl-workbench: Disposable Linux validation compiles a cold development toolchain


* **Update**: FRIC-2 resolved: Serialize the test harness while preserving explicit batch concurrency tests.


* **Addition**: FRIC-2 records detour tooling friction with mori://shinzui/hurl-workbench: Parallel tests race process-global environment mutation


* **Addition**: FRIC-1 records blocked environment friction with mori://shinzui/mori: Mori registry unavailable during dependency and lease discovery

* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
