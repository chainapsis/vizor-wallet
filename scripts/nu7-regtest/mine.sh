#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

blocks="${1:-1}"
if ! [[ "$blocks" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: mine.sh <positive-block-count>" >&2
  exit 1
fi

zebra_rpc generate "[$blocks]" >/dev/null
wait_for_lightwalletd_tip
current_height
