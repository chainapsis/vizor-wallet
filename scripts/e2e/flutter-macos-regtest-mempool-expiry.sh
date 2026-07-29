#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39069}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
DRIVER_LOG="$ROOT_DIR/.regtest/mempool-expiry-driver.log"
BASE_COMPOSE="$ROOT_DIR/docker-compose.zcash-regtest.yml"
EXPIRY_COMPOSE="$ROOT_DIR/docker-compose.zcash-regtest-expiry.yml"
driver_pid=""
expiry_stack_started=0

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd fvm
require_cmd python3

cd "$ROOT_DIR"

cleanup() {
  if [[ -n "$driver_pid" ]]; then
    kill "$driver_pid" >/dev/null 2>&1 || true
    wait "$driver_pid" >/dev/null 2>&1 || true
  fi

  if [[ "$expiry_stack_started" == "1" && "${RESTORE_REGTEST_CONFIG:-1}" == "1" ]]; then
    echo "restoring regtest stack with default mining config"
    docker compose -f "$BASE_COMPOSE" up -d --force-recreate zcashd lightwalletd >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

echo "preparing shielded faucet for expiring unmined external funding"
PREPARED_FAUCET_ZADDR="$(scripts/regtest/prepare-unmined-faucet.sh 0.35)"

echo "restarting regtest stack with expiry mining config"
docker compose -f "$BASE_COMPOSE" -f "$EXPIRY_COMPOSE" up -d --force-recreate zcashd lightwalletd
expiry_stack_started=1
source scripts/regtest/lib.sh
wait_for_zcashd
wait_for_lightwalletd
wait_for_lightwalletd_tip "$(zcash_cli getblockcount)"

mkdir -p "$ROOT_DIR/.regtest"
: > "$DRIVER_LOG"

python3 -u scripts/e2e/mempool-receive-history-driver.py \
  --repo-root "$ROOT_DIR" \
  --port "$DRIVER_PORT" \
  --prepared-faucet-zaddr "$PREPARED_FAUCET_ZADDR" \
  >"$DRIVER_LOG" 2>&1 &
driver_pid="$!"

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

raise SystemExit("Timed out waiting for mempool expiry driver")
PY

echo "running Flutter macOS mempool expiry integration test"
set +e
fvm flutter test \
  integration_test/regtest_mempool_receive_history_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL" \
  --dart-define=ZCASH_E2E_MEMPOOL_TEST_MODE=expiry \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "mempool expiry driver log:" >&2
  sed -n '1,260p' "$DRIVER_LOG" >&2 || true
fi

exit "$status"
