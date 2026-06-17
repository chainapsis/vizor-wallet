#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
SHIELDED_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39067}"
DRIVER_LOG="$ROOT_DIR/.regtest/mobile-mempool-receive-driver.log"

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

start_e2e_driver "$DRIVER_PORT" "$DRIVER_LOG"
cleanup() {
  kill "$DRIVER_PID" >/dev/null 2>&1 || true
  wait "$DRIVER_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

UDID="$(pick_simulator)"
set +e
run_mobile_e2e integration_test/regtest_mobile_mempool_receive_test.dart "$UDID" \
  --dart-define=ZCASH_E2E_DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "driver log:" >&2
  sed -n '1,220p' "$DRIVER_LOG" >&2 || true
fi

exit "$status"
