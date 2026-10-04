#!/usr/bin/env bash
# Upgrade probe: create wallets with the published build at <base-ref>, upgrade
# and verify them twice with the current tree. Writable downgrades are not qualified.
#
# Unsupported upgrade sources: builds pinned to wallet-libraries before #86
# (unreleased PR 783 builds such as 3442ab0c1) dropped transactions.zip318_kind,
# which the current library cannot restore. Upgrading their wallets is
# unsupported by design; their users restore from seed. For such a base the
# probe still creates the fixture with it and runs `verify` with the current
# build, requires `verify` to fail for exactly that reason, and skips the rest.
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
# An unsupported downgrade is still exercised, not skipped: the base build must
# fail to reopen the upgraded wallet for the documented cause
# (`DOWNGRADE_FAILURE`), and the current build must still open and verify the
# wallet afterwards. If the base starts reading the
# upgraded wallet, or fails for any other cause, the probe fails, so the
# exemption cannot outlive its reason.
DOWNGRADE_UNSUPPORTED=""
DOWNGRADE_FAILURE=""
case "$BASE_REF" in
  mobile/v0.0.18)
    DOWNGRADE_UNSUPPORTED="mobile/v0.0.18 predates wallet-libraries rc5, which \
replaced tx_retrieval_queue's unique key (txid); the upgrade does not keep \
it, so that build cannot use the upgraded wallet"
    # SQLite's error for an upsert whose unique key is gone: the base's
    # tx_retrieval_queue insert relies on the removed key.
    DOWNGRADE_FAILURE="ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint"
    # The schema objects the current build removes that this base needs; the
    # probe accepts exactly these as missing, and requires each to be missing.
    export VIZOR_DB_UPGRADE_DOWNGRADE_UNSUPPORTED="unique:tx_retrieval_queue(txid)"
    ;;
esac

# A base whose wallets cannot be upgraded at all, keyed on the resolved commit
# so it matches however the base is spelled. The upgrade is still exercised:
# `verify` must fail for the documented cause (`UPGRADE_FAILURE`, matched by
# both the probe's assertion and SQLite's own read error); a success or any
# other failure fails the probe, so the declaration cannot outlive its reason.
UPGRADE_UNSUPPORTED=""
UPGRADE_FAILURE="no such column: transactions.zip318_kind"
case "$(git -C "$ROOT_DIR" rev-parse "$BASE_REF^{commit}")" in
  3442ab0c144e4ffa162d421f4472bccace58d68b)
    UPGRADE_UNSUPPORTED="unreleased PR 783 build from before wallet-libraries \
#86 dropped transactions.zip318_kind; its wallets must be restored from seed"
    ;;
esac

for scenario in "${SCENARIOS[@]}"; do
  db_path="$TEMP_DIR/$scenario.db"
  manifest_path="$TEMP_DIR/$scenario.json"

  run_probe "$OLD_WORKTREE" create "$scenario" "$db_path" "$manifest_path"
  if [[ -n "$UPGRADE_UNSUPPORTED" ]]; then
    verify_log="$TEMP_DIR/$scenario.verify.log"
    if run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path" \
      >"$verify_log" 2>&1; then
      cat "$verify_log"
      echo "error: $BASE_REF declared unsupported but upgrade succeeded; drop" \
        "the declaration from $0" >&2
      exit 1
    fi
    if ! grep -qF "$UPGRADE_FAILURE" "$verify_log"; then
      cat "$verify_log"
      echo "error: upgrading $BASE_REF failed for a cause other than the" \
        "documented one ($UPGRADE_FAILURE)" >&2
      exit 1
    fi
    echo "upgrade from $BASE_REF ($scenario): refused as documented" \
      "($UPGRADE_FAILURE)"
    continue
  fi
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"
  run_probe "$ROOT_DIR" verify "$scenario" "$db_path" "$manifest_path"

done

if [[ -n "$UPGRADE_UNSUPPORTED" ]]; then
  echo "ok: $BASE_REF upgrade unsupported by design ($UPGRADE_UNSUPPORTED)"
elif [[ -n "$DOWNGRADE_UNSUPPORTED" ]]; then
  echo "ok: $BASE_REF database upgrade compatibility (downgrade unsupported by design)"
else
  echo "ok: $BASE_REF database upgrade compatibility"
fi
