#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39067}"
DRIVER_LOG="$ROOT_DIR/.ironwood-regtest/mobile-gift-onboarding-driver.log"
DEEPLINK_BASE_URL="${VIZOR_DEEPLINK_BASE_URL:-https://link-dev.vizor.cash}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"
source "$ROOT_DIR/scripts/ironwood-regtest/lib.sh"

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3
require_cmd xcrun
cd "$ROOT_DIR"
UDID="$(pick_simulator)"
export IRONWOOD_ACTIVATION_HEIGHT
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:${LIGHTWALLETD_PORT}}"
ZCASHD_RPC_URL="${E2E_ZCASHD_RPC_URL:-http://127.0.0.1:${IRONWOOD_ZCASHD_RPC_PORT:-19232}}"
FUNDER_DB="$ROOT_DIR/.ironwood-regtest/gift-funder.db"
(cd rust && cargo build --quiet --example regtest_gift_funder)
FUNDER_BINARY="$(cd rust && cargo metadata --no-deps --format-version 1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["target_directory"] + "/debug/examples/regtest_gift_funder")')"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/ironwood-regtest/reset.sh
  scripts/ironwood-regtest/up.sh
  "$FUNDER_BINARY" prepare "$FUNDER_DB" >"$ROOT_DIR/.ironwood-regtest/gift-funder-addresses.json"
  funder_addresses="$(python3 - "$ROOT_DIR/.ironwood-regtest/gift-funder-addresses.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    print(json.dumps(json.load(source)["addresses"]))
PY
)"
  # Three independent 0.5 ZEC notes, funded before NU6.3. The Rust faucet
  # delivers each Gift through Ironwood after activation, like the app does.
  scripts/ironwood-regtest/fund-orchard.sh "$funder_addresses" 1.5 10 1 3
  scripts/ironwood-regtest/activate-ironwood.sh
else
  pin_activation_height
  [[ -f "$FUNDER_DB" ]] || { echo "Gift funder missing; run with RESET_REGTEST=1" >&2; exit 1; }
  scripts/ironwood-regtest/status.sh >/dev/null
fi

cleanup() {
  if [[ -n "${DRIVER_PID:-}" ]]; then
    kill "$DRIVER_PID" >/dev/null 2>&1 || true
    wait "$DRIVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
python3 -u scripts/e2e/ironwood-regtest-driver.py \
  --repo-root "$ROOT_DIR" --port "$DRIVER_PORT" \
  --activation-height "$IRONWOOD_ACTIVATION_HEIGHT" \
  --gift-funder-db "$FUNDER_DB" --gift-funder-binary "$FUNDER_BINARY" \
  --lightwalletd-url "$LIGHTWALLETD_URL" >"$DRIVER_LOG" 2>&1 &
DRIVER_PID="$!"
python3 - "http://127.0.0.1:${DRIVER_PORT}/health" <<'PY'
import sys
import time
import urllib.request
for _ in range(50):
    try:
        with urllib.request.urlopen(sys.argv[1], timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit("Timed out waiting for Gift E2E driver")
PY

E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" run_mobile_e2e integration_test/regtest_mobile_gift_onboarding_test.dart "$UDID" \
  --tags mobile --run-skipped \
  --dart-define=ZCASH_E2E_DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}" \
  --dart-define=ZCASH_E2E_ZCASHD_RPC_URL="$ZCASHD_RPC_URL" \
  --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$IRONWOOD_ACTIVATION_HEIGHT" \
  --dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true \
  --dart-define=VIZOR_DEEPLINK_BASE_URL="$DEEPLINK_BASE_URL"
