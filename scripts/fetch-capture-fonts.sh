#!/usr/bin/env bash
# Compatibility entry point. Captures now load the shipped UI subsets, so no
# separate capture font installation is needed. Update subsets if stale.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 tool/l10n/ui_fonts.py
