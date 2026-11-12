#!/usr/bin/env bash
# Required real-lease acceptance. No database or provider simulation fallback.
set -euo pipefail
exec python3 "$(dirname "$0")/check-scenario-isolation.py" "$@"
