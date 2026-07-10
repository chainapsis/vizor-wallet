#!/usr/bin/env bash
# Invalidate a recent block and mine a replacement branch.
# Usage: reorg.sh [depth=5] [extra=25] [longer|same-height] [keep-mempool|drop-mempool] [txids-to-drop]
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

wait_for_zcashd
wait_for_lightwalletd

depth="${1:-5}"
extra="${2:-25}"
tip_mode="${3:-longer}"
mempool_mode="${4:-keep-mempool}"
txids_to_drop="${5:-}"

case "$tip_mode" in
  longer)
    # invalidateblock also removes the named block, so the replacement branch
    # needs at least depth + 2 blocks to finish above the old tip.
    if (( extra < depth + 2 )); then
      echo "reorg.sh: extra ($extra) must be at least depth + 2 ($((depth + 2)))" >&2
      exit 1
    fi
    ;;
  same-height)
    if (( extra != depth + 1 )); then
      echo "reorg.sh: same-height requires extra=depth+1 ($((depth + 1))), got $extra" >&2
      exit 1
    fi
    ;;
  *)
    echo "reorg.sh: tip mode must be 'longer' or 'same-height', got '$tip_mode'" >&2
    exit 1
    ;;
esac

case "$mempool_mode" in
  keep-mempool|drop-mempool) ;;
  *)
    echo "reorg.sh: mempool mode must be 'keep-mempool' or 'drop-mempool', got '$mempool_mode'" >&2
    exit 1
    ;;
esac

# A same-height replacement cannot be synchronized reliably by watching only
# GetLatestBlock.height: the old and new branches have the same value. Fail
# deterministically when the hash-capable gRPC probe is unavailable instead of
# racing the next wallet sync against stale lightwalletd state.
if [[ "$tip_mode" == "same-height" ]] && ! command -v grpcurl >/dev/null 2>&1; then
  echo "reorg.sh: same-height mode requires grpcurl to verify the replacement tip hash" >&2
  exit 1
fi

old_tip="$(zcash_cli getblockcount)"
target_height=$((old_tip - depth))
target_hash="$(zcash_cli getblockhash "$target_height")"
old_tip_hash="$(zcash_cli getblockhash "$old_tip")"

zcash_cli invalidateblock "$target_hash"

# Transactions from disconnected blocks normally return to the mempool and
# would simply be mined again on the replacement branch. Restarting zcashd
# clears externally-submitted transactions from its non-persistent regtest
# mempool, making orphan-transaction tests deterministic. Transactions owned
# by zcashd's own wallet may be rebroadcast after restart, so assert the
# caller's specific transaction is absent instead of requiring a globally
# empty mempool.
if [[ "$mempool_mode" == "drop-mempool" ]]; then
  if [[ -z "$txids_to_drop" ]]; then
    echo "reorg.sh: drop-mempool requires a comma-separated txids-to-drop value" >&2
    exit 1
  fi
  compose restart zcashd >/dev/null
  wait_for_zcashd
  # lightwalletd treats a transient zcashd RPC failure as fatal. Restart it
  # explicitly after zcashd is ready; `compose up` can otherwise observe the
  # old process as running just before that process exits.
  compose restart lightwalletd >/dev/null
  wait_for_lightwalletd
  mempool_json="$(zcash_cli getrawmempool)"
  if ! python3 - "$txids_to_drop" "$mempool_json" <<'PY'
import json
import sys

txids = sys.argv[1].split(",")
mempool = json.loads(sys.argv[2])
raise SystemExit(0 if all(txid not in mempool for txid in txids) else 1)
PY
  then
    echo "reorg.sh: a disconnected transaction returned to the mempool after restart: $txids_to_drop" >&2
    exit 1
  fi
fi

zcash_cli generate "$extra" >/dev/null

new_tip="$(zcash_cli getblockcount)"
new_tip_hash="$(zcash_cli getblockhash "$new_tip")"
if [[ "$tip_mode" == "longer" ]] && (( new_tip <= old_tip )); then
  echo "reorg.sh: replacement branch did not exceed the old tip (old=$old_tip new=$new_tip)" >&2
  exit 1
fi
if [[ "$tip_mode" == "same-height" ]] && (( new_tip != old_tip )); then
  echo "reorg.sh: replacement branch did not finish at the old height (old=$old_tip new=$new_tip)" >&2
  exit 1
fi
if [[ "$new_tip_hash" == "$old_tip_hash" ]]; then
  echo "reorg.sh: replacement branch retained the old tip hash $old_tip_hash" >&2
  exit 1
fi

# A height-only wait returns immediately for a same-height reorg while
# lightwalletd may still serve the old branch. Wait for the canonical hash at
# the replacement tip so the test cannot race its next wallet sync.
if command -v grpcurl >/dev/null 2>&1; then
  observed_hash=""
  for _ in $(seq 1 120); do
    observed_hash="$(
      grpcurl \
        -plaintext \
        -import-path "$ROOT_DIR/protos" \
        -proto service.proto \
        -d "{\"height\": $new_tip}" \
        "${LIGHTWALLETD_HOST}:${LIGHTWALLETD_PORT}" \
        cash.z.wallet.sdk.rpc.CompactTxStreamer/GetTreeState \
        2>/dev/null \
        | python3 -c 'import json, sys; print(json.load(sys.stdin).get("hash", ""))' \
      || true
    )"
    if [[ "$observed_hash" == "$new_tip_hash" ]]; then
      break
    fi
    sleep 1
  done
  if [[ "$observed_hash" != "$new_tip_hash" ]]; then
    echo "reorg.sh: lightwalletd did not switch to replacement hash $new_tip_hash" >&2
    exit 1
  fi
else
  # Height is sufficient only when the replacement branch must be longer.
  wait_for_lightwalletd_tip "$new_tip"
fi

echo "reorg: invalidated height=$target_height old_tip=$old_tip old_hash=$old_tip_hash new_tip=$new_tip new_hash=$new_tip_hash"
