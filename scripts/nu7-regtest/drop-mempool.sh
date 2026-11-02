#!/usr/bin/env bash
set -euo pipefail

# Restarts Zebra, which keeps no mempool across restarts, so transactions
# broadcast so far are never mined.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

compose restart zebra >/dev/null
wait_for_zebra
# lightwalletd shares Zebra's network namespace, so it is recreated after it.
compose up -d --force-recreate --no-deps lightwalletd >/dev/null
wait_for_lightwalletd
wait_for_lightwalletd_tip
size="$(zebra_rpc getrawmempool | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [[ "$size" != "0" ]]; then
  echo "Zebra mempool still holds $size transactions after restart" >&2
  exit 1
fi
