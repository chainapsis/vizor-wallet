#!/usr/bin/env bash
set -euo pipefail

# iOS-simulator lane for the real-proof voting E2E. The macOS voting script
# owns the whole stack (vote-sdk chain, PIR, signed config, gateway); this
# wrapper only swaps in the mobile test files and a simulator device.
#
# The iOS test runner reinstalls the app between `flutter test` invocations,
# so the migrated wallet DB does not survive from the setup step to the
# voting step. The mobile voting test therefore re-imports the deterministic
# wallet and rediscovers the Ironwood notes from the chain
# (E2E_REUSE_MIGRATED_WALLET=false), instead of reusing the on-disk wallet
# the desktop lane keeps.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd git
require_cmd grpcurl
require_cmd jq
require_cmd make
require_cmd python3
require_cmd xcrun

cd "$ROOT_DIR"
UDID="$(pick_simulator)"

FLUTTER_DEVICE="$UDID" \
VIZOR_FORM_FACTOR=mobile \
E2E_VOTING_SETUP_TEST_FILE=integration_test/regtest_mobile_voting_ironwood_setup_test.dart \
E2E_TEST_FILE=integration_test/regtest_mobile_voting_test.dart \
E2E_REUSE_MIGRATED_WALLET=false \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-voting.sh"
