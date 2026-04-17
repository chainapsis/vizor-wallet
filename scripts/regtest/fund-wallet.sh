#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

destination="${1:?usage: fund-wallet.sh <unified-address> [zec-amount] [confirming-blocks]}"
requested_amount="${2:-1.0}"
confirming_blocks="${3:-10}"

wait_for_zcashd
wait_for_wallet_spend_ready
wait_for_lightwalletd
ensure_faucet_state

sender_address="$(faucet_transparent_sender)"
faucet_zaddr="$(zcash_cli z_getnewaddress sapling)"

shield_opid="$(extract_opid "$(zcash_cli z_shieldcoinbase "$sender_address" "$faucet_zaddr" 0.0001 1)")"
wait_for_operation "$shield_opid" >/dev/null
zcash_cli generate 10 >/dev/null
wait_for_lightwalletd_tip "$(zcash_cli getblockcount)"

recipients="$(python3 - "$destination" "$requested_amount" <<'PY'
import json
import sys

print(json.dumps([{"address": sys.argv[1], "amount": float(sys.argv[2])}]))
PY
)"

opid="$(extract_opid "$(zcash_cli z_sendmany "$faucet_zaddr" "$recipients" 1 0.0001 AllowRevealedAmounts)")"
txid="$(wait_for_operation "$opid")"
zcash_cli generate "$confirming_blocks" >/dev/null
wait_for_lightwalletd_tip "$(zcash_cli getblockcount)"
echo "$txid"
