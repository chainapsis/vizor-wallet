#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${REGTEST_COMPOSE_FILE:-$ROOT_DIR/docker-compose.zcash-regtest.yml}"
STATE_DIR="$ROOT_DIR/.regtest"
INITIALIZED_FILE="$STATE_DIR/initialized"
RUNTIME_FINGERPRINT_FILE="$STATE_DIR/runtime-fingerprint"
REGTEST_PRESERVE_STATE="${REGTEST_PRESERVE_STATE:-0}"
REGTEST_STARTUP_TIMEOUT_SECONDS="${REGTEST_STARTUP_TIMEOUT_SECONDS:-60}"
LIGHTWALLETD_HOST="${LIGHTWALLETD_HOST:-127.0.0.1}"
LIGHTWALLETD_PORT="${LIGHTWALLETD_PORT:-9067}"

compose() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

zcash_cli() {
  compose exec -T zcashd zcash-cli -conf=/etc/zcash/zcash.conf "$@"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "Neither shasum nor sha256sum is available" >&2
    return 1
  fi
}

regtest_runtime_fingerprint() {
  local input
  input="$(
    for file in \
      "$COMPOSE_FILE" \
      "$ROOT_DIR/scripts/regtest/zcash.conf" \
      "$ROOT_DIR/scripts/regtest/lightwalletd-zcash.conf"; do
      sha256_file "$file"
    done
  )"

  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$input" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$input" | sha256sum | awk '{print $1}'
  fi
}

prepare_compatible_regtest_state() {
  local expected_fingerprint existing_fingerprint=""
  if [[ -z "$STATE_DIR" || "$STATE_DIR" == "/" || "$STATE_DIR" == "$ROOT_DIR" ]]; then
    echo "Refusing unsafe regtest state directory: $STATE_DIR" >&2
    return 1
  fi
  expected_fingerprint="$(regtest_runtime_fingerprint)"

  if [[ -f "$RUNTIME_FINGERPRINT_FILE" ]]; then
    existing_fingerprint="$(tr -d '[:space:]' <"$RUNTIME_FINGERPRINT_FILE")"
  fi

  local has_state=0
  if [[ -d "$STATE_DIR" ]] && [[ -n "$(find "$STATE_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
    has_state=1
  fi

  if [[ "$has_state" -eq 1 ]] && [[ "$existing_fingerprint" != "$expected_fingerprint" ]]; then
    if [[ "$REGTEST_PRESERVE_STATE" == "1" ]]; then
      echo "Regtest runtime changed while REGTEST_PRESERVE_STATE=1." >&2
      echo "Refusing to reuse an incompatible datadir; run scripts/regtest/reset.sh." >&2
      return 1
    fi

    echo "Regtest runtime changed; resetting disposable state instead of reindexing."
    compose down -v --remove-orphans >/dev/null 2>&1 || true
    rm -rf "$STATE_DIR"
  fi

  mkdir -p "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
  chmod 0777 "$STATE_DIR/zcashd" "$STATE_DIR/lightwalletd"
  printf '%s\n' "$expected_fingerprint" >"$RUNTIME_FINGERPRINT_FILE"
}

wait_for_zcashd() {
  local deadline=$((SECONDS + REGTEST_STARTUP_TIMEOUT_SECONDS)) logs
  while ((SECONDS < deadline)); do
    # zcashd begins accepting some RPCs before its wallet is loaded. Wait for
    # the explicit initialization-complete event instead of polling a wallet
    # method that may report the misleading transient "reindexing" error.
    logs="$(compose logs zcashd 2>/dev/null || true)"
    if zcash_cli getblockcount >/dev/null 2>&1 && \
      [[ "$logs" == *"init message: Done loading"* ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out after ${REGTEST_STARTUP_TIMEOUT_SECONDS}s waiting for zcashd initialization" >&2
  compose logs --tail=40 zcashd >&2 || true
  return 1
}

assert_wallet_ready() {
  local output
  if output="$(zcash_cli listunspent 1 9999999 "[]" false 2>&1)"; then
    return 0
  fi

  if [[ "$output" == *"reindexing"* ]]; then
    echo "zcashd wallet is reindexing; refusing to wait on a nondeterministic E2E setup." >&2
    echo "Run scripts/regtest/reset.sh, or unset REGTEST_PRESERVE_STATE so up.sh can reset stale state." >&2
  else
    echo "zcashd wallet is not ready: $output" >&2
  fi
  return 1
}

wait_for_lightwalletd() {
  local deadline=$((SECONDS + REGTEST_STARTUP_TIMEOUT_SECONDS))
  if command -v grpcurl >/dev/null 2>&1; then
    while ((SECONDS < deadline)); do
      if grpcurl \
        -max-time 2 \
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

  while ((SECONDS < deadline)); do
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
    assert_wallet_ready
    touch "$INITIALIZED_FILE"
    return 0
  fi

  # A fresh v6.20 regtest chain reports the generic "wallet operation is
  # disabled while reindexing" error until its first block is generated.
  # `generate` is synchronous, so bootstrap the deterministic chain first and
  # perform one wallet-readiness assertion afterwards instead of polling.
  zcash_cli generate 110 >/dev/null
  assert_wallet_ready
  if ! faucet_coinbase_ready; then
    echo "Faucet coinbase was not spendable immediately after synchronous block generation." >&2
    return 1
  fi
  touch "$INITIALIZED_FILE"
}
