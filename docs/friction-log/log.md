# Bundle Update Log

## 2026-11-12

* **Update**: FRIC-10 resolved: Fix readiness publication ordering in the existing fixture.


* **Update**: FRIC-9 accepted: Accept the local registry outage for this implementation without dependency changes.


* **Addition**: FRIC-10 records detour tooling friction with mori://shinzui/hurl-workbench: Lifecycle fixture publishes readiness before logging readiness


* **Addition**: FRIC-9 records detour environment friction with mori://shinzui/mori: Mori dependency discovery requires unavailable PostgreSQL


* **Update**: FRIC-8 resolved: Eliminate shared cross-platform build metadata and host hook writes from the Linux gate.


* **Addition**: FRIC-8 records detour tooling friction with mori://shinzui/hurl-workbench: Linux checks overwrite the macOS Cabal package database


* **Update**: FRIC-7 accepted: Keep consumer build repair outside this workbench plan; record the verified cohort and artifact digests.


* **Addition**: FRIC-7 records detour tooling friction with mori://shinzui/rei: Rei 9 live fixture fails to link its generated Note owner


* **Update**: FRIC-6 resolved: User identified stale shell; registry discovery now succeeds.


* **Addition**: FRIC-6 records blocked environment friction with mori://shinzui/mori: Mori registry unavailable during multi-service implementation


* **Update**: FRIC-5 resolved: Linux container release validation uses devShells.check; all 91 core and 37 CLI tests plus the complete release gate pass.


* **Addition**: FRIC-5 records detour tooling friction with mori://shinzui/hurl-workbench: Linux release gate realizes editor-only HLS dependencies


* **Update**: FRIC-4 resolved: Registry list/search/show/docs succeed with the current profile endpoint; continue dependency and Hinagata integration.


* **Addition**: FRIC-4 records blocked environment friction with mori://shinzui/mori: Mori registry unavailable through PostgreSQL tunnel

* **Update**: FRIC-1 resolved: Verified registry search/show/docs against the current local PostgreSQL endpoint; no database service change was necessary.

## 2026-11-11

* **Update**: FRIC-3 accepted: All Linux gate components passed through the temporary shell and a stable-source Nix retry.


* **Addition**: FRIC-3 records slowdown environment friction with mori://shinzui/hurl-workbench: Disposable Linux validation compiles a cold development toolchain


* **Update**: FRIC-2 resolved: Serialize the test harness while preserving explicit batch concurrency tests.


* **Addition**: FRIC-2 records detour tooling friction with mori://shinzui/hurl-workbench: Parallel tests race process-global environment mutation


* **Addition**: FRIC-1 records blocked environment friction with mori://shinzui/mori: Mori registry unavailable during dependency and lease discovery

* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
