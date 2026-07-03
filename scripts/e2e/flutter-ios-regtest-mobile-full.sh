#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

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
require_cmd xcrun

cd "$ROOT_DIR"

# Keep this ordered from the narrowest smoke test to broader user flows.
# Desktop scenarios without a mobile counterpart yet (feature gaps):
# custom-endpoint privacy (no mobile endpoint settings UI) and
# shield-transparent ×2 (no mobile transparent balance / shield UI).
run_test "1/7 create wallet via passcode onboarding and sync" \
  "scripts/e2e/flutter-ios-regtest-mobile-create-sync.sh"

run_test "2/7 import funded wallet and sync balance" \
  "scripts/e2e/flutter-ios-regtest-mobile-import-sync.sh"

run_test "3/7 manage accounts and rotate the passcode" \
  "scripts/e2e/flutter-ios-regtest-mobile-account-management.sh"

run_test "4/7 import two accounts and send shielded funds" \
  "scripts/e2e/flutter-ios-regtest-mobile-multi-account-send.sh"

run_test "5/7 show mempool receives in activity" \
  "scripts/e2e/flutter-ios-regtest-mobile-mempool-receive.sh"

run_test "6/7 fall back from unavailable endpoint" \
  "scripts/e2e/flutter-ios-regtest-mobile-fallback-endpoint.sh"

run_test "7/7 fall back from slow-height primary and recover" \
  "scripts/e2e/flutter-ios-regtest-mobile-slow-height-fallback.sh"

echo
echo "all iOS mobile regtest E2E tests passed"
