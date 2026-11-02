#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Pays the coinbase of new blocks to a regtest address. Before NU6.3 a unified
# address's coinbase lands in Orchard, from NU6.3 in Ironwood. Coinbase needs
# 100 confirmations before it can be spent.
address="${1:-}"
blocks="${2:-1}"
if [[ -z "$address" ]] || ! [[ "$blocks" =~ ^[1-9][0-9]*$ ]]; then
  echo "usage: fund.sh <regtest-address> [positive-block-count]" >&2
  exit 1
fi

zebra_rpc generatetoaddress "[$blocks, \"$address\"]" >/dev/null
wait_for_lightwalletd_tip
current_height
