#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
ZCASHD_RPC_URL="${E2E_ZCASHD_RPC_URL:-http://127.0.0.1:18232}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

json_field() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
print(data[sys.argv[2]])
PY
}

fund_transparent() {
  local label="$1"
  local address="$2"
  local amount="$3"

  echo "funding ${label} ${address} with ${amount} TAZ"
  scripts/regtest/fund-wallet.sh "$address" "$amount" "$CONFIRMING_BLOCKS" >/dev/null
}

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

source scripts/regtest/lib.sh
wait_for_zcashd
wait_for_lightwalletd
birthday_height="$(zcash_cli getblockcount)"

addresses_json="$(cd rust && cargo run --quiet --example regtest_ledger_transparent_addresses -- "$MNEMONIC")"
external0="$(json_field "$addresses_json" external0)"
software_receive_transparent="$(json_field "$addresses_json" softwareReceiveTransparent)"
external9="$(json_field "$addresses_json" external9)"
external19="$(json_field "$addresses_json" external19)"
internal9="$(json_field "$addresses_json" internal9)"
internal19="$(json_field "$addresses_json" internal19)"

fund_transparent "m/44'/133'/0'/0/0" "$external0" "0.11"
fund_transparent "m/44'/133'/0'/0/9" "$external9" "0.12"
fund_transparent "m/44'/133'/0'/0/19" "$external19" "0.13"
fund_transparent "m/44'/133'/0'/1/9" "$internal9" "0.14"
fund_transparent "m/44'/133'/0'/1/19" "$internal19" "0.15"

echo "running Flutter macOS Ledger transparent discovery integration test"
fvm flutter test \
  integration_test/regtest_ledger_transparent_discovery_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_NETWORK=regtest \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_ZCASHD_RPC_URL="$ZCASHD_RPC_URL" \
  --dart-define=ZCASH_E2E_IMPORT_BIRTHDAY_HEIGHT="$birthday_height" \
  --dart-define=ZCASH_E2E_EXPECTED_TRANSPARENT_ADDRESS="$software_receive_transparent" \
  --dart-define=ZCASH_E2E_EXPECTED_TRANSPARENT_BALANCE_ZAT=65000000
