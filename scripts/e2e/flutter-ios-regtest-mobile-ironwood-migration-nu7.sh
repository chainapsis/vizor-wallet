#!/usr/bin/env bash
# iOS simulator counterpart of flutter-macos-ironwood-migration-nu7.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd xcrun
cd "$ROOT_DIR"
UDID="$(pick_simulator)"

FLUTTER_DEVICE="$UDID" \
VIZOR_FORM_FACTOR=mobile \
E2E_TEST_FILE="${E2E_TEST_FILE:-integration_test/regtest_mobile_ironwood_migration_test.dart}" \
E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-0.0105}" \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-ironwood-migration-nu7.sh"
