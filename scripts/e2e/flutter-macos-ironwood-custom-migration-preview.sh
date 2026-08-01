#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"
export E2E_TEST_FILE="integration_test/regtest_ironwood_custom_migration_preview_test.dart"
export E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39084}"
export E2E_FAKE_MIGRATION_BALANCE_ZEC="${E2E_FAKE_MIGRATION_BALANCE_ZEC:-1000000}"
export E2E_CUSTOM_MIGRATION_PREVIEW_HOLD_MS="${E2E_CUSTOM_MIGRATION_PREVIEW_HOLD_MS:-900000}"
export VIZOR_E2E_HIDDEN_WINDOW=false
exec scripts/e2e/flutter-macos-ironwood-migration.sh
