#!/usr/bin/env bash
# Opt-in, observable desktop migration on the same Zebra stack as the NU7 E2E.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p migration_sim_test/artifacts
run_dir="$(mktemp -d migration_sim_test/artifacts/full-XXXXXXXX)"
echo "Simulation artifacts: $run_dir"

FLUTTER_DEVICE=macos VIZOR_FORM_FACTOR=desktop \
VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-false}" \
E2E_TEST_FILE=integration_test/migration_sim_full_migration_test.dart \
E2E_ORCHARD_FUNDING_AMOUNT=10.0002 E2E_ORCHARD_FUNDING_NOTE_COUNT=20 \
E2E_FAST_TESTNET_MIGRATION=true \
  scripts/e2e/flutter-macos-ironwood-migration-nu7.sh 2>&1 | tee "$run_dir/run.log"
