#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Regression for the multi-minute stall reported when an unhealthy helper was
# retried serially for every encrypted share. The gateway delays one logical
# helper while forwarding to the real local helper, then the base E2E asserts
# that multiple delayed share requests overlapped.
E2E_SLOW_HELPER_MODE=1 \
  exec "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-voting.sh" "$@"
