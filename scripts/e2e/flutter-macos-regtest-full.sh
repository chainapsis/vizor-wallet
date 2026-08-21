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
run_test "1/14 import funded wallet and sync balances" \
  "scripts/e2e/flutter-macos-regtest-import-sync.sh"

run_test "2/14 fallback from unavailable endpoint and sync balances" \
  "scripts/e2e/flutter-macos-regtest-fallback-endpoint.sh"

run_test "3/14 keep custom endpoint failures private" \
  "scripts/e2e/flutter-macos-regtest-custom-endpoint-no-fallback.sh"

run_test "4/14 recover from a stalled startup stream" \
  "scripts/e2e/flutter-macos-regtest-sync-startup-stall-recovery.sh"

run_test "5/14 fallback from slow-height primary and recover" \
  "scripts/e2e/flutter-macos-regtest-slow-height-fallback.sh"

run_test "6/14 create wallet and shield transparent funds" \
  "scripts/e2e/flutter-macos-regtest-shield-transparent.sh"

run_test "7/14 retry shield transparent broadcast failure" \
  "scripts/e2e/flutter-macos-regtest-shield-transparent-retry.sh"

run_test "8/14 import two accounts and send shielded funds" \
  "scripts/e2e/flutter-macos-regtest-multi-account-send.sh"

run_test "9/14 send shielded funds to a TEX address" \
  "scripts/e2e/flutter-macos-regtest-tex-send.sh"

run_test "10/14 show mempool receives in activity history" \
  "scripts/e2e/flutter-macos-regtest-mempool-receive-history.sh"

run_test "11/14 show mempool receives while sync is running" \
  "scripts/e2e/flutter-macos-regtest-mempool-during-sync.sh"

run_test "12/14 expire unmined mempool receives" \
  "scripts/e2e/flutter-macos-regtest-mempool-expiry.sh"

run_test "13/14 complete a real Ironwood vote" \
  "scripts/e2e/flutter-macos-regtest-voting.sh"

run_test "14/14 keep voting concurrent with a slow helper" \
  "scripts/e2e/flutter-macos-regtest-voting-slow-helper.sh"

echo
echo "all macOS regtest E2E tests passed"
