#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export E2E_PREPARE_TEST_FILE="integration_test/regtest_payment_link_failure_prepare_test.dart"
export E2E_RESUME_TEST_FILE="integration_test/regtest_payment_link_failure_reorg_resume_test.dart"
export E2E_RESTART_CONFIRMING_BLOCKS="5"
export E2E_LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:19068}"

exec "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-payment-link.sh"
