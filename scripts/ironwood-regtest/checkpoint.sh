#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

action="${1:-}"
name="${2:-}"
if [[ "$action" != "save" && "$action" != "restore" ]] ||
  ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "usage: checkpoint.sh <save|restore> <name>" >&2
  exit 1
fi

archive="$SNAPSHOT_DIR/$name.tar.gz"
mkdir -p "$SNAPSHOT_DIR"

if [[ "$action" == "save" ]]; then
  wait_for_zcashd
  wait_for_lightwalletd
  compose stop
  trap 'compose start >/dev/null' EXIT
  tar -C "$ROOT_DIR" -czf "$archive" .ironwood-regtest
  echo "$archive"
  exit 0
fi

if [[ ! -f "$archive" ]]; then
  echo "checkpoint not found: $archive" >&2
  exit 1
fi
compose down --remove-orphans || true
rm -rf "$STATE_DIR"
tar -C "$ROOT_DIR" -xzf "$archive"
echo "restored $archive; run scripts/ironwood-regtest/up.sh"
