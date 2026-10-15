#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$ROOT_DIR/.regtest-logs"
LOG_FILE="$LOG_DIR/regtest-rust-tests.log"
SAPLING_PARAMS_DIR="${SAPLING_PARAMS_DIR:-$HOME/.zcash-params}"
SAPLING_SPEND_PATH="$SAPLING_PARAMS_DIR/sapling-spend.params"
SAPLING_OUTPUT_PATH="$SAPLING_PARAMS_DIR/sapling-output.params"
SAPLING_SPEND_HASH="a15ab54c2888880e53c823a3063820c728444126"
SAPLING_OUTPUT_HASH="0ebc5a1ef3653948e1c46cf7a16071eac4b7e352"
SAPLING_PARAM_BASE_URL="https://download.z.cash/downloads"
RUNNER_ARGS=()
SCENARIOS=()

usage() {
  cat <<'EOF'
Usage: ./run-regtest-rust-tests.sh [--keep] [SCENARIO...]

Runs the Rust regtest integration tests one at a time, each against its own
fresh Zakura node and lightwalletd (scripts/e2e/zakura-run.py). The test
executables are built once from the committed rust/ tree, so commit Rust
changes first. Streams the output to the terminal and saves a copy to:

  .regtest-logs/regtest-rust-tests.log

Each run also writes a JSON report and per-test logs under
.regtest-logs/zakura-<run id>/.

Select scenarios by ID or dotted prefix; the default is every Rust scenario:

  ./run-regtest-rust-tests.sh rust.import rust.send.basic

List them with `python3 scripts/e2e/zakura-run.py --list`.

Sapling proving params are cached outside the repository by default:

  ~/.zcash-params

Override with:

  SAPLING_PARAMS_DIR=/custom/path ./run-regtest-rust-tests.sh

Options:

  --keep    Keep the Zakura containers and wallet files of failed tests for
            debugging. Passing tests are always cleaned up.
EOF
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --keep)
      RUNNER_ARGS+=(--keep-failed)
      ;;
    -*)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 1
      ;;
    *)
      SCENARIOS+=("$arg")
      ;;
  esac
done
if [[ "${#SCENARIOS[@]}" -eq 0 ]]; then
  SCENARIOS=(rust)
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

echo "==> Ensuring Sapling params"
mkdir -p "$SAPLING_PARAMS_DIR"
ensure_param_file "$SAPLING_SPEND_PATH" "$SAPLING_SPEND_HASH" "$SAPLING_PARAM_BASE_URL/sapling-spend.params"
ensure_param_file "$SAPLING_OUTPUT_PATH" "$SAPLING_OUTPUT_HASH" "$SAPLING_PARAM_BASE_URL/sapling-output.params"
export REGTEST_SAPLING_PARAMS_DIR="$SAPLING_PARAMS_DIR"

echo "==> Running Rust regtest integration tests on Zakura regtest chains"
echo "==> Log file: $LOG_FILE"

set +e
python3 "$ROOT_DIR/scripts/e2e/zakura-run.py" ${RUNNER_ARGS[@]+"${RUNNER_ARGS[@]}"} "${SCENARIOS[@]}" 2>&1 | tee "$LOG_FILE"
test_status=${PIPESTATUS[0]}
set -e

echo
if [[ "$test_status" -eq 0 ]]; then
  echo "==> Regtest Rust integration tests passed"
else
  echo "==> Regtest Rust integration tests failed (exit $test_status)" >&2
fi
echo "==> Full log saved to $LOG_FILE"

exit "$test_status"
