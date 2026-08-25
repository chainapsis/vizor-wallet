#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECEIVER_MNEMONIC="return try reason flat civil wolf dwarf announce toddler uphold equip range neck proof gauge east rifle swim tray twin venue fossil will version"

cd "$ROOT_DIR"

receiver_addresses_json="$(
  cd rust
  cargo run --quiet --example regtest_wallet_addresses -- "$RECEIVER_MNEMONIC"
)"
recipient_address="$(
  python3 -c 'import json, sys; print(json.load(sys.stdin)["unifiedAddress"])' \
    <<<"$receiver_addresses_json"
)"

export E2E_TEST_FILE="integration_test/regtest_mobile_ironwood_pre_migration_send_test.dart"
export E2E_DRIVER_PORT="${E2E_DRIVER_PORT:-39089}"
export E2E_SEND_RECIPIENT_ADDRESS="$recipient_address"
exec scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration.sh
