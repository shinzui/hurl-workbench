#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
hook_backup="$(mktemp -d "${TMPDIR:-/tmp}/hurl-workbench-hooks.XXXXXX")"

restore_hooks() {
  local hook
  for hook in pre-commit commit-msg; do
    if [[ -e "$hook_backup/$hook.present" ]]; then
      cp -Pp "$hook_backup/$hook" "$repo_root/.git/hooks/$hook"
    else
      rm -f "$repo_root/.git/hooks/$hook"
    fi
  done
  rm -rf "$hook_backup"
}

trap restore_hooks EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for hook in pre-commit commit-msg; do
  if [[ -e "$repo_root/.git/hooks/$hook" || -L "$repo_root/.git/hooks/$hook" ]]; then
    cp -Pp "$repo_root/.git/hooks/$hook" "$hook_backup/$hook"
    touch "$hook_backup/$hook.present"
  fi
done

container run --rm --cpus 4 --memory 8G \
  --env NIX_CONFIG=$'experimental-features = nix-command flakes\naccept-flake-config = true' \
  --volume "$repo_root:/workspace" --workdir /workspace \
  ghcr.io/nixos/nix:2.35.2 \
  nix develop --accept-flake-config -c just check
