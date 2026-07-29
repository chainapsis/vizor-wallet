#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"
export E2E_TEST_FILE="integration_test/regtest_ironwood_migration_large_balance_test.dart"
export E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39081}"
export E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-99.0002}"
export E2E_ORCHARD_PREFUND_BLOCKS="${E2E_ORCHARD_PREFUND_BLOCKS:-20}"
export E2E_ORCHARD_FUNDING_COINBASE_LIMIT="${E2E_ORCHARD_FUNDING_COINBASE_LIMIT:-0}"
exec scripts/e2e/flutter-macos-ironwood-migration.sh
