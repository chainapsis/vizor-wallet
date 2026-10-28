#!/usr/bin/env bash
set -euo pipefail

# Runs each NU7 upgrade scenario on a fresh chain, then stops it. Pass --keep
# to leave the last chain running for debugging, and scenario names to run
# only those.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
keep=false
if [[ "${1:-}" == "--keep" ]]; then
  keep=true
  shift
fi
scenarios=("$@")
if [[ "${#scenarios[@]}" -eq 0 ]]; then
  scenarios=(
    migration_and_sends_cross_nu7_activation
    a_part_that_misses_the_upgrade_returns_its_input_when_the_run_stops
  )
fi

status=0
for scenario in "${scenarios[@]}"; do
  "$ROOT_DIR/scripts/nu7-regtest/reset.sh"
  (cd "$ROOT_DIR/rust" &&
    cargo test --test nu7_regtest_upgrade -- --ignored --nocapture --test-threads=1 \
      --exact "$scenario") || status=$?
done
if [[ "$keep" == false ]]; then
  "$ROOT_DIR/scripts/nu7-regtest/down.sh"
fi
exit "$status"
