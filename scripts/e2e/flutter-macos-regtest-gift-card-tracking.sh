#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/e2e/lib-payment-link.sh"
cd "$ROOT_DIR"
export VIZOR_E2E_ARTIFACT_DIR="$ROOT_DIR/.regtest-logs/gift-card-tracking"
mkdir -p "$VIZOR_E2E_ARTIFACT_DIR"
exec > >(tee "$VIZOR_E2E_ARTIFACT_DIR/run.log") 2>&1
collect_tracking_screenshots() {
  python3 - "$VIZOR_E2E_ARTIFACT_DIR" <<'PYTHON'
from pathlib import Path
import shutil
import sys
root = Path(sys.argv[1])
for line in (root / 'run.log').read_text().splitlines():
    marker = '[gift-card-tracking-screenshot] '
    if marker not in line:
        continue
    source = Path(line.split(marker, 1)[1].strip())
    if source.parent.name == 'gift_card_tracking_e2e_screenshots' and source.suffix == '.png' and source.is_file():
        shutil.copy2(source, root / source.name)
PYTHON
}
trap collect_tracking_screenshots EXIT
start_payment_link_regtest
run_payment_link_phase integration_test/regtest_gift_card_tracking_prepare_test.dart
scripts/regtest/mine.sh 200 >/dev/null
run_payment_link_phase integration_test/regtest_gift_card_tracking_resume_test.dart
