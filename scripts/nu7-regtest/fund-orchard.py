#!/usr/bin/env python3
"""Fund Orchard notes before NU6.3 on the Zebra NU7 regtest chain.

Zebra has no wallet, so coinbase is mined to the offline signer in
rust/examples/regtest-orchard-funder, matured, and spent into Orchard. The total splits
evenly across the given addresses, one note each, in one transaction.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COINBASE_MATURITY = 100
# The signer pins NU6.3 at this height (rust/examples/regtest-orchard-funder).
SIGNER_NU63_HEIGHT = 500
MAX_INPUTS = 64
MAX_PAYMENTS = 500


def rpc(method, params=None):
    port = os.environ.get("NU7_REGTEST_RPC_PORT", "48232")
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or []})
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}", body.encode(), {"content-type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        reply = json.load(response)
    if reply.get("error"):
        raise SystemExit(f"{method} failed: {reply['error']}")
    return reply["result"]


def funder(binary, command, request=None):
    result = subprocess.run(
        [binary, command],
        input=None if request is None else json.dumps(request),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"regtest_orchard_funder {command} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def mine(blocks):
    subprocess.run([str(ROOT / "scripts/nu7-regtest/mine.sh"), str(blocks)], check=True,
                   stdout=subprocess.DEVNULL)


def coinbase_source(height, miner):
    block = rpc("getblock", [str(height), 2])
    coinbase = block["tx"][0]
    outputs = [output for output in coinbase["vout"]
               if output.get("scriptPubKey", {}).get("addresses") == [miner]]
    if len(outputs) != 1:
        raise SystemExit(f"block {height} coinbase does not pay the signer once")
    return {"coinbase_hex": coinbase["hex"], "coinbase_height": height,
            "coinbase_vout": outputs[0]["n"]}, outputs[0]["valueZat"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--funder", required=True, help="regtest_orchard_funder binary")
    parser.add_argument("--amount-zatoshi", type=int, required=True)
    parser.add_argument("--confirmations", type=int, default=10)
    parser.add_argument("addresses", nargs="+")
    args = parser.parse_args()

    addresses = args.addresses
    if len(set(addresses)) != len(addresses) or len(addresses) > MAX_PAYMENTS:
        raise SystemExit(f"need 1 to {MAX_PAYMENTS} distinct addresses")
    if args.amount_zatoshi < len(addresses) or args.confirmations < 1:
        raise SystemExit("amount must cover one zatoshi per note and confirmations must be positive")
    nu63 = rpc("getblockchaininfo")["upgrades"]
    nu63 = next(item["activationheight"] for item in nu63.values() if item["name"] == "NU6.3")
    if nu63 != SIGNER_NU63_HEIGHT:
        raise SystemExit(f"the signer needs NU6.3 at {SIGNER_NU63_HEIGHT}, the chain has {nu63}")

    miner = funder(args.funder, "identity")["miner_address"]
    inputs, value = [], 0
    # Pre-NU6.3 ZIP 317: one action per P2PKH input (one change output),
    # plus one per Orchard payment, padded to at least two Orchard actions.
    orchard_actions = max(2, len(addresses))
    for input_count in range(1, MAX_INPUTS + 1):
        rpc("generatetoaddress", [1, miner])
        source, source_value = coinbase_source(rpc("getblockcount"), miner)
        inputs.append(source)
        value += source_value
        fee = 5_000 * (input_count + orchard_actions)
        if value > args.amount_zatoshi + fee:  # The signer requires positive change.
            break
    else:
        raise SystemExit("amount needs more coinbase inputs than one transaction takes")
    mine(COINBASE_MATURITY)

    target = rpc("getblockcount") + 1
    if target + args.confirmations > nu63:
        raise SystemExit(f"Orchard funding must be mined and confirmed before NU6.3 at {nu63}")
    base, extra = divmod(args.amount_zatoshi, len(addresses))
    payments = [{"recipient_address": address, "amount_zatoshi": base + (1 if index < extra else 0)}
                for index, address in enumerate(addresses)]
    signed = funder(args.funder, "build-batch", {
        "schema_version": 1, "coinbase_inputs": inputs, "target_height": target,
        "recipient_pool": "orchard", "nu6_3_activation_height": nu63,
        "payments": payments, "expiry_height": None,
    })
    txid = rpc("sendrawtransaction", [signed["raw_tx_hex"]])
    if txid != signed["txid"]:
        raise SystemExit(f"node accepted {txid}, the signer built {signed['txid']}")
    mine(args.confirmations)
    mined = rpc("getrawtransaction", [txid, 1])
    if mined.get("height") != target:
        raise SystemExit(f"funding {txid} was not mined at {target}: {mined.get('height')}")
    print(json.dumps({"txid": txid, "height": target, "fee_zatoshi": signed["fee_zatoshi"]}))


if __name__ == "__main__":
    sys.exit(main())
