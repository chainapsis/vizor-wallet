"""Owned direct-fixture funding with independent integer/raw/compact oracles.

This proves a fixture payment, not wallet note decryption or scenario PASS.
"""
from __future__ import annotations

import base64
import binascii
import json
import math
import re
import threading
import time
import uuid

import e2e_runtime as runtime
from funder_execution import run_offline_funder
from native_case_lifecycle import NativeCaseLifecycle
from native_zakura_backend import OwnedNativeZakuraBackend


class ZakuraFundingError(runtime.RunnerError):
    """Funding source, conservation, submission or exact inclusion is unproven."""


def _integer(value, label, *, minimum=0, maximum=0xFFFFFFFF):
    if type(value) is not int or not minimum <= value <= maximum:
        raise ZakuraFundingError(f"{label} is not a bounded integer")
    return value


def _proto_integer(value, label):
    if isinstance(value, str) and re.fullmatch(r"0|[1-9][0-9]*", value):
        value = int(value)
    return _integer(value, label, maximum=0x7FFFFFFFFFFFFFFF)


def _hex(value, label, *, byte_count=None):
    if (not isinstance(value, str) or not value or len(value) % 2
        or not re.fullmatch(r"[0-9a-f]+", value)
        or (byte_count is not None and len(value) != byte_count * 2)):
        raise ZakuraFundingError(f"{label} is not exact lowercase hex")
    return value


def _base64_hex(value, label, *, reverse=False, byte_count=None):
    if not isinstance(value, str):
        raise ZakuraFundingError(f"{label} is not base64 text")
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ZakuraFundingError(f"{label} has invalid base64 bytes") from error
    if not decoded or (byte_count is not None and len(decoded) != byte_count):
        raise ZakuraFundingError(f"{label} has the wrong byte length")
    return (decoded[::-1] if reverse else decoded).hex()


def _coinbase(block, height, block_hash, miner):
    if not isinstance(block, dict) or block.get("hash") != block_hash or type(block.get("height")) is not int or block["height"] != height:
        raise ZakuraFundingError("node returned the wrong coinbase source block")
    transactions = block.get("tx")
    if not isinstance(transactions, list) or not transactions or not isinstance(transactions[0], dict):
        raise ZakuraFundingError("coinbase source block is incomplete")
    transaction = transactions[0]
    inputs = transaction.get("vin")
    if not isinstance(inputs, list) or len(inputs) != 1 or not isinstance(inputs[0], dict) or "coinbase" not in inputs[0]:
        raise ZakuraFundingError("funding source is not a coinbase transaction")
    txid = _hex(transaction.get("txid"), "coinbase txid", byte_count=32)
    raw = _hex(transaction.get("hex"), "coinbase raw transaction")
    outputs = transaction.get("vout")
    if not isinstance(outputs, list):
        raise ZakuraFundingError("coinbase outputs are unavailable")
    candidates = [output for output in outputs if isinstance(output, dict)
                  and isinstance(output.get("scriptPubKey"), dict)
                  and output["scriptPubKey"].get("addresses") == [miner]]
    if len(candidates) != 1:
        raise ZakuraFundingError("coinbase does not identify one fixed miner output")
    output = candidates[0]
    return txid, raw, _integer(output.get("n"), "coinbase output index"), _integer(
        output.get("valueZat"), "coinbase zatoshis", minimum=1, maximum=2_100_000_000_000_000)


def _signed_result(value, request, source_txid, source_value, pool):
    required = {"schema_version", "raw_tx_hex", "txid", "fee_zatoshi", "input_value_zatoshi",
        "amount_zatoshi", "coinbase_source_height", "coinbase_txid", "coinbase_vout",
        "change_zatoshi", "target_height", "maturity_validated", "pools"}
    if pool == "transparent":
        required.add("recipient_output")
    if not isinstance(value, dict) or set(value) != required or type(value.get("schema_version")) is not int or value["schema_version"] != 1:
        raise ZakuraFundingError("signer funding fields are not exact schema-1 evidence")
    for field in ("fee_zatoshi", "input_value_zatoshi", "amount_zatoshi", "change_zatoshi"):
        _integer(value[field], field, minimum=1, maximum=2_100_000_000_000_000)
    for field in ("coinbase_source_height", "coinbase_vout", "target_height"):
        _integer(value[field], field)
    if (value["amount_zatoshi"] != request["amount_zatoshi"]
        or value["coinbase_source_height"] != request["coinbase_height"]
        or value["coinbase_vout"] != request["coinbase_vout"]
        or value["coinbase_txid"] != source_txid or value["target_height"] != request["target_height"]
        or value["input_value_zatoshi"] != source_value
        or source_value != value["amount_zatoshi"] + value["fee_zatoshi"] + value["change_zatoshi"]
        or value["maturity_validated"] is not True
        or value["pools"] != (["transparent"] if pool == "transparent" else ["transparent", pool])):
        raise ZakuraFundingError("signer source, pool or integer conservation differs from the request")
    _hex(value["txid"], "signed txid", byte_count=32)
    _hex(value["raw_tx_hex"], "signed transaction")


def _transparent(backend, funding, request, transaction, target, deadline):
    output = funding["recipient_output"]
    if (not isinstance(output, dict) or set(output) != {"address", "vout", "script_hex", "amount_zatoshi"}
        or output["address"] != request["recipient_address"] or output["amount_zatoshi"] != request["amount_zatoshi"]):
        raise ZakuraFundingError("transparent recipient evidence differs from the request")
    _integer(output["vout"], "recipient output index")
    _integer(output["amount_zatoshi"], "recipient zatoshis", minimum=1, maximum=2_100_000_000_000_000)
    _hex(output["script_hex"], "recipient script")
    matches = [item for item in transaction.get("vout", []) if isinstance(item, dict)
        and type(item.get("n")) is int and item["n"] == output["vout"]
        and type(item.get("valueZat")) is int and item["valueZat"] == output["amount_zatoshi"]
        and isinstance(item.get("scriptPubKey"), dict)
        and item["scriptPubKey"].get("hex") == output["script_hex"]
        and item["scriptPubKey"].get("addresses") == [output["address"]]]
    if len(matches) != 1:
        raise ZakuraFundingError("raw block did not prove the exact transparent output")
    rows = backend.grpc_stream("GetTaddressTxids", {"address": output["address"],
        "range": {"start": {"height": str(target)}, "end": {"height": str(target)}}}, deadline=deadline)
    matches = [item for item in rows if _proto_integer(item["height"], "transaction height") == target
               and _base64_hex(item["data"], "transaction bytes") == funding["raw_tx_hex"]]
    if len(matches) != 1:
        raise ZakuraFundingError("lightwalletd did not stream exactly one raw funding transaction")
    rows = backend.grpc_stream("GetAddressUtxosStream", {"addresses": [output["address"]],
        "startHeight": str(target), "maxEntries": 16}, deadline=deadline)
    matches = [item for item in rows if
        _base64_hex(item["txid"], "UTXO txid", reverse=True, byte_count=32) == funding["txid"]
        and type(item["index"]) is int and item["index"] == output["vout"]
        and item["address"] == output["address"]
        and _proto_integer(item["valueZat"], "UTXO zatoshis") == output["amount_zatoshi"]
        and _proto_integer(item["height"], "UTXO height") == target
        and _base64_hex(item["script"], "UTXO script") == output["script_hex"]]
    if len(matches) != 1:
        raise ZakuraFundingError("lightwalletd did not prove exactly one transparent UTXO")
    return dict(output, raw_output_exact=True, lwd_raw_stream_exact=True, lwd_utxo_exact=True)


def fund_zakura(case, backend, artifact, *, recipient_address, amount_zatoshi,
                source_height=1, recipient_pool="ironwood", confirmations=10,
                timeout=120.0, cancel_event=None):
    """Explicit mature source; no faucet/wallet RPC or automatic source guessing.

    Calls are synchronous and bounded by the pinned backend's transport budget;
    cancellation is checked between calls, not within Docker/RPC transport.
    Caller owns failed retention and all final backend/native teardown.
    """
    if (not isinstance(case, NativeCaseLifecycle) or not isinstance(backend, OwnedNativeZakuraBackend)
        or backend._case is not case or not case.accepting_launches):
        raise ZakuraFundingError("funding requires this original accepting case/backend")
    if not isinstance(recipient_address, str) or not recipient_address or len(recipient_address) > 4096:
        raise ZakuraFundingError("recipient address is invalid")
    _integer(amount_zatoshi, "requested zatoshis", minimum=1, maximum=2_100_000_000_000_000)
    _integer(source_height, "source height", minimum=1)
    _integer(confirmations, "confirmations", minimum=1, maximum=1000)
    if not isinstance(recipient_pool, str) or recipient_pool not in {"ironwood", "orchard", "transparent"}:
        raise ZakuraFundingError("unsupported recipient pool")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise ZakuraFundingError("funding timeout must be positive and finite")
    deadline = time.monotonic() + timeout
    cancellation = cancel_event if cancel_event is not None else threading.Event()
    def check():
        if cancellation.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= deadline:
            raise ZakuraFundingError("funding deadline expired", 124)
        backend._running()
    def rpc(method, params=None):
        check()
        value = backend.rpc(method, params, deadline=deadline)
        check()
        return value
    check()
    identity = run_offline_funder(case, artifact, "identity", timeout=deadline-time.monotonic(), cancel_event=cancellation)
    if backend._fixture.miner_address != identity["miner_address"]:
        raise ZakuraFundingError("backend miner differs from original signer identity")
    activation = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])["regtest_ironwood_activation_height"]
    tip = _integer(rpc("getblockcount"), "initial tip", minimum=1, maximum=0xFFFFFFFF-41)
    target = tip + 1
    if tip < source_height + 100 or target + confirmations - 1 > 0xFFFFFFFF:
        raise ZakuraFundingError("source is not mature or confirmations exceed chain bounds")
    if recipient_pool == "orchard" and (activation != 500 or target + confirmations - 1 >= 500):
        raise ZakuraFundingError("Orchard funding must finish before controlled activation")
    if recipient_pool == "ironwood" and target < activation:
        raise ZakuraFundingError("Ironwood funding precedes its activation")
    block_hash = _hex(rpc("getblockhash", [source_height]), "source block hash", byte_count=32)
    source_txid, raw, vout, value = _coinbase(rpc("getblock", [block_hash, 2]), source_height, block_hash, identity["miner_address"])
    if not isinstance(rpc("gettxout", [source_txid, vout, True]), dict):
        raise ZakuraFundingError("source outpoint is already spent or unavailable")
    request = {"schema_version":1,"coinbase_hex":raw,"coinbase_height":source_height,
        "coinbase_vout":vout,"target_height":target,"recipient_address":recipient_address,"amount_zatoshi":amount_zatoshi}
    if recipient_pool == "orchard":
        request["nu6_3_activation_height"] = 500
    check()
    funding = run_offline_funder(case, artifact,
        {"ironwood":"build","orchard":"build-orchard","transparent":"build-transparent"}[recipient_pool],
        request, timeout=deadline-time.monotonic(), cancel_event=cancellation)
    _signed_result(funding, request, source_txid, value, recipient_pool)
    if rpc("getblockcount") != tip:
        raise ZakuraFundingError("tip changed before funding submission")
    submitted = rpc("sendrawtransaction", [funding["raw_tx_hex"]])
    if submitted != funding["txid"]:
        raise ZakuraFundingError("node and independent signer transaction IDs differ")
    while submitted not in rpc("getrawmempool"):
        time.sleep(min(0.05, max(0.0, deadline-time.monotonic())))
    check()
    mined = backend.mine(confirmations)
    check()
    hashes = mined.get("hashes")
    if (not isinstance(hashes, list) or len(hashes) != confirmations or len(set(hashes)) != confirmations
        or any(_hex(item, "mined block hash", byte_count=32) != item for item in hashes)
        or type(mined.get("tip", {}).get("height")) is not int or mined["tip"]["height"] != tip + confirmations):
        raise ZakuraFundingError("node mined an unexpected confirmation range")
    block = rpc("getblock", [hashes[0], 2])
    if block.get("hash") != hashes[0] or type(block.get("height")) is not int or block["height"] != target:
        raise ZakuraFundingError("node returned the wrong inclusion block")
    included = [tx for tx in block.get("tx", []) if isinstance(tx, dict) and tx.get("txid") == submitted]
    if len(included) != 1 or included[0].get("hex") != funding["raw_tx_hex"]:
        raise ZakuraFundingError("raw block omitted the exact signed transaction")
    check()
    compact = backend.grpc("GetBlock", {"height":str(target)}, deadline=deadline)
    if (_proto_integer(compact["height"], "compact height") != target
        or _base64_hex(compact["hash"], "compact hash", reverse=True, byte_count=32) != block["hash"]):
        raise ZakuraFundingError("compact and raw inclusion block identities differ")
    transparent = None
    action_count = 0
    if recipient_pool == "transparent":
        transparent = _transparent(backend, funding, request, included[0], target, deadline)
    else:
        matches = [tx for tx in compact.get("vtx", []) if
            _base64_hex(tx["txid"], "compact txid", reverse=True, byte_count=32) == submitted]
        field, forbidden = ("actions", "ironwoodActions") if recipient_pool == "orchard" else ("ironwoodActions", "actions")
        if len(matches) != 1 or not isinstance(matches[0].get(field), list) or not matches[0][field] or matches[0].get(forbidden):
            raise ZakuraFundingError("compact block omitted or misclassified the funded shielded pool")
        action_count = len(matches[0][field])
    check()
    proof = {"schema_version":1,"txid_hex":submitted,"pool":recipient_pool,"amount_zatoshi":amount_zatoshi,
        "mined_height":target,"final_tip_height":tip+confirmations,"confirmations":confirmations,
        "source_height":source_height,"source_txid":source_txid,"source_vout":vout,
        "input_value_zatoshi":value,"fee_zatoshi":funding["fee_zatoshi"],"change_zatoshi":funding["change_zatoshi"],
        "raw_transaction_exact":True,"raw_compact_block_exact":True,"compact_action_count":action_count,
        "transparent_output":transparent,"wallet_or_catalog_pass":False}
    backend._write_text("funding-inclusion-"+uuid.uuid4().hex+".json", json.dumps({"proof":proof,"signer":funding},indent=2)+"\n")
    return proof
