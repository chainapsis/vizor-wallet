"""Original-case unmined funding and held-safe expiry for native mempool E2Es."""
from __future__ import annotations

import json
import math
import threading
import time
import uuid

import e2e_runtime as runtime
from funder_execution import run_offline_funder
from native_case_lifecycle import NativeCaseLifecycle
from native_zakura_backend import OwnedNativeZakuraBackend
from zakura_funding import ZakuraFundingError, _base64_hex, _coinbase, _hex, _integer, _proto_integer


def _context(case, backend, timeout, cancel_event):
    if (not isinstance(case, NativeCaseLifecycle) or not isinstance(backend, OwnedNativeZakuraBackend)
        or backend._case is not case or not case.accepting_launches):
        raise ZakuraFundingError("mempool operation requires this original accepting case/backend")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise ZakuraFundingError("mempool timeout must be positive and finite")
    deadline = time.monotonic() + timeout
    cancel = cancel_event if cancel_event is not None else threading.Event()
    def check():
        if cancel.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= deadline:
            raise ZakuraFundingError("mempool operation deadline expired", 124)
        backend._running()
    def rpc(method, params=None):
        check()
        result = backend.rpc(method, params, deadline=deadline)
        check()
        return result
    check()
    return check, rpc, deadline, cancel


def fund_zakura_unmined(case, backend, artifact, *, recipient_address, amount_zatoshi,
                       source_height=1, expiry_height=None, timeout=120.0, cancel_event=None):
    """One independent Ironwood note from a mature explicit coinbase, without mining.

    The existing batch signer supplies expiry metadata. Raw node/mempool identity
    is checked separately; wallet decryption remains the actual app's assertion.
    """
    check, rpc, deadline, cancel = _context(case, backend, timeout, cancel_event)
    if not isinstance(recipient_address, str) or not recipient_address or len(recipient_address) > 4096:
        raise ZakuraFundingError("unmined recipient address is invalid")
    _integer(amount_zatoshi, "unmined zatoshis", minimum=1, maximum=2_100_000_000_000_000)
    _integer(source_height, "unmined source height", minimum=1)
    manifest = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    if manifest["regtest_ironwood_activation_height"] != 1:
        raise ZakuraFundingError("native mempool funding requires the height1 Ironwood profile")
    tip = _integer(rpc("getblockcount"), "unmined initial tip", minimum=1, maximum=0xFFFFFFFF-41)
    target = tip + 1
    if target < source_height + 100:
        raise ZakuraFundingError("unmined source is not mature")
    if expiry_height is not None:
        _integer(expiry_height, "unmined expiry", minimum=target+1, maximum=min(0xFFFFFFFF, target+10000))
    identity = run_offline_funder(case, artifact, "identity", timeout=deadline-time.monotonic(), cancel_event=cancel)
    if backend._fixture.miner_address != identity["miner_address"]:
        raise ZakuraFundingError("unmined miner differs from the original signer")
    block_hash = _hex(rpc("getblockhash", [source_height]), "unmined source hash", byte_count=32)
    txid, raw, vout, value = _coinbase(rpc("getblock", [block_hash, 2]), source_height, block_hash, identity["miner_address"])
    if not isinstance(rpc("gettxout", [txid, vout, True]), dict):
        raise ZakuraFundingError("unmined source is spent or unavailable")
    payments = [{"recipient_address":recipient_address, "amount_zatoshi":amount_zatoshi}]
    sources = [{"coinbase_source_height":source_height, "coinbase_txid":txid,
                "coinbase_vout":vout, "input_value_zatoshi":value}]
    request = {"schema_version":1, "coinbase_inputs":[{"coinbase_hex":raw,
        "coinbase_height":source_height, "coinbase_vout":vout}], "target_height":target,
        "recipient_pool":"ironwood", "nu6_3_activation_height":1,
        "payments":payments, "expiry_height":expiry_height}
    signed = run_offline_funder(case, artifact, "build-batch", request,
        timeout=deadline-time.monotonic(), cancel_event=cancel)
    fields = {"schema_version", "raw_tx_hex", "txid", "fee_zatoshi", "input_value_zatoshi",
        "amount_zatoshi", "change_zatoshi", "target_height", "expiry_height",
        "maturity_validated", "pools", "coinbase_inputs", "payments"}
    if not isinstance(signed, dict) or set(signed) != fields or type(signed["schema_version"]) is not int or signed["schema_version"] != 1:
        raise ZakuraFundingError("unmined signer fields are not exact schema-1 evidence")
    for field in ("fee_zatoshi", "input_value_zatoshi", "amount_zatoshi", "change_zatoshi"):
        _integer(signed[field], field, minimum=1, maximum=2_100_000_000_000_000)
    _integer(signed["target_height"], "unmined target", minimum=1)
    _integer(signed["expiry_height"], "signed unmined expiry", minimum=target+1, maximum=min(0xFFFFFFFF, target+10000))
    if (signed["amount_zatoshi"] != amount_zatoshi or signed["input_value_zatoshi"] != value
        or value != amount_zatoshi + signed["fee_zatoshi"] + signed["change_zatoshi"]
        or signed["target_height"] != target or signed["maturity_validated"] is not True
        or signed["pools"] != ["transparent", "ironwood"] or signed["coinbase_inputs"] != sources
        or signed["payments"] != payments
        or any(type(signed["coinbase_inputs"][0][key]) is not int
               for key in ("coinbase_source_height", "coinbase_vout", "input_value_zatoshi"))
        or type(signed["payments"][0]["amount_zatoshi"]) is not int
        or (expiry_height is not None and signed["expiry_height"] != expiry_height)):
        raise ZakuraFundingError("unmined signer source, payment, expiry or conservation differs")
    _hex(signed["txid"], "unmined signed txid", byte_count=32)
    _hex(signed["raw_tx_hex"], "unmined signed bytes")
    if rpc("getblockcount") != tip:
        raise ZakuraFundingError("unmined tip changed before submission")
    submitted = rpc("sendrawtransaction", [signed["raw_tx_hex"]])
    if submitted != signed["txid"]:
        raise ZakuraFundingError("node and unmined signer transaction IDs differ")
    while submitted not in rpc("getrawmempool"):
        time.sleep(min(0.05, max(0.0, deadline-time.monotonic())))
    observed = rpc("getrawtransaction", [submitted, 1])
    _pending_raw(observed, submitted, signed["expiry_height"], signed["raw_tx_hex"])
    if rpc("getblockcount") != tip:
        raise ZakuraFundingError("unmined funding advanced the original chain")
    proof = {"schema_version":1, "txid_hex":submitted, "amount_zatoshi":amount_zatoshi,
        "pool":"ironwood", "source_height":source_height, "expiry_height":signed["expiry_height"],
        "initial_tip_height":tip, "final_tip_height":tip, "mined_height":None, "confirmations":0,
        "exact_unmined_raw_verified":True, "wallet_or_catalog_pass":False}
    check()
    backend._write_text("funding-unmined-"+uuid.uuid4().hex+".json",
                        json.dumps({"proof":proof, "signer":signed}, indent=2)+"\n")
    return proof


def _pending_raw(raw, txid, expiry, expected_hex=None):
    expiries = [value for key, value in raw.items()
                if key.replace("_", "").lower() == "expiryheight"] if isinstance(raw, dict) else []
    if (not isinstance(raw, dict) or raw.get("txid") != txid
        or len(expiries) != 1 or type(expiries[0]) is not int or expiries[0] != expiry
        or type(raw.get("confirmations", 0)) is not int or raw.get("confirmations", 0) != 0
        or type(raw.get("height", 0)) is not int or raw.get("height", 0) != 0 or raw.get("blockhash")
        or (expected_hex is not None and raw.get("hex") != expected_hex)):
        raise ZakuraFundingError("unmined raw transaction or expiry differs")
    _hex(raw.get("hex"), "pending raw bytes")


def expire_zakura_unmined(case, backend, *, txid, expiry_height, timeout=120.0, cancel_event=None):
    """Original pinned fixture holds the exact pending bytes while mining a donor.

    Verify raw/compact exclusion at every adopted height, then actual mempool
    absence. This never changes transaction bytes or fabricates an app result.
    """
    _hex(txid, "expiry txid", byte_count=32)
    check, rpc, deadline, _cancel = _context(case, backend, timeout, cancel_event)
    before = backend.wait_synced(deadline=deadline)
    initial = _integer(before["height"], "expiry initial tip", minimum=1)
    _integer(expiry_height, "expiry target", minimum=initial+1, maximum=min(0xFFFFFFFF, initial+1000))
    raw = rpc("getrawtransaction", [txid, 1])
    _pending_raw(raw, txid, expiry_height)
    if txid not in rpc("getrawmempool"):
        raise ZakuraFundingError("expiry transaction is not in the original mempool")
    check()
    held = backend.hold_pending_transactions([txid], expiry_height=expiry_height, deadline=deadline)
    if (not isinstance(held, dict) or type(held.get("initial_tip_height")) is not int
        or type(held.get("expiry_height")) is not int or held != {"initial_tip_height":initial, "initial_tip_hash":before["hash"],
                "held_txids":[txid], "expiry_height":expiry_height}):
        raise ZakuraFundingError("original expiry hold proof differs")
    observations = []
    for height in range(initial+1, expiry_height+1):
        check()
        mined = backend.mine(1)
        check()
        hashes = mined.get("hashes")
        if not isinstance(hashes, list) or len(hashes) != 1 or mined.get("tip", {}).get("height") != height:
            raise ZakuraFundingError("expiry mining range differs")
        block_hash = _hex(hashes[0], "expiry block hash", byte_count=32)
        block = rpc("getblock", [block_hash, 2])
        compact = backend.grpc("GetBlock", {"height":str(height)}, deadline=deadline)
        check()
        if (not isinstance(block, dict) or block.get("hash") != block_hash or type(block.get("height")) is not int
            or block["height"] != height or not isinstance(block.get("tx"), list)
            or not isinstance(compact, dict) or _proto_integer(compact["height"], "expiry compact height") != height
            or _base64_hex(compact["hash"], "expiry compact hash", reverse=True, byte_count=32) != block_hash
            or not isinstance(compact.get("vtx", []), list)
            or any(tx.get("txid") == txid for tx in block["tx"])
            or any(_base64_hex(tx["txid"], "expiry compact txid", reverse=True, byte_count=32) == txid
                   for tx in compact.get("vtx", []))):
            raise ZakuraFundingError("expiry raw/compact exclusion is unproven")
        pending = rpc("getrawmempool")
        if not isinstance(pending, list) or (height < expiry_height and txid not in pending):
            raise ZakuraFundingError("expiry transaction vanished before its expiry")
        if txid in pending:
            _pending_raw(rpc("getrawtransaction", [txid, 1]), txid, expiry_height, raw["hex"])
        observations.append({"height":height, "hash":block_hash, "pending":txid in pending})
    parity = backend.wait_synced(deadline=deadline)
    if (parity.get("height") != expiry_height or parity.get("hash") != observations[-1]["hash"]
        or txid in rpc("getrawmempool")):
        raise ZakuraFundingError("original expiry parity or mempool absence is unproven")
    proof = {"schema_version":1, "txid_hex":txid, "expiry_height":expiry_height,
        "initial_tip_height":initial, "final_tip_height":expiry_height,
        "raw_compact_exclusion_verified":True, "expired_mempool_absence_verified":True,
        "wallet_or_catalog_pass":False}
    check()
    backend._write_text("funding-expiry-"+uuid.uuid4().hex+".json",
        json.dumps({"proof":proof, "held":held, "blocks":observations, "exact_raw_tx_hex":raw["hex"]}, indent=2)+"\n")
    return proof
