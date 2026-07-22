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
E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39093}" \
E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-1.23}" \
E2E_PREPARE_TEST_FILE=integration_test/regtest_mobile_ironwood_background_restart_prepare_test.dart \
E2E_RESUME_TEST_FILE=integration_test/regtest_mobile_ironwood_background_restart_resume_test.dart \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-ironwood-migration-restart.sh"
