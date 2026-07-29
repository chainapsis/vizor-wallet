#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command docker
require_command grpcurl
require_command python3
validate_activation_height
pin_activation_height

mkdir -p "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
chmod 0777 "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"

compose up -d --build zcashd lightwalletd
wait_for_zcashd
wait_for_lightwalletd
ensure_faucet

tip="$(current_height)"
if [[ "$tip" -ge "$IRONWOOD_ACTIVATION_HEIGHT" ]]; then
  echo "existing chain is already at or past NU6.3 activation; reset or restore a pre-Ironwood snapshot" >&2
  exit 1
fi

echo "Ironwood regtest is ready at Orchard height $tip"
echo "NU6.3 activation height: $IRONWOOD_ACTIVATION_HEIGHT"
echo "lightwalletd: http://${LIGHTWALLETD_HOST}:${LIGHTWALLETD_PORT}"
