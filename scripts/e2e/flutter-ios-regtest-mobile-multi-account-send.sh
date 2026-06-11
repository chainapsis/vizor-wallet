#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIRST_MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
SHIELDED_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
RESET_REGTEST="${RESET_REGTEST:-1}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
print(data[sys.argv[2]])
PY
}

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3
require_cmd xcrun

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$FIRST_MNEMONIC")"
unified_address="$(json_field "$addresses_json" unifiedAddress)"

echo "funding first wallet shielded address with ${SHIELDED_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh "$unified_address" "$SHIELDED_AMOUNT" "$CONFIRMING_BLOCKS" >/dev/null

UDID="$(pick_simulator)"
run_mobile_e2e integration_test/regtest_mobile_multi_account_send_test.dart "$UDID"
