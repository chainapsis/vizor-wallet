#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG_REF='mobile/v0.0.18^{}'
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vizor-db-upgrade-mobile-v0.0.18.XXXXXX")"
OLD_WORKTREE="$TEMP_DIR/mobile-v0.0.18"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT_DIR/rust/target/db-upgrade-mobile-v0.0.18}"
OLD_WORKTREE_ADDED=false

cleanup() {
  if [[ "$OLD_WORKTREE_ADDED" == true ]]; then
    git -C "$ROOT_DIR" worktree remove --force "$OLD_WORKTREE" >/dev/null 2>&1 || true
  fi
  find "$TEMP_DIR" -depth -mindepth 1 -delete 2>/dev/null || true
  rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

git -C "$ROOT_DIR" worktree add --detach "$OLD_WORKTREE" "$TAG_REF"
OLD_WORKTREE_ADDED=true
cp "$ROOT_DIR/rust/examples/db_upgrade_mobile_v0_0_18.rs" \
  "$OLD_WORKTREE/rust/examples/db_upgrade_mobile_v0_0_18.rs"

run_probe() {
  local worktree="$1"
  shift
  (
    cd "$worktree/rust"
    CARGO_TARGET_DIR="$TARGET_DIR" \
      cargo run --locked --quiet --example db_upgrade_mobile_v0_0_18 -- "$@"
  )
}

for scenario in single-derived multi-seed imported-only; do
  db_path="$TEMP_DIR/$scenario.db"
  manifest_path="$TEMP_DIR/$scenario.json"

  run_probe "$OLD_WORKTREE" create "$scenario" "$db_path" "$manifest_path"
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"
  run_probe "$OLD_WORKTREE" open-old "$scenario" "$db_path" "$manifest_path"
done

echo "ok: mobile/v0.0.18 database upgrade compatibility"
