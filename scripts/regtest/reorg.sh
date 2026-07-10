#!/usr/bin/env bash
# Invalidate a recent block and mine a longer replacement branch.
# Usage: reorg.sh [depth=5] [extra=25]
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

wait_for_zcashd
wait_for_lightwalletd

depth="${1:-5}"
extra="${2:-25}"

# invalidateblock also removes the named block, so the replacement branch
# needs at least depth + 2 blocks to finish above the old tip.
if (( extra < depth + 2 )); then
  echo "reorg.sh: extra ($extra) must be at least depth + 2 ($((depth + 2)))" >&2
  exit 1
fi

old_tip="$(zcash_cli getblockcount)"
target_height=$((old_tip - depth))
target_hash="$(zcash_cli getblockhash "$target_height")"

zcash_cli invalidateblock "$target_hash"
zcash_cli generate "$extra" >/dev/null

new_tip="$(zcash_cli getblockcount)"
if (( new_tip <= old_tip )); then
  echo "reorg.sh: replacement branch did not exceed the old tip (old=$old_tip new=$new_tip)" >&2
  exit 1
fi

wait_for_lightwalletd_tip "$new_tip"
echo "reorg: invalidated height=$target_height (old_tip=$old_tip) -> new_tip=$new_tip"
