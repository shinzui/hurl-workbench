#!/usr/bin/env bash
set -euo pipefail

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/hurl" "$work_dir/schema"
cp schema/*.dhall "$work_dir/schema/"

for number in $(seq 1 100); do
  printf 'GET {{base_url}}/health?case=%s\nHTTP 200\n' "$number" >"$work_dir/hurl/fragment-$number.hurl"
done

{
  printf '%s\n' 'let Schema = ./schema/package.dhall' '' 'let fragments ='
  for number in $(seq 1 100); do
    separator=','
    if [[ "$number" == 1 ]]; then separator='['; fi
    printf '      %s Schema.Fragment::{ name = "fragment-%s", path = "hurl/fragment-%s.hurl" }\n' "$separator" "$number" "$number"
  done
  printf '%s\n' '      ]' '' 'let fragmentNames ='
  for number in $(seq 1 100); do
    separator=','
    if [[ "$number" == 1 ]]; then separator='['; fi
    printf '      %s "fragment-%s"\n' "$separator" "$number"
  done
  printf '%s\n' '      ]' '' 'let cases ='
  for number in $(seq 1 100); do
    separator=','
    if [[ "$number" == 1 ]]; then separator='['; fi
    printf '      %s Schema.MatrixCase::{ name = "case-%s" }\n' "$separator" "$number"
  done
  printf '%s\n' \
    '      ]' \
    '' \
    'in  Schema.Workspace::{' \
    '    , schemaVersion = Schema.schemaVersion' \
    '    , parameters = [ Schema.Parameter::{ name = "base_url", defaultValue = Some "http://127.0.0.1:18080" } ]' \
    '    , fragments = fragments' \
    '    , workflows = [ Schema.Workflow::{ name = "bulk", fragments = fragmentNames, parameters = [ "base_url" ] } ]' \
    '    , recipes = [ Schema.Recipe::{ name = "bulk", workflow = "bulk", safety = Schema.Safety.ReadOnly } ]' \
    '    , matrices = [ Schema.Matrix::{ name = "bulk", recipe = "bulk", cases = cases } ]' \
    '    }'
} >"$work_dir/hurl-workbench.dhall"

workbench="$(cabal list-bin hurl-workbench)"
started="$(date +%s)"
"$workbench" --workspace "$work_dir/hurl-workbench.dhall" validate >/dev/null
"$workbench" --workspace "$work_dir/hurl-workbench.dhall" render workflow bulk --output "$work_dir/rendered.hurl"
elapsed="$(( $(date +%s) - started ))"

test "$elapsed" -lt 30
test "$(rg -c '^GET ' "$work_dir/rendered.hurl")" -eq 100
echo "performance smoke: PASS (${elapsed}s for 100 fragments and 100 cases)"
