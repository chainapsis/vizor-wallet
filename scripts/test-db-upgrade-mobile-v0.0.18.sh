#!/usr/bin/env bash
set -euo pipefail

exec "$(dirname "${BASH_SOURCE[0]}")/test-db-upgrade.sh" mobile/v0.0.18 "$@"
