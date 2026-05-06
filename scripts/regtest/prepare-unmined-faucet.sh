#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

requested_amount="${1:-0.35}"

wait_for_zcashd
wait_for_wallet_spend_ready
wait_for_lightwalletd
ensure_faucet_state

sender_address="$(faucet_transparent_sender)"
faucet_zaddr="$(zcash_cli z_getnewaddress sapling)"

shield_opid="$(extract_opid "$(zcash_cli z_shieldcoinbase "$sender_address" "$faucet_zaddr" 0.0001 1)")"
wait_for_operation "$shield_opid" >/dev/null

zcash_cli generate 20 >/dev/null
wait_for_lightwalletd_tip "$(zcash_cli getblockcount)"
wait_for_zaddr_balance "$faucet_zaddr" "$requested_amount"

echo "$faucet_zaddr"
