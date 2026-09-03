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
run_test "1/17 import funded wallet and sync balances" \
  "scripts/e2e/flutter-macos-regtest-import-sync.sh"

run_test "2/17 fallback from unavailable endpoint and sync balances" \
  "scripts/e2e/flutter-macos-regtest-fallback-endpoint.sh"

run_test "3/17 keep custom endpoint failures private" \
  "scripts/e2e/flutter-macos-regtest-custom-endpoint-no-fallback.sh"

run_test "4/17 recover from a stalled startup stream" \
  "scripts/e2e/flutter-macos-regtest-sync-startup-stall-recovery.sh"

run_test "5/17 fallback from slow-height primary and recover" \
  "scripts/e2e/flutter-macos-regtest-slow-height-fallback.sh"

run_test "6/17 create wallet and shield transparent funds" \
  "scripts/e2e/flutter-macos-regtest-shield-transparent.sh"

run_test "7/17 retry shield transparent broadcast failure" \
  "scripts/e2e/flutter-macos-regtest-shield-transparent-retry.sh"

run_test "8/17 import two accounts and send shielded funds" \
  "scripts/e2e/flutter-macos-regtest-multi-account-send.sh"

run_test "9/17 send shielded funds to a TEX address" \
  "scripts/e2e/flutter-macos-regtest-tex-send.sh"

run_test "10/17 show mempool receives in activity history" \
  "scripts/e2e/flutter-macos-regtest-mempool-receive-history.sh"

run_test "11/17 show mempool receives while sync is running" \
  "scripts/e2e/flutter-macos-regtest-mempool-during-sync.sh"

run_test "12/17 expire unmined mempool receives" \
  "scripts/e2e/flutter-macos-regtest-mempool-expiry.sh"

run_test "13/17 complete a real Ironwood vote" \
  "scripts/e2e/flutter-macos-regtest-voting.sh"

run_test "14/17 keep voting concurrent with a slow helper" \
  "scripts/e2e/flutter-macos-regtest-voting-slow-helper.sh"

run_test "15/17 open a zcash: payment URI and send from the card" \
  "scripts/e2e/flutter-macos-regtest-payment-uri-send.sh"

run_test "16/17 pay a payment URI opened while the wallet is locked" \
  "scripts/e2e/flutter-macos-regtest-payment-uri-locked-send.sh"

run_test "17/17 compose a payment request and pay it round-trip" \
  "scripts/e2e/flutter-macos-regtest-payment-request-round-trip.sh"

echo
echo "all macOS regtest E2E tests passed"
