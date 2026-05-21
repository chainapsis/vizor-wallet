#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39069}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
DRIVER_LOG="$ROOT_DIR/.regtest/shield-transparent-retry-driver.log"

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

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

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

raise SystemExit("Timed out waiting for shield transparent retry E2E driver")
PY

echo "running Flutter macOS shield-transparent retry integration test"
set +e
fvm flutter test \
  integration_test/regtest_shield_transparent_retry_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "shield transparent retry driver log:" >&2
  sed -n '1,220p' "$DRIVER_LOG" >&2 || true
fi

exit "$status"
