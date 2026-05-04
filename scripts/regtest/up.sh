#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

mkdir -p "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
chmod 0777 "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
sync
sleep 1
compose up -d zcashd lightwalletd
wait_for_zcashd
wait_for_lightwalletd
ensure_faucet_state

echo "regtest services are ready"
echo "lightwalletd: http://127.0.0.1:9067"
