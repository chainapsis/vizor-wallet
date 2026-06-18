#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.keplr.vizor}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

read_install_sentinel() {
  /usr/libexec/PlistBuddy -c 'Print :vizor_install_sentinel_v1' "$1" \
    2>/dev/null || true
}

install_sentinel_is_true() {
  local value
  value="$(read_install_sentinel "$1")"
  [[ "$value" == "true" || "$value" == "1" ]]
}

require_cmd fvm
require_cmd xcrun

cd "$ROOT_DIR"

UDID="$(pick_simulator)"
LEGACY_LOG_DIR="$ROOT_DIR/.regtest-logs"
CREATE_LOG="$LEGACY_LOG_DIR/mainnet-create-wallet-state.log"
LEGACY_LOG="$LEGACY_LOG_DIR/mainnet-legacy-launch.log"

echo "resetting simulator keychain and app state on ${UDID}"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl keychain "$UDID" reset

mkdir -p "$LEGACY_LOG_DIR"
: > "$CREATE_LOG"
run_mobile_mainnet_e2e \
  integration_test/mainnet_mobile_create_wallet_state_test.dart \
  "$UDID" \
  --dart-define=ZCASH_E2E_HOLD_AFTER_CREATE=true \
  >"$CREATE_LOG" 2>&1 &
CREATE_PID="$!"

create_ok=0
for _ in {1..300}; do
  if grep -q "mainnet wallet state created with DB" "$CREATE_LOG"; then
    create_ok=1
    break
  fi
  if ! kill -0 "$CREATE_PID" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if [[ "$create_ok" != "1" ]]; then
  echo "mainnet wallet state setup did not complete; log follows:" >&2
  cat "$CREATE_LOG" >&2
  exit 1
fi

kill "$CREATE_PID" >/dev/null 2>&1 || true
wait "$CREATE_PID" >/dev/null 2>&1 || true

echo "removing install sentinel while preserving app data and keychain"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
data_container="$(xcrun simctl get_app_container "$UDID" "$APP_BUNDLE_ID" data)"
sentinel_plist="$data_container/Library/Preferences/${APP_BUNDLE_ID}.plist"
/usr/libexec/PlistBuddy -c 'Delete :vizor_install_sentinel_v1' \
  "$sentinel_plist" >/dev/null 2>&1 || true
if [[ -n "$(read_install_sentinel "$sentinel_plist")" ]]; then
  echo "failed to remove install sentinel from ${APP_BUNDLE_ID}" >&2
  exit 1
fi

wallet_db_count="$(find "$data_container/Library/Application Support" \
  -maxdepth 1 -name 'zcash_wallet_*.db' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$wallet_db_count" == "0" ]]; then
  echo "expected an existing wallet DB before legacy launch" >&2
  exit 1
fi

echo "launching app to verify legacy data is preserved"
: > "$LEGACY_LOG"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch --console "$UDID" "$APP_BUNDLE_ID" \
  >"$LEGACY_LOG" 2>&1 &
LAUNCH_PID="$!"

legacy_ok=0
for _ in {1..30}; do
  if grep -q "fresh install: cleared stale iOS keychain values" "$LEGACY_LOG"; then
    break
  fi
  if install_sentinel_is_true "$sentinel_plist"; then
    legacy_ok=1
    break
  fi
  sleep 1
done

kill "$LAUNCH_PID" >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true

if [[ "$legacy_ok" != "1" ]]; then
  echo "legacy launch did not preserve wallet state; log follows:" >&2
  cat "$LEGACY_LOG" >&2
  exit 1
fi

if grep -q "fresh install: cleared stale iOS keychain values" "$LEGACY_LOG"; then
  echo "legacy launch unexpectedly cleared keychain values; log follows:" >&2
  cat "$LEGACY_LOG" >&2
  exit 1
fi

sentinel_value="$(read_install_sentinel "$sentinel_plist")"
if [[ "$sentinel_value" != "true" && "$sentinel_value" != "1" ]]; then
  echo "expected legacy launch to restore install sentinel, got: ${sentinel_value}" >&2
  exit 1
fi

echo "uninstalling ${APP_BUNDLE_ID} without resetting keychain"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID"

run_mobile_mainnet_e2e \
  integration_test/mainnet_mobile_fresh_install_keychain_cleanup_test.dart \
  "$UDID"

echo "mainnet iOS keychain cleanup E2E passed"
