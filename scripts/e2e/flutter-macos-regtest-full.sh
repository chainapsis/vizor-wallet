#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

run_test() {
  local name="$1"
  local script="$2"

  echo
  echo "==> ${name}"
  RESET_REGTEST=1 "$ROOT_DIR/$script"
}

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3

cd "$ROOT_DIR"

# Keep this ordered from the narrowest smoke test to broader user flows.
run_test "1/10 import funded wallet and sync balances" \
  "scripts/e2e/flutter-macos-regtest-import-sync.sh"

run_test "2/10 fallback from unavailable endpoint and sync balances" \
  "scripts/e2e/flutter-macos-regtest-fallback-endpoint.sh"

run_test "3/10 keep custom endpoint failures private" \
  "scripts/e2e/flutter-macos-regtest-custom-endpoint-no-fallback.sh"

run_test "4/10 fallback from slow-height primary and recover" \
  "scripts/e2e/flutter-macos-regtest-slow-height-fallback.sh"

run_test "5/10 create wallet and shield transparent funds" \
  "scripts/e2e/flutter-macos-regtest-shield-transparent.sh"

run_test "6/10 retry shield transparent broadcast failure" \
  "scripts/e2e/flutter-macos-regtest-shield-transparent-retry.sh"

run_test "7/10 import two accounts and send shielded funds" \
  "scripts/e2e/flutter-macos-regtest-multi-account-send.sh"

run_test "8/10 show mempool receives in activity history" \
  "scripts/e2e/flutter-macos-regtest-mempool-receive-history.sh"

run_test "9/10 show mempool receives while sync is running" \
  "scripts/e2e/flutter-macos-regtest-mempool-during-sync.sh"

run_test "10/10 expire unmined mempool receives" \
  "scripts/e2e/flutter-macos-regtest-mempool-expiry.sh"

echo
echo "all macOS regtest E2E tests passed"
