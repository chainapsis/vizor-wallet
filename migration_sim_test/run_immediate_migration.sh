#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="$ROOT_DIR/migration_sim_test"
ARTIFACT_DIR="$SIM_DIR/artifacts"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="$ARTIFACT_DIR/immediate-$RUN_ID.log"
OS_LOG="$ARTIFACT_DIR/immediate-$RUN_ID-rust.log"
DRIVER_LOG="$ROOT_DIR/.ironwood-regtest/migration_sim_immediate_migration_test-driver.log"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p "$ARTIFACT_DIR"

export E2E_TEST_FILE="integration_test/migration_sim_immediate_migration_test.dart"
export E2E_FAST_TESTNET_MIGRATION=true
export E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-99.0002}"
export E2E_ORCHARD_FUNDING_ZATOSHI="${E2E_ORCHARD_FUNDING_ZATOSHI:-9900020000}"
export E2E_ORCHARD_FUNDING_COINBASE_LIMIT="${E2E_ORCHARD_FUNDING_COINBASE_LIMIT:-0}"
export E2E_ORCHARD_FUNDING_NOTE_COUNT="${E2E_ORCHARD_FUNDING_NOTE_COUNT:-20}"
export E2E_ORCHARD_FUNDING_TX_COUNT="${E2E_ORCHARD_FUNDING_TX_COUNT:-4}"
export E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS="${E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS:-3000}"
export E2E_MIGRATION_SIM_REVIEW_HOLD_MS="${E2E_MIGRATION_SIM_REVIEW_HOLD_MS:-5000}"
export E2E_MIGRATION_SIM_HOME_HOLD_MS="${E2E_MIGRATION_SIM_HOME_HOLD_MS:-15000}"
export VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-false}"

cd "$ROOT_DIR"
set +e
scripts/e2e/flutter-macos-ironwood-migration.sh 2>&1 | tee "$RUN_LOG"
status="${PIPESTATUS[0]}"
set -e

if [[ -f "$DRIVER_LOG" ]]; then
  cp "$DRIVER_LOG" "$ARTIFACT_DIR/immediate-$RUN_ID-driver.log"
fi

/usr/bin/log show \
  --style compact \
  --start "$START_TIME" \
  --predicate 'subsystem == "frb_user"' \
  >"$OS_LOG" 2>/dev/null || true

db_path="$(
  sed -n 's/.*migration-sim-immediate wallet_db=\(.*\) account=.*/\1/p' "$RUN_LOG" |
    tail -1
)"
if [[ -n "$db_path" && -f "$db_path" ]]; then
  sqlite3 "$db_path" ".timeout 5000" ".backup '$ARTIFACT_DIR/immediate-$RUN_ID.db'"
  "$SIM_DIR/inspect.sh" "$db_path" \
    >"$ARTIFACT_DIR/immediate-$RUN_ID-state.txt" 2>&1 || true
fi

echo "artifacts: $ARTIFACT_DIR/immediate-$RUN_ID*"
exit "$status"
