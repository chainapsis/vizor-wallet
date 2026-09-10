#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREPARE_TEST_FILE="${E2E_PREPARE_TEST_FILE:-integration_test/regtest_payment_link_restart_prepare_test.dart}"
RESUME_TEST_FILE="${E2E_RESUME_TEST_FILE:-integration_test/regtest_payment_link_restart_resume_test.dart}"
RESTART_CONFIRMING_BLOCKS="${E2E_RESTART_CONFIRMING_BLOCKS:-6}"

source "$ROOT_DIR/scripts/e2e/lib-payment-link.sh"

cd "$ROOT_DIR"

start_payment_link_regtest

echo "running Gift Card multi-claim restart preparation phase"
run_payment_link_phase "$PREPARE_TEST_FILE"

echo "mining ${RESTART_CONFIRMING_BLOCKS} blocks while Vizor is stopped"
scripts/regtest/mine.sh "$RESTART_CONFIRMING_BLOCKS" >/dev/null

echo "running Gift Card process-restart recovery phase"
run_payment_link_phase "$RESUME_TEST_FILE"
