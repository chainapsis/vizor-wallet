#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"
export E2E_TEST_FILE="integration_test/regtest_ironwood_migration_multi_account_test.dart"
export E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39079}"
export E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-0.011}"
exec scripts/e2e/flutter-macos-ironwood-migration.sh
