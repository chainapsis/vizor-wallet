#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39067}"
DRIVER_LOG="$ROOT_DIR/.regtest/mobile-gift-onboarding-driver.log"
DEEPLINK_BASE_URL="${VIZOR_DEEPLINK_BASE_URL:-https://link-dev.vizor.cash}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd docker
require_cmd fvm
require_cmd python3
require_cmd xcrun
cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh
UDID="$(pick_simulator)"

cleanup() {
  if [[ -n "${DRIVER_PID:-}" ]]; then
    kill "$DRIVER_PID" >/dev/null 2>&1 || true
    wait "$DRIVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
start_e2e_driver "$DRIVER_PORT" "$DRIVER_LOG"

run_mobile_e2e integration_test/regtest_mobile_gift_onboarding_test.dart "$UDID" \
  --tags mobile --run-skipped \
  --dart-define=ZCASH_E2E_DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}" \
  --dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true \
  --dart-define=VIZOR_DEEPLINK_BASE_URL="$DEEPLINK_BASE_URL"
