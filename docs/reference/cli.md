# CLI reference

```text
hurl-workbench [--workspace FILE] COMMAND
```

`--workspace` selects a manifest explicitly; otherwise discovery walks from the current directory
upward. `--version` prints the Cabal package version and short build revision. `--help`, empty
invocations, and parse errors show contextual help.

## Commands

| Command | Purpose | Primary output |
|---|---|---|
| `validate` | Decode, semantically validate, and Hurlfmt-check every workflow. | Counts on stdout; diagnostics on stderr. |
| `list [CATEGORY]` | List `all`, `parameters`, `fragments`, `workflows`, `recipes`, `matrices`, `services`, or `suites`. | Stable tables on stdout. |
| `render workflow NAME` | Compose and Hurlfmt-check a workflow. | Hurl on stdout or atomically to `--output FILE`. |
| `render recipe NAME` | Render a recipe's selected workflow; `--explain` lists binding sources without values. | Hurl on stdout; explanation/path on stderr. |
| `run workflow|recipe NAME` | Execute in Hurl client mode. | Hurl streams directly to the terminal. |
| `test workflow|recipe NAME` | Execute in Hurl test mode. | Hurl streams directly to the terminal. |
| `matrix NAME` | Expand and execute every recipe case. | Ordered diagnostics and case summaries on stderr. |
| `test suite NAME` | Preflight and execute a suite, optionally managing its service. | Ordered diagnostics, summaries, and artifact paths on stderr. |
| `doctor` | Probe Hurl and Hurlfmt paths, versions, and support status. | Tool report on stdout. |
| `completions bash|zsh|fish` | Generate a shell script that delegates to this parser. | Script on stdout. |

Run any command with `--help` for its complete grouped options.

## Bindings and execution controls

Execution commands accept repeatable `--variable NAME=VALUE`, `--variables-file FILE`,
`--secret-env NAME=ENVIRONMENT_NAME`, and `--secrets-file FILE`. `--allow-mutating` is required for
mutating recipes/matrix cases and for unclassified direct workflows inside suites.

Typed Hurl controls are `--connect-timeout`, `--max-time`, `--retry`, `--retry-interval`,
`--insecure`, `--include`, `--json`, `--verbose` or `--very-verbose`, and `--curl FILE`. The only
accepted repeatable `--hurl-arg` values are:

```text
--compressed  --location  --location-trusted  --no-color  --path-as-is
```

Options taking values are never accepted through passthrough.

Matrices add `--mode run|test`, `--jobs N`, `--fail-fast`/`--keep-going`, `--output-dir DIR`, and
`--overwrite`. Parallel client mode requires an output directory. Suites add `--jobs`, safety and
fail-fast controls, `--external-service`, repeatable `--report junit|html|json|tap`, `--report-dir`,
and `--overwrite`.

## Artifacts and reports

Client matrix responses use `OUTPUT/MATRIX/CASE.response`. Suite reports use
`REPORT/SUITE/RUN/`: `junit.xml`, `html/`, `json/`, or `report.tap`. Every suite writes a redacted
`summary.json` when a report directory is selected. Output directories are owner-only (`0700`) and
files are owner-readable/writable (`0600`). Existing targets fail preflight unless overwrite is
explicit; suite overwrite removes only the validated selected suite subtree.

## Exit behavior

- `0`: workbench success and every started Hurl process succeeded;
- `1`: ordinary discovery, decoding, validation, or selection failure for inspection commands;
- `2`: execution preflight, binding, safety-gate, or artifact-layout failure;
- `3`: missing dependency, secure-file/start failure, or report-summary write failure;
- `4`: managed-service lifecycle failure;
- another non-zero status: for a started single run, Hurl's exact status; batches select the first
  Hurl failure in declaration order unless a higher-priority workbench/service failure applies.

Parse failures are emitted by optparse-applicative with contextual usage. Failures before a child
starts are labeled as workbench/preflight errors; Hurl failures remain child results.

## Completion installation

```bash
hurl-workbench completions bash > ~/.local/share/bash-completion/completions/hurl-workbench
hurl-workbench completions zsh > ~/.zfunc/_hurl-workbench
hurl-workbench completions fish > ~/.config/fish/completions/hurl-workbench.fish
```

The generated scripts require `hurl-workbench` on `PATH` and query its hidden completion protocol
at tab-completion time.
