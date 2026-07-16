#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

validate_activation_height
wait_for_zcashd
wait_for_lightwalletd

tip="$(current_height)"
if [[ "$tip" -gt "$IRONWOOD_ACTIVATION_HEIGHT" ]]; then
  echo "chain is already past NU6.3 activation (tip=$tip)" >&2
  exit 1
fi
if [[ "$tip" -lt "$IRONWOOD_ACTIVATION_HEIGHT" ]]; then
  zcash_cli generate "$((IRONWOOD_ACTIVATION_HEIGHT - tip))" >/dev/null
fi
wait_for_lightwalletd_tip "$IRONWOOD_ACTIVATION_HEIGHT"

branch_id="$(zcash_cli getblockchaininfo | python3 -c 'import json,sys; print(json.load(sys.stdin)["consensus"]["chaintip"])')"
normalized_branch_id="$(printf '%s' "$branch_id" | tr '[:upper:]' '[:lower:]')"
if [[ "$normalized_branch_id" != "37a5165b" ]]; then
  echo "expected NU6.3 branch 37a5165b at activation, got $branch_id" >&2
  exit 1
fi

echo "NU6.3 active at height $(current_height) (branch $branch_id)"
