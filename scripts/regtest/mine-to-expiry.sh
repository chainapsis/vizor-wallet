#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

txid="${1:?usage: mine-to-expiry.sh <txid> <expiry-height> [extra-blocks]}"
expiry_height="${2:?usage: mine-to-expiry.sh <txid> <expiry-height> [extra-blocks]}"
extra_blocks="${3:-0}"
target_height=$((expiry_height + extra_blocks))

wait_for_zcashd
wait_for_lightwalletd

is_mined() {
  local raw_json
  if ! raw_json="$(zcash_cli getrawtransaction "$txid" 1 2>/dev/null)"; then
    return 1
  fi

  python3 - "$raw_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
confirmations = int(data.get("confirmations") or 0)
height = int(data.get("height") or 0)
blockhash = data.get("blockhash")
raise SystemExit(0 if confirmations > 0 or height > 0 or blockhash else 1)
PY
}

while [[ "$(zcash_cli getblockcount)" -lt "$target_height" ]]; do
  zcash_cli generate 1 >/dev/null
  if is_mined; then
    echo "Transaction $txid was mined before expiry height $expiry_height" >&2
    exit 1
  fi
done

wait_for_lightwalletd_tip "$target_height"
echo "$target_height"
