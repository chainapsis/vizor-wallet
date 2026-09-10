#!/usr/bin/env bash
# Shared helpers for the macOS Gift Card (payment-link) regtest E2E runners.
# Source this from scripts/e2e/flutter-macos-regtest-payment-link*.sh.

PAYMENT_LINK_MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
PAYMENT_LINK_SENDER_AMOUNT="1.25"
PAYMENT_LINK_CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
PAYMENT_LINK_LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
PAYMENT_LINK_ZCASHD_RPC_URL="${E2E_ZCASHD_RPC_URL:-http://127.0.0.1:18232}"
PAYMENT_LINK_DEEPLINK_BASE_URL="${VIZOR_DEEPLINK_BASE_URL:-https://link-dev.vizor.cash}"
PAYMENT_LINK_FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
print(data[sys.argv[2]])
PY
}

# Starts the regtest stack and funds the sender account the Gift Card suites
# import, deriving its address from the mnemonic the tests themselves use.
start_payment_link_regtest() {
  require_cmd cargo
  require_cmd docker
  require_cmd fvm
  require_cmd python3

  if [[ "${RESET_REGTEST:-1}" == "1" ]]; then
    scripts/regtest/reset.sh
    # Docker Desktop can observe the bind mount before a freshly recreated
    # hidden worktree directory has propagated through /host_mnt.
    mkdir -p .regtest/lightwalletd .regtest/zcashd
    sleep "${E2E_REGTEST_MOUNT_SETTLE_SECONDS:-2}"
  fi
  scripts/regtest/up.sh

  local addresses_json
  addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$PAYMENT_LINK_MNEMONIC")"
  local unified_address
  unified_address="$(json_field "$addresses_json" unifiedAddress)"

  echo "funding payment-link sender with ${PAYMENT_LINK_SENDER_AMOUNT} TAZ"
  scripts/regtest/fund-wallet.sh \
    "$unified_address" \
    "$PAYMENT_LINK_SENDER_AMOUNT" \
    "$PAYMENT_LINK_CONFIRMING_BLOCKS" \
    >/dev/null
}

# Runs one Gift Card integration test file. Payment links stay gated off
# without VIZOR_PAYMENT_LINK_REGTEST_ENABLED, so every phase needs it.
run_payment_link_phase() {
  local test_file="$1"
  fvm flutter test \
    "$test_file" \
    -d "$PAYMENT_LINK_FLUTTER_DEVICE" \
    --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
    --dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true \
    --dart-define=VIZOR_DEEPLINK_BASE_URL="$PAYMENT_LINK_DEEPLINK_BASE_URL" \
    --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$PAYMENT_LINK_LIGHTWALLETD_URL" \
    --dart-define=ZCASH_E2E_ZCASHD_RPC_URL="$PAYMENT_LINK_ZCASHD_RPC_URL" \
    --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
}
