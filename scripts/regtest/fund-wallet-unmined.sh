#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

destination="${1:?usage: fund-wallet-unmined.sh <destination-address> [zec-amount]}"
requested_amount="${2:-0.25}"

wait_for_zcashd
wait_for_wallet_spend_ready
wait_for_lightwalletd
ensure_faucet_state

faucet_zaddr="${REGTEST_UNMINED_FAUCET_ZADDR:-}"
if [[ -z "$faucet_zaddr" ]]; then
  sender_address="$(faucet_transparent_sender)"
  faucet_zaddr="$(zcash_cli z_getnewaddress sapling)"

  shield_opid="$(extract_opid "$(zcash_cli z_shieldcoinbase "$sender_address" "$faucet_zaddr" 0.0001 1)")"
  wait_for_operation "$shield_opid" >/dev/null

  # Confirm only the faucet shielding transaction. The final z_sendmany below is
  # intentionally left unmined so wallet mempool observers can discover it.
  zcash_cli generate 20 >/dev/null
  wait_for_lightwalletd_tip "$(zcash_cli getblockcount)"
fi
wait_for_zaddr_balance "$faucet_zaddr" "$requested_amount"

recipients="$(python3 - "$destination" "$requested_amount" <<'PY'
import json
import sys

print(json.dumps([{"address": sys.argv[1], "amount": float(sys.argv[2])}]))
PY
)"

privacy_policy="AllowRevealedAmounts"
if [[ "$destination" == t* ]]; then
  privacy_policy="AllowRevealedRecipients"
fi

opid="$(extract_opid "$(zcash_cli z_sendmany "$faucet_zaddr" "$recipients" 1 0.0001 "$privacy_policy")")"
txid="$(wait_for_operation "$opid")"

for _ in $(seq 1 30); do
  mempool_json="$(zcash_cli getrawmempool)"
  if python3 - "$txid" "$mempool_json" <<'PY'
import json
import sys

txid = sys.argv[1]
mempool = json.loads(sys.argv[2])
raise SystemExit(0 if txid in mempool else 1)
PY
  then
    echo "$txid"
    exit 0
  fi
  sleep 1
done

echo "Timed out waiting for $txid to appear in zcashd mempool" >&2
exit 1
