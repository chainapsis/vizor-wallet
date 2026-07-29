#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.zcash-ironwood-regtest.yml"
STATE_DIR="$ROOT_DIR/.ironwood-regtest"
SNAPSHOT_DIR="$ROOT_DIR/.ironwood-regtest-snapshots"
ACTIVATION_FILE="$STATE_DIR/activation-height"
if [[ -z "${IRONWOOD_ACTIVATION_HEIGHT:-}" && -f "$ACTIVATION_FILE" ]]; then
  IRONWOOD_ACTIVATION_HEIGHT="$(<"$ACTIVATION_FILE")"
else
  IRONWOOD_ACTIVATION_HEIGHT="${IRONWOOD_ACTIVATION_HEIGHT:-500}"
fi
LIGHTWALLETD_HOST="${LIGHTWALLETD_HOST:-127.0.0.1}"
LIGHTWALLETD_PORT="${IRONWOOD_LIGHTWALLETD_PORT:-19067}"

export IRONWOOD_ACTIVATION_HEIGHT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    return 1
  fi
}

validate_activation_height() {
  if ! [[ "$IRONWOOD_ACTIVATION_HEIGHT" =~ ^[0-9]+$ ]] ||
    [[ "$IRONWOOD_ACTIVATION_HEIGHT" -lt 150 ]]; then
    echo "IRONWOOD_ACTIVATION_HEIGHT must be an integer at least 150" >&2
    return 1
  fi
}

pin_activation_height() {
  if [[ -f "$ACTIVATION_FILE" ]]; then
    local pinned
    pinned="$(<"$ACTIVATION_FILE")"
    if [[ "$pinned" != "$IRONWOOD_ACTIVATION_HEIGHT" ]]; then
      echo "existing chain pins NU6.3 at height $pinned, not $IRONWOOD_ACTIVATION_HEIGHT; reset before changing it" >&2
      return 1
    fi
    return 0
  fi
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$IRONWOOD_ACTIVATION_HEIGHT" >"$ACTIVATION_FILE"
}

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

zcash_cli() {
  compose exec -T zcashd zcash-cli -conf=/etc/zcash/zcash.conf "$@"
}

current_height() {
  zcash_cli getblockcount
}

wait_for_zcashd() {
  for _ in $(seq 1 180); do
    if zcash_cli getblockcount >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for Ironwood zcashd RPC" >&2
  return 1
}

wait_for_lightwalletd() {
  require_command grpcurl
  for _ in $(seq 1 180); do
    if grpcurl \
      -plaintext \
      -import-path "$ROOT_DIR/protos" \
      -proto service.proto \
      -d '{}' \
      "${LIGHTWALLETD_HOST}:${LIGHTWALLETD_PORT}" \
      cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for Ironwood lightwalletd" >&2
  return 1
}

lightwalletd_tip_height() {
  grpcurl \
    -plaintext \
    -import-path "$ROOT_DIR/protos" \
    -proto service.proto \
    -d '{}' \
    "${LIGHTWALLETD_HOST}:${LIGHTWALLETD_PORT}" \
    cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("height", 0))'
}

lightwalletd_tip_hash() {
  grpcurl \
    -plaintext \
    -import-path "$ROOT_DIR/protos" \
    -proto service.proto \
    -d '{}' \
    "${LIGHTWALLETD_HOST}:${LIGHTWALLETD_PORT}" \
    cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock 2>/dev/null |
    python3 -c 'import base64,json,sys
value = json.load(sys.stdin).get("hash", "")
raw = base64.b64decode(value) if value else b""
print(raw[::-1].hex())'
}

wait_for_lightwalletd_tip() {
  local target_height="$1"
  for _ in $(seq 1 180); do
    local tip
    tip="$(lightwalletd_tip_height 2>/dev/null || true)"
    if [[ "$tip" =~ ^[0-9]+$ ]] && [[ "$tip" -ge "$target_height" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for lightwalletd to reach height $target_height" >&2
  return 1
}

wait_for_lightwalletd_tip_hash() {
  local target_hash="$1"
  for _ in $(seq 1 180); do
    local tip_hash
    tip_hash="$(lightwalletd_tip_hash 2>/dev/null || true)"
    if [[ "$tip_hash" == "$target_hash" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for lightwalletd tip hash $target_hash" >&2
  return 1
}

wait_for_operation() {
  local opid="$1"
  for _ in $(seq 1 180); do
    local raw status=0
    raw="$(zcash_cli z_getoperationresult "[\"$opid\"]")"
    python3 - "$raw" <<'PY' || status=$?
import json
import sys

data = json.loads(sys.argv[1])
if not data:
    raise SystemExit(3)
entry = data[0]
if entry.get("status") != "success":
    error = entry.get("error", {})
    raise SystemExit(error.get("message") or f"operation failed: {entry}")
print(entry.get("result", {}).get("txid", ""))
PY
    if [[ "$status" -eq 3 ]]; then
      sleep 1
      continue
    fi
    return "$status"
  done
  echo "timed out waiting for operation $opid" >&2
  return 1
}

wait_for_spendable_shielded_note() {
  local address="$1"
  for _ in $(seq 1 180); do
    local notes
    notes="$(zcash_cli z_listunspent 1 9999999 true)"
    if python3 - "$address" "$notes" <<'PY'
import json
import sys

address = sys.argv[1]
if not any(
    note.get("address") == address and note.get("spendable")
    for note in json.loads(sys.argv[2])
):
    raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for shielded note at $address" >&2
  return 1
}

extract_opid() {
  python3 - "$1" <<'PY'
import json
import sys

raw = sys.argv[1].strip()
if raw.startswith("opid-"):
    print(raw)
    raise SystemExit(0)
value = json.loads(raw)
print(value if isinstance(value, str) else value["opid"])
PY
}

faucet_sender() {
  zcash_cli listunspent 1 9999999 '[]' false |
    python3 -c 'import json,sys
for item in json.load(sys.stdin):
    if item.get("generated") and item.get("spendable") and int(item.get("amountZat", 0)) >= 625000000:
        print(item["address"])
        raise SystemExit(0)
raise SystemExit("no mature coinbase UTXO available")'
}

ensure_faucet() {
  if faucet_sender >/dev/null 2>&1; then
    return 0
  fi
  zcash_cli generate 110 >/dev/null
  wait_for_lightwalletd_tip "$(current_height)"
  faucet_sender >/dev/null
}

assert_pre_ironwood_room() {
  local blocks_needed="$1"
  local tip
  tip="$(current_height)"
  if [[ $((tip + blocks_needed)) -ge "$IRONWOOD_ACTIVATION_HEIGHT" ]]; then
    echo "operation would cross NU6.3 activation at height $IRONWOOD_ACTIVATION_HEIGHT (tip=$tip, blocks=$blocks_needed)" >&2
    return 1
  fi
}
