#!/usr/bin/env bash
set -euo pipefail

# Desktop E2E on the NU7 regtest stack: a Private migration started before NU7
# is held, stopped by the upgrade, and its remainder moved by a new run.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
NU63_HEIGHT="${NU7_REGTEST_NU63_HEIGHT:-300}"
NU7_HEIGHT="${NU7_REGTEST_NU7_HEIGHT:-600}"
# The app starts this far before NU7 so preparation ends before the hold window.
APP_START_BEFORE_NU7="${E2E_APP_START_BEFORE_NU7:-100}"
LIGHTWALLETD_URL="http://127.0.0.1:${NU7_REGTEST_LIGHTWALLETD_PORT:-49067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
VIZOR_FORM_FACTOR="${VIZOR_FORM_FACTOR:-desktop}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39080}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
TEST_FILE="${E2E_TEST_FILE:-integration_test/regtest_nu7_migration_stop_test.dart}"
DRIVER_LOG="$ROOT_DIR/.nu7-regtest/e2e-driver.log"

# The app starts once Ironwood is active, so NU7 must leave room after NU6.3.
if [[ "$((NU7_HEIGHT - APP_START_BEFORE_NU7))" -le "$NU63_HEIGHT" ]]; then
  echo "NU7_REGTEST_NU7_HEIGHT must be more than E2E_APP_START_BEFORE_NU7 ($APP_START_BEFORE_NU7) blocks after NU7_REGTEST_NU63_HEIGHT" >&2
  exit 1
fi
for command in cargo docker fvm python3 grpcurl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "missing required command: $command" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
export NU7_REGTEST_NU63_HEIGHT="$NU63_HEIGHT" NU7_REGTEST_NU7_HEIGHT="$NU7_HEIGHT"
scripts/nu7-regtest/reset.sh
scripts/nu7-regtest/up.sh

address="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC" 1 |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["unifiedAddress"])')"
# Orchard coinbase before NU6.3, matured, then the chain waits before NU7.
scripts/nu7-regtest/fund.sh "$address" 2 >/dev/null
scripts/nu7-regtest/mine.sh 110 >/dev/null
tip="$(scripts/nu7-regtest/rpc.sh getblockcount)"
start_height=$((NU7_HEIGHT - APP_START_BEFORE_NU7))
if [[ "$tip" -lt "$start_height" ]]; then
  scripts/nu7-regtest/mine.sh $((start_height - tip)) >/dev/null
fi

: >"$DRIVER_LOG"
python3 -u scripts/e2e/nu7-regtest-driver.py --repo-root "$ROOT_DIR" --port "$DRIVER_PORT" \
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

for _ in range(100):
    try:
        with urllib.request.urlopen(sys.argv[1] + "/health", timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit("Timed out waiting for the NU7 E2E driver")
PY

echo "running Flutter NU7 migration stop integration test: $TEST_FILE"
flutter_args=("$TEST_FILE" -d "$FLUTTER_DEVICE")
if [[ "$VIZOR_FORM_FACTOR" == "mobile" ]]; then
  # The mobile test is tagged out of the default (desktop) lane.
  flutter_args+=(--tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile)
fi
set +e
fvm flutter test "${flutter_args[@]}" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$NU63_HEIGHT" \
  --dart-define=ZCASH_REGTEST_NU7_ACTIVATION_HEIGHT="$NU7_HEIGHT" \
  --dart-define=ZCASH_FAST_TESTNET_MIGRATION=true \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
  --dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "NU7 E2E driver log:" >&2
  sed -n '1,200p' "$DRIVER_LOG" >&2 || true
fi
exit "$status"
