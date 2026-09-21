#!/usr/bin/env bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

sdist_dir="$work_dir/sdist"
unpack_dir="$work_dir/unpacked"
mkdir -p "$sdist_dir" "$unpack_dir"

cabal sdist all --output-directory="$sdist_dir"

core_archive="$sdist_dir/hurl-workbench-core-0.1.0.0.tar.gz"
cli_archive="$sdist_dir/hurl-workbench-cli-0.1.0.0.tar.gz"
test -f "$core_archive"
test -f "$cli_archive"

core_listing="$(tar -tzf "$core_archive")"
cli_listing="$(tar -tzf "$cli_archive")"

for required in LICENSE CHANGELOG.md README.md schema/package.dhall; do
  rg -q "/$required$" <<<"$core_listing"
  rg -q "/$required$" <<<"$cli_listing"
done
rg -q '/examples/vendor-odata/hurl-workbench.dhall$' <<<"$cli_listing"
rg -q '/examples/integration-service/hurl-workbench.dhall$' <<<"$cli_listing"
rg -q '/examples/quick-start/hurl-workbench.dhall$' <<<"$cli_listing"

if rg -q '(^|/)(dist-newstyle|build|reports)(/|$)|[.]env$|[.]response$' <<<"$core_listing$cli_listing"; then
  echo "source distribution contains generated or secret-shaped artifacts" >&2
  exit 1
fi

tar -xzf "$core_archive" -C "$unpack_dir"
tar -xzf "$cli_archive" -C "$unpack_dir"

if rg -n '/Users/|/home/[^/]+/' "$unpack_dir"; then
  echo "source distribution contains a personal absolute path" >&2
  exit 1
fi

printf '%s\n' \
  'packages:' \
  '  ./hurl-workbench-core-0.1.0.0' \
  '  ./hurl-workbench-cli-0.1.0.0' \
  >"$unpack_dir/cabal.project"

(
  cd "$unpack_dir"
  cabal build all
  version_output="$("$(cabal list-bin exe:hurl-workbench)" --version)"
  if [[ "$version_output" != "hurl-workbench 0.1.0.0 (unknown)" ]]; then
    echo "source distribution version fallback is not deterministic: $version_output" >&2
    exit 1
  fi
)

echo "source distributions: PASS"
