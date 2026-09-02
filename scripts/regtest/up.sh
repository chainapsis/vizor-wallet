#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

prepare_compatible_regtest_state
sync
start_regtest_services
wait_for_lightwalletd
ensure_faucet_state

echo "regtest services are ready"
echo "lightwalletd: http://127.0.0.1:9067"
