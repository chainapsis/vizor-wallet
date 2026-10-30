#!/usr/bin/env bash
set -euo pipefail

# This released build uses upstream SQLite without the fork's unknown-migration
# guard. Probe what it does; do not claim that its writable downgrade is safe.
export DB_UPGRADE_OLD_READER_MODE="${DB_UPGRADE_OLD_READER_MODE:-probe-old}"
exec "$(dirname "${BASH_SOURCE[0]}")/test-db-upgrade.sh" mobile/v0.0.18 "$@"
