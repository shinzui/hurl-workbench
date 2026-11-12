# Bundle Update Log

## 2026-11-12
* **Update**: Reconciliation audit against ExecPlans 8-13 and their acceptance evidence. Status changes: IR-1, IR-2, IR-3, IR-4, IR-5 proposed -> completed; IR-6 accepted -> completed. Added completedAt from the commit recording each final criterion (IR-1 64af575, IR-2 bec9eb9, IR-3 b3f065c, IR-4 7200166, IR-5 0d7a85b, IR-6 64af575), resolution evidence, and targetPlan links: IR-1 docs/plans/10-support-ordered-multi-service-suite-lifecycles.md, IR-2 docs/plans/11-generate-fresh-parameters-for-each-workflow-execution.md, IR-3 docs/plans/12-support-caller-owned-file-roots-for-hurl-executions.md, IR-4 docs/plans/13-run-executable-checks-as-ordered-suite-barriers.md, IR-5 docs/plans/9-declare-scenario-isolation-and-guard-parallel-mutations.md, IR-6 docs/plans/8-support-explicit-clean-environments-for-managed-processes.md (previously a body-only link). Replaced IR-6 stale "not started" planning prose. Historical reviews, verified entries, and generation provenance unchanged.

## 2026-11-11
* **Update**: Accepted IR-6 and linked ExecPlan 8 (docs/plans/8-support-explicit-clean-environments-for-managed-processes.md); implementation and acceptance verification remain pending.

## 2026-10-11
* **Update**: Amended IR-1, IR-3 and IR-4 for mori://shinzui/rei/masterplans/29-close-rei-cli-and-http-api-gaps-on-the-haskell-jitsurei-contract: reverse cleanup and lifecycle/check barriers, real command/read observation, and concurrent temporary payload roots. Added IR-5 scenario isolation and IR-6 clean process environments. All remain proposed; historical reviews retain their original revision scope.

## 2026-09-24
* **Addition**: IR-1 through IR-4 filed from mori://tan/notification-hub after checking the workbench against its integration harness: several managed services per suite with setup and teardown commands, generated parameter kinds, a run-scoped file root, and executable checks as ordered suite runs.
