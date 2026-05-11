#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
SHIELDED_AMOUNT="1.25"
FAUCET_AMOUNT="${E2E_SLOW_FALLBACK_FAUCET_AMOUNT:-3.0}"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_SLOW_FALLBACK_DRIVER_PORT:-39068}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
DRIVER_LOG="$ROOT_DIR/.regtest/slow-height-fallback-driver.log"

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

addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC")"
unified_address="$(json_field "$addresses_json" unifiedAddress)"

echo "preparing reusable shielded faucet with ${FAUCET_AMOUNT} ZEC"
faucet_zaddr="$(scripts/regtest/prepare-unmined-faucet.sh "$FAUCET_AMOUNT")"

echo "funding shielded address with ${SHIELDED_AMOUNT} ZEC"
REGTEST_UNMINED_FAUCET_ZADDR="$faucet_zaddr" \
  scripts/regtest/fund-wallet-unmined.sh "$unified_address" "$SHIELDED_AMOUNT" >/dev/null
scripts/regtest/mine.sh "$CONFIRMING_BLOCKS" >/dev/null

mkdir -p "$ROOT_DIR/.regtest"
: > "$DRIVER_LOG"

python3 -u scripts/e2e/mempool-receive-history-driver.py \
  --repo-root "$ROOT_DIR" \
  --port "$DRIVER_PORT" \
  --prepared-faucet-zaddr "$faucet_zaddr" \
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

raise SystemExit("Timed out waiting for slow-height fallback driver")
PY

echo "running Flutter macOS slow-height fallback integration test"
set +e
fvm flutter test \
  integration_test/regtest_slow_height_fallback_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
  --dart-define=ZCASH_E2E_UNIFIED_ADDRESS="$unified_address" \
  --dart-define=ZCASH_E2E_FAUCET_ZADDR="$faucet_zaddr"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "slow-height fallback driver log:" >&2
  sed -n '1,220p' "$DRIVER_LOG" >&2 || true
fi

exit "$status"
