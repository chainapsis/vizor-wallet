#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
SHIELDED_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
RESET_REGTEST="${RESET_REGTEST:-1}"
SHOT_PORT="${E2E_SCREENSHOT_PORT:-39070}"
SHOT_DIR="${E2E_SCREENSHOT_DIR:-$ROOT_DIR/.regtest-logs/send-screens}"
SHOT_LOG="$ROOT_DIR/.regtest-logs/send-screenshot-driver.log"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

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
require_cmd xcrun

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC")"
unified_address="$(json_field "$addresses_json" unifiedAddress)"

echo "funding shielded address with ${SHIELDED_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh "$unified_address" "$SHIELDED_AMOUNT" "$CONFIRMING_BLOCKS" >/dev/null

UDID="$(pick_simulator)"

mkdir -p "$(dirname "$SHOT_LOG")" "$SHOT_DIR"
: > "$SHOT_LOG"
python3 -u scripts/e2e/screenshot-driver.py \
  --udid "$UDID" \
  --out-dir "$SHOT_DIR" \
  --port "$SHOT_PORT" \
  >"$SHOT_LOG" 2>&1 &
DRIVER_PID="$!"
cleanup() {
  kill "$DRIVER_PID" >/dev/null 2>&1 || true
  wait "$DRIVER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

python3 - "http://127.0.0.1:${SHOT_PORT}" <<'PY'
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

raise SystemExit("Timed out waiting for screenshot driver")
PY

run_mobile_e2e integration_test/regtest_mobile_send_screenshot_test.dart "$UDID" \
  --dart-define=ZCASH_E2E_SCREENSHOT_DRIVER_URL="http://127.0.0.1:${SHOT_PORT}"

echo "send screens captured under $SHOT_DIR"
