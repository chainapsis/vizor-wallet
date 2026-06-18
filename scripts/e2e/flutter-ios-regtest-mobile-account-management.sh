#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESET_REGTEST="${RESET_REGTEST:-1}"

source "$ROOT_DIR/scripts/e2e/lib-mobile.sh"

require_cmd docker
require_cmd fvm
require_cmd xcrun

cd "$ROOT_DIR"

if [[ "$RESET_REGTEST" == "1" ]]; then
  scripts/regtest/reset.sh
fi
scripts/regtest/up.sh

UDID="$(pick_simulator)"
run_mobile_e2e integration_test/regtest_mobile_account_management_test.dart "$UDID"
