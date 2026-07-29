#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
db_path="${1:-}"
interval="${MIGRATION_SIM_WATCH_INTERVAL_SECONDS:-5}"

if ! [[ "$interval" =~ ^[1-9][0-9]*$ ]]; then
  echo "MIGRATION_SIM_WATCH_INTERVAL_SECONDS must be a positive integer" >&2
  exit 1
fi

while true; do
  "$SCRIPT_DIR/inspect.sh" "$db_path" || true
  sleep "$interval"
done
