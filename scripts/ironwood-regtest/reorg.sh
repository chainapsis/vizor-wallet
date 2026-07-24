#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fork_height="${1:-}"
if ! [[ "$fork_height" =~ ^[0-9]+$ ]]; then
  echo "usage: reorg.sh <fork-height>" >&2
  exit 1
fi

wait_for_zcashd
wait_for_lightwalletd
old_tip="$(current_height)"
if [[ "$fork_height" -ge "$old_tip" ]]; then
  echo "fork height must be below the current tip ($old_tip)" >&2
  exit 1
fi

old_tip_hash="$(zcash_cli getblockhash "$old_tip")"
invalidated_hash="$(zcash_cli getblockhash "$((fork_height + 1))")"
before_mempool="$(zcash_cli getrawmempool)"
zcash_cli invalidateblock "$invalidated_hash"
after_mempool="$(zcash_cli getrawmempool)"

while IFS= read -r txid; do
  [[ -z "$txid" ]] || zcash_cli prioritisetransaction "$txid" 0 -100000000 >/dev/null
done < <(
  python3 - "$after_mempool" <<'PY'
import json
import sys

for txid in json.loads(sys.argv[1]):
    print(txid)
PY
)

# Extend one block past the old tip so height-only clients are forced to sync
# and discover the changed block hash.
replacement_blocks="$((old_tip - fork_height + 1))"
zcash_cli generate "$replacement_blocks" >/dev/null
new_tip="$(current_height)"
new_tip_hash="$(zcash_cli getblockhash "$new_tip")"
wait_for_lightwalletd_tip_hash "$new_tip_hash"

python3 - \
  "$fork_height" \
  "$old_tip" \
  "$new_tip" \
  "$old_tip_hash" \
  "$new_tip_hash" \
  "$invalidated_hash" \
  "$before_mempool" \
  "$after_mempool" <<'PY'
import json
import sys

before = set(json.loads(sys.argv[7]))
after = set(json.loads(sys.argv[8]))
print(json.dumps({
    "forkHeight": int(sys.argv[1]),
    "oldTip": int(sys.argv[2]),
    "newTip": int(sys.argv[3]),
    "oldTipHash": sys.argv[4],
    "newTipHash": sys.argv[5],
    "invalidatedHash": sys.argv[6],
    "heldTxids": sorted(after),
    "reintroducedTxids": sorted(after - before),
}))
PY
