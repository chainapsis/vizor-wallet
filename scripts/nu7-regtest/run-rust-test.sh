#!/usr/bin/env bash
set -euo pipefail

# Runs the NU7 upgrade scenario on a fresh chain, then stops it. Pass --keep to
# leave the chain running for debugging.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
keep=false
[[ "${1:-}" == "--keep" ]] && keep=true

"$ROOT_DIR/scripts/nu7-regtest/reset.sh"
status=0
(cd "$ROOT_DIR/rust" &&
  cargo test --test nu7_regtest_upgrade -- --ignored --nocapture --test-threads=1) ||
  status=$?
if [[ "$keep" == false ]]; then
  "$ROOT_DIR/scripts/nu7-regtest/down.sh"
fi
exit "$status"
