#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
ACTIVATION_HEIGHT="${IRONWOOD_ACTIVATION_HEIGHT:-500}"
LIGHTWALLETD_URL="${E2E_LIGHTWALLETD_URL:-http://127.0.0.1:19067}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
VIZOR_FORM_FACTOR="${VIZOR_FORM_FACTOR:-desktop}"
DRIVER_PORT="${E2E_DRIVER_PORT:-39078}"
DRIVER_URL="http://127.0.0.1:${DRIVER_PORT}"
TEST_FILE="${E2E_TEST_FILE:-integration_test/regtest_ironwood_migration_test.dart}"
TEST_NAME="$(basename "$TEST_FILE" .dart)"
REGTEST_STATE_DIR="${IRONWOOD_STATE_DIR:-$ROOT_DIR/.ironwood-regtest}"
DRIVER_LOG="$REGTEST_STATE_DIR/${TEST_NAME}-driver.log"
CHECKPOINT="${E2E_IRONWOOD_CHECKPOINT:-}"
FUNDING_AMOUNT="${E2E_ORCHARD_FUNDING_AMOUNT:-0.011}"
FUNDING_CONFIRMATIONS="${E2E_ORCHARD_FUNDING_CONFIRMATIONS:-10}"
FUNDING_COINBASE_LIMIT="${E2E_ORCHARD_FUNDING_COINBASE_LIMIT:-1}"
FUNDING_NOTE_COUNT="${E2E_ORCHARD_FUNDING_NOTE_COUNT:-1}"
FUNDING_TX_COUNT="${E2E_ORCHARD_FUNDING_TX_COUNT:-1}"
PREFUND_BLOCKS="${E2E_ORCHARD_PREFUND_BLOCKS:-0}"
MACOS_SIGNING_OVERRIDES="$ROOT_DIR/macos/Runner/Configs/FlavorOverrides.xcconfig"

macos_development_team="${E2E_MACOS_DEVELOPMENT_TEAM:-}"
if [[ -z "$macos_development_team" && -f "$MACOS_SIGNING_OVERRIDES" ]]; then
  macos_development_team="$(
    sed -nE \
      's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([^[:space:]#;]+).*/\1/p' \
      "$MACOS_SIGNING_OVERRIDES" | tail -n 1
  )"
fi
if [[ -n "$macos_development_team" ]]; then
  export FLUTTER_XCODE_DEVELOPMENT_TEAM="${FLUTTER_XCODE_DEVELOPMENT_TEAM:-$macos_development_team}"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

derive_addresses() {
  local output_file="$1"
  local attempt

  for attempt in 1 2 3; do
    (cd rust && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC" "$FUNDING_NOTE_COUNT") >"$output_file"
    if python3 - "$output_file" "$FUNDING_NOTE_COUNT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
addresses = data.get("unifiedAddresses")
if not data.get("unifiedAddress") or not isinstance(addresses, list):
    raise SystemExit(1)
if len(addresses) != int(sys.argv[2]) or len(set(addresses)) != len(addresses):
    raise SystemExit(1)
PY
    then
      return 0
    fi

    echo "address derivation produced invalid output (attempt ${attempt}/3); retrying" >&2
    sleep 1
  done

  echo "failed to derive the deterministic regtest wallet address" >&2
  return 1
}

require_cmd cargo
require_cmd docker
require_cmd fvm
require_cmd python3

cd "$ROOT_DIR"
export IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT"

if [[ -n "$CHECKPOINT" ]]; then
  scripts/ironwood-regtest/checkpoint.sh restore "$CHECKPOINT"
  scripts/ironwood-regtest/up.sh
else
  scripts/ironwood-regtest/reset.sh
  scripts/ironwood-regtest/up.sh
fi

if ! [[ "$PREFUND_BLOCKS" =~ ^[0-9]+$ ]]; then
  echo "E2E_ORCHARD_PREFUND_BLOCKS must be a non-negative integer" >&2
  exit 1
fi
if ! [[ "$FUNDING_NOTE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "E2E_ORCHARD_FUNDING_NOTE_COUNT must be a positive integer" >&2
  exit 1
fi
if ! [[ "$FUNDING_TX_COUNT" =~ ^[1-9][0-9]*$ ]] ||
  [[ "$FUNDING_TX_COUNT" -gt "$FUNDING_NOTE_COUNT" ]]; then
  echo "E2E_ORCHARD_FUNDING_TX_COUNT must be between 1 and the note count" >&2
  exit 1
fi
if [[ -z "$CHECKPOINT" ]]; then
  if [[ "$PREFUND_BLOCKS" -gt 0 ]]; then
    scripts/ironwood-regtest/mine.sh "$PREFUND_BLOCKS" >/dev/null
  fi

  addresses_file="$REGTEST_STATE_DIR/e2e-addresses.json"
  derive_addresses "$addresses_file"
  funding_manifest="$REGTEST_STATE_DIR/e2e-funding-manifest.tsv"
  python3 - \
    "$addresses_file" \
    "$FUNDING_AMOUNT" \
    "$FUNDING_TX_COUNT" \
    >"$funding_manifest" <<'PY'
from decimal import Decimal, InvalidOperation
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    addresses = json.load(source)["unifiedAddresses"]
try:
    amount = Decimal(sys.argv[2])
except InvalidOperation as error:
    raise SystemExit(f"invalid E2E_ORCHARD_FUNDING_AMOUNT: {sys.argv[2]}") from error
total_zatoshis = amount * Decimal(100_000_000)
if total_zatoshis != total_zatoshis.to_integral_value() or total_zatoshis <= 0:
    raise SystemExit("E2E_ORCHARD_FUNDING_AMOUNT must be positive with at most 8 decimals")

tx_count = int(sys.argv[3])
base_count, extra = divmod(len(addresses), tx_count)
note_counts = [base_count + (1 if index < extra else 0) for index in range(tx_count)]
weight_total = tx_count * (tx_count + 1) // 2
batch_zatoshis = [int(total_zatoshis) * weight // weight_total for weight in range(1, tx_count + 1)]
batch_zatoshis[-1] += int(total_zatoshis) - sum(batch_zatoshis)

offset = 0
for count, zatoshis in zip(note_counts, batch_zatoshis):
    if zatoshis < count:
        raise SystemExit("funding batch must provide at least one zatoshi per note")
    destinations = addresses[offset:offset + count]
    offset += count
    amount_text = format(Decimal(zatoshis) / Decimal(100_000_000), ".8f")
    addresses_text = json.dumps(destinations, separators=(",", ":"))
    print(f"{amount_text}\t{count}\t{addresses_text}")
PY

  while IFS=$'\t' read -r batch_amount batch_note_count batch_destinations; do
    scripts/ironwood-regtest/fund-orchard.sh \
      "$batch_destinations" \
      "$batch_amount" \
      "$FUNDING_CONFIRMATIONS" \
      "$FUNDING_COINBASE_LIMIT" \
      "$batch_note_count" </dev/null >/dev/null
  done <"$funding_manifest"
fi

mkdir -p "$REGTEST_STATE_DIR"
: > "$DRIVER_LOG"
python3 -u scripts/e2e/ironwood-regtest-driver.py \
  --repo-root "$ROOT_DIR" \
  --port "$DRIVER_PORT" \
  --activation-height "$ACTIVATION_HEIGHT" \
  >"$DRIVER_LOG" 2>&1 &
driver_pid="$!"

cleanup() {
  kill "$driver_pid" >/dev/null 2>&1 || true
  wait "$driver_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

python3 - "$DRIVER_URL" <<'PY'
import sys
import time
import urllib.request

url = sys.argv[1] + "/health"
for _ in range(100):
    try:
        with urllib.request.urlopen(url, timeout=1) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit("Timed out waiting for Ironwood E2E driver")
PY

echo "running Flutter Ironwood migration integration test: $TEST_FILE"
flutter_args=(
  "$TEST_FILE"
  -d "$FLUTTER_DEVICE"
)
if [[ "$VIZOR_FORM_FACTOR" == "mobile" ]]; then
  flutter_args+=(--dart-define=VIZOR_FORM_FACTOR=mobile)
fi
scenario_define_args=(
  --dart-define=ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT="$FUNDING_NOTE_COUNT"
  --dart-define=ZCASH_FAST_TESTNET_MIGRATION="${E2E_FAST_TESTNET_MIGRATION:-false}"
)
if [[ -n "${E2E_ORCHARD_FUNDING_ZATOSHI:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI="$E2E_ORCHARD_FUNDING_ZATOSHI"
  )
fi
if [[ -n "${E2E_EXPECTED_SPLIT_STAGE_COUNT:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_EXPECTED_SPLIT_STAGE_COUNT="$E2E_EXPECTED_SPLIT_STAGE_COUNT"
  )
fi
if [[ -n "${E2E_EXPECTED_MIGRATION_BATCH_COUNT:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_EXPECTED_MIGRATION_BATCH_COUNT="$E2E_EXPECTED_MIGRATION_BATCH_COUNT"
  )
fi
if [[ -n "${E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_MIGRATION_SIM_BLOCK_INTERVAL_MS="$E2E_MIGRATION_SIM_BLOCK_INTERVAL_MS"
  )
fi
if [[ -n "${E2E_MIGRATION_SIM_MAX_BLOCKS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_MIGRATION_SIM_MAX_BLOCKS="$E2E_MIGRATION_SIM_MAX_BLOCKS"
  )
fi
if [[ -n "${E2E_MIGRATION_SIM_HOME_HOLD_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_MIGRATION_SIM_HOME_HOLD_MS="$E2E_MIGRATION_SIM_HOME_HOLD_MS"
  )
fi
if [[ -n "${E2E_MIGRATION_SIM_REVIEW_HOLD_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_MIGRATION_SIM_REVIEW_HOLD_MS="$E2E_MIGRATION_SIM_REVIEW_HOLD_MS"
  )
fi
if [[ -n "${E2E_IRONWOOD_MIGRATION_PRIVACY_LOCK:-}" ]]; then
  scenario_define_args+=(
    --dart-define=VIZOR_IRONWOOD_MIGRATION_PRIVACY_LOCK="$E2E_IRONWOOD_MIGRATION_PRIVACY_LOCK"
  )
fi
if [[ -n "${E2E_FAKE_MIGRATION_BALANCE_ZEC:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_REGTEST_FAKE_MIGRATION_BALANCE_ZEC="$E2E_FAKE_MIGRATION_BALANCE_ZEC"
  )
fi
if [[ -n "${E2E_CUSTOM_MIGRATION_PREVIEW_HOLD_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_CUSTOM_MIGRATION_PREVIEW_HOLD_MS="$E2E_CUSTOM_MIGRATION_PREVIEW_HOLD_MS"
  )
fi
if [[ -n "${E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS="$E2E_CUSTOM_MIGRATION_LIVE_HOLD_MS"
  )
fi
if [[ -n "${E2E_CUSTOM_MIGRATION_AUTO_START:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_CUSTOM_MIGRATION_AUTO_START="$E2E_CUSTOM_MIGRATION_AUTO_START"
  )
fi
if [[ -n "${E2E_CUSTOM_MIGRATION_PACE_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_CUSTOM_MIGRATION_PACE_MS="$E2E_CUSTOM_MIGRATION_PACE_MS"
  )
fi
if [[ -n "${E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS="$E2E_CUSTOM_MIGRATION_COMPLETION_HOLD_MS"
  )
fi
if [[ -n "${E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN:-}" ]]; then
  scenario_define_args+=(
    --dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN="$E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN"
  )
fi
flutter_args+=(
  "${scenario_define_args[@]}"
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest
  --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT"
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL"
  --dart-define=ZCASH_E2E_DRIVER_URL="$DRIVER_URL"
  --dart-define=ZCASH_E2E_ORCHARD_FUNDING_TX_COUNT="$FUNDING_TX_COUNT"
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
)
set +e
fvm flutter test "${flutter_args[@]}"
status="$?"
set -e

if [[ "$status" -ne 0 ]]; then
  echo "Ironwood E2E driver log:" >&2
  sed -n '1,260p' "$DRIVER_LOG" >&2 || true
fi

exit "$status"
