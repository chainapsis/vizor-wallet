#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

echo "running Flutter macOS custom endpoint no-fallback integration test"
fvm flutter test \
  integration_test/regtest_custom_endpoint_no_fallback_test.dart \
  -d "$FLUTTER_DEVICE" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
