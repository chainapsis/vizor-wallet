#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$#" -eq 0 ]]; then
  echo "usage: release-reorg-transactions.sh <txid> [txid ...]" >&2
  exit 1
fi

wait_for_zcashd
for txid in "$@"; do
  if ! [[ "$txid" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "invalid transaction id: $txid" >&2
    exit 1
  fi
  zcash_cli prioritisetransaction "$txid" 0 100000000 >/dev/null
done

python3 - "$@" <<'PY'
import json
import sys

print(json.dumps({"releasedTxids": sys.argv[1:]}))
PY
