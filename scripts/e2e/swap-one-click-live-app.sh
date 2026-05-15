#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Run the Flutter app with the NEAR Intents 1Click live quote configuration.

This is for local UI validation of the app's Review quote path. It passes the
shell environment JWT into Flutter as a compile-time dart-define, which the app
reads through String.fromEnvironment.

Equivalent to:
  fvm flutter run --dart-define=ZCASH_SWAP_1CLICK_JWT="$ZCASH_SWAP_1CLICK_JWT"

Required:
  ZCASH_SWAP_1CLICK_JWT

Optional:
  ZCASH_SWAP_1CLICK_BASE_URL
  ZCASH_SWAP_1CLICK_REFERRAL
  ZCASH_SWAP_ENABLE_LIVE_FUNDS=false  disable live wallet deposit paths

No-history setup:
  printf 'ZCASH_SWAP_1CLICK_JWT: '
  read -r -s ZCASH_SWAP_1CLICK_JWT
  printf '\n'
  export ZCASH_SWAP_1CLICK_JWT

Examples:
  scripts/e2e/swap-one-click-live-app.sh -d macos

  scripts/e2e/swap-one-click-live-app.sh -d "iPhone 16 Pro"
USAGE
}

fail() {
  echo "fail: $*" >&2
  exit 64
}

fail_missing_jwt() {
  {
    echo "fail: Set ZCASH_SWAP_1CLICK_JWT."
    echo "No-history setup:"
    echo "  printf 'ZCASH_SWAP_1CLICK_JWT: '"
    echo "  read -r -s ZCASH_SWAP_1CLICK_JWT"
    echo "  printf '\\n'"
    echo "  export ZCASH_SWAP_1CLICK_JWT"
    echo "Then rerun scripts/e2e/swap-one-click-live-app.sh."
  } >&2
  exit 64
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -z "${ZCASH_SWAP_1CLICK_JWT:-}" ]]; then
  fail_missing_jwt
fi

require_cmd fvm

args=(flutter run "$@")
args+=("--dart-define=ZCASH_SWAP_1CLICK_JWT=$ZCASH_SWAP_1CLICK_JWT")

if [[ -n "${ZCASH_SWAP_1CLICK_BASE_URL:-}" ]]; then
  args+=("--dart-define=ZCASH_SWAP_1CLICK_BASE_URL=$ZCASH_SWAP_1CLICK_BASE_URL")
fi

if [[ -n "${ZCASH_SWAP_1CLICK_REFERRAL:-}" ]]; then
  args+=("--dart-define=ZCASH_SWAP_1CLICK_REFERRAL=$ZCASH_SWAP_1CLICK_REFERRAL")
fi

if [[ -n "${ZCASH_SWAP_ENABLE_LIVE_FUNDS:-}" ]]; then
  args+=("--dart-define=ZCASH_SWAP_ENABLE_LIVE_FUNDS=$ZCASH_SWAP_ENABLE_LIVE_FUNDS")
fi

echo "running Flutter app with 1Click live quote config"
echo "JWT configured: yes"
echo "live funds enabled: ${ZCASH_SWAP_ENABLE_LIVE_FUNDS:-true}"
exec fvm "${args[@]}"
