#!/usr/bin/env bash
# Upgrade probe: create wallets with the build at <base-ref>, upgrade and verify
# them with the current tree, hand them back to the base build through the
# downgrade handover, let the base build read and write them (open-old, then
# read-old in a fresh process), and verify them
# with the current tree again (new -> old -> new).
#
# usage: scripts/test-db-upgrade.sh <base-ref> [scenario...]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <base-ref> [scenario...]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="$1"
shift
SCENARIOS=("$@")
if [[ ${#SCENARIOS[@]} -eq 0 ]]; then
  SCENARIOS=(single-derived multi-seed imported-only hardware-first)
fi
BASE_SLUG="$(printf '%s' "$BASE_REF" | tr -c 'A-Za-z0-9' '_')"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vizor-db-upgrade-$BASE_SLUG.XXXXXX")"
OLD_WORKTREE="$TEMP_DIR/base"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT_DIR/rust/target/db-upgrade-$BASE_SLUG}"
OLD_WORKTREE_ADDED=false

cleanup() {
  if [[ "$OLD_WORKTREE_ADDED" == true ]]; then
    git -C "$ROOT_DIR" worktree remove --force "$OLD_WORKTREE" >/dev/null 2>&1 || true
  fi
  find "$TEMP_DIR" -depth -mindepth 1 -delete 2>/dev/null || true
  rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

git -C "$ROOT_DIR" worktree add --detach "$OLD_WORKTREE" "$BASE_REF^{commit}"
OLD_WORKTREE_ADDED=true
EXAMPLES="$ROOT_DIR/rust/examples"
mkdir -p "$OLD_WORKTREE/rust/examples/db_upgrade"
cp "$EXAMPLES/db_upgrade.rs" "$OLD_WORKTREE/rust/examples/db_upgrade.rs"
# API that changed since the base lives in db_upgrade/compat.rs; a base can
# override it with db_upgrade/compat_<base>.rs.
COMPAT="$EXAMPLES/db_upgrade/compat_$BASE_SLUG.rs"
[[ -f "$COMPAT" ]] || COMPAT="$EXAMPLES/db_upgrade/compat.rs"
cp "$COMPAT" "$OLD_WORKTREE/rust/examples/db_upgrade/compat.rs"
# Checks only the current build can run are stubbed out in the base build.
cp "$EXAMPLES/db_upgrade/current_stub.rs" "$OLD_WORKTREE/rust/examples/db_upgrade/current.rs"

run_probe() {
  local worktree="$1"
  shift
  (
    cd "$worktree/rust"
    CARGO_TARGET_DIR="$TARGET_DIR" \
      cargo run --locked --quiet --example db_upgrade -- "$@"
  )
}

# Per-base capabilities. Every base supports every step unless it is listed
# here with the reason. The forward upgrade is always checked in full.
#
# An unsupported downgrade is still exercised, not skipped: the handover runs
# and checks its schema, the base build must then fail to reopen the wallet
# for the documented cause (`DOWNGRADE_FAILURE`), and the current build must
# still open and verify the wallet afterwards. If the base starts reading the
# handed-over wallet, or fails for any other cause, the probe fails, so the
# exemption cannot outlive its reason.
DOWNGRADE_UNSUPPORTED=""
DOWNGRADE_FAILURE=""
case "$BASE_REF" in
  mobile/v0.0.18)
    DOWNGRADE_UNSUPPORTED="mobile/v0.0.18 predates wallet-libraries rc5, which \
replaced tx_retrieval_queue's unique key (txid); the downgrade handover does \
not restore it, so that build cannot use the upgraded wallet"
    # SQLite's error for an upsert whose unique key is gone: the base's
    # tx_retrieval_queue insert relies on the removed key.
    DOWNGRADE_FAILURE="ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"
    # The schema objects the current build removes that this base needs; the
    # probe accepts exactly these as missing, and requires each to be missing.
    export VIZOR_DB_UPGRADE_DOWNGRADE_UNSUPPORTED="unique:tx_retrieval_queue(txid)"
    ;;
esac

for scenario in "${SCENARIOS[@]}"; do
  db_path="$TEMP_DIR/$scenario.db"
  manifest_path="$TEMP_DIR/$scenario.json"

  run_probe "$OLD_WORKTREE" create "$scenario" "$db_path" "$manifest_path"
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"
  run_probe "$ROOT_DIR" prepare-rollback "$scenario" "$db_path" "$manifest_path"
  if [[ -n "$DOWNGRADE_UNSUPPORTED" ]]; then
    echo "downgrade to $BASE_REF: unsupported: $DOWNGRADE_UNSUPPORTED"
    old_log="$TEMP_DIR/$scenario.open-old.log"
    if run_probe "$OLD_WORKTREE" open-old "$scenario" "$db_path" "$manifest_path" \
      >"$old_log" 2>&1; then
      cat "$old_log"
      echo "error: $BASE_REF now reopens the handed-over wallet; remove its" \
        "downgrade exemption from $0" >&2
      exit 1
    fi
    if ! grep -qF "$DOWNGRADE_FAILURE" "$old_log"; then
      cat "$old_log"
      echo "error: $BASE_REF failed to reopen the wallet for a cause other than" \
        "the documented one ($DOWNGRADE_FAILURE)" >&2
      exit 1
    fi
    echo "downgrade to $BASE_REF: refused as documented ($DOWNGRADE_FAILURE)"
  else
    run_probe "$OLD_WORKTREE" open-old "$scenario" "$db_path" "$manifest_path"
    run_probe "$OLD_WORKTREE" read-old "$scenario" "$db_path" "$manifest_path"
  fi
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"
done

if [[ -n "$DOWNGRADE_UNSUPPORTED" ]]; then
  echo "ok: $BASE_REF database upgrade compatibility (downgrade unsupported by design)"
else
  echo "ok: $BASE_REF database upgrade compatibility"
fi
