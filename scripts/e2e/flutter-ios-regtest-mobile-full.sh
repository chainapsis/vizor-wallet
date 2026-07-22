#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INCLUDE_500_NOTE_MIGRATION="${E2E_INCLUDE_500_NOTE_MIGRATION:-0}"
INCLUDE_ACCOUNT_REIMPORT_MIGRATION="${E2E_INCLUDE_ACCOUNT_REIMPORT_MIGRATION:-0}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

run_test() {
  local name="$1"
  local script="$2"

  echo
  echo "==> ${name}"
  RESET_REGTEST=1 "$ROOT_DIR/$script"
}

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3
require_cmd xcrun

case "$INCLUDE_500_NOTE_MIGRATION" in
  0 | 1) ;;
  *)
    echo "E2E_INCLUDE_500_NOTE_MIGRATION must be 0 or 1" >&2
    exit 2
    ;;
esac

case "$INCLUDE_ACCOUNT_REIMPORT_MIGRATION" in
  0 | 1) ;;
  *)
    echo "E2E_INCLUDE_ACCOUNT_REIMPORT_MIGRATION must be 0 or 1" >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"

# Keep this ordered from the narrowest smoke test to broader user flows.
# Desktop scenarios without a mobile counterpart yet (feature gaps):
# custom-endpoint privacy (no mobile endpoint settings UI) and
# shield-transparent ×2 (no mobile transparent balance / shield UI).
run_test "1/15 create wallet via passcode onboarding and sync" \
  "scripts/e2e/flutter-ios-regtest-mobile-create-sync.sh"

run_test "2/15 import funded wallet and sync balance" \
  "scripts/e2e/flutter-ios-regtest-mobile-import-sync.sh"

run_test "3/15 manage accounts and rotate the passcode" \
  "scripts/e2e/flutter-ios-regtest-mobile-account-management.sh"

run_test "4/15 import two accounts and send shielded funds" \
  "scripts/e2e/flutter-ios-regtest-mobile-multi-account-send.sh"

run_test "5/15 show mempool receives in activity" \
  "scripts/e2e/flutter-ios-regtest-mobile-mempool-receive.sh"

run_test "6/15 fall back from unavailable endpoint" \
  "scripts/e2e/flutter-ios-regtest-mobile-fallback-endpoint.sh"

run_test "7/15 fall back from slow-height primary and recover" \
  "scripts/e2e/flutter-ios-regtest-mobile-slow-height-fallback.sh"

run_test "8/15 migrate the minimum viable Orchard balance to Ironwood" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration.sh"

run_test "9/15 migrate twenty Orchard notes through two split stages" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-many-notes.sh"

run_test "10/15 isolate an Ironwood migration across two accounts" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-multi-account.sh"

run_test "11/15 rebuild an Ironwood migration after a chain reorg" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-reorg.sh"

run_test "12/15 resume an Ironwood migration after process restart" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-restart.sh"

run_test "13/15 resume an Ironwood migration after network recovery" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-network-recovery.sh"

run_test "14/15 advance Ironwood migration through native background wakes" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-background-migration.sh"

run_test "15/15 resume a persisted Ironwood proof after process restart" \
  "scripts/e2e/flutter-ios-regtest-mobile-ironwood-background-restart.sh"

if [[ "$INCLUDE_ACCOUNT_REIMPORT_MIGRATION" == "1" ]]; then
  run_test "optional: recover migrated balances after account re-import" \
    "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-account-reimport.sh"
else
  echo
  echo "skipping optional account re-import recovery; set E2E_INCLUDE_ACCOUNT_REIMPORT_MIGRATION=1 to run it"
fi

if [[ "$INCLUDE_500_NOTE_MIGRATION" == "1" ]]; then
  run_test "optional: migrate 500 Orchard notes to Ironwood" \
    "scripts/e2e/flutter-ios-regtest-mobile-ironwood-migration-500-notes.sh"
else
  echo
  echo "skipping optional 500-note migration; set E2E_INCLUDE_500_NOTE_MIGRATION=1 to run it"
fi

echo
echo "all iOS mobile regtest E2E tests passed"
