set shell := ["bash", "-euo", "pipefail", "-c"]

cabal-index:
    cabal update

build: cabal-index
    cabal build all

test: cabal-index
    cabal test all --test-show-details=direct

fmt:
    nix fmt

fmt-check:
    nix fmt -- --ci
    echo "formatting: PASS"

hurlfmt-check:
    rg --files -g '*.hurl' | xargs hurlfmt --check
    echo "Hurl formatting: PASS"

sync-check:
    cmp LICENSE hurl-workbench-core/LICENSE
    cmp LICENSE hurl-workbench-cli/LICENSE
    cmp CHANGELOG.md hurl-workbench-core/CHANGELOG.md
    cmp CHANGELOG.md hurl-workbench-cli/CHANGELOG.md
    cmp README.md hurl-workbench-core/README.md
    cmp README.md hurl-workbench-cli/README.md
    diff -qr schema hurl-workbench-core/schema
    diff -qr schema hurl-workbench-cli/schema
    diff -qr examples hurl-workbench-cli/examples
    echo "release copies: PASS"

schema-check: cabal-index
    cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/minimal/hurl-workbench.dhall validate
    cabal run hurl-workbench -- --workspace hurl-workbench-core/test/fixtures/workspaces/minimal-explicit/hurl-workbench.dhall validate
    echo "schema compatibility: PASS"

performance: cabal-index
    bash scripts/performance-smoke.sh

examples: cabal-index
    @work_dir="$(mktemp -d)"; \
    server_pid=""; \
    cleanup() { if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "$work_dir"; }; \
    trap cleanup EXIT; \
    workbench="$(cabal list-bin hurl-workbench)"; \
    fixture_server="$(cabal list-bin hurl-workbench-fixture-server)"; \
    "$fixture_server" --port 18080 >"$work_dir/server.log" 2>&1 & \
    server_pid=$!; \
    for attempt in $(seq 1 100); do if curl --fail --silent http://127.0.0.1:18080/health >/dev/null; then break; fi; if [[ "$attempt" == 100 ]]; then cat "$work_dir/server.log" >&2; exit 1; fi; sleep 0.05; done; \
    QUICKSTART_TOKEN=fixture-secret "$workbench" --workspace examples/quick-start/hurl-workbench.dhall test workflow health; \
    VENDOR_ODATA_CLIENT_SECRET=fixture-secret "$workbench" --workspace examples/vendor-odata/hurl-workbench.dhall matrix property-by-mls --mode run --jobs 2 --output-dir "$work_dir/vendor" --variable baseUrl=http://127.0.0.1:18080; \
    VENDOR_ODATA_CLIENT_SECRET=fixture-secret "$workbench" --workspace examples/vendor-odata/hurl-workbench.dhall test workflow co-buyer-investigation --variable baseUrl=http://127.0.0.1:18080 --variable clientId=fixture-client; \
    "$workbench" --workspace examples/vendor-odata/hurl-workbench.dhall test workflow raw-decoding-investigation --variable baseUrl=http://127.0.0.1:18080; \
    kill "$server_pid"; wait "$server_pid" 2>/dev/null || true; server_pid=""; \
    "$workbench" --workspace examples/integration-service/hurl-workbench.dhall test suite default --jobs 2 --report junit --report html --report json --report tap --report-dir "$work_dir/reports"; \
    "$workbench" --workspace examples/integration-service/hurl-workbench.dhall test suite perimeter; \
    "$workbench" --workspace examples/integration-service/hurl-workbench.dhall test suite writes --allow-mutating; \
    echo "examples: PASS"

sdist: cabal-index
    bash scripts/check-sdist.sh

nix-check:
    nix flake check

# Run the complete release gate in a disposable ARM64 Linux VM through Apple's
# `container` CLI. Invoke this recipe from macOS, outside the Nix dev shell.
linux-check:
    bash scripts/linux-check.sh

check: fmt-check hurlfmt-check sync-check build test schema-check performance examples sdist nix-check
    echo "all checks: PASS"
