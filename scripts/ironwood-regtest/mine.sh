#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

blocks="${1:-1}"
if ! [[ "$blocks" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: mine.sh <positive-block-count>" >&2
  exit 1
fi

wait_for_zcashd
wait_for_lightwalletd
zcash_cli generate "$blocks"
tip_hash="$(zcash_cli getblockhash "$(current_height)")"
wait_for_lightwalletd_tip_hash "$tip_hash"
