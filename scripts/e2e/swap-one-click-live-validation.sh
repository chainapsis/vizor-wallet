#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Validate the NEAR Intents 1Click token/quote/status path with the local Dart parser.

Token-list validation:
  scripts/e2e/swap-one-click-live-validation.sh --tokens-only

Required for quote/status validation:
  ZCASH_SWAP_1CLICK_JWT

No-history setup:
  printf 'ZCASH_SWAP_1CLICK_JWT: '
  read -r -s ZCASH_SWAP_1CLICK_JWT
  printf '\n'
  export ZCASH_SWAP_1CLICK_JWT

Quote validation env:
  ZCASH_SWAP_PROBE_AMOUNT
  ZCASH_SWAP_PROBE_DESTINATION
  ZCASH_SWAP_PROBE_REFUND

Optional quote env:
  ZCASH_SWAP_PROBE_DIRECTION  zec-to-external or external-to-zec; default zec-to-external
  ZCASH_SWAP_PROBE_ASSET      USDC, ETH, BTC, SOL, USDT, DAI, WBTC, NEAR, or DOGE; default USDC
  ZCASH_SWAP_PROBE_ASSET_ID   exact 1Click assetId from --tokens-only output; mutually exclusive with USDC-specific overrides
  ZCASH_SWAP_PROBE_DRY_RUN    true or false; default true. false only requests a real quote/deposit instruction; it does not send funds
  ZCASH_SWAP_PROBE_USDC_CHAIN eth, base, arb, or near; default probe/provider behavior is Ethereum USDC
  ZCASH_SWAP_PROBE_USDC_ASSET_ID exact 1Click assetId for USDC; mutually exclusive with chain

Optional provider env:
  ZCASH_SWAP_1CLICK_BASE_URL
  ZCASH_SWAP_1CLICK_REFERRAL

Optional status env:
  ZCASH_SWAP_PROBE_STATUS_DEPOSIT
  ZCASH_SWAP_PROBE_STATUS_MEMO

Examples:
  # Set ZCASH_SWAP_1CLICK_JWT in the environment first.
  ZCASH_SWAP_PROBE_DIRECTION=zec-to-external \
  ZCASH_SWAP_PROBE_AMOUNT=0.01 \
  ZCASH_SWAP_PROBE_DESTINATION=<external-recipient> \
  ZCASH_SWAP_PROBE_REFUND=<zec-refund-address> \
    scripts/e2e/swap-one-click-live-validation.sh

  # Set ZCASH_SWAP_1CLICK_JWT in the environment first.
  ZCASH_SWAP_PROBE_STATUS_DEPOSIT=<deposit-address> \
    scripts/e2e/swap-one-click-live-validation.sh
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
    echo "Then rerun scripts/e2e/swap-one-click-live-validation.sh."
  } >&2
  exit 64
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    if [[ "$name" == "ZCASH_SWAP_1CLICK_JWT" ]]; then
      fail_missing_jwt
    fi
    fail "Set $name."
  fi
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

tokens_only=0
if [[ "${1:-}" == "--tokens-only" ]]; then
  tokens_only=1
  shift
fi

if [[ "$#" -ne 0 ]]; then
  usage >&2
  fail "unexpected arguments: $*"
fi

if [[ "$tokens_only" == "1" ]]; then
  require_cmd fvm
  args=(
    tool/swap_one_click_probe.dart
    --tokens-only
  )
  if [[ -n "${ZCASH_SWAP_1CLICK_BASE_URL:-}" ]]; then
    args+=(--base-url "$ZCASH_SWAP_1CLICK_BASE_URL")
  fi
  echo "running 1Click token-list probe"
  fvm dart run "${args[@]}"
  exit
fi

require_env ZCASH_SWAP_1CLICK_JWT
require_cmd fvm

direction="${ZCASH_SWAP_PROBE_DIRECTION:-zec-to-external}"
asset="${ZCASH_SWAP_PROBE_ASSET:-USDC}"
status_deposit="${ZCASH_SWAP_PROBE_STATUS_DEPOSIT:-}"
quote_requested=0

if [[ -n "${ZCASH_SWAP_PROBE_AMOUNT:-}" ||
  -n "${ZCASH_SWAP_PROBE_DESTINATION:-}" ||
  -n "${ZCASH_SWAP_PROBE_REFUND:-}" ||
  -z "$status_deposit" ]]; then
  quote_requested=1
fi

args=(
  tool/swap_one_click_probe.dart
)

if [[ "$quote_requested" == "1" ]]; then
  require_env ZCASH_SWAP_PROBE_AMOUNT
  require_env ZCASH_SWAP_PROBE_DESTINATION
  require_env ZCASH_SWAP_PROBE_REFUND
  args+=(
    --direction "$direction"
    --asset "$asset"
    --amount "$ZCASH_SWAP_PROBE_AMOUNT"
    --destination "$ZCASH_SWAP_PROBE_DESTINATION"
    --refund "$ZCASH_SWAP_PROBE_REFUND"
  )
  if [[ -n "${ZCASH_SWAP_PROBE_DRY_RUN:-}" ]]; then
    args+=(--dry-run "$ZCASH_SWAP_PROBE_DRY_RUN")
  fi
  if [[ -n "${ZCASH_SWAP_PROBE_ASSET_ID:-}" ]]; then
    args+=(--asset-id "$ZCASH_SWAP_PROBE_ASSET_ID")
  fi
  if [[ -n "${ZCASH_SWAP_PROBE_USDC_CHAIN:-}" ]]; then
    args+=(--usdc-chain "$ZCASH_SWAP_PROBE_USDC_CHAIN")
  fi
  if [[ -n "${ZCASH_SWAP_PROBE_USDC_ASSET_ID:-}" ]]; then
    args+=(--usdc-asset-id "$ZCASH_SWAP_PROBE_USDC_ASSET_ID")
  fi
fi

if [[ -n "${ZCASH_SWAP_1CLICK_BASE_URL:-}" ]]; then
  args+=(--base-url "$ZCASH_SWAP_1CLICK_BASE_URL")
fi

if [[ -n "${ZCASH_SWAP_1CLICK_REFERRAL:-}" ]]; then
  args+=(--referral "$ZCASH_SWAP_1CLICK_REFERRAL")
fi

if [[ -n "$status_deposit" ]]; then
  args+=(--status-deposit "$status_deposit")
  if [[ -n "${ZCASH_SWAP_PROBE_STATUS_MEMO:-}" ]]; then
    args+=(--status-memo "$ZCASH_SWAP_PROBE_STATUS_MEMO")
  fi
fi

echo "running 1Click quote/status probe"
if [[ "$quote_requested" == "1" ]]; then
  echo "direction=$direction asset=$asset amount=$ZCASH_SWAP_PROBE_AMOUNT"
  echo "dry_run=${ZCASH_SWAP_PROBE_DRY_RUN:-true}"
  if [[ -n "${ZCASH_SWAP_PROBE_USDC_CHAIN:-}" ]]; then
    echo "usdc_chain=$ZCASH_SWAP_PROBE_USDC_CHAIN"
  fi
  if [[ -n "${ZCASH_SWAP_PROBE_ASSET_ID:-}" ]]; then
    echo "asset_id=custom"
  fi
  if [[ -n "${ZCASH_SWAP_PROBE_USDC_ASSET_ID:-}" ]]; then
    echo "usdc_asset_id=custom"
  fi
  echo "destination=$ZCASH_SWAP_PROBE_DESTINATION"
  echo "refund=$ZCASH_SWAP_PROBE_REFUND"
else
  echo "quote=skipped"
fi
if [[ -n "$status_deposit" ]]; then
  echo "status_deposit=$status_deposit"
fi

fvm dart run "${args[@]}"
