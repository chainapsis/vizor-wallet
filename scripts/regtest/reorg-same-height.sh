#!/usr/bin/env bash
# Invalidate a recent block and mine a replacement branch ending at the same height.
# Usage: reorg-same-height.sh [depth=5]
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

wait_for_zcashd
wait_for_lightwalletd

depth="${1:-5}"
old_tip="$(zcash_cli getblockcount)"
target_height=$((old_tip - depth))
target_hash="$(zcash_cli getblockhash "$target_height")"
old_tip_hash="$(zcash_cli getblockhash "$old_tip")"

zcash_cli invalidateblock "$target_hash"
# invalidateblock removes the target block too, hence depth + 1 replacements.
zcash_cli generate "$((depth + 1))" >/dev/null

new_tip="$(zcash_cli getblockcount)"
new_tip_hash="$(zcash_cli getblockhash "$new_tip")"
if (( new_tip != old_tip )); then
  echo "reorg-same-height.sh: replacement tip moved (old=$old_tip new=$new_tip)" >&2
  exit 1
fi
if [[ "$new_tip_hash" == "$old_tip_hash" ]]; then
  echo "reorg-same-height.sh: replacement retained old hash $old_tip_hash" >&2
  exit 1
fi

# A height-only wait returns immediately here. Wait until lightwalletd serves
# the replacement hash so the wallet sync cannot race its cache.
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
    echo "reorg-same-height.sh: lightwalletd did not switch to $new_tip_hash" >&2
    exit 1
  fi
else
  # This at least verifies service availability when grpcurl is unavailable.
  # CI installs grpcurl and therefore takes the hash-aware path above.
  wait_for_lightwalletd_tip "$new_tip"
fi

echo "same-height reorg: height=$new_tip old_hash=$old_tip_hash new_hash=$new_tip_hash"
