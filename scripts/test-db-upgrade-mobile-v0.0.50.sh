#!/usr/bin/env bash
# Released mobile baseline using the published Zakura rc7 wallet packages.
# These packages predate unknown-migration refusal; probe the old reader and
# report acceptance as an unsupported downgrade rather than passing a guard.
set -euo pipefail
export DB_UPGRADE_OLD_READER_MODE="${DB_UPGRADE_OLD_READER_MODE:-probe-old}"
exec "$(dirname "${BASH_SOURCE[0]}")/test-db-upgrade.sh" mobile/v0.0.50 "$@"
