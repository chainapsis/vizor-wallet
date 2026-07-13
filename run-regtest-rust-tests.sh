#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$ROOT_DIR/.regtest"
LOG_DIR="$ROOT_DIR/.regtest-logs"
LOG_FILE="$LOG_DIR/regtest-rust-tests.log"
SAPLING_PARAMS_DIR="${SAPLING_PARAMS_DIR:-$HOME/.zcash-params}"
SAPLING_SPEND_PATH="$SAPLING_PARAMS_DIR/sapling-spend.params"
SAPLING_OUTPUT_PATH="$SAPLING_PARAMS_DIR/sapling-output.params"
SAPLING_SPEND_HASH="a15ab54c2888880e53c823a3063820c728444126"
SAPLING_OUTPUT_HASH="0ebc5a1ef3653948e1c46cf7a16071eac4b7e352"
SAPLING_PARAM_BASE_URL="https://download.z.cash/downloads"
KEEP_STATE=0

usage() {
  cat <<'EOF'
Usage: ./run-regtest-rust-tests.sh [--keep]

Resets the local zcashd/lightwalletd regtest state, starts a fresh regtest stack,
runs the Rust regtest integration tests, streams the full output to the terminal,
and saves a copy to:

  .regtest-logs/regtest-rust-tests.log

Sapling proving params are cached outside .regtest by default:

  ~/.zcash-params

Override with:

  SAPLING_PARAMS_DIR=/custom/path ./run-regtest-rust-tests.sh

Prerequisites:

  grpcurl    Required for deterministic same-height reorg tests.

Options:

  --keep    Skip the final down/reset cleanup so the regtest state stays
            available for debugging after the run.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for arg in "$@"; do
  case "$arg" in
    --keep)
      KEEP_STATE=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# The full suite includes same-height reorg scenarios. A TCP or height-only
# readiness check cannot distinguish the old lightwalletd tip from its
# same-height replacement, so fail before resetting any existing regtest state
# when the hash-capable gRPC probe is unavailable.
if ! command -v grpcurl >/dev/null 2>&1; then
  echo "grpcurl is required to run the full Rust regtest suite (same-height reorg verification)." >&2
  echo "Install grpcurl and retry, or run an individual non-reorg test target manually." >&2
  exit 1
fi

cleanup() {
  if [[ "$KEEP_STATE" -eq 1 ]]; then
    echo "==> Keeping regtest services and state for debugging"
    return 0
  fi

  echo "==> Cleaning up regtest services and state"
  "$ROOT_DIR/scripts/regtest/down.sh" >/dev/null 2>&1 || true
  "$ROOT_DIR/scripts/regtest/reset.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$LOG_DIR"

sha1_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "$1" | awk '{print $1}'
  elif command -v sha1sum >/dev/null 2>&1; then
    sha1sum "$1" | awk '{print $1}'
  else
    openssl sha1 "$1" | awk '{print $2}'
  fi
}

ensure_param_file() {
  local path="$1"
  local expected_hash="$2"
  local url="$3"

  if [[ -f "$path" ]] && [[ "$(sha1_file "$path")" == "$expected_hash" ]]; then
    return 0
  fi

  rm -f "$path"
  echo "==> Downloading $(basename "$path")"
  curl -fL "$url" -o "$path"

  local actual_hash
  actual_hash="$(sha1_file "$path")"
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    echo "SHA-1 mismatch for $path: expected $expected_hash, got $actual_hash" >&2
    exit 1
  fi
}

start_regtest_services() {
  local attempt
  for attempt in 1 2; do
    if "$ROOT_DIR/scripts/regtest/up.sh"; then
      return 0
    fi

    if [[ "$attempt" -eq 2 ]]; then
      return 1
    fi

    echo "==> regtest startup failed; retrying once with a clean reset" >&2
    "$ROOT_DIR/scripts/regtest/down.sh" >/dev/null 2>&1 || true
    "$ROOT_DIR/scripts/regtest/reset.sh" >/dev/null 2>&1 || true
    mkdir -p "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
    chmod 0777 "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
  done
}

echo "==> Resetting regtest services and state"
"$ROOT_DIR/scripts/regtest/down.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/regtest/reset.sh"
mkdir -p "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
chmod 0777 "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"

echo "==> Ensuring Sapling params"
mkdir -p "$SAPLING_PARAMS_DIR"
ensure_param_file "$SAPLING_SPEND_PATH" "$SAPLING_SPEND_HASH" "$SAPLING_PARAM_BASE_URL/sapling-spend.params"
ensure_param_file "$SAPLING_OUTPUT_PATH" "$SAPLING_OUTPUT_HASH" "$SAPLING_PARAM_BASE_URL/sapling-output.params"

echo "==> Starting fresh regtest services"
start_regtest_services

echo "==> Running Rust regtest integration tests"
echo "==> Log file: $LOG_FILE"

(
  cd "$ROOT_DIR/rust"
  export REGTEST_SAPLING_PARAMS_DIR="$SAPLING_PARAMS_DIR"
  if [[ -n "${RUSTFLAGS:-}" ]]; then
    export RUSTFLAGS="$RUSTFLAGS -Awarnings"
  else
    export RUSTFLAGS="-Awarnings"
  fi
  for test_target in \
    regtest_receive_sync \
    regtest_send \
    regtest_import \
    regtest_multi_account \
    regtest_reorg
  do
    cargo test --test "$test_target" -- --ignored --nocapture --test-threads=1
  done
) 2>&1 | tee "$LOG_FILE"
test_status=${PIPESTATUS[0]}

echo
if [[ "$test_status" -eq 0 ]]; then
  echo "==> Regtest Rust integration tests passed"
else
  echo "==> Regtest Rust integration tests failed (exit $test_status)" >&2
fi
echo "==> Full log saved to $LOG_FILE"

exit "$test_status"
