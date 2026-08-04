#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Fixed external oracles generated with bip_utils and the Python
# zcash-test-vectors implementation, not with the app's Rust code.
UNIFIED_ADDRESS="uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn"
TRANSPARENT_ADDRESS="tmPTcChwqcza88W1mydzwkZ25C9qQm3ugiM"
SHIELDED_AMOUNT="1.25"
TRANSPARENT_AMOUNT="0.75"
CONFIRMING_BLOCKS="${E2E_CONFIRMING_BLOCKS:-10}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:9067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
RESET_REGTEST="${RESET_REGTEST:-1}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd fvm

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

echo "funding shielded address with ${SHIELDED_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh "$UNIFIED_ADDRESS" "$SHIELDED_AMOUNT" "$CONFIRMING_BLOCKS" >/dev/null

echo "funding transparent address with ${TRANSPARENT_AMOUNT} TAZ"
scripts/regtest/fund-wallet.sh "$TRANSPARENT_ADDRESS" "$TRANSPARENT_AMOUNT" "$CONFIRMING_BLOCKS" >/dev/null

echo "running Flutter macOS integration test"
fvm flutter test \
  integration_test/regtest_import_sync_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL" \
  --dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
