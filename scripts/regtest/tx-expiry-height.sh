#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

txid="${1:?usage: tx-expiry-height.sh <txid>}"

wait_for_zcashd

raw_json="$(zcash_cli getrawtransaction "$txid" 1)"

python3 - "$raw_json" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])

for key, value in data.items():
    normalized = key.replace("_", "").lower()
    if normalized == "expiryheight":
        print(int(value))
        raise SystemExit(0)

raise SystemExit(f"expiry height not found in getrawtransaction output: {data}")
PY
