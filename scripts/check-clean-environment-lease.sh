#!/usr/bin/env bash
# Run inside an already active caller-owned PostgreSQL lease.
set -euo pipefail
for name in PGHOST PGPORT PGUSER PGDATABASE; do
  if [[ -z "${!name+x}" ]]; then
    echo "missing required lease variable: $name" >&2
    exit 2
  fi
done
exec python3 "$(dirname "$0")/check-clean-environment-lease.py" "$@"
