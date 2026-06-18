#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.keplr.vizor}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd fvm
require_cmd xcrun

cd "$ROOT_DIR"

UDID="$(pick_simulator)"

echo "resetting simulator keychain and app state on ${UDID}"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl keychain "$UDID" reset

run_mobile_mainnet_e2e \
  integration_test/mainnet_mobile_create_wallet_state_test.dart \
  "$UDID"

echo "uninstalling ${APP_BUNDLE_ID} without resetting keychain"
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$APP_BUNDLE_ID"

run_mobile_mainnet_e2e \
  integration_test/mainnet_mobile_fresh_install_keychain_cleanup_test.dart \
  "$UDID"

echo "mainnet iOS fresh-install keychain cleanup E2E passed"
