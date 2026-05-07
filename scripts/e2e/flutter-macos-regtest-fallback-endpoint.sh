#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
SHIELDED_AMOUNT="1.25"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
PRIMARY_LIGHTWALLETD_URL="${E2E_PRIMARY_LIGHTWALLETD_URL:-http://127.0.0.1:19067}"
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

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

addresses_json="$(cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC")"
unified_address="$(json_field "$addresses_json" unifiedAddress)"

echo "funding shielded address with ${SHIELDED_AMOUNT} ZEC"
scripts/regtest/fund-wallet.sh "$unified_address" "$SHIELDED_AMOUNT" "$CONFIRMING_BLOCKS" >/dev/null

echo "running Flutter macOS fallback endpoint integration test"
fvm flutter test \
  integration_test/regtest_fallback_endpoint_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$PRIMARY_LIGHTWALLETD_URL"
