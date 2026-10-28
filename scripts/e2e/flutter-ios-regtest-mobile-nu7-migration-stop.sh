#!/usr/bin/env bash
set -euo pipefail

# iOS simulator counterpart of flutter-macos-nu7-migration-stop.sh: the same
# NU7 regtest stack and driver, with the mobile migration screens.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd xcrun

cd "$ROOT_DIR"
UDID="$(pick_simulator)"

FLUTTER_DEVICE="$UDID" \
VIZOR_FORM_FACTOR=mobile \
E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39086}" \
E2E_TEST_FILE="${E2E_TEST_FILE:-integration_test/regtest_mobile_nu7_migration_stop_test.dart}" \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-nu7-migration-stop.sh"
