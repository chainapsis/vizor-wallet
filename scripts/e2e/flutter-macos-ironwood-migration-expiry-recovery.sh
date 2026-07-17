#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$ROOT_DIR"

E2E_ORCHARD_FUNDING_AMOUNT=0.011 \
E2E_TEST_FILE=integration_test/regtest_ironwood_migration_expiry_recovery_test.dart \
  scripts/e2e/flutter-macos-ironwood-migration.sh
