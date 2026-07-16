#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"
export E2E_TEST_FILE="integration_test/regtest_ironwood_migration_mixed_notes_test.dart"
export E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39083}"
export E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-10.0002}"
export E2E_ORCHARD_FUNDING_NOTE_COUNT="${E2E_ORCHARD_FUNDING_NOTE_COUNT:-20}"
export E2E_ORCHARD_FUNDING_TX_COUNT="${E2E_ORCHARD_FUNDING_TX_COUNT:-4}"
export E2E_ORCHARD_FUNDING_COINBASE_LIMIT="${E2E_ORCHARD_FUNDING_COINBASE_LIMIT:-1}"
exec scripts/e2e/flutter-macos-ironwood-migration.sh
