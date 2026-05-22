#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd fvm

cd "$ROOT_DIR"

echo "running Flutter macOS payment URI prefill integration test"
fvm flutter test \
  integration_test/payment_uri_prefill_test.dart \
  -d "$FLUTTER_DEVICE"
