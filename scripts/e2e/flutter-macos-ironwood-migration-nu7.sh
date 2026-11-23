#!/usr/bin/env bash
# Runs the Ironwood migration E2E on the Zebra chain, where NU6.3 and NU7 both
# activate while the app runs, so the migration pays the NU7 fee. Orchard is
# funded before NU6.3 by the offline signer in rust/examples/regtest-orchard-funder.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
# The signer pins NU6.3 at 500.
NU63_HEIGHT=500
NU7_HEIGHT="${NU7_REGTEST_NU7_HEIGHT:-520}"
LIGHTWALLETD_URL="http://127.0.0.1:${NU7_REGTEST_LIGHTWALLETD_PORT:-49067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
VIZOR_FORM_FACTOR="${VIZOR_FORM_FACTOR:-desktop}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39078}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
TEST_FILE="${E2E_TEST_FILE:-integration_test/regtest_ironwood_migration_test.dart}"
# 0.0105 ZEC clears the NU7 start gate (1,019,000 zatoshis) but not the
# pre-NU7 one (1,095,000), so the run fails if the gate ignores NU7 fees.
FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-0.0105}"
FUNDING_NOTE_COUNT="${E2E_ORCHARD_FUNDING_NOTE_COUNT:-1}"
FUNDING_CONFIRMATIONS="${E2E_ORCHARD_FUNDING_CONFIRMATIONS:-10}"
FUNDER_DIR="$ROOT_DIR/rust/examples/regtest-orchard-funder"
FUNDER_TARGET="${CARGO_TARGET_DIR:-$FUNDER_DIR/target}"
FUNDER="$FUNDER_TARGET/debug/regtest_orchard_funder"

for cmd in cargo docker fvm python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
cargo build --quiet --locked --manifest-path "$FUNDER_DIR/Cargo.toml" \
  --target-dir "$FUNDER_TARGET" --bin regtest_orchard_funder

export NU7_REGTEST_NU63_HEIGHT="$NU63_HEIGHT" NU7_REGTEST_NU7_HEIGHT="$NU7_HEIGHT"
# Each run owns its node volumes, config and driver.
NU7_REGTEST_RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vizor-nu7-XXXXXXXX")"
export NU7_REGTEST_RUN_DIR
export COMPOSE_PROJECT_NAME="vizor-nu7-migration-$$"
DRIVER_LOG="$NU7_REGTEST_RUN_DIR/driver.log"
driver_pid=
cleanup() {
  if [[ -n "$driver_pid" ]]; then
    kill "$driver_pid" >/dev/null 2>&1 || true
    wait "$driver_pid" >/dev/null 2>&1 || true
  fi
  docker compose -f docker-compose.zcash-nu7-regtest.yml down -v
  rm -rf -- "$NU7_REGTEST_RUN_DIR"
}
trap cleanup EXIT
scripts/nu7-regtest/up.sh

addresses="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- \
  "$MNEMONIC" "$FUNDING_NOTE_COUNT" |
  python3 -c 'import json,sys; print(" ".join(json.load(sys.stdin)["unifiedAddresses"]))')"
funding_zatoshi="$(python3 -c '
from decimal import Decimal
import sys
value = Decimal(sys.argv[1]) * 100_000_000
if value != value.to_integral_value() or value <= 0:
    raise SystemExit("E2E_ORCHARD_FUNDING_AMOUNT must be positive with at most 8 decimals")
print(int(value))' "$FUNDING_AMOUNT")"
# shellcheck disable=SC2086 # one address per word
scripts/nu7-regtest/fund-orchard.py --funder "$FUNDER" \
  --amount-zatoshi "$funding_zatoshi" --confirmations "$FUNDING_CONFIRMATIONS" $addresses

: >"$DRIVER_LOG"
python3 -u scripts/e2e/nu7-regtest-driver.py --repo-root "$ROOT_DIR" --port "$DRIVER_PORT" \
  >"$DRIVER_LOG" 2>&1 &
driver_pid="$!"
python3 - "$DRIVER_URL" <<'PY'
import sys
import time
import urllib.request

for _ in range(100):
    try:
        with urllib.request.urlopen(sys.argv[1] + "/health", timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit("Timed out waiting for the NU7 E2E driver")
PY

echo "running Flutter Ironwood migration integration test under NU7: $TEST_FILE"
flutter_args=("$TEST_FILE" -d "$FLUTTER_DEVICE")
if [[ "$VIZOR_FORM_FACTOR" == "mobile" ]]; then
  flutter_args+=(--dart-define=VIZOR_FORM_FACTOR=mobile)
fi
set +e
fvm flutter test "${flutter_args[@]}" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$NU63_HEIGHT" \
  --dart-define=ZCASH_REGTEST_NU7_ACTIVATION_HEIGHT="$NU7_HEIGHT" \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
  --dart-define=ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI="$funding_zatoshi" \
  --dart-define=ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT="$FUNDING_NOTE_COUNT" \
  --dart-define=ZCASH_E2E_ORCHARD_FUNDING_TX_COUNT=1 \
  --dart-define=ZCASH_FAST_TESTNET_MIGRATION="${E2E_FAST_TESTNET_MIGRATION:-false}" \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
status="$?"
set -e
if [[ "$status" -ne 0 ]]; then
  echo "NU7 E2E driver log:" >&2
  sed -n '1,260p' "$DRIVER_LOG" >&2 || true
fi
exit "$status"
