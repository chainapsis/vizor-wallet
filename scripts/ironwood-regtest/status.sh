#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

wait_for_zcashd
wait_for_lightwalletd
tip="$(current_height)"
branch_id="$(zcash_cli getblockchaininfo | python3 -c 'import json,sys; print(json.load(sys.stdin)["consensus"]["chaintip"]')"
lwd_tip="$(lightwalletd_tip_height)"

python3 - "$tip" "$lwd_tip" "$IRONWOOD_ACTIVATION_HEIGHT" "$branch_id" <<'PY'
import json
import sys

tip, lwd_tip, activation = map(int, sys.argv[1:4])
print(json.dumps({
    "zcashdHeight": tip,
    "lightwalletdHeight": lwd_tip,
    "ironwoodActivationHeight": activation,
    "ironwoodActive": tip >= activation,
    "consensusBranchId": sys.argv[4],
}, indent=2))
PY
