#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# A 50-card group loses its accepted broadcast response, the app stops, and a
# new process must restore the same group. The lost response is injected by
# the in-test proxy on 19068, so the app must talk to lightwalletd through it.
export E2E_PREPARE_TEST_FILE="integration_test/regtest_payment_link_batch_restart_prepare_test.dart"
export E2E_RESUME_TEST_FILE="integration_test/regtest_payment_link_batch_restart_resume_test.dart"
export E2E_RESTART_CONFIRMING_BLOCKS="6"
export E2E_LIGHTWALLETD_URL="http://127.0.0.1:19068"
export E2E_ZCASHD_RPC_URL="http://127.0.0.1:18232"

exec "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-payment-link.sh"
