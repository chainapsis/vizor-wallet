#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SENDER_MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
RECEIVER_MNEMONIC="return try reason flat civil wolf dwarf announce toddler uphold equip range neck proof gauge east rifle swim tray twin venue fossil will version"
SHIELDED_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
ZCASHD_RPC_URL="${E2E_ZCASHD_RPC_URL:-http://127.0.0.1:18232}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39068}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
DRIVER_LOG="$ROOT_DIR/.regtest/tex-send-driver.log"

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

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

sender_addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$SENDER_MNEMONIC")"
receiver_addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$RECEIVER_MNEMONIC")"
sender_unified_address="$(json_field "$sender_addresses_json" unifiedAddress)"
receiver_tex_address="$(json_field "$receiver_addresses_json" texAddress)"

echo "funding sender shielded address with ${SHIELDED_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh "$sender_unified_address" "$SHIELDED_AMOUNT" "$CONFIRMING_BLOCKS" >/dev/null

mkdir -p "$ROOT_DIR/.regtest"
: > "$DRIVER_LOG"
python3 -u scripts/e2e/mempool-receive-history-driver.py \
  --repo-root "$ROOT_DIR" \
  --port "$DRIVER_PORT" \
  >"$DRIVER_LOG" 2>&1 &
driver_pid="$!"
cleanup() {
  kill "$driver_pid" >/dev/null 2>&1 || true
  wait "$driver_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

python3 - "$DRIVER_URL" <<'PY'
import sys
import time
import urllib.request

url = sys.argv[1] + "/health"
for _ in range(50):
    try:
        with urllib.request.urlopen(url, timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)

raise SystemExit("Timed out waiting for TEX send E2E driver")
PY

echo "running Flutter macOS TEX send integration test"
# Returned-funds checks are otherwise randomized over a day.
ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW=1 \
fvm flutter test \
  integration_test/regtest_tex_send_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_ZCASHD_RPC_URL="$ZCASHD_RPC_URL" \
  --dart-define=ZCASH_E2E_TEX_ADDRESS="$receiver_tex_address" \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
