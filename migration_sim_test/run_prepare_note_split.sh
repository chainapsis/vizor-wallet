#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM_DIR="$ROOT_DIR/migration_sim_test"
ARTIFACT_DIR="$SIM_DIR/artifacts"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="$ARTIFACT_DIR/prepare-$RUN_ID.log"
OS_LOG="$ARTIFACT_DIR/prepare-$RUN_ID-rust.log"
DRIVER_LOG="$ROOT_DIR/.ironwood-regtest/migration_sim_prepare_note_split_test-driver.log"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

mkdir -p "$ARTIFACT_DIR"

export E2E_TEST_FILE="integration_test/migration_sim_prepare_note_split_test.dart"
export E2E_FAST_TESTNET_MIGRATION=true
export E2E_ORCHARD_FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-12.82182}"
export E2E_ORCHARD_FUNDING_ZATOSHI="${E2E_ORCHARD_FUNDING_ZATOSHI:-1282182000}"
export E2E_ORCHARD_FUNDING_COINBASE_LIMIT="${E2E_ORCHARD_FUNDING_COINBASE_LIMIT:-0}"
export E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS="${E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS:-6000}"
export E2E_MIGRATION_SIM_MAX_BLOCKS="${E2E_MIGRATION_SIM_MAX_BLOCKS:-40}"
export VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"

cd "$ROOT_DIR"
set +e
scripts/e2e/flutter-macos-ironwood-migration.sh 2>&1 | tee "$RUN_LOG"
status="${PIPESTATUS[0]}"
set -e

if [[ -f "$DRIVER_LOG" ]]; then
  cp "$DRIVER_LOG" "$ARTIFACT_DIR/prepare-$RUN_ID-driver.log"
fi

/usr/bin/log show \
  --style compact \
  --start "$START_TIME" \
  --predicate 'subsystem == "frb_user"' \
  >"$OS_LOG" 2>/dev/null || true

db_path="$(
  sed -n 's/.*migration-sim wallet_db=\(.*\) account=.*/\1/p' "$RUN_LOG" |
    tail -1
)"
if [[ -n "$db_path" && -f "$db_path" ]]; then
  sqlite3 "$db_path" ".timeout 5000" ".backup '$ARTIFACT_DIR/prepare-$RUN_ID.db'"
  "$SIM_DIR/inspect.sh" "$db_path" \
    >"$ARTIFACT_DIR/prepare-$RUN_ID-state.txt" 2>&1 || true
fi

echo "artifacts: $ARTIFACT_DIR/prepare-$RUN_ID*"
exit "$status"
