"""Confirmed multi-note funding through the existing original batch signer."""
from __future__ import annotations

import json
import time
import uuid

from funder_execution import run_offline_funder
from zakura_funding import (
    ZakuraFundingError, _base64_hex, _coinbase, _hex, _integer, _proto_integer,
)
from zakura_mempool import _context, _pending_raw


def migration_note_batches(addresses, *, total_zatoshi, tx_count):
    """Match the original migration shell's weighted batches and note values."""
    if (not isinstance(addresses, (list, tuple)) or not 1 <= len(addresses) <= 500
        or any(not isinstance(address, str) or not address.startswith("uregtest1")
               or len(address) > 4096 for address in addresses)
        or len(set(addresses)) != len(addresses)):
        raise ZakuraFundingError("migration requires distinct regtest note addresses")
    _integer(total_zatoshi, "migration total", minimum=len(addresses),
             maximum=2_100_000_000_000_000)
    _integer(tx_count, "migration funding transactions", minimum=1, maximum=len(addresses))
    base_count, extra_count = divmod(len(addresses), tx_count)
    weight_total = tx_count*(tx_count+1)//2
    totals = [total_zatoshi*weight//weight_total for weight in range(1, tx_count+1)]
    totals[-1] += total_zatoshi-sum(totals)
    result, offset = [], 0
    for index, batch_total in enumerate(totals):
        count = base_count+(1 if index < extra_count else 0)
        if batch_total < count:
            raise ZakuraFundingError("migration batch cannot provide one zatoshi per note")
        base_value, remainder = divmod(batch_total, count)
        result.append(tuple({"recipient_address":address,
            "amount_zatoshi":base_value+(1 if note < remainder else 0)}
            for note,address in enumerate(addresses[offset:offset+count])))
        offset += count
    return tuple(result)


def fund_zakura_batch(case, backend, artifact, *, payments, source_heights,
                      recipient_pool="orchard", confirmations=10,
                      timeout=120.0, cancel_event=None):
    """Explicit mature outpoints and distinct notes; no faucet/source guessing.

    This inclusion proof is not wallet decryption or catalog PASS. The original
    caller owns backend/native cleanup and retains failures with their evidence.
    """
    if not isinstance(recipient_pool, str) or recipient_pool not in {"orchard", "ironwood"}:
        raise ZakuraFundingError("batch recipient pool must be shielded")
    if not isinstance(payments, (list, tuple)) or not 1 <= len(payments) <= 500:
        raise ZakuraFundingError("batch requires 1 to 500 payments")
    encoded = []
    for payment in payments:
        if not isinstance(payment, dict) or set(payment) != {"recipient_address", "amount_zatoshi"}:
            raise ZakuraFundingError("batch payment fields must be exact")
        address = payment["recipient_address"]
        if not isinstance(address, str) or not 1 <= len(address) <= 4096:
            raise ZakuraFundingError("batch recipient address is invalid")
        _integer(payment["amount_zatoshi"], "batch payment zatoshis", minimum=1,
                 maximum=2_100_000_000_000_000)
        encoded.append(dict(payment))
    if len({item["recipient_address"] for item in encoded}) != len(encoded):
        raise ZakuraFundingError("batch notes require distinct recipient addresses")
    total = _integer(sum(item["amount_zatoshi"] for item in encoded), "batch total", minimum=1,
                     maximum=2_100_000_000_000_000)
    if not isinstance(source_heights, (list, tuple)) or not 1 <= len(source_heights) <= 64:
        raise ZakuraFundingError("batch requires 1 to 64 explicit source heights")
    for height in source_heights:
        _integer(height, "batch source height", minimum=1)
    if len(set(source_heights)) != len(source_heights):
        raise ZakuraFundingError("batch source heights must be distinct")
    _integer(confirmations, "batch confirmations", minimum=1, maximum=1000)
    check, rpc, deadline, cancel = _context(case, backend, timeout, cancel_event)
    activation = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])[
        "regtest_ironwood_activation_height"]
    tip = _integer(rpc("getblockcount"), "batch initial tip", minimum=1,
                   maximum=0xFFFFFFFF-confirmations)
    target = tip + 1
    if target < max(source_heights) + 100:
        raise ZakuraFundingError("batch source is not mature")
    if recipient_pool == "orchard" and (activation != 500 or tip + confirmations >= 500):
        raise ZakuraFundingError("Orchard batch must finish before controlled activation")
    if recipient_pool == "ironwood" and target < activation:
        raise ZakuraFundingError("Ironwood batch precedes activation")
    identity = run_offline_funder(case, artifact, "identity", timeout=deadline-time.monotonic(),
                                 cancel_event=cancel)
    if identity["miner_address"] != backend._fixture.miner_address:
        raise ZakuraFundingError("batch miner differs from the original signer")
    inputs, sources = [], []
    for height in source_heights:
        block_hash = _hex(rpc("getblockhash", [height]), "batch source hash", byte_count=32)
        txid, raw, vout, value = _coinbase(rpc("getblock", [block_hash, 2]), height,
                                        block_hash, identity["miner_address"])
        if not isinstance(rpc("gettxout", [txid, vout, True]), dict):
            raise ZakuraFundingError("batch source is already spent or unavailable")
        inputs.append({"coinbase_hex":raw, "coinbase_height":height, "coinbase_vout":vout})
        sources.append({"coinbase_source_height":height, "coinbase_txid":txid,
                        "coinbase_vout":vout, "input_value_zatoshi":value})
    input_value = sum(item["input_value_zatoshi"] for item in sources)
    _integer(input_value, "batch input value", minimum=1, maximum=2_100_000_000_000_000)
    if len({(item["coinbase_txid"], item["coinbase_vout"]) for item in sources}) != len(sources):
        raise ZakuraFundingError("batch sources repeat an outpoint")
    request = {"schema_version":1, "coinbase_inputs":inputs, "target_height":target,
        "recipient_pool":recipient_pool, "nu6_3_activation_height":activation,
        "payments":encoded, "expiry_height":None}
    check()
    signed = run_offline_funder(case, artifact, "build-batch", request,
                               timeout=deadline-time.monotonic(), cancel_event=cancel)
    fields = {"schema_version", "raw_tx_hex", "txid", "fee_zatoshi", "input_value_zatoshi",
        "amount_zatoshi", "change_zatoshi", "target_height", "expiry_height",
        "maturity_validated", "pools", "coinbase_inputs", "payments"}
    if not isinstance(signed, dict) or set(signed) != fields or type(signed["schema_version"]) is not int or signed["schema_version"] != 1:
        raise ZakuraFundingError("batch signer fields are not exact schema-1 evidence")
    for field in ("fee_zatoshi", "input_value_zatoshi", "amount_zatoshi", "change_zatoshi"):
        _integer(signed[field], field, minimum=1, maximum=2_100_000_000_000_000)
    _integer(signed["target_height"], "batch target height", minimum=1)
    _integer(signed["expiry_height"], "batch expiry", minimum=target+1,
             maximum=min(0xFFFFFFFF, target+10000))
    if (signed["input_value_zatoshi"] != input_value or signed["amount_zatoshi"] != total
        or input_value != total + signed["fee_zatoshi"] + signed["change_zatoshi"]
        or signed["target_height"] != target or signed["maturity_validated"] is not True
        or signed["pools"] != ["transparent", recipient_pool]
        or signed["coinbase_inputs"] != sources or signed["payments"] != encoded
        or any(type(item[field]) is not int for item in signed["coinbase_inputs"]
               for field in ("coinbase_source_height", "coinbase_vout", "input_value_zatoshi"))
        or any(type(item["amount_zatoshi"]) is not int for item in signed["payments"])):
        raise ZakuraFundingError("batch signer source, notes, pool or conservation differs")
    _hex(signed["txid"], "batch txid", byte_count=32)
    _hex(signed["raw_tx_hex"], "batch raw transaction")
    if rpc("getblockcount") != tip:
        raise ZakuraFundingError("batch tip changed before submission")
    submitted = rpc("sendrawtransaction", [signed["raw_tx_hex"]])
    if submitted != signed["txid"]:
        raise ZakuraFundingError("node and batch signer transaction IDs differ")
    while submitted not in rpc("getrawmempool"):
        time.sleep(min(0.05, max(0.0, deadline-time.monotonic())))
    _pending_raw(rpc("getrawtransaction", [submitted, 1]), submitted,
                 signed["expiry_height"], signed["raw_tx_hex"])
    check()
    mined = backend.mine(confirmations)
    check()
    hashes = mined.get("hashes")
    if (not isinstance(hashes, list) or len(hashes) != confirmations or len(set(hashes)) != confirmations
        or any(_hex(value, "batch inclusion hash", byte_count=32) != value for value in hashes)
        or type(mined.get("tip", {}).get("height")) is not int or mined["tip"]["height"] != tip+confirmations):
        raise ZakuraFundingError("batch confirmation range differs")
    block = rpc("getblock", [hashes[0], 2])
    included = [tx for tx in block.get("tx", []) if isinstance(tx, dict) and tx.get("txid") == submitted]
    if (block.get("hash") != hashes[0] or type(block.get("height")) is not int
        or block["height"] != target or len(included) != 1 or included[0].get("hex") != signed["raw_tx_hex"]):
        raise ZakuraFundingError("batch inclusion omitted the exact signed transaction")
    compact = backend.grpc("GetBlock", {"height":str(target)}, deadline=deadline)
    if (_proto_integer(compact["height"], "batch compact height") != target
        or _base64_hex(compact["hash"], "batch compact hash", reverse=True, byte_count=32) != hashes[0]):
        raise ZakuraFundingError("batch raw/compact block identities differ")
    matches = [tx for tx in compact.get("vtx", []) if
               _base64_hex(tx["txid"], "batch compact txid", reverse=True, byte_count=32) == submitted]
    field, forbidden = ("actions", "ironwoodActions") if recipient_pool == "orchard" else ("ironwoodActions", "actions")
    if (len(matches) != 1 or not isinstance(matches[0].get(field), list)
        or len(matches[0][field]) < len(encoded) or matches[0].get(forbidden)):
        raise ZakuraFundingError("batch compact pool or action count differs")
    check()
    proof = {"schema_version":1, "txid_hex":submitted, "pool":recipient_pool,
        "amount_zatoshi":total, "payment_count":len(encoded), "source_heights":list(source_heights),
        "mined_height":target, "final_tip_height":tip+confirmations, "confirmations":confirmations,
        "raw_transaction_exact":True, "raw_compact_block_exact":True,
        "compact_action_count":len(matches[0][field]), "wallet_or_catalog_pass":False}
    backend._write_text("funding-batch-"+uuid.uuid4().hex+".json",
                        json.dumps({"proof":proof, "signer":signed}, indent=2)+"\n")
    return proof
