#!/usr/bin/env bash
# Runs on Zakura regtest chains; see scripts/e2e/README.md.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/zakura-run.py" flutter.ios.ironwood-immediate-migration "$@"
