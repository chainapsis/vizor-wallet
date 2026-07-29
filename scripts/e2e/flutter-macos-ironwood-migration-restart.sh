#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
ACTIVATION_HEIGHT="${IRONWOOD_ACTIVATION_HEIGHT:-500}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:19067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
VIZOR_FORM_FACTOR="${VIZOR_FORM_FACTOR:-desktop}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39078}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
DRIVER_LOG="$ROOT_DIR/.ironwood-regtest/restart-driver.log"
FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-0.011}"
PREPARE_TEST_FILE="${E2E_PREPARE_TEST_FILE:-integration_test/regtest_ironwood_migration_restart_prepare_test.dart}"
RESUME_TEST_FILE="${E2E_RESUME_TEST_FILE:-integration_test/regtest_ironwood_migration_restart_resume_test.dart}"
MINE_BETWEEN_PHASES="${E2E_MINE_BETWEEN_PHASES:-0}"

json_file_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
print(data[sys.argv[2]])
PY
}

derive_addresses() {
  local output_file="$1"
  local attempt

  for attempt in 1 2 3; do
    (cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC") >"$output_file"
    if python3 - "$output_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
if not data.get("unifiedAddress"):
    raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  return 1
}

run_flutter_phase() {
  local test_file="$1"
  local form_factor_args=()
  if [[ "$VIZOR_FORM_FACTOR" == "mobile" ]]; then
    form_factor_args+=(--dart-define=VIZOR_FORM_FACTOR=mobile)
  fi
  fvm flutter test \
    "$test_file" \
    -d "$FLUTTER_DEVICE" \
    "${form_factor_args[@]}" \
    --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
    --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT" \
    --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
    --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
    --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
}

cd "$ROOT_DIR"
export IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT"

scripts/ironwood-regtest/reset.sh
scripts/ironwood-regtest/up.sh

addresses_file="$ROOT_DIR/.ironwood-regtest/restart-e2e-addresses.json"
derive_addresses "$addresses_file"
unified_address="$(json_file_field "$addresses_file" unifiedAddress)"
scripts/ironwood-regtest/fund-orchard.sh \
  "$unified_address" \
  "$FUNDING_AMOUNT" \
  10 >/dev/null

: >"$DRIVER_LOG"
python3 -u scripts/e2e/ironwood-regtest-driver.py \
  --repo-root "$ROOT_DIR" \
  --port "$DRIVER_PORT" \
  --activation-height "$ACTIVATION_HEIGHT" \
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
for _ in range(100):
    try:
        with urllib.request.urlopen(url, timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit("Timed out waiting for Ironwood E2E driver")
PY

echo "running migration restart preparation phase"
if ! run_flutter_phase "$PREPARE_TEST_FILE"; then
  sed -n '1,320p' "$DRIVER_LOG" >&2 || true
  exit 1
fi

if [[ "$MINE_BETWEEN_PHASES" -gt 0 ]]; then
  echo "mining $MINE_BETWEEN_PHASES block(s) while the app process is stopped"
  scripts/ironwood-regtest/mine.sh "$MINE_BETWEEN_PHASES" >/dev/null
fi

echo "running migration process-restart resume phase"
if ! run_flutter_phase "$RESUME_TEST_FILE"; then
  sed -n '1,320p' "$DRIVER_LOG" >&2 || true
  exit 1
fi
