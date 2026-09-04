#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export E2E_PREPARE_TEST_FILE="integration_test/regtest_payment_link_failure_prepare_test.dart"
export E2E_RESUME_TEST_FILE="integration_test/regtest_payment_link_failure_reorg_resume_test.dart"
export E2E_RESTART_CONFIRMING_BLOCKS="5"
# The failure/reorg phases inject faults through the in-test proxy, which
# always listens on 19068 in front of the local regtest stack, so neither the
# lightwalletd nor the zcashd endpoint can be pointed elsewhere.
PROXY_URL="http://127.0.0.1:19068"
LOCAL_RPC_URL="http://127.0.0.1:18232"
if [[ -n "${E2E_LIGHTWALLETD_URL:-}" && "${E2E_LIGHTWALLETD_URL}" != "$PROXY_URL" ]]; then
  echo "ignoring E2E_LIGHTWALLETD_URL=${E2E_LIGHTWALLETD_URL}; this scenario runs through the proxy at ${PROXY_URL}" >&2
fi
if [[ -n "${E2E_ZCASHD_RPC_URL:-}" && "${E2E_ZCASHD_RPC_URL}" != "$LOCAL_RPC_URL" ]]; then
  echo "ignoring E2E_ZCASHD_RPC_URL=${E2E_ZCASHD_RPC_URL}; this scenario reorganises the local regtest node at ${LOCAL_RPC_URL}" >&2
fi
export E2E_LIGHTWALLETD_URL="$PROXY_URL"
export E2E_ZCASHD_RPC_URL="$LOCAL_RPC_URL"

exec "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-payment-link.sh"
