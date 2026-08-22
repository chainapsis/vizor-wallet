#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd xcrun

UDID="$(pick_simulator)"
FLUTTER_DEVICE="$UDID" \
VIZOR_FORM_FACTOR=mobile \
E2E_VOTING_TEST_FILE=integration_test/regtest_mobile_voting_test.dart \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-voting.sh"
