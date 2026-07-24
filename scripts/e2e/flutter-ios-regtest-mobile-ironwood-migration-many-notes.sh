#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3
require_cmd xcrun

cd "$ROOT_DIR"
UDID="$(pick_simulator)"

FLUTTER_DEVICE="$UDID" \
VIZOR_FORM_FACTOR=mobile \
E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39086}" \
E2E_TEST_FILE=integration_test/regtest_mobile_ironwood_migration_many_notes_test.dart \
E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-10.0002}" \
E2E_ORCHARD_FUNDING_ZATOSHI="${E2E_ORCHARD_FUNDING_ZATOSHI:-1000020000}" \
E2E_ORCHARD_FUNDING_NOTE_COUNT="${E2E_ORCHARD_FUNDING_NOTE_COUNT:-20}" \
E2E_ORCHARD_FUNDING_COINBASE_LIMIT="${E2E_ORCHARD_FUNDING_COINBASE_LIMIT:-0}" \
E2E_EXPECTED_SPLIT_STAGE_COUNT="${E2E_EXPECTED_SPLIT_STAGE_COUNT:-2}" \
E2E_EXPECTED_MIGRATION_BATCH_COUNT="${E2E_EXPECTED_MIGRATION_BATCH_COUNT:-9}" \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-ironwood-migration.sh"
