#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

export E2E_CUSTOM_MIGRATION_AUTO_START=true
export E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS=0
export E2E_CUSTOM_MIGRATION_PACE_MS=0
export E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS=0
export VIZOR_E2E_HIDDEN_WINDOW=true
exec scripts/e2e/flutter-macos-ironwood-custom-migration-live.sh
