#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.zcash-nu7-regtest.yml"
STATE_DIR="$ROOT_DIR/.nu7-regtest"
HEIGHTS_FILE="$STATE_DIR/activation-heights"
if [[ -z "${NU7_REGTEST_NU63_HEIGHT:-}${NU7_REGTEST_NU7_HEIGHT:-}" && -f "$HEIGHTS_FILE" ]]; then
  read -r NU7_REGTEST_NU63_HEIGHT NU7_REGTEST_NU7_HEIGHT <"$HEIGHTS_FILE"
fi
NU7_REGTEST_NU63_HEIGHT="${NU7_REGTEST_NU63_HEIGHT:-300}"
NU7_REGTEST_NU7_HEIGHT="${NU7_REGTEST_NU7_HEIGHT:-600}"
NU7_REGTEST_RPC_PORT="${NU7_REGTEST_RPC_PORT:-48232}"
NU7_REGTEST_LIGHTWALLETD_PORT="${NU7_REGTEST_LIGHTWALLETD_PORT:-49067}"
LIGHTWALLETD_HOST="${LIGHTWALLETD_HOST:-127.0.0.1}"

export NU7_REGTEST_RPC_PORT NU7_REGTEST_LIGHTWALLETD_PORT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    return 1
  fi
}

validate_heights() {
  if ! [[ "$NU7_REGTEST_NU63_HEIGHT" =~ ^[0-9]+$ && "$NU7_REGTEST_NU7_HEIGHT" =~ ^[0-9]+$ ]] ||
    [[ "$NU7_REGTEST_NU63_HEIGHT" -lt 250 ]] ||
    [[ "$NU7_REGTEST_NU7_HEIGHT" -le "$NU7_REGTEST_NU63_HEIGHT" ]]; then
    echo "NU7_REGTEST_NU63_HEIGHT must be at least 250 and NU7_REGTEST_NU7_HEIGHT above it" >&2
    return 1
  fi
}

# A chain keeps the heights it was created with; reset before changing them.
pin_heights() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$HEIGHTS_FILE" ]]; then
    local pinned
    pinned="$(<"$HEIGHTS_FILE")"
    if [[ "$pinned" != "$NU7_REGTEST_NU63_HEIGHT $NU7_REGTEST_NU7_HEIGHT" ]]; then
      echo "existing chain pins NU6.3/NU7 at $pinned; reset before changing them" >&2
      return 1
    fi
  else
    printf '%s %s\n' "$NU7_REGTEST_NU63_HEIGHT" "$NU7_REGTEST_NU7_HEIGHT" >"$HEIGHTS_FILE"
  fi
  cat >"$STATE_DIR/zebrad.toml" <<TOML
[network]
network = "Regtest"
listen_addr = "127.0.0.1:0"

[network.testnet_parameters.activation_heights]
BeforeOverwinter = 1
Overwinter = 1
Sapling = 1
Blossom = 1
Heartwood = 1
Canopy = 1
NU5 = 1
NU6 = 1
"NU6.1" = 1
"NU6.2" = 1
"NU6.3" = $NU7_REGTEST_NU63_HEIGHT
NU7 = $NU7_REGTEST_NU7_HEIGHT

# Filler blocks pay a fixed transparent address; funding uses generatetoaddress.
[mining]
miner_address = "t27eWDgjFYJGVXmzrXeVjnb5J3uXDM9xH9v"

[rpc]
listen_addr = "0.0.0.0:18232"
enable_cookie_auth = false

[state]
cache_dir = "/var/cache/zebrad-cache"
TOML
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

# Usage: zebra_rpc METHOD [JSON_PARAMS_ARRAY]. Prints the JSON result.
zebra_rpc() {
  local method="$1" params="${2:-[]}" response
  response="$(curl -sS --max-time 60 -H 'content-type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$method\",\"params\":$params}" \
    "http://127.0.0.1:${NU7_REGTEST_RPC_PORT}")"
  python3 -c 'import json,sys
body = json.loads(sys.argv[1])
if body.get("error"):
    raise SystemExit("zebra rpc error: " + json.dumps(body["error"]))
print(json.dumps(body["result"]))' "$response"
}

current_height() {
  zebra_rpc getblockcount
}

wait_for_zebra() {
  for _ in $(seq 1 180); do
    if zebra_rpc getblockcount >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for Zebra RPC" >&2
  return 1
}

lightwalletd_tip_hash() {
  grpcurl -plaintext -import-path "$ROOT_DIR/protos" -proto service.proto -d '{}' \
    "${LIGHTWALLETD_HOST}:${NU7_REGTEST_LIGHTWALLETD_PORT}" \
    cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock 2>/dev/null |
    python3 -c 'import base64,json,sys
value = json.load(sys.stdin).get("hash", "")
print(base64.b64decode(value)[::-1].hex() if value else "")'
}

wait_for_lightwalletd() {
  require_command grpcurl
  for _ in $(seq 1 180); do
    if [[ -n "$(lightwalletd_tip_hash || true)" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for NU7 regtest lightwalletd" >&2
  return 1
}

# Waits until lightwalletd serves the node's tip, so a wallet sync sees it.
wait_for_lightwalletd_tip() {
  local target
  target="$(zebra_rpc getbestblockhash | tr -d '"')"
  for _ in $(seq 1 180); do
    if [[ "$(lightwalletd_tip_hash || true)" == "$target" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for lightwalletd tip $target" >&2
  return 1
}
