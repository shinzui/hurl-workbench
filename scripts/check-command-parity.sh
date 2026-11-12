#!/usr/bin/env bash
# Execute inside caller-owned, independently provisioned CLI and HTTP scopes.
set -euo pipefail
: "${HURL_WORKBENCH_CONSUMER_WORKSPACE:?absolute consumer manifest required}"
: "${HURL_WORKBENCH_CONSUMER_SUITE:?consumer suite required}"
: "${HURL_WORKBENCH_CLI_FIXTURE:?CLI fixture path required}"
: "${HURL_WORKBENCH_API_URL:?HTTP fixture endpoint required}"
: "${HURL_WORKBENCH_CLI_FIXTURE_ID:?CLI fixture identity required}"
: "${HURL_WORKBENCH_API_FIXTURE_ID:?HTTP fixture identity required}"
: "${HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT:?new private evidence root required}"
if [[ "$HURL_WORKBENCH_CONSUMER_WORKSPACE" != /* || "$HURL_WORKBENCH_CLI_FIXTURE_ID" == "$HURL_WORKBENCH_API_FIXTURE_ID" ]]; then
  echo 'absolute manifest and distinct fixture identities required' >&2
  exit 2
fi
workbench="${HURL_WORKBENCH_EXECUTABLE:-hurl-workbench}"
evidence="$HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT"
(umask 077; mkdir "$evidence")
inputs=(--variable "cliFixture=$HURL_WORKBENCH_CLI_FIXTURE" --variable "apiUrl=$HURL_WORKBENCH_API_URL" --variable "cliFixtureId=$HURL_WORKBENCH_CLI_FIXTURE_ID" --variable "apiFixtureId=$HURL_WORKBENCH_API_FIXTURE_ID")
suite="$HURL_WORKBENCH_CONSUMER_SUITE"
mismatch_suite="${HURL_WORKBENCH_CONSUMER_MISMATCH_SUITE:-$suite-mismatch}"
set +e
"$workbench" --workspace "$HURL_WORKBENCH_CONSUMER_WORKSPACE" test suite "$suite" --jobs 2 --report-dir "$evidence/match" "${inputs[@]}" >"$evidence/match.log" 2>&1
matched=$?
# The application-owned mismatch suite changes only its disposable HTTP fixture
# through a supported API, then runs the same assertion. Shared writes are serial.
"$workbench" --workspace "$HURL_WORKBENCH_CONSUMER_WORKSPACE" test suite "$mismatch_suite" --jobs 1 --allow-mutating --report-dir "$evidence/mismatch" "${inputs[@]}" >"$evidence/mismatch.log" 2>&1
mismatched=$?
set -e
chmod 600 "$evidence/match.log" "$evidence/mismatch.log"
python3 - "$evidence" "$suite" "$mismatch_suite" "$matched" "$mismatched" <<'PY'
import json
import os
from pathlib import Path
import sys
root, suite, mismatch, matched, mismatched = sys.argv[1:]
root = Path(root)
assert int(matched) == 0, 'matching consumer failed; see private match.log'
assert int(mismatched) not in (0, 2, 3, 4, 124, 130), 'mismatch must be an assertion failure'
for variant, name, expected in [('match', suite, 'passed'), ('mismatch', mismatch, 'failed')]:
    raw = (root / variant / name / 'summary.json').read_text()
    data = json.loads(raw)
    checks = [s for s in data['steps'] if s['kind'] == 'check']
    assert checks and all(s['status'] == expected for s in checks)
    for check in checks:
        assert check['elapsedSeconds'] is not None and check['stdout'] and check['stderr']
    sentinel = os.environ.get('HURL_WORKBENCH_CONSUMER_SECRET_SENTINEL', '')
    if sentinel:
        assert sentinel not in raw and sentinel not in (root / (variant + '.log')).read_text()
print('independent CLI/API match and named semantic mismatch: PASS')
PY
