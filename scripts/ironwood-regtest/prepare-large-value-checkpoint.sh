#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/large-value-env.sh"
source "$SCRIPT_DIR/lib.sh"

MNEMONIC="winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
FUNDING_AMOUNT="${1:-50001.0002}"
CHECKPOINT_NAME="${2:-custom-migration-50001-zec}"
EXPECTED_GRANT_ZATOSHI=110000000000000

for command in cargo docker fvm grpcurl python3; do
  require_command "$command"
done

funding_zatoshi="$(python3 - "$FUNDING_AMOUNT" <<'PY'
from decimal import Decimal, InvalidOperation
import sys

try:
    amount = Decimal(sys.argv[1])
except InvalidOperation as error:
    raise SystemExit(f"invalid funding amount: {sys.argv[1]}") from error
zatoshis = amount * Decimal(100_000_000)
if zatoshis != zatoshis.to_integral_value() or not (0 < zatoshis < 1_100_000 * 100_000_000):
    raise SystemExit("funding amount must be positive, below 1,100,000 ZEC, and have at most 8 decimals")
print(int(zatoshis))
PY
)"

"$SCRIPT_DIR/build-large-value-zcashd.sh"
"$SCRIPT_DIR/reset.sh"
"$SCRIPT_DIR/up.sh"

generated_utxos="$(zcash_cli listunspent 1 9999999 '[]' false)"
python3 - "$generated_utxos" "$EXPECTED_GRANT_ZATOSHI" <<'PY'
import json
import sys

utxos = json.loads(sys.argv[1])
expected = int(sys.argv[2])
values = [int(item.get("amountZat", 0)) for item in utxos if item.get("generated")]
if expected not in values:
    raise SystemExit(f"height-1 faucet grant missing; generated values were {values}")
print(f"verified one-time regtest faucet grant: {expected} zatoshi")
PY

addresses_file="$STATE_DIR/e2e-addresses.json"
(cd "$ROOT_DIR/rust" && cargo run --quiet --example regtest_wallet_addresses -- "$MNEMONIC" 1) >"$addresses_file"
destination="$(python3 - "$addresses_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
addresses = data.get("unifiedAddresses")
if not isinstance(addresses, list) or len(addresses) != 1:
    raise SystemExit("expected one deterministic regtest address")
print(addresses[0])
PY
)"

funding_txid="$("$SCRIPT_DIR/fund-orchard.sh" "$destination" "$FUNDING_AMOUNT" 10 0 1)"
tip="$(current_height)"
python3 - \
  "$STATE_DIR/large-value-manifest.json" \
  "$FUNDING_AMOUNT" \
  "$funding_zatoshi" \
  "$funding_txid" \
  "$destination" \
  "$tip" \
  "$IRONWOOD_ACTIVATION_HEIGHT" \
  "$IRONWOOD_ZCASHD_IMAGE" <<'PY'
import json
import sys

path, amount, zatoshis, txid, address, tip, activation, image = sys.argv[1:]
with open(path, "w", encoding="utf-8") as output:
    json.dump(
        {
            "fundingAmountZec": amount,
            "fundingZatoshi": int(zatoshis),
            "fundingTxid": txid,
            "unifiedAddress": address,
            "preActivationHeight": int(tip),
            "activationHeight": int(activation),
            "zcashdImage": image,
            "zeroRevision": "93a1d844c5e9f749b4b4a5a52de5c1ea8d02c523",
            "faucetGrantZec": 1_100_000,
        },
        output,
        indent=2,
        sort_keys=True,
    )
    output.write("\n")
PY

"$SCRIPT_DIR/checkpoint.sh" save "$CHECKPOINT_NAME" >/dev/null
"$SCRIPT_DIR/down.sh"

echo "large-value checkpoint ready: $SNAPSHOT_DIR/$CHECKPOINT_NAME.tar.gz"
echo "funded one real Orchard note with $FUNDING_AMOUNT ZEC ($funding_zatoshi zatoshi)"
