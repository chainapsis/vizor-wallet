#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENDER_ADDRESS="uregtest1dwwn6pcjc82hq2yu3nuwe4w4pzhdm04qprtl2n9knk6de6g8dkyraplcnmvztt47mrekzgdfnyrqycppg8l4yvnf2cg2tyxplcs95haxfyg4qt5xv3vly32lnt7m3tz4uznudek464gn795k26v05chgaw8z3fdjc5zxc5vx6yq552zm"
SENDER_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
ZCASHD_RPC_URL="${E2E_ZCASHD_RPC_URL:-http://127.0.0.1:18232}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd fvm

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

echo "funding payment-link sender with ${SENDER_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh \
  "$SENDER_ADDRESS" \
  "$SENDER_AMOUNT" \
  "$CONFIRMING_BLOCKS" \
  >/dev/null

echo "running Flutter macOS payment-link round-trip integration test"
fvm flutter test \
  integration_test/regtest_payment_link_round_trip_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_ZCASHD_RPC_URL="$ZCASHD_RPC_URL" \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
