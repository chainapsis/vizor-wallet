#!/usr/bin/env bash
# Transparent history qualification suite (H01-H13).
#
# Builds one isolated Docker regtest chain (pinned zcashd + lightwalletd, its
# own ports and config; the shared scripts/regtest stack is never touched),
# runs every case through Vizor's Rust API, and checks the results against
# the independent oracle (scripts/e2e/transparent_history_oracle.py) under one
# expectation profile: public (lightwalletd discovery, the default) or private
# (PrivateRequired: transparent PIR recovery from an in-process service the
# harness publishes from the chain; debug builds only).
#
# Usage:
#   scripts/e2e/transparent-history-cases.sh                 # Rust layer, public
#   scripts/e2e/transparent-history-cases.sh --profile private
#   scripts/e2e/transparent-history-cases.sh --flutter desktop
#   scripts/e2e/transparent-history-cases.sh --flutter mobile
#   scripts/e2e/transparent-history-cases.sh --flutter both
#   scripts/e2e/transparent-history-cases.sh --profile private --flutter desktop
#
# Private app layer (desktop only): the Rust layer's test process hosts the
# transparent PIR service. After its gate it keeps serving the final
# publication on the same loopback origin, H13's faults cleared, and records
# the app's requests (pir-requests.json, "app") until the macOS layer is done.
#
# Env:
#   TH_PROFILE   public (default) or private; --profile overrides it.
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
PROFILE="${TH_PROFILE:-public}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --flutter)
      FLUTTER_LAYERS="$2"
      shift 2
      ;;
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,33p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

case "$PROFILE" in
  public | private) ;;
  *)
    echo "unknown profile: $PROFILE (public or private)" >&2
    exit 2
    ;;
esac
if [[ "$PROFILE" == "private" && -n "$FLUTTER_LAYERS" && "$FLUTTER_LAYERS" != "desktop" ]]; then
  # The private switches reach Rust through the app's environment, which the
  # macOS app inherits from flutter test and the simulator's app does not.
  echo "--profile private supports --flutter desktop only" >&2
  exit 2
fi
# The private app layer recovers from the Rust layer's transparent PIR
# service, so that process keeps running (in the background) while it does.
SERVE_TPIR=""
if [[ "$PROFILE" == "private" && -n "$FLUTTER_LAYERS" ]]; then
  SERVE_TPIR=1
fi

OUT="${TH_OUT_DIR:-$ROOT/rust/target/transparent-history-cases/run-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
export TH_OUT_DIR="$OUT"

HANDOFF_DIR=""
RUST_PID=""
cleanup() {
  if [[ -n "$RUST_PID" ]]; then
    # Stop the transparent PIR service and let the Rust layer record the
    # app's requests before the chain goes away.
    touch "$HANDOFF_DIR/tpir-stop" 2>/dev/null || true
    wait "$RUST_PID" 2>/dev/null || true
  fi
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

run_rust_layer() {
  cd "$ROOT/rust"
  # One profile per process: the private profile's switches are process-wide.
  cargo test --test transparent_history_cases -- --ignored --nocapture --test-threads=1 \
    --exact "${PROFILE}_profile_h01_to_h13"
}

echo "== Rust layer, $PROFILE profile (output: $OUT)"
rust_started=$(date +%s)
if [[ -n "$SERVE_TPIR" ]]; then
  # The Rust layer's status (its gate and privacy violations) arrives in
  # tpir-ready; the process's own, which adds the app layer's violations,
  # once the service stops.
  (run_rust_layer 2>&1 | tee "$OUT/rust.log") &
  RUST_PID=$!
  while [[ ! -f "$HANDOFF_DIR/tpir-ready" ]] && kill -0 "$RUST_PID" 2>/dev/null; do
    sleep 2
  done
  if [[ -f "$HANDOFF_DIR/tpir-ready" ]]; then
    rust_status="$(cat "$HANDOFF_DIR/tpir-ready")"
  else
    set +e
    wait "$RUST_PID"
    rust_status=$?
    set -e
    RUST_PID=""
  fi
else
  set +e
  (run_rust_layer) 2>&1 | tee "$OUT/rust.log"
  rust_status=${PIPESTATUS[0]}
  set -e
fi
echo "profile=$PROFILE rust_layer_seconds=$(( $(date +%s) - rust_started )) status=$rust_status" | tee -a "$OUT/runtime.txt"

if [[ -z "$FLUTTER_LAYERS" ]]; then
  exit "$rust_status"
fi

if [[ ! -f "$HANDOFF_DIR/handoff.env" ]]; then
  echo "Rust layer did not hand off a live chain; skipping Flutter layers" >&2
  exit 1
fi
if [[ -n "$SERVE_TPIR" && -z "$RUST_PID" ]]; then
  echo "Rust layer ended before serving transparent PIR; skipping Flutter layers" >&2
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

# The macOS app inherits flutter test's environment. As in the Rust layer,
# every ephemeral (TEX) address check is due on each sync, so a fresh restore
# finds TEX leg 2 without the daily schedule (debug builds only).
desktop_env=(ZCASH_E2E_EPHEMERAL_CHECKS_DUE_NOW=1)
desktop_defines=()
if [[ "$PROFILE" == "private" ]]; then
  if [[ -z "${TH_TPIR_URL:-}" ]]; then
    echo "Rust layer handed off no transparent PIR origin" >&2
    exit 1
  fi
  # Debug builds only, all default off: Rust's switch that lets regtest select
  # private recovery and reach the loopback service, and that service's
  # origin; the private recovery build flag; and the app's own allowance for
  # private queries on regtest.
  desktop_env+=(ZCASH_E2E_REGTEST_PRIVATE_TRANSPARENT=1 "VIZOR_TRANSPARENT_PIR_URL=$TH_TPIR_URL")
  desktop_defines+=(
    "--dart-define=ZCASH_PRIVATE_TRANSPARENT_RECOVERY=true"
    "--dart-define=ZCASH_E2E_PRIVATE_TRANSPARENT_REGTEST=true"
  )
fi

flutter_status=0
if [[ "$FLUTTER_LAYERS" == "desktop" || "$FLUTTER_LAYERS" == "both" ]]; then
  echo "== Flutter desktop layer, $PROFILE profile"
  started=$(date +%s)
  set +e
  (
    cd "$ROOT"
    env "${desktop_env[@]}" \
    fvm flutter test integration_test/regtest_transparent_history_cases_test.dart \
      -d macos \
      "${flutter_defines[@]}" \
      ${desktop_defines[@]+"${desktop_defines[@]}"} \
      "--dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true" \
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

if [[ -n "$RUST_PID" ]]; then
  touch "$HANDOFF_DIR/tpir-stop"
  set +e
  wait "$RUST_PID"
  rust_status=$?
  set -e
  RUST_PID=""
  echo "tpir_service_status=$rust_status" | tee -a "$OUT/runtime.txt"
fi

if [[ $rust_status -ne 0 ]]; then
  exit "$rust_status"
fi
exit "$flutter_status"
