#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_FILE="${E2E_TEST_FILE:-integration_test/regtest_payment_link_round_trip_test.dart}"

source "$ROOT_DIR/scripts/e2e/lib-payment-link.sh"

cd "$ROOT_DIR"

start_payment_link_regtest

echo "running Gift Card create/open/claim round trip"
run_payment_link_phase "$TEST_FILE"
