#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/ironwood-regtest/large-value-env.sh"

CHECKPOINT_NAME="${E2E_LARGE_VALUE_CHECKPOINT:-custom-migration-50001-zec}"
CHECKPOINT_PATH="$IRONWOOD_SNAPSHOT_DIR/$CHECKPOINT_NAME.tar.gz"
if [[ ! -f "$CHECKPOINT_PATH" ]]; then
  "$ROOT_DIR/scripts/ironwood-regtest/prepare-large-value-checkpoint.sh" \
    "${E2E_LARGE_VALUE_FUNDING_AMOUNT:-50001.0002}" \
    "$CHECKPOINT_NAME"
fi

cd "$ROOT_DIR"
export E2E_TEST_FILE="integration_test/regtest_ironwood_custom_migration_live_test.dart"
export E2E_IRONWOOD_CHECKPOINT="$CHECKPOINT_NAME"
export E2E_ORCHARD_FUNDING_ZATOSHI="${E2E_ORCHARD_FUNDING_ZATOSHI:-5000100020000}"
export E2E_ORCHARD_FUNDING_NOTE_COUNT=1
export E2E_ORCHARD_FUNDING_TX_COUNT=1
export E2E_FAST_TESTNET_MIGRATION=false
export E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS="${E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS:-3600000}"
export E2E_CUSTOM_MIGRATION_PACE_MS="${E2E_CUSTOM_MIGRATION_PACE_MS:-1500}"
export E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS="${E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS:-300000}"
export E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true
export VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-false}"
exec scripts/e2e/flutter-macos-ironwood-migration.sh
