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
# custom-endpoint privacy (no mobile endpoint settings UI).
run_test "1/12 create wallet via passcode onboarding and sync" \
  "scripts/e2e/flutter-ios-regtest-mobile-create-sync.sh"

run_test "2/12 import funded wallet and sync balance" \
  "scripts/e2e/flutter-ios-regtest-mobile-import-sync.sh"

run_test "3/12 manage accounts and rotate the passcode" \
  "scripts/e2e/flutter-ios-regtest-mobile-account-management.sh"

run_test "4/12 import two accounts and send shielded funds" \
  "scripts/e2e/flutter-ios-regtest-mobile-multi-account-send.sh"

run_test "5/12 show mempool receives in activity" \
  "scripts/e2e/flutter-ios-regtest-mobile-mempool-receive.sh"

run_test "6/12 fall back from unavailable endpoint" \
  "scripts/e2e/flutter-ios-regtest-mobile-fallback-endpoint.sh"

run_test "7/12 fall back from slow-height primary and recover" \
  "scripts/e2e/flutter-ios-regtest-mobile-slow-height-fallback.sh"

run_test "8/12 migrate Orchard funds at the NU7 fee on Zebra" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-nu7.sh"

run_test "9/12 resume a persisted Ironwood proof after process restart" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-background-restart.sh"

run_test "10/12 create, open, and claim a Gift Card between two accounts" \
  "scripts/e2e/flutter-ios-regtest-mobile-payment-link-round-trip.sh"

run_test "11/12 answer a zcash: payment URI and send from its request card" \
  "scripts/e2e/flutter-ios-regtest-mobile-payment-uri-send.sh"

run_test "12/12 redeem a Gift Card during first-wallet setup and complete Home setup" \
  "scripts/e2e/flutter-ios-regtest-mobile-gift-onboarding.sh"

echo
echo "all iOS mobile regtest E2E tests passed"
