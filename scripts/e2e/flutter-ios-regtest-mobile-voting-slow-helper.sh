#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SLOW_HELPER_MODE=1 \
  exec "$ROOT_DIR/scripts/e2e/flutter-ios-regtest-mobile-voting.sh"
