#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

destination="${1:?usage: fund-orchard.sh <unified-address> [zec-amount] [confirming-blocks] [coinbase-limit]}"
amount="${2:-1.0002}"
confirming_blocks="${3:-10}"
coinbase_limit="${4:-1}"

if [[ "$destination" != uregtest1* ]]; then
  echo "fund-orchard.sh requires a regtest unified address" >&2
  exit 1
fi
if ! [[ "$confirming_blocks" =~ ^[1-9][0-9]*$ ]]; then
  echo "confirming-blocks must be a positive integer" >&2
  exit 1
fi
if ! [[ "$coinbase_limit" =~ ^[0-9]+$ ]]; then
  echo "coinbase-limit must be a non-negative integer" >&2
  exit 1
fi

wait_for_zcashd
wait_for_lightwalletd
ensure_faucet
assert_pre_ironwood_room "$((20 + confirming_blocks))"

sender="$(faucet_sender)"
sapling_faucet="$(zcash_cli z_getnewaddress sapling)"
shield_opid="$(extract_opid "$(zcash_cli z_shieldcoinbase "$sender" "$sapling_faucet" 0.0001 "$coinbase_limit")")"
wait_for_operation "$shield_opid" >/dev/null
zcash_cli generate 20 >/dev/null
wait_for_lightwalletd_tip "$(current_height)"
wait_for_spendable_shielded_note "$sapling_faucet"

recipients="$(python3 - "$destination" "$amount" <<'PY'
import json
import sys
print(json.dumps([{"address": sys.argv[1], "amount": float(sys.argv[2])}]))
PY
)"
txid=""
for attempt in $(seq 1 10); do
  opid="$(extract_opid "$(zcash_cli z_sendmany "$sapling_faucet" "$recipients" 1 0.0001 AllowRevealedAmounts)")"
  if txid="$(wait_for_operation "$opid")"; then
    break
  fi
  echo "Orchard funding anchor is not ready (attempt ${attempt}/10); retrying" >&2
  sleep 1
done
if [[ -z "$txid" ]]; then
  echo "failed to fund Orchard address after 10 attempts" >&2
  exit 1
fi
zcash_cli generate "$confirming_blocks" >/dev/null
wait_for_lightwalletd_tip "$(current_height)"

echo "$txid"
