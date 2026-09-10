#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/e2e/lib-payment-link.sh"
cd "$ROOT_DIR"

# All traffic must cross the local fault-injection proxy for request counts
# and response-loss assertions to be meaningful.
PAYMENT_LINK_LIGHTWALLETD_URL="http://127.0.0.1:19068"
PAYMENT_LINK_ZCASHD_RPC_URL="http://127.0.0.1:18232"
mkdir -p .regtest-logs
exec > >(tee .regtest-logs/gift-card-outcomes.log) 2>&1

# Three scenarios, four process phases: competition creates the real archived
# loser used by archive/restore; response loss needs its own restart pair.
start_payment_link_regtest
run_payment_link_phase integration_test/regtest_gift_card_competition_test.dart
run_payment_link_phase integration_test/regtest_gift_card_archive_resume_test.dart
start_payment_link_regtest
run_payment_link_phase integration_test/regtest_gift_card_response_prepare_test.dart
# Do not mine between these processes: manual checks must observe a still
# pending transaction before the resume test mines and releases recovery.
run_payment_link_phase integration_test/regtest_gift_card_response_resume_test.dart
