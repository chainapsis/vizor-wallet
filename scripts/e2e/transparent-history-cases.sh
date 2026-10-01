#!/usr/bin/env bash
# Transparent history qualification suite (H01-H13), public profile.
#
# Builds one isolated Docker regtest chain (pinned zcashd + lightwalletd, its
# own ports and config; the shared scripts/regtest stack is never touched),
# runs every case through Vizor's Rust API, and checks the results against
# the independent oracle (scripts/e2e/transparent_history_oracle.py).
#
# Usage:
#   scripts/e2e/transparent-history-cases.sh                 # Rust layer
#   scripts/e2e/transparent-history-cases.sh --flutter desktop
#   scripts/e2e/transparent-history-cases.sh --flutter mobile
#   scripts/e2e/transparent-history-cases.sh --flutter both
#
# Env:
#   TH_OUT_DIR   output directory (default rust/target/transparent-history-cases/run-<ts>)
#   TH_CASES     comma list for development runs; anything short of H01-H13
#                fails the gate by design.
#   VIZOR_E2E_HIDDEN_WINDOW  macOS window hidden by default (true).
#
# Wallet keys are generated at runtime. Mnemonics reach Flutter only as
# --dart-define values read from a 0600 handoff file that is deleted as soon
# as it is read; no fixture or output file contains them.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLUTTER_LAYERS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --flutter)
      FLUTTER_LAYERS="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,25p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

OUT="${TH_OUT_DIR:-$ROOT/rust/target/transparent-history-cases/run-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
export TH_OUT_DIR="$OUT"

HANDOFF_DIR=""
cleanup() {
  if [[ -n "$HANDOFF_DIR" ]]; then
    rm -rf "$HANDOFF_DIR"
  fi
  if [[ -f "$OUT/chain.env" ]]; then
    # shellcheck disable=SC1091
    source "$OUT/chain.env"
    docker rm -f "${TH_CHAIN_LWD:-}" "${TH_CHAIN_NODE:-}" >/dev/null 2>&1 || true
    # A kept chain's data directory outlives the Rust layer; remove it too.
    if [[ "${TH_CHAIN_DIR:-}" == /tmp/vizor-th-chain-* ]]; then
      rm -rf "$TH_CHAIN_DIR" 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

if [[ -n "$FLUTTER_LAYERS" ]]; then
  HANDOFF_DIR="$(mktemp -d)"
  chmod 700 "$HANDOFF_DIR"
  export TH_KEEP_CHAIN=1
  export TH_FLUTTER_HANDOFF_DIR="$HANDOFF_DIR"
fi

echo "== Rust layer (output: $OUT)"
rust_started=$(date +%s)
set +e
(
  cd "$ROOT/rust"
  cargo test --test transparent_history_cases -- --ignored --nocapture --test-threads=1
) 2>&1 | tee "$OUT/rust.log"
rust_status=${PIPESTATUS[0]}
set -e
echo "rust_layer_seconds=$(( $(date +%s) - rust_started )) status=$rust_status" | tee -a "$OUT/runtime.txt"

if [[ -z "$FLUTTER_LAYERS" ]]; then
  exit "$rust_status"
fi

if [[ ! -f "$HANDOFF_DIR/handoff.env" ]]; then
  echo "Rust layer did not hand off a live chain; skipping Flutter layers" >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$HANDOFF_DIR/handoff.env"
rm -f "$HANDOFF_DIR/handoff.env"

flutter_defines=(
  "--dart-define=ZCASH_DEFAULT_NETWORK=regtest"
  "--dart-define=ZCASH_E2E_LIGHTWALLETD_URL=$TH_LWD_URL"
  "--dart-define=ZCASH_E2E_ZCASHD_RPC_URL=$TH_RPC_URL"
  "--dart-define=TH_A0_MNEMONIC=$TH_A0_MNEMONIC"
  "--dart-define=TH_A1_MNEMONIC=$TH_A1_MNEMONIC"
  "--dart-define=TH_EXPECTED_UI=$TH_EXPECTED_UI"
)

flutter_status=0
if [[ "$FLUTTER_LAYERS" == "desktop" || "$FLUTTER_LAYERS" == "both" ]]; then
  echo "== Flutter desktop layer"
  started=$(date +%s)
  set +e
  (
    cd "$ROOT"
    fvm flutter test integration_test/regtest_transparent_history_cases_test.dart \
      -d macos \
      "${flutter_defines[@]}" \
      "--dart-define=VIZOR_E2E_HIDDEN_WINDOW=${VIZOR_E2E_HIDDEN_WINDOW:-true}"
  ) 2>&1 | tee "$OUT/flutter-desktop.log"
  status=${PIPESTATUS[0]}
  set -e
  echo "flutter_desktop_seconds=$(( $(date +%s) - started )) status=$status" | tee -a "$OUT/runtime.txt"
  [[ $status -eq 0 ]] || flutter_status=$status
fi

if [[ "$FLUTTER_LAYERS" == "mobile" || "$FLUTTER_LAYERS" == "both" ]]; then
  echo "== Flutter mobile layer"
  # shellcheck disable=SC1091
  source "$ROOT/scripts/e2e/lib-mobile.sh"
  UDID="$(pick_simulator)"
  started=$(date +%s)
  set +e
  (
    cd "$ROOT"
    E2E_LIGHTWALLETD_URL="$TH_LWD_URL" run_mobile_e2e \
      integration_test/regtest_mobile_transparent_history_cases_test.dart "$UDID" \
      "--dart-define=ZCASH_E2E_ZCASHD_RPC_URL=$TH_RPC_URL" \
      "--dart-define=TH_A0_MNEMONIC=$TH_A0_MNEMONIC" \
      "--dart-define=TH_A1_MNEMONIC=$TH_A1_MNEMONIC" \
      "--dart-define=TH_EXPECTED_UI=$TH_EXPECTED_UI"
  ) 2>&1 | tee "$OUT/flutter-mobile.log"
  status=${PIPESTATUS[0]}
  set -e
  echo "flutter_mobile_seconds=$(( $(date +%s) - started )) status=$status" | tee -a "$OUT/runtime.txt"
  [[ $status -eq 0 ]] || flutter_status=$status
fi

if [[ $rust_status -ne 0 ]]; then
  exit "$rust_status"
fi
exit "$flutter_status"
