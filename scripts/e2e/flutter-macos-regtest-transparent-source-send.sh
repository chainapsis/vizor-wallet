#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECEIVER_MNEMONIC="return try reason flat civil wolf dwarf announce toddler uphold equip range neck proof gauge east rifle swim tray twin venue fossil will version"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39068}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
DRIVER_LOG="$ROOT_DIR/.regtest/transparent-source-send-driver.log"

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

addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$RECEIVER_MNEMONIC")"
receiver_unified_address="$(json_field "$addresses_json" unifiedAddress)"

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

raise SystemExit("Timed out waiting for transparent-source send E2E driver")
PY

echo "running Flutter macOS transparent-source send integration test"
set +e
fvm flutter test \
  integration_test/regtest_transparent_source_send_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
  --dart-define=ZCASH_E2E_TRANSPARENT_SOURCE_RECIPIENT="$receiver_unified_address"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "transparent-source send driver log:" >&2
  sed -n '1,220p' "$DRIVER_LOG" >&2 || true
fi

exit "$status"
