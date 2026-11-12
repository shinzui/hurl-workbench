#!/usr/bin/env bash
# This driver runs INSIDE an existing caller lease and never releases it.
set -euo pipefail
: "${HURL_WORKBENCH_CONSUMER_WORKSPACE:?absolute consumer manifest required}"
: "${HURL_WORKBENCH_CONSUMER_SUITE:?consumer suite name required}"
: "${HURL_WORKBENCH_CONSUMER_EVIDENCE_ROOT:?private evidence root required}"
: "${HURL_WORKBENCH_EXECUTABLE:?built workbench executable required}"
exec python3 "$(dirname "$0")/check-multi-service-lease.py"
