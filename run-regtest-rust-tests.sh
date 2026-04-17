#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/.regtest"
LOG_FILE="$LOG_DIR/regtest-rust-tests.log"
SAPLING_PARAMS_DIR="$LOG_DIR/sapling_params"
SAPLING_SPEND_PATH="$SAPLING_PARAMS_DIR/sapling-spend.params"
SAPLING_OUTPUT_PATH="$SAPLING_PARAMS_DIR/sapling-output.params"
SAPLING_SPEND_HASH="a15ab54c2888880e53c823a3063820c728444126"
SAPLING_OUTPUT_HASH="0ebc5a1ef3653948e1c46cf7a16071eac4b7e352"
SAPLING_PARAM_BASE_URL="https://download.z.cash/downloads"

usage() {
  cat <<'EOF'
Usage: ./run-regtest-rust-tests.sh

Resets the local zcashd/lightwalletd regtest state, starts a fresh regtest stack,
runs the Rust regtest integration tests, streams the full output to the terminal,
and saves a copy to:

  .regtest/regtest-rust-tests.log
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  usage >&2
  exit 1
fi

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

echo "==> Resetting regtest services and state"
"$ROOT_DIR/scripts/regtest/down.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/regtest/reset.sh"

echo "==> Ensuring Sapling params"
mkdir -p "$SAPLING_PARAMS_DIR"
ensure_param_file "$SAPLING_SPEND_PATH" "$SAPLING_SPEND_HASH" "$SAPLING_PARAM_BASE_URL/sapling-spend.params"
ensure_param_file "$SAPLING_OUTPUT_PATH" "$SAPLING_OUTPUT_HASH" "$SAPLING_PARAM_BASE_URL/sapling-output.params"

echo "==> Starting fresh regtest services"
"$ROOT_DIR/scripts/regtest/up.sh"

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
  cargo test --test regtest_wallet_flow -- --ignored --nocapture
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
