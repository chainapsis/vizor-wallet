#!/usr/bin/env bash
# Shared helpers for the mobile (iOS simulator) regtest E2E runners.
# Source this from scripts/e2e/flutter-ios-regtest-*.sh.

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

# Picks the target simulator: $SIMULATOR_UDID wins; otherwise the single
# booted simulator. Refuses ambiguity (clear-app.sh once wiped the wrong
# device when several sims were booted).
pick_simulator() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    echo "$SIMULATOR_UDID"
    return
  fi
  local booted
  booted="$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' || true)"
  local count
  count="$(echo "$booted" | grep -c . || true)"
  if [[ "$count" -eq 0 ]]; then
    echo "no booted iOS simulator; boot one or set SIMULATOR_UDID" >&2
    exit 1
  fi
  if [[ "$count" -gt 1 ]]; then
    echo "multiple booted simulators; set SIMULATOR_UDID explicitly" >&2
    exit 1
  fi
  echo "$booted"
}

# Runs one mobile integration test file against the regtest stack.
# The simulator shares the host loopback, so 127.0.0.1 URLs work as-is.
# Extra --dart-define flags can be passed as additional arguments.
# E2E_SKIP_LWD_OVERRIDE=1 omits the lightwalletd override define — the
# endpoint-failover tests manage endpoints via the in-test proxy preset
# and the bootstrap override would clobber it.
run_mobile_e2e() {
  local test_file="$1"
  local udid="$2"
  shift 2
  local lightwalletd_url="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"

  local defines=(
    --dart-define=VIZOR_FORM_FACTOR=mobile
    --dart-define=ZCASH_DEFAULT_NETWORK=regtest
  )
  if [[ "${E2E_SKIP_LWD_OVERRIDE:-0}" != "1" ]]; then
    defines+=(--dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$lightwalletd_url")
  fi

  echo "running mobile regtest E2E ${test_file} on ${udid}"
  fvm flutter test \
    "$test_file" \
    -d "$udid" \
    "${defines[@]}" \
    "$@"
}

# Runs one mobile integration test file against the public mainnet endpoint.
# Extra --dart-define flags can be passed as additional arguments.
run_mobile_mainnet_e2e() {
  local test_file="$1"
  local udid="$2"
  shift 2

  echo "running mobile mainnet E2E ${test_file} on ${udid}"
  fvm flutter test \
    "$test_file" \
    -d "$udid" \
    --dart-define=VIZOR_FORM_FACTOR=mobile \
    --dart-define=ZCASH_DEFAULT_NETWORK=main \
    --dart-define=ZCASH_E2E_NETWORK=mainnet \
    "$@"
}

# Starts the python E2E driver on $1 (port), logging to $2. Sets
# DRIVER_PID; callers must trap and kill it. Extra args pass through to
# the driver (e.g. --prepared-faucet-zaddr).
start_e2e_driver() {
  local port="$1"
  local log_file="$2"
  shift 2

  mkdir -p "$(dirname "$log_file")"
  : > "$log_file"
  python3 -u scripts/e2e/mempool-receive-history-driver.py \
    --repo-root "$PWD" \
    --port "$port" \
    "$@" \
    >"$log_file" 2>&1 &
  DRIVER_PID="$!"

  python3 - "http://127.0.0.1:${port}" <<'PY'
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

raise SystemExit("Timed out waiting for E2E driver")
PY
}
