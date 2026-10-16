#!/usr/bin/env bash
# Shared helpers for the mobile (iOS simulator) E2E runners that run against
# public networks; the regtest runners run through zakura-run.py.

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
