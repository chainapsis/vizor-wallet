#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command docker
require_command curl
require_command grpcurl
require_command python3
validate_heights
pin_heights

compose up -d zebra lightwalletd
wait_for_zebra
wait_for_lightwalletd

tip="$(current_height)"
if [[ "$tip" -ge "$NU7_REGTEST_NU63_HEIGHT" ]]; then
  echo "existing chain is already at or past NU6.3; reset to start before the upgrades" >&2
  exit 1
fi

echo "NU7 regtest is ready at height $tip"
echo "NU6.3 activation height: $NU7_REGTEST_NU63_HEIGHT"
echo "NU7 activation height: $NU7_REGTEST_NU7_HEIGHT"
echo "lightwalletd: http://${LIGHTWALLETD_HOST}:${NU7_REGTEST_LIGHTWALLETD_PORT}"
