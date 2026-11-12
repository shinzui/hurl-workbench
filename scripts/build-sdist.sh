#!/usr/bin/env bash
# Canonical release archives retain executable workspace helpers. Cabal itself
# deliberately normalizes every source entry to 0644.
set -euo pipefail
output_directory="${1:?source archive output directory required}"
cabal sdist all --output-directory="$output_directory"
for archive in "$output_directory"/hurl-workbench-cli-*.tar.gz; do
  python3 scripts/normalize-sdist-modes.py "$archive"
done
