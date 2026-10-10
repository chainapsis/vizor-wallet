"""Verify one original raw backend's empty genesis for the native LWD shim.

The immutable handoff is evidence, never cleanup authority or wallet PASS.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import os
import re
import time

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
from native_zakura_backend import OwnedNativeZakuraBackend


MAX_PROOF_BYTES = 64 * 1024
EMPTY_TREE_CODEC = "zakura-primitives-2.0.0:legacy-commitment-tree-none-none-empty-vector"
_NAME = "genesis-proof.json"
_TOKEN = object()


class ZakuraGenesisError(runtime.RunnerError):
    """Genesis identity, empty pools or the original handoff is unproven."""


def _tree_state(genesis_hash, block, node_tree):
    # The pinned SDK's write_commitment_tree encodes two Optional::None
    # values followed by an empty CompactSize parents vector: 00 00 00.
    if (not isinstance(genesis_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", genesis_hash)
        or genesis_hash == "0" * 64):
        raise ZakuraGenesisError("genesis hash is invalid")
    for label, value in (("block", block), ("tree", node_tree)):
        if (not isinstance(value, dict) or value.get("hash") != genesis_hash
            or type(value.get("height")) is not int or value["height"] != 0
            or type(value.get("time")) is not int or not 0 < value["time"] <= 0xFFFFFFFF):
            raise ZakuraGenesisError(f"genesis {label} identity is invalid")
    if block["time"] != node_tree["time"]:
        raise ZakuraGenesisError("genesis block and tree timestamps differ")
    transactions = block.get("tx")
    if (type(block.get("nTx")) is not int or block["nTx"] != 1
        or not isinstance(transactions, list) or len(transactions) != 1):
        raise ZakuraGenesisError("genesis must contain exactly its transparent coinbase")
    transaction = transactions[0]
    if not isinstance(transaction, dict):
        raise ZakuraGenesisError("genesis transaction is invalid")
    inputs = transaction.get("vin")
    if (type(transaction.get("version")) is not int or transaction["version"] != 1
        or transaction.get("overwintered") is not False
        or transaction.get("blockhash") != genesis_hash
        or type(transaction.get("height")) is not int or transaction["height"] != 0
        or not isinstance(inputs, list) or len(inputs) != 1 or not isinstance(inputs[0], dict)
        or not isinstance(inputs[0].get("coinbase"), str) or not inputs[0]["coinbase"]):
        raise ZakuraGenesisError("genesis transaction is not a version-one coinbase")
    if any(transaction.get(field) != [] for field in ("vShieldedSpend", "vShieldedOutput", "vjoinsplit")):
        raise ZakuraGenesisError("genesis contains shielded commitments")
    orchard = transaction.get("orchard")
    if not isinstance(orchard, dict) or orchard.get("actions") != []:
        raise ZakuraGenesisError("genesis contains Orchard actions or incomplete evidence")
    # Version-one genesis transactions have no Ironwood bundle on this pin.
    if "ironwood" in transaction:
        ironwood = transaction["ironwood"]
        if not isinstance(ironwood, dict) or ironwood.get("actions") != []:
            raise ZakuraGenesisError("genesis contains Ironwood actions or incomplete evidence")
    pools = block.get("valuePools")
    if not isinstance(pools, list):
        raise ZakuraGenesisError("genesis pool values are unavailable")
    for pool in ("sapling", "orchard", "ironwood"):
        if node_tree.get(pool) != {"commitments": {}}:
            raise ZakuraGenesisError("genesis is not an empty pre-activation tree")
        entries = [entry for entry in pools if isinstance(entry, dict) and entry.get("id") == pool]
        if (len(entries) != 1 or any(type(entries[0].get(field)) is not int or entries[0][field] != 0
                                   for field in ("chainValueZat", "valueDeltaZat"))):
            raise ZakuraGenesisError("genesis shielded pool value is not zero")
    return {"network": "regtest", "height": "0", "hash": genesis_hash, "time": node_tree["time"],
            "saplingTree": "000000", "orchardTree": "000000", "ironwoodTree": "000000"}


class OwnedZakuraGenesisProof:
    """An original published file, bound to its still-running backend handle."""
    def __init__(self, backend, identity, digest, upstream_port, state, token):
        if token is not _TOKEN:
            raise ZakuraGenesisError("use create_zakura_genesis_proof")
        self._backend, self._identity, self._digest = backend, identity, digest
        self._upstream_port = upstream_port
        self._fixture_run_id = backend._fixture.run_id
        self._state = copy.deepcopy(state)

    def tree_state(self):
        """Return the captured node-verified state only after original-file checks."""
        self.handoff()
        return copy.deepcopy(self._state)

    def handoff(self):
        """Recheck the original attachment before passing the file to a child."""
        backend = self._backend
        backend._running()
        if (backend._fixture.run_id != self._fixture_run_id
            or backend._fixture._lightwalletd_url != f"127.0.0.1:{self._upstream_port}"):
            raise ZakuraGenesisError("genesis proof backend identity changed")
        descriptor = os.open(_NAME, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=backend._directory_fd)
        try:
            details = os.fstat(descriptor)
            tree.check(details, directory=False, private=True)
            if tree.identity(details) != self._identity or details.st_mode & 0o777 != 0o400:
                raise ZakuraGenesisError("genesis proof original file identity changed")
            with os.fdopen(descriptor, "rb", closefd=False) as source:
                data = source.read(MAX_PROOF_BYTES + 1)
            if len(data) > MAX_PROOF_BYTES or hashlib.sha256(data).hexdigest() != self._digest:
                raise ZakuraGenesisError("genesis proof original bytes changed")
            backend._running()
            if (tree.identity(os.fstat(descriptor)) != self._identity
                or tree.identity(os.stat(_NAME, dir_fd=backend._directory_fd,
                                         follow_symlinks=False)) != self._identity):
                raise ZakuraGenesisError("genesis proof attachment changed during verification")
        finally:
            os.close(descriptor)
        return {"path": str(backend.root / _NAME), "sha256": self._digest,
                "fixture_run_id": self._fixture_run_id, "upstream_port": self._upstream_port}


def create_zakura_genesis_proof(case, backend, *, timeout=60.0, cancel_event=None):
    """Observe raw height zero, never borrow height one's frontier or fallback.

    Deadline/cancellation are checked between the pinned helper's synchronous
    calls; this does not claim interruption of an in-progress RPC.
    """
    if (not isinstance(case, NativeCaseLifecycle) or not isinstance(backend, OwnedNativeZakuraBackend)
        or backend._case is not case or not case.accepting_launches):
        raise ZakuraGenesisError("expected the original accepting case/backend pair")
    if (isinstance(timeout, bool) or not isinstance(timeout, (int, float))
        or not math.isfinite(timeout) or timeout <= 0):
        raise ZakuraGenesisError("genesis timeout must be positive and finite")
    deadline = time.monotonic() + timeout

    def check():
        if cancel_event is not None and cancel_event.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= deadline:
            raise ZakuraGenesisError("genesis verification deadline expired", 124)
        backend._running()

    def rpc(method, params):
        check()
        result = backend.rpc(method, params, deadline=deadline)
        check()
        return result

    check()
    ready = copy.deepcopy(backend._ready)
    fixture = backend._fixture
    identity = ready.get("identity")
    endpoint = ready.get("endpoints", {}).get("lightwalletd_url")
    match = re.fullmatch(r"127\.0\.0\.1:([1-9][0-9]{0,4})", endpoint or "")
    if (not isinstance(identity, dict) or identity.get("run_id") != fixture.run_id
        or not re.fullmatch(r"[0-9a-f]{32}", fixture.run_id)
        or match is None or not 1 <= int(match[1]) <= 65535
        or endpoint != fixture._lightwalletd_url):
        raise ZakuraGenesisError("genesis upstream does not match the original backend identity")
    genesis_hash = rpc("getblockhash", [0])
    block = rpc("getblock", [genesis_hash, 2])
    node_tree = rpc("z_gettreestate", [genesis_hash])
    state = _tree_state(genesis_hash, block, node_tree)
    if rpc("getblockhash", [0]) != genesis_hash:
        raise ZakuraGenesisError("owned genesis identity changed during verification")
    # Raw LWD limitations are diagnostic probes, not proof/cleanup authority.
    # The future shim consumes only this independently verified node evidence.
    proof = {"schema_version": 1, "fixture_run_id": fixture.run_id,
             "upstream_port": int(match[1]), "identity": identity,
             "source": backend._source.identity(), "genesis_block": block,
             "genesis_node_tree": node_tree, "tree_state": state,
             "empty_tree_codec": EMPTY_TREE_CODEC, "wallet_or_catalog_pass": False}
    data = bytearray()
    try:
        for chunk in json.JSONEncoder(sort_keys=True, separators=(",", ":"), allow_nan=False).iterencode(proof):
            encoded = chunk.encode("utf-8")
            if len(data) + len(encoded) + 1 > MAX_PROOF_BYTES:
                raise ZakuraGenesisError("genesis proof exceeds its bounded handoff size")
            data.extend(encoded)
    except (TypeError, ValueError, RecursionError) as error:
        raise ZakuraGenesisError("genesis proof is not finite JSON evidence") from error
    data.extend(b"\n")
    check()
    descriptor = os.open(_NAME, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=backend._directory_fd)
    with os.fdopen(descriptor, "wb") as output:
        output.write(data)
        output.flush()
        os.fchmod(output.fileno(), 0o400)
        os.fsync(output.fileno())
        file_identity = tree.identity(os.fstat(output.fileno()))
    check()
    result = OwnedZakuraGenesisProof(backend, file_identity, hashlib.sha256(data).hexdigest(), int(match[1]), state, _TOKEN)
    result.handoff()
    return result
