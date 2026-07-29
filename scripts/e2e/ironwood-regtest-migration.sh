#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export IRONWOOD_ACTIVATION_HEIGHT="${IRONWOOD_ACTIVATION_HEIGHT:-500}"

cd "$ROOT_DIR"
scripts/ironwood-regtest/reset.sh
scripts/ironwood-regtest/up.sh

cd rust
cargo test \
  --test ironwood_regtest_migration \
  orchard_funds_migrate_after_controlled_nu6_3_activation \
  -- --ignored --exact --nocapture
