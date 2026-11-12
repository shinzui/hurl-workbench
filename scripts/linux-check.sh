#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
snapshot="$(mktemp -d "${TMPDIR:-/tmp}/hurl-workbench-linux.XXXXXX")"
trap 'rm -rf "$snapshot"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Capture the current tracked working tree (including staged new files), together
# with its Git identity. Linux must not overwrite macOS's Cabal plan/package DB or
# install Linux hooks into the developer's checkout. Build products stay here.
git -C "$repo_root" ls-files -z |
  tar -C "$repo_root" --null -T - -cf - |
  tar -C "$snapshot" -xf -
cp -Rp "$repo_root/.git" "$snapshot/.git"

container run --rm --cpus 4 --memory 8G \
  --env NIX_CONFIG=$'experimental-features = nix-command flakes\naccept-flake-config = true' \
  --volume "$snapshot:/workspace" --workdir /workspace \
  ghcr.io/nixos/nix:2.35.2 \
  nix develop .#check --accept-flake-config -c just check
