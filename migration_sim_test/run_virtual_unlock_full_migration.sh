#!/usr/bin/env bash
set -euo pipefail

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export E2E_TEST_FILE="integration_test/migration_sim_virtual_unlock_full_migration_test.dart"
export E2E_MIGRATION_SIM_ARTIFACT_PREFIX="virtual-unlock-full"
export E2E_IRONWOOD_MIGRATION_PRIVACY_LOCK=true
export VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"

exec "$SIM_DIR/run_full_migration.sh"
