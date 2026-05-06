#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.zcash-regtest.yml"
STATE_DIR="$ROOT_DIR/.regtest"
INITIALIZED_FILE="$STATE_DIR/initialized"
LIGHTWALLETD_HOST="${LIGHTWALLETD_HOST:-127.0.0.1}"
LIGHTWALLETD_PORT="${LIGHTWALLETD_PORT:-9067}"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

zcash_cli() {
  compose exec -T zcashd zcash-cli -conf=/etc/zcash/zcash.conf "$@"
}

wait_for_zcashd() {
  for _ in $(seq 1 120); do
    if zcash_cli getblockcount >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for zcashd RPC" >&2
  return 1
}

wait_for_wallet_ready() {
  for _ in $(seq 1 120); do
    if zcash_cli getwalletinfo >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for zcashd wallet readiness" >&2
  return 1
}

wait_for_wallet_spend_ready() {
  for _ in $(seq 1 120); do
    if zcash_cli listunspent 1 9999999 "[]" false >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for zcashd wallet spend readiness" >&2
  return 1
}

wait_for_lightwalletd() {
  if command -v grpcurl >/dev/null 2>&1; then
    for _ in $(seq 1 120); do
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
    echo "Timed out waiting for lightwalletd gRPC readiness" >&2
    return 1
  fi

  for _ in $(seq 1 120); do
    if python3 - "$LIGHTWALLETD_HOST" "$LIGHTWALLETD_PORT" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])
try:
    with socket.create_connection((host, port), timeout=1):
        pass
except OSError:
    raise SystemExit(1)
PY
    then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for lightwalletd gRPC port" >&2
  return 1
}

lightwalletd_tip_height() {
  local raw
  raw="$(
    grpcurl \
    -plaintext \
    -import-path "$ROOT_DIR/protos" \
    -proto service.proto \
    -d '{}' \
    "${LIGHTWALLETD_HOST}:${LIGHTWALLETD_PORT}" \
    cash.z.wallet.sdk.rpc.CompactTxStreamer/GetLatestBlock \
    2>/dev/null
  )"
  python3 - "$raw" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
print(data.get("height", 0))
PY
}

wait_for_lightwalletd_tip() {
  local target_height="$1"

  if ! command -v grpcurl >/dev/null 2>&1; then
    sleep 2
    return 0
  fi

  for _ in $(seq 1 120); do
    local current_height
    current_height="$(lightwalletd_tip_height)" || {
      sleep 1
      continue
    }
    if [[ "$current_height" -ge "$target_height" ]]; then
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for lightwalletd to reach height $target_height" >&2
  return 1
}

wait_for_operation() {
  local opid="$1"

  for _ in $(seq 1 120); do
    local raw
    raw="$(zcash_cli z_getoperationresult "[\"$opid\"]")"
    local status=0
    local txid=""
    txid="$(
      python3 - "$raw" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])
if not data:
    raise SystemExit(3)
entry = data[0]
status = entry.get("status")
if status != "success":
    error = entry.get("error", {})
    message = error.get("message") or entry.get("result", {}).get("error")
    print(message or f"operation failed with status={status}", file=sys.stderr)
    raise SystemExit(2)
result = entry.get("result", {})
print(result.get("txid", ""))
PY
    )" || status=$?
    if [[ "$status" -eq 3 ]]; then
      sleep 1
      continue
    fi
    if [[ "$status" -ne 0 ]]; then
      return "$status"
    fi
    echo "$txid"
    return 0
  done

  echo "Timed out waiting for operation $opid" >&2
  return 1
}

wait_for_zaddr_balance() {
  local address="$1"
  local amount="$2"

  for _ in $(seq 1 60); do
    local utxos
    utxos="$(zcash_cli z_listunspent 1 9999999 false "[\"$address\"]")"
    if python3 - "$utxos" "$amount" <<'PY'
from decimal import Decimal
import json
import sys

utxos = json.loads(sys.argv[1])
balance = Decimal("0")
for utxo in utxos:
    if "amountZat" in utxo:
        balance += Decimal(int(utxo["amountZat"])) / Decimal(100_000_000)
    else:
        balance += Decimal(str(utxo.get("amount", "0")))
amount = Decimal(sys.argv[2])
raise SystemExit(0 if balance >= amount else 1)
PY
    then
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for shielded faucet balance at $address" >&2
  return 1
}

extract_opid() {
  python3 - "$1" <<'PY'
import json
import sys

raw = sys.argv[1].strip()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    if raw:
        print(raw)
        raise SystemExit(0)
    raise
if isinstance(data, str):
    print(data)
elif isinstance(data, dict):
    print(data["opid"])
else:
    raise SystemExit("Unsupported operation response shape")
PY
}

faucet_coinbase_ready() {
  local raw
  raw="$(zcash_cli listunspent 1 9999999 "[]" false 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    return 1
  fi
  python3 - "$raw" <<'PY'
import json
import sys

utxos = json.loads(sys.argv[1])
for utxo in utxos:
    if utxo.get("generated") and utxo.get("spendable") and int(utxo.get("amountZat", 0)) >= 625000000:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

faucet_transparent_sender() {
  local raw
  raw="$(zcash_cli listunspent 1 9999999 "[]" false)"
  python3 - "$raw" <<'PY'
import json
import sys

utxos = json.loads(sys.argv[1])
for utxo in utxos:
    if utxo.get("generated") and utxo.get("spendable") and int(utxo.get("amountZat", 0)) >= 625000000:
        print(utxo["address"])
        raise SystemExit(0)
raise SystemExit("No mature coinbase UTXO available")
PY
}

ensure_faucet_state() {
  mkdir -p "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
  chmod 0777 "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"

  if faucet_coinbase_ready; then
    touch "$INITIALIZED_FILE"
    return 0
  fi

  zcash_cli generate 110 >/dev/null
  wait_for_wallet_spend_ready
  faucet_coinbase_ready
  touch "$INITIALIZED_FILE"
}
