#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENDER_ADDRESS="uregtest1dwwn6pcjc82hq2yu3nuwe4w4pzhdm04qprtl2n9knk6de6g8dkyraplcnmvztt47mrekzgdfnyrqycppg8l4yvnf2cg2tyxplcs95haxfyg4qt5xv3vly32lnt7m3tz4uznudek464gn795k26v05chgaw8z3fdjc5zxc5vx6yq552zm"
SENDER_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
ZCASHD_RPC_URL="${E2E_ZCASHD_RPC_URL:-http://127.0.0.1:18232}"
DEEPLINK_BASE_URL="${VIZOR_DEEPLINK_BASE_URL:-https://link-dev.vizor.cash}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"
PREPARE_TEST_FILE="${E2E_PREPARE_TEST_FILE:-integration_test/regtest_payment_link_restart_prepare_test.dart}"
RESUME_TEST_FILE="${E2E_RESUME_TEST_FILE:-integration_test/regtest_payment_link_restart_resume_test.dart}"
RESTART_CONFIRMING_BLOCKS="${E2E_RESTART_CONFIRMING_BLOCKS:-6}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd fvm

run_flutter_phase() {
  local test_file="$1"
  fvm flutter test \
    "$test_file" \
    -d "$FLUTTER_DEVICE" \
    --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
    --dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true \
    --dart-define=VIZOR_DEEPLINK_BASE_URL="$DEEPLINK_BASE_URL" \
    --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
    --dart-define=ZCASH_E2E_ZCASHD_RPC_URL="$ZCASHD_RPC_URL" \
    --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
}

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
  # Docker Desktop can observe the bind mount before a freshly recreated
  # hidden worktree directory has propagated through /host_mnt.
  mkdir -p .regtest/lightwalletd .regtest/zcashd
  sleep "${E2E_REGTEST_MOUNT_SETTLE_SECONDS:-2}"
fi
scripts/regtest/up.sh

echo "funding payment-link sender with ${SENDER_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh \
  "$SENDER_ADDRESS" \
  "$SENDER_AMOUNT" \
  "$CONFIRMING_BLOCKS" \
  >/dev/null

echo "running Gift Card multi-claim restart preparation phase"
run_flutter_phase "$PREPARE_TEST_FILE"

echo "mining ${RESTART_CONFIRMING_BLOCKS} blocks while Vizor is stopped"
scripts/regtest/mine.sh "$RESTART_CONFIRMING_BLOCKS" >/dev/null

echo "running Gift Card process-restart recovery phase"
run_flutter_phase "$RESUME_TEST_FILE"
