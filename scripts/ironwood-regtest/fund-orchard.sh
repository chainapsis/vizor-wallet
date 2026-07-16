#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

destination_input="${1:?usage: fund-orchard.sh <unified-address-or-json-array> [zec-amount] [confirming-blocks] [coinbase-limit] [note-count]}"
amount="${2:-1.0002}"
confirming_blocks="${3:-10}"
coinbase_limit="${4:-1}"
note_count="${5:-1}"

if ! [[ "$confirming_blocks" =~ ^[1-9][0-9]*$ ]]; then
  echo "confirming-blocks must be a positive integer" >&2
  exit 1
fi
if ! [[ "$coinbase_limit" =~ ^[0-9]+$ ]]; then
  echo "coinbase-limit must be a non-negative integer" >&2
  exit 1
fi
if ! [[ "$note_count" =~ ^[1-9][0-9]*$ ]]; then
  echo "note-count must be a positive integer" >&2
  exit 1
fi

wait_for_zcashd
wait_for_lightwalletd
ensure_faucet
assert_pre_ironwood_room "$((20 + confirming_blocks))"

sender="$(faucet_sender)"
sapling_faucet="$(zcash_cli z_getnewaddress sapling)"
shield_opid="$(extract_opid "$(zcash_cli z_shieldcoinbase "$sender" "$sapling_faucet" 0.0001 "$coinbase_limit")")"
wait_for_operation "$shield_opid" >/dev/null
zcash_cli generate 20 >/dev/null
wait_for_lightwalletd_tip "$(current_height)"
wait_for_spendable_shielded_note "$sapling_faucet"

funding_values="$(python3 - "$destination_input" "$amount" "$note_count" <<'PY'
from decimal import Decimal, InvalidOperation
import json
import sys

raw_destination = sys.argv[1]
if raw_destination.startswith("["):
    destinations = json.loads(raw_destination)
else:
    destinations = [raw_destination]
if (
    len(destinations) != int(sys.argv[3])
    or len(set(destinations)) != len(destinations)
    or any(not isinstance(value, str) or not value.startswith("uregtest1") for value in destinations)
):
    raise SystemExit("fund-orchard.sh requires one unique regtest address per note")
try:
    amount = Decimal(sys.argv[2])
except InvalidOperation as error:
    raise SystemExit(f"invalid ZEC amount: {sys.argv[2]}") from error
note_count = int(sys.argv[3])
zatoshis = amount * Decimal(100_000_000)
if zatoshis != zatoshis.to_integral_value() or zatoshis <= 0:
    raise SystemExit("zec-amount must be positive with at most 8 decimal places")
total_zatoshis = int(zatoshis)
if total_zatoshis < note_count:
    raise SystemExit("zec-amount must provide at least one zatoshi per note")

base, remainder = divmod(total_zatoshis, note_count)
recipients = []
for index in range(note_count):
    value = base + (1 if index < remainder else 0)
    recipients.append(
        '{"address":%s,"amount":%s}'
        % (
            json.dumps(destinations[index]),
            format(Decimal(value) / Decimal(100_000_000), ".8f"),
        )
    )

print("[" + ",".join(recipients) + "]")
# Cover the Sapling spend, recipient outputs, and possible change conservatively.
logical_actions = max(2, note_count + 2)
print(format(Decimal(logical_actions * 5_000) / Decimal(100_000_000), ".8f"))
PY
)"
recipients="$(printf '%s\n' "$funding_values" | sed -n '1p')"
funding_fee="$(printf '%s\n' "$funding_values" | sed -n '2p')"
txid=""
for attempt in $(seq 1 10); do
  opid="$(extract_opid "$(zcash_cli z_sendmany "$sapling_faucet" "$recipients" 1 "$funding_fee" AllowRevealedAmounts)")"
  if txid="$(wait_for_operation "$opid")"; then
    break
  fi
  echo "Orchard funding anchor is not ready (attempt ${attempt}/10); retrying" >&2
  sleep 1
done
if [[ -z "$txid" ]]; then
  echo "failed to fund Orchard address after 10 attempts" >&2
  exit 1
fi
zcash_cli generate "$confirming_blocks" >/dev/null
wait_for_lightwalletd_tip "$(current_height)"

echo "$txid"
