#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Funds Orchard on a fresh Zakura regtest chain, then activates NU6.3 at 500.
exec "$ROOT_DIR/run-regtest-rust-tests.sh" rust.ironwood.migration "$@"
