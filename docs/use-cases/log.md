# Bundle Update Log

## 2026-09-20
* **Delivery**: UC-1 deterministic-session-composition and secure-runtime-bindings are delivered by EP-2 and EP-3: opaque complete-entry fragments render deterministically, while resolved plain and secret bindings reach Hurl through protected files rather than source or argv.
* **Delivery**: All UC-4 features are delivered by EP-2 and EP-3: native Hurl scenarios execute without semantic rewriting, child streams and exit status remain faithful, and the workbench's runtime boundary does not disclose declared secrets.
* **Delivery**: All UC-2 features are delivered by EP-3 and EP-4: recipes and ordered matrix cases reduce to isolated secure runs, bounded workers retain truthful per-case outcomes, and mutating selections require an invocation-local authorization flag.

## 2026-09-19
* **Delivery**: UC-1 typed-reusable-workspace is delivered by EP-1 (docs/plans/1-define-the-typed-hurl-workspace-contract.md): the full fixture validates one OAuth fragment shared by two workflows, and list shows both.

## 2026-09-18
* **Addition**: UC-1 through UC-4 capture authenticated workflow reuse, parameterized
API scenarios, repeatable integration suites, and raw-wire diagnosis.
* **Contract gate**: Each planned feature is traced to public contracts and an owning
ExecPlan before product implementation begins.
* **Maturity boundary**: The scenarios are validated from existing repository evidence;
their features remain planned. This bundle claims no runtime delivery.
* **Profile**: The bundle uses OKF 0.2 and the `jtbd-use-cases` profile from
`mori://shinzui/okf-profiles/profiles/use-cases`, pinned to v0.15.0.
