#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
E2E_VOTING_DISCOVERY_TRANSITION=1 \
E2E_VOTING_TEST_FILE=integration_test/regtest_mobile_voting_discovery_test.dart \
  exec "$ROOT_DIR/scripts/e2e/flutter-ios-regtest-mobile-voting.sh"
