#!/usr/bin/env bash
# Exercise the consumer driver without a database. This is not real lease evidence.
set -euo pipefail
simulation_dir=$(mktemp -d)
trap 'rm -rf "$simulation_dir"' EXIT
cat > "$simulation_dir/psql" <<'MOCK'
#!/bin/sh
printf '%s|%s\n' "$PGDATABASE" "$PGUSER"
MOCK
chmod +x "$simulation_dir/psql"
export PATH="$simulation_dir:$PATH"
export HURL_WORKBENCH_EXECUTABLE="$(cabal list-bin hurl-workbench)"
export PGHOST=simulation PGPORT=5432 PGUSER=simulation PGDATABASE=simulation
unset PGPASSFILE
bash scripts/check-clean-environment-lease.sh
printf '%s\n' 'simulated clean lease driver: PASS (no provider allocation or release)'
