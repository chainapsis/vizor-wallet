"""One case's Zakura regtest node and lightwalletd, from the official images.

Each case gets its own Zakura node and lightwalletd on a private Docker
network: the official `zakuracore/zakura` image and the lightwalletd that
Zcash Labs builds for Zakura (`thus-spoke-zakura`), both pinned by digest.
Tests steer the chain only with RPCs Zakura ships for Regtest: `generate`,
`submitblock` and `invalidateblock`.

Zakura cannot keep a mempool transaction out of the blocks it mines; it has no
`prioritisetransaction`. To hold transactions pending while the chain moves, a
second node without peers mines the blocks and the main node accepts them
through `submitblock`. Reorgs use the same second node: it builds a longer
branch from the fork point, the main node drops its own branch with
`invalidateblock`, and then accepts the new one.
"""
from __future__ import annotations

import base64
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid

from e2e_runtime import RunnerError, run_logged_command
from native_ports import lease_native_ports


# zakuracore/zakura:1.6.0, the latest Zakura release.
ZAKURA_IMAGE = "zakuracore/zakura@sha256:bf53c178e9549217fce7cfaa21efc85c478129ba6dc5307d55640514affeb0ac"
# thus-spoke-zakura lightwalletd 0.3.0, from github.com/zcashlabs/thus-spoke-zakura.
LIGHTWALLETD_IMAGE = ("ghcr.io/zcashlabs/thus-spoke-zakura-lightwalletd@sha256:"
                      "ac78a456daee0bb98ceced333f5b8a2526b18b436ef90dc6033eef1686a92270")
PINNED_IMAGES = (ZAKURA_IMAGE, LIGHTWALLETD_IMAGE)
NU63_BRANCH_ID = "37a5165b"
NU62_BRANCH_ID = "5437f330"
# Zakura's Testnet lockbox address. Regtest's NU6.1 activation block pays the
# one-time lockbox disbursement configured with it.
LOCKBOX_ADDRESS = "t2RnBRiqrN1nW4ecZs1Fj3WWjNdnSs4kiX8"
RUN_LABEL = "com.keplr.vizor.e2e.zakura-run"
GRPC_SERVICE = "cash.z.wallet.sdk.rpc.CompactTxStreamer"
NODE_RPC_PORT = 18232
LIGHTWALLETD_PORT = 9067
MAX_HELD = 64
MAX_REORG_DEPTH = 512
MAX_STREAM_BYTES = 8 * 1024 * 1024
MAX_STREAM_MESSAGES = 10_000
# Zakura re-verifies its old mempool in the background after a reorg. A
# mempool that has not changed for this long is taken as settled.
SETTLE_SECONDS = 5.0
# Retrying a mutation after a short timeout could apply it twice.
_MUTATIONS = {"generate", "submitblock", "sendrawtransaction", "invalidateblock"}
_HASH = re.compile(r"[0-9a-f]{64}")
_TRANSPARENT = re.compile(r"(?:tm|t2)[1-9A-HJ-NP-Za-km-z]{33}")
_INSPECT_TIMEOUT_SECONDS = 60
_PULL_TIMEOUT_SECONDS = 900


class ZakuraRegtestError(RunnerError):
    """A node, lightwalletd or Docker operation failed or ran out of time."""


def _hash(value, what):
    if not isinstance(value, str) or not _HASH.fullmatch(value.lower()):
        raise ZakuraRegtestError(f"{what} is not a 32-byte hash")
    return value.lower()


def _hex(value, what):
    if not isinstance(value, str) or not value or len(value) % 2 or not re.fullmatch(r"[0-9a-fA-F]+", value):
        raise ZakuraRegtestError(f"{what} is not hex bytes")
    return value.lower()


def _number(value, what):
    if isinstance(value, bool) or not isinstance(value, (int, str)) or (isinstance(value, str) and not value.isdecimal()):
        raise ZakuraRegtestError(f"{what} is not a whole number")
    return int(value)


def _txids(value, *, minimum=1):
    if (not isinstance(value, list) or not minimum <= len(value) <= MAX_HELD
        or any(not isinstance(txid, str) or not _HASH.fullmatch(txid) for txid in value)
        or len(set(value)) != len(value)):
        raise ZakuraRegtestError(f"expected {minimum} to {MAX_HELD} distinct lowercase transaction IDs")
    return sorted(value)


def _remaining(deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ZakuraRegtestError("Zakura regtest operation ran out of time", 124)
    return remaining


def _pause(deadline, failure, *, seconds=0.1):
    """Sleep before the next poll, or fail with `failure` when the deadline would pass first."""
    if time.monotonic() + seconds >= deadline:
        raise ZakuraRegtestError(failure, 124)
    time.sleep(seconds)


def _final_state(tree, pool):
    value = tree.get(pool)
    commitments = value.get("commitments") if isinstance(value, dict) else None
    final = commitments.get("finalState") if isinstance(commitments, dict) else None
    if not isinstance(final, str):
        raise ZakuraRegtestError(f"the node has no {pool} tree")
    return final.lower()


def _block_id_hash(encoded, expected):
    """lightwalletd's latest block hash, in display order, and the byte order it came in."""
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (TypeError, ValueError) as error:
        raise ZakuraRegtestError("lightwalletd's latest block hash is not base64") from error
    for value, orientation in ((raw.hex(), "display"), (raw[::-1].hex(), "wire-reversed")):
        if len(raw) == 32 and value == expected:
            return value, orientation
    raise ZakuraRegtestError("lightwalletd's latest block is not the node's tip")


def _block_transactions(block):
    """Transaction IDs and raw bytes of a verbose block, coinbase first."""
    if not isinstance(block, dict) or not isinstance(block.get("tx"), list) or not block["tx"]:
        raise ZakuraRegtestError("getblock returned a block without transactions")
    transactions = {}
    for entry in block["tx"]:
        txid = _hash(entry.get("txid") if isinstance(entry, dict) else None, "block transaction ID")
        if txid in transactions:
            raise ZakuraRegtestError("a block lists one transaction twice")
        transactions[txid] = _hex(entry.get("hex"), "block transaction")
    return transactions


class ZakuraRegtest:
    """A node, lightwalletd, private network and lightwalletd volume for one case.

    NU6.3 (Ironwood) activates at `activation_height`: 1, or 500 for scenarios
    that fund Orchard first. Every Docker resource carries `labels`, and the
    runner removes or stops only resources whose labels still match. Evidence
    goes through `write_text(name, text)` into `artifacts`, which also holds
    the node's config.
    """

    def __init__(self, artifacts, grpcurl, proto_dir, *, run_id, miner_address, activation_height,
                 network_subnet=None, labels=None, write_text=None, timeout=60.0):
        if activation_height not in (1, 500):
            raise ZakuraRegtestError("Ironwood activates at height 1 or 500")
        if not isinstance(miner_address, str) or not _TRANSPARENT.fullmatch(miner_address):
            raise ZakuraRegtestError("miner_address must be a regtest transparent address")
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not 0 < timeout < math.inf:
            raise ZakuraRegtestError("timeout must be positive and finite")
        if network_subnet is not None:
            try:
                subnet = ipaddress.ip_network(network_subnet, strict=True)
            except (TypeError, ValueError) as error:
                raise ZakuraRegtestError("network_subnet is not a network") from error
            if subnet.version != 4 or not subnet.is_private or subnet.prefixlen > 29:
                raise ZakuraRegtestError("network_subnet must be a private IPv4 range of /29 or larger")
        self.artifacts = Path(artifacts)
        self.grpcurl = Path(grpcurl)
        self.proto_dir = Path(proto_dir)
        self.service_proto = self.proto_dir / "service.proto"
        if not os.access(self.grpcurl, os.X_OK) or not self.service_proto.is_file():
            raise ZakuraRegtestError("grpcurl or lightwalletd's service.proto is missing")
        self.run_id = uuid.UUID(str(run_id)).hex
        self.miner_address = miner_address
        self.activation_height = activation_height
        self.network_subnet = network_subnet
        self.timeout = float(timeout)
        prefix = "vizor-zakura-" + self.run_id[:12]
        self.network_name, self.node_name, self.donor_name = prefix + "-net", prefix + "-node", prefix + "-donor"
        self.lwd_name, self.lwd_volume = prefix + "-lwd", prefix + "-lwd-data"
        self.labels = {RUN_LABEL: self.run_id, **(labels or {})}
        self.config_path = self.artifacts / "zakurad.toml"
        self.lightwalletd_url = None
        self.closed = self.retained = False
        self._write = write_text or self._write_file
        self._started = False
        self._attempted = {}  # name -> kind, for every resource whose creation began
        self._ids = {}  # name -> Docker ID (a volume's is its name)
        self._leases = {}  # port role -> native port lease
        self._urls = {}  # "node"/"donor" -> RPC URL
        self._held = {}  # txid -> raw bytes kept out of blocks
        self._released = set()
        self._expiry = None
        self._reorgs = self._releases = 0
        self._cleanup = self._retention = None

    # Lifecycle

    def start(self):
        """Start the node and lightwalletd; return their identity and first sync check."""
        if self._started or self.closed or self.retained:
            raise ZakuraRegtestError("this regtest chain was already started")
        self._started = True
        deadline = time.monotonic() + self.timeout
        try:
            images = {"zakura": self._check_image(ZAKURA_IMAGE, deadline),
                      "lightwalletd": self._check_image(LIGHTWALLETD_IMAGE, deadline)}
            for kind, name in (("network", self.network_name), ("volume", self.lwd_volume),
                               ("container", self.node_name), ("container", self.lwd_name)):
                if self._present(kind, name, deadline):
                    raise ZakuraRegtestError(f"{kind} {name} already exists")
            self._write_config()
            subnet = ["--subnet", self.network_subnet] if self.network_subnet else []
            self._create("network", self.network_name,
                         ["network", "create", *self._label_args(), "--driver", "bridge", *subnet, self.network_name],
                         deadline)
            self._create("volume", self.lwd_volume, ["volume", "create", *self._label_args(), self.lwd_volume],
                         deadline)
            node = self._start_node("node", deadline)
            bootstrap = self._hashes(self.rpc("generate", [1], deadline=deadline), 1)
            port = self._lease("lightwalletd")
            self._create("container", self.lwd_name, [
                "create", "--name", self.lwd_name, *self._label_args(), "--network", self.network_name,
                "--publish", f"127.0.0.1:{port}:{LIGHTWALLETD_PORT}",
                "--mount", f"type=volume,src={self.lwd_volume},dst=/var/lib/lightwalletd", "--user", "0:0",
                LIGHTWALLETD_IMAGE, "--no-tls-very-insecure", "--grpc-bind-addr", f"0.0.0.0:{LIGHTWALLETD_PORT}",
                "--rpchost", "zakura", "--rpcport", str(NODE_RPC_PORT), "--rpcuser", "unused",
                "--rpcpassword", "unused", "--data-dir", "/var/lib/lightwalletd", "--log-file", "/dev/stdout",
            ], deadline, lease="lightwalletd")
            self._docker(["start", self.lwd_name], deadline)
            self._check_published(self.lwd_name, LIGHTWALLETD_PORT, port, deadline)
            self.lightwalletd_url = f"127.0.0.1:{port}"
            tip = self.wait_synced(deadline=deadline)
            if tip["height"] != 1 or tip["hash"] != bootstrap[0]:
                raise ZakuraRegtestError("lightwalletd did not reach the first block")
            proof = {"schema_version": 1,
                     "identity": {"run_id": self.run_id, "network": self._ids[self.network_name],
                                  "lightwalletd_volume": self.lwd_volume, "images": images,
                                  "containers": {name: self._ids[name] for name in (self.node_name, self.lwd_name)}},
                     "endpoints": {"node_rpc_url": self._urls["node"], "lightwalletd_url": self.lightwalletd_url},
                     "activation_height": self.activation_height, "miner_address": self.miner_address,
                     "node": node, "bootstrap": bootstrap, "tip": tip}
            self._write_json("start.json", proof)
            return proof
        except BaseException as error:
            self._diagnose("start-failure")
            try:
                cleanup = self.close()
            except Exception as cleanup_error:
                cleanup = {"errors": [str(cleanup_error)]}
            if cleanup.get("errors"):
                error.add_note(f"regtest cleanup after the failed start: {cleanup['errors']}")
            raise

    def retain(self):
        """Stop the containers, keeping them, the volume, network and port locks for inspection.

        Nothing can run on a retained chain, and it is never removed automatically.
        """
        if self.closed:
            raise ZakuraRegtestError("this regtest chain was already removed")
        if self.retained:
            return self._retention
        self.retained = True
        self._diagnose("retain")
        deadline = time.monotonic() + self.timeout
        stopped, errors = [], []
        for name in (self.donor_name, self.lwd_name, self.node_name):
            if name not in self._attempted:
                continue
            try:
                container = self._owned_id("container", name, deadline)
                if container is None:
                    continue
                self._docker(["stop", "--time", "5", container], deadline)
                state = self._inspect("container", name, deadline).get("State") or {}
                if state.get("Running") is not False or state.get("Restarting") or state.get("Paused"):
                    raise ZakuraRegtestError("the container is still running")
                stopped.append({"name": name, "id": container})
            except Exception as error:
                errors.append(f"container {name}: {error}")
        proof = {"schema_version": 1, "run_id": self.run_id, "mode": "stopped-and-kept", "stopped": stopped,
                 "identity": {"network": self._ids.get(self.network_name),
                              "lightwalletd_volume": self._ids.get(self.lwd_volume),
                              "containers": {name: self._ids[name] for name in
                                             (self.node_name, self.lwd_name, self.donor_name) if name in self._ids}},
                 "port_leases": sorted(self._leases), "errors": errors, "complete": not errors}
        try:
            self._write_json("retention.json", proof)
        except Exception as error:
            errors.append(f"retention record: {error}")
            proof["complete"] = False
        self._retention = proof
        return proof

    def close(self):
        """Remove the containers, volume and network, each only while its labels still match."""
        if self.retained:
            raise ZakuraRegtestError("a retained regtest chain is kept for inspection")
        if self._cleanup is not None and self.closed:
            return self._cleanup
        if self._ids:
            self._diagnose("close")
        deadline = time.monotonic() + self.timeout
        removed, errors = [], []
        for kind, name in (("container", self.donor_name), ("container", self.lwd_name),
                           ("container", self.node_name), ("volume", self.lwd_volume),
                           ("network", self.network_name)):
            if name not in self._attempted:
                continue
            try:
                resource = self._remove(kind, name, deadline)
                if resource is not None:
                    removed.append({"kind": kind, "name": name, "id": resource})
            except Exception as error:
                errors.append(f"{kind} {name}: {error}")
        for role, name in (("node", self.node_name), ("lightwalletd", self.lwd_name), ("donor", self.donor_name)):
            # A port stays locked while a container that publishes it may remain.
            if role in self._leases and name not in self._attempted:
                try:
                    self._leases.pop(role).close()
                except Exception as error:
                    errors.append(f"port lease {role}: {error}")
        proof = {"schema_version": 1, "run_id": self.run_id, "removed": removed, "errors": errors,
                 "complete": not errors}
        try:
            self._write_json("cleanup.json", proof)
        except Exception as error:
            errors.append(f"cleanup record: {error}")
            proof["complete"] = False
        self.closed = proof["complete"]
        self._cleanup = proof
        return proof

    # Node and lightwalletd calls

    def rpc(self, method, params=None, *, deadline=None):
        """Call the main node's JSON-RPC and return its result."""
        return self._call("node", method, params, deadline)

    def grpc(self, method, payload=None, *, deadline=None):
        """Call a unary lightwalletd method and return its JSON response."""
        output = self._grpc(method, payload, deadline, stream=False)
        try:
            value = json.loads(output)
        except ValueError as error:
            raise ZakuraRegtestError(f"gRPC {method} returned invalid JSON") from error
        if not isinstance(value, dict):
            raise ZakuraRegtestError(f"gRPC {method} returned a non-object")
        return value

    def grpc_stream(self, method, payload=None, *, deadline=None):
        """Call a server-streaming lightwalletd method and return its messages."""
        output = self._grpc(method, payload, deadline, stream=True)
        if len(output.encode()) > MAX_STREAM_BYTES:
            raise ZakuraRegtestError(f"gRPC {method} streamed more than {MAX_STREAM_BYTES} bytes")
        decoder, messages, offset = json.JSONDecoder(), [], 0
        while True:
            while offset < len(output) and output[offset].isspace():
                offset += 1
            if offset == len(output):
                return messages
            if len(messages) >= MAX_STREAM_MESSAGES:
                raise ZakuraRegtestError(f"gRPC {method} streamed more than {MAX_STREAM_MESSAGES} messages")
            try:
                message, offset = decoder.raw_decode(output, offset)
            except ValueError as error:
                raise ZakuraRegtestError(f"gRPC {method} streamed invalid JSON") from error
            if not isinstance(message, dict):
                raise ZakuraRegtestError(f"gRPC {method} streamed a non-object")
            messages.append(message)

    def wait_synced(self, *, deadline=None):
        """Wait until lightwalletd serves the node's tip: height, hash, time, trees and branch."""
        deadline = self._deadline(deadline)
        last_error, checked = None, time.monotonic()
        while True:
            self._require_running()
            try:
                return self._parity(deadline)
            except ZakuraRegtestError as error:
                last_error = error
            if time.monotonic() - checked >= 2:
                self._require_containers(deadline)
                checked = time.monotonic()
            if time.monotonic() >= deadline:
                raise ZakuraRegtestError(f"lightwalletd did not reach the node's tip: {last_error}", 124)
            time.sleep(min(0.1, max(0.0, deadline - time.monotonic())))

    # Chain control

    def mine(self, count):
        """Mine `count` blocks and wait until lightwalletd serves the new tip.

        While transactions are held, the second node mines the blocks without them.
        """
        if isinstance(count, bool) or not isinstance(count, int) or not 1 <= count <= 10_000:
            raise ZakuraRegtestError("block count must be 1 to 10000")
        self._require_running()
        if self._pending_holds():
            return self._mine_without_held(count)
        deadline = time.monotonic() + self.timeout
        height = _number(self.rpc("getblockcount", deadline=deadline), "node height")
        hashes = self._hashes(self.rpc("generate", [count], deadline=deadline), count)
        tip = self.wait_synced(deadline=deadline)
        if tip["height"] != height + count or tip["hash"] != hashes[-1]:
            raise ZakuraRegtestError("the mined blocks are not the chain tip")
        result = {"hashes": hashes, "tip": tip}
        self._write_json(f"mine-{tip['height']}.json", result)
        return result

    def hold_pending_transactions(self, txids, *, expiry_height=None, deadline=None):
        """Keep `txids` out of every block mined from now on; they leave the mempool only by expiring."""
        required = _txids(txids)
        self._require_running()
        self._require_no_hold()
        deadline = self._deadline(deadline)
        tip = self.wait_synced(deadline=deadline)
        if expiry_height is not None and (isinstance(expiry_height, bool) or not isinstance(expiry_height, int)
                                          or not tip["height"] < expiry_height <= tip["height"] + 10_000):
            raise ZakuraRegtestError("the expiry height must be above the tip")
        pool = self._wait_for_mempool(required, deadline)
        self._start_donor(tip["height"], deadline)
        current = self._mempool("node", deadline)
        if any(current.get(txid) != pool[txid] for txid in required):
            raise ZakuraRegtestError("a held transaction left the mempool while the second node started")
        self._held, self._released, self._expiry = {txid: pool[txid] for txid in required}, set(), expiry_height
        result = {"initial_tip_height": tip["height"], "initial_tip_hash": tip["hash"], "held_txids": required,
                  "expiry_height": expiry_height}
        self._write_json("pending-hold.json", dict(result, tip=tip))
        return result

    def replace_tip_holding(self, required_txids, *, deadline=None):
        """Replace the tip block with two empty blocks while `required_txids` stay pending."""
        return self._reorg(_txids(required_txids), None, deadline)

    def replace_fork_holding(self, required_txids, *, fork_height, deadline=None):
        """Replace every block above `fork_height` with an empty branch one block longer.

        `required_txids`, pending or mined in the replaced blocks, end up in the
        mempool. Everything pending afterwards stays out of blocks until released.
        """
        if isinstance(fork_height, bool) or not isinstance(fork_height, int) or fork_height < 1:
            raise ZakuraRegtestError("the fork height must be a positive height")
        return self._reorg(_txids(required_txids, minimum=0), fork_height, deadline)

    def release_held_transactions(self, txids, *, deadline=None):
        """Let held transactions into the blocks mined from now on."""
        requested = _txids(txids)
        self._require_running()
        if not set(requested) <= set(self._held):
            raise ZakuraRegtestError("only held transactions can be released")
        deadline = self._deadline(deadline)
        pool = self._mempool("node", deadline)
        if any(pool.get(txid) != self._held[txid] for txid in set(requested) - self._released):
            raise ZakuraRegtestError("a held transaction left the mempool or changed before its release")
        tip = self.wait_synced(deadline=deadline)
        self._released.update(requested)
        self._releases += 1
        result = {"released_txids": requested, "tip_height": tip["height"], "tip_hash": tip["hash"]}
        self._write_json(f"release-{self._releases}.json", dict(result, tip=tip))
        return result

    def _reorg(self, required, fork_height, deadline):
        self._require_running()
        self._require_no_hold()
        deadline = self._deadline(deadline)
        before = self.wait_synced(deadline=deadline)
        old_height, old_hash = before["height"], before["hash"]
        if fork_height is None:
            fork_height = old_height - 1
            # A tip replacement keeps transactions that are already pending.
            self._wait_for_mempool(required, deadline)
        depth = old_height - fork_height
        if fork_height < 1 or not 1 <= depth <= MAX_REORG_DEPTH:
            raise ZakuraRegtestError(f"cannot fork at height {fork_height} below the tip at {old_height}")
        fork_hash = _hash(self.rpc("getblockhash", [fork_height], deadline=deadline), "fork block hash")
        replaced, mined = [], {}
        for height in range(fork_height + 1, old_height + 1):
            block_hash = _hash(self.rpc("getblockhash", [height], deadline=deadline), "replaced block hash")
            replaced.append(block_hash)
            mined.update(list(_block_transactions(self.rpc("getblock", [block_hash, 2], deadline=deadline)).items())[1:])
        self._require_reorg_inputs(required, self._mempool("node", deadline), mined)

        self._start_donor(fork_height, deadline)
        replacement = self._hashes(self._call("donor", "generate", [depth + 1], deadline), depth + 1)
        raw_blocks, parent = [], fork_hash
        for offset, block_hash in enumerate(replacement, start=1):
            block = self._call("donor", "getblock", [block_hash, 2], deadline)
            if (len(_block_transactions(block)) != 1
                or _number(block.get("height"), "replacement height") != fork_height + offset
                or block.get("previousblockhash") != parent):
                raise ZakuraRegtestError("the replacement is not a chain of empty blocks on the fork")
            raw_blocks.append(_hex(self._call("donor", "getblock", [block_hash, 0], deadline), "replacement block"))
            parent = block_hash

        # Taken last, so that a transaction sent while the second node started is not lost.
        pending = self._mempool("node", deadline)
        self._require_reorg_inputs(required, pending, mined)
        if self.rpc("invalidateblock", [replaced[0]], deadline=deadline) is not None:
            raise ZakuraRegtestError("invalidateblock returned an unexpected result")
        self._wait_for_tip(fork_height, fork_hash, deadline)
        held, restoration = self._restore(required, pending, mined, deadline)
        for offset, (block_hash, raw) in enumerate(zip(replacement, raw_blocks), start=1):
            if self.rpc("submitblock", [raw], deadline=deadline) is not None:
                raise ZakuraRegtestError("the main node rejected a replacement block")
            if _hash(self.rpc("getblockhash", [fork_height + offset], deadline=deadline), "block hash") != block_hash:
                raise ZakuraRegtestError("the main node did not take the replacement block")
            # Asking for the mempool after every block also lets Zakura see each
            # block as growth rather than one more chain switch.
            if self._mempool("node", deadline) != held:
                raise ZakuraRegtestError("the mempool changed while the replacement branch was submitted")
        after = self.wait_synced(deadline=deadline)
        if after["height"] != old_height + 1 or after["hash"] != replacement[-1]:
            raise ZakuraRegtestError("lightwalletd did not reach the replacement tip")
        self._held, self._released, self._expiry = held, set(), None
        self._reorgs += 1
        result = {"fork_height": fork_height, "old_tip_height": old_height, "old_tip_hash": old_hash,
                  "invalidated_hash": replaced[0], "new_tip_height": after["height"],
                  "new_tip_hash": after["hash"], "replacement_hashes": replacement,
                  "held_txids": sorted(held), "reintroduced_txids": sorted(set(held) - set(pending)),
                  "reintroduction": restoration}
        self._write_json(f"reorg-{self._reorgs}.json",
                         dict(result, replaced_hashes=replaced, before=before, after=after))
        return result

    @staticmethod
    def _require_reorg_inputs(required, pending, mined):
        if not set(required) <= set(pending) | set(mined):
            raise ZakuraRegtestError("required transactions are neither pending nor in the replaced blocks")

    def _restore(self, required, pending, mined, deadline):
        """Bring `required` back into the mempool after `invalidateblock`.

        Zakura empties its mempool when the best chain switches and re-verifies
        the old contents in the background; transactions from the dropped blocks
        do not come back. The required ones among those are sent again.
        """
        pool = self._settled_mempool(pending, deadline)
        resubmitted = []
        for txid, raw in mined.items():
            if txid in required and txid not in pool:
                if self.rpc("sendrawtransaction", [raw], deadline=deadline) != txid:
                    raise ZakuraRegtestError("sendrawtransaction returned another transaction ID")
                resubmitted.append(txid)
        held = self._mempool("node", deadline)
        if not set(required) <= set(held):
            raise ZakuraRegtestError(f"required transactions did not return: {sorted(set(required) - set(held))}")
        if any(raw != mined.get(txid, pending.get(txid)) for txid, raw in held.items()):
            raise ZakuraRegtestError("the mempool holds a transaction from outside the reorg")
        return held, {"resubmitted_txids": sorted(resubmitted),
                      "preserved_pending_txids": sorted(set(pending) & set(held)),
                      "invalidated_pending_txids": sorted(set(pending) - set(held))}

    def _mine_without_held(self, count):
        deadline = time.monotonic() + self.timeout
        tip = self.wait_synced(deadline=deadline)
        hashes, blocks = [], []
        for _ in range(count):
            self._require_peerless(deadline)
            pool = self._mempool("node", deadline)
            held = self._check_held(pool, tip["height"])
            allowed = {txid: raw for txid, raw in pool.items() if txid not in held}
            self._send_to_donor(allowed, deadline)
            block_hash = self._hashes(self._call("donor", "generate", [1], deadline), 1)[0]
            block = self._call("donor", "getblock", [block_hash, 2], deadline)
            included = _block_transactions(block)
            if (_number(block.get("height"), "block height") != tip["height"] + 1
                or _hash(block.get("previousblockhash"), "parent hash") != tip["hash"]
                or dict(list(included.items())[1:]) != allowed):
                raise ZakuraRegtestError("the second node's block is not the allowed transactions on the tip")
            raw = _hex(self._call("donor", "getblock", [block_hash, 0], deadline), "raw block")
            if self.rpc("submitblock", [raw], deadline=deadline) is not None:
                raise ZakuraRegtestError("the main node rejected the second node's block")
            tip = self.wait_synced(deadline=deadline)
            if tip["hash"] != block_hash:
                raise ZakuraRegtestError("the second node's block is not the main tip")
            hashes.append(block_hash)
            blocks.append({"hash": block_hash, "height": tip["height"], "included_txids": sorted(allowed),
                           "held_txids": sorted(held)})
        self._check_held(self._mempool("node", deadline), tip["height"])
        result = {"hashes": hashes, "tip": tip}
        self._write_json(f"mine-{tip['height']}.json", dict(result, blocks=blocks))
        return result

    def _check_held(self, pool, height):
        """Held transactions still pending; an expired one is let go once the tip reaches its expiry."""
        pending = {}
        for txid, raw in list(self._held.items()):
            if txid in self._released:
                continue
            if pool.get(txid) == raw:
                pending[txid] = raw
            elif txid not in pool and self._expiry is not None and height >= self._expiry:
                del self._held[txid]
            else:
                raise ZakuraRegtestError(f"held transaction {txid} left the mempool or changed")
        return pending

    def _pending_holds(self):
        return set(self._held) - self._released

    def _require_no_hold(self):
        if self._pending_holds():
            raise ZakuraRegtestError("transactions are still held; release them first")

    # Second node

    def _start_donor(self, height, deadline):
        """A fresh second node holding the main chain up to `height` and an empty mempool."""
        if self.donor_name in self._attempted:
            self._remove("container", self.donor_name, deadline)
            self._urls.pop("donor", None)
            if "donor" in self._leases:
                self._leases.pop("donor").close()
        self._start_node("donor", deadline)
        if _number(self._call("donor", "getblockcount", [], deadline), "second node height") != 0:
            raise ZakuraRegtestError("the second node did not start at genesis")
        if (_hash(self._call("donor", "getblockhash", [0], deadline), "genesis hash")
                != _hash(self.rpc("getblockhash", [0], deadline=deadline), "genesis hash")):
            raise ZakuraRegtestError("the second node has another genesis block")
        for current in range(1, height + 1):
            block_hash = self.rpc("getblockhash", [current], deadline=deadline)
            raw = _hex(self.rpc("getblock", [block_hash, 0], deadline=deadline), "raw block")
            if self._call("donor", "submitblock", [raw], deadline) is not None:
                raise ZakuraRegtestError(f"the second node rejected block {current}")
        if (_hash(self._call("donor", "getbestblockhash", [], deadline), "second node tip")
                != _hash(self.rpc("getblockhash", [height], deadline=deadline), "main block hash")
            or self._call("donor", "z_gettreestate", [str(height)], deadline)
                != self.rpc("z_gettreestate", [str(height)], deadline=deadline)):
            raise ZakuraRegtestError("the second node did not reach the main chain")
        if self._call("donor", "getrawmempool", [], deadline) != []:
            raise ZakuraRegtestError("the second node's mempool is not empty")
        self._require_peerless(deadline)

    def _send_to_donor(self, transactions, deadline):
        waiting = dict(transactions)
        while waiting:
            accepted = []
            for txid, raw in waiting.items():
                try:
                    result = self._call("donor", "sendrawtransaction", [raw], deadline)
                except ZakuraRegtestError:
                    continue  # A child can come before its parent; try it again after the others.
                if result != txid:
                    raise ZakuraRegtestError("sendrawtransaction returned another transaction ID")
                accepted.append(txid)
            if not accepted:
                raise ZakuraRegtestError(f"the second node rejected {sorted(waiting)}")
            for txid in accepted:
                del waiting[txid]
        if self._mempool("donor", deadline) != transactions:
            raise ZakuraRegtestError("the second node's mempool is not the allowed transactions")

    def _require_peerless(self, deadline):
        # A peer would relay the held transactions to the second node.
        for node in self._urls:
            if self._call(node, "getpeerinfo", [], deadline) != []:
                raise ZakuraRegtestError(f"the {node} has peers")

    # Chain and mempool observations

    def _parity(self, deadline):
        info = self.rpc("getblockchaininfo", deadline=deadline)
        height = _number(info.get("blocks") if isinstance(info, dict) else None, "node height")
        tip = _hash(self.rpc("getbestblockhash", deadline=deadline), "node tip hash")
        tree = self.rpc("z_gettreestate", [str(height)], deadline=deadline)
        if (not isinstance(tree, dict) or _number(tree.get("height"), "tree height") != height
            or str(tree.get("hash", "")).lower() != tip):
            raise ZakuraRegtestError("the node's tree state is not at its tip")
        lightd = self.grpc("GetLightdInfo", deadline=deadline)
        latest = self.grpc("GetLatestBlock", deadline=deadline)
        lwd_tree = self.grpc("GetTreeState", {"height": str(height)}, deadline=deadline)
        if (_number(lightd.get("blockHeight"), "lightwalletd height") != height
            or _number(latest.get("height"), "lightwalletd latest height") != height
            or _number(lwd_tree.get("height"), "lightwalletd tree height") != height
            or str(lwd_tree.get("hash", "")).lower() != tip):
            raise ZakuraRegtestError(f"lightwalletd has not reached height {height}")
        latest_hash, orientation = _block_id_hash(latest.get("hash"), tip)
        time_ = _number(tree.get("time"), "node tree time")
        if _number(lwd_tree.get("time"), "lightwalletd tree time") != time_:
            raise ZakuraRegtestError("lightwalletd's tree state time differs from the node's")
        fields = {"sapling": "saplingTree", "orchard": "orchardTree"}
        if height >= self.activation_height:
            fields["ironwood"] = "ironwoodTree"
        trees = {}
        for pool, field in fields.items():
            trees[pool] = _final_state(tree, pool)
            if str(lwd_tree.get(field, "")).lower() != trees[pool]:
                raise ZakuraRegtestError(f"lightwalletd's {pool} tree differs from the node's")
        branch = str(lightd.get("consensusBranchId", "")).lower()
        if branch != (NU63_BRANCH_ID if height >= self.activation_height else NU62_BRANCH_ID):
            raise ZakuraRegtestError(f"lightwalletd reports consensus branch {branch} at height {height}")
        chain = lightd.get("chainName")
        if chain not in {"test", "regtest"} or lwd_tree.get("network") != chain:
            raise ZakuraRegtestError("lightwalletd does not report a test chain")
        return {"height": height, "hash": tip, "time": time_, "trees": trees, "latest_block_hash": latest_hash,
                "latest_block_hash_orientation": orientation, "chain_name": chain,
                "consensus_branch_id": branch}

    def _mempool(self, node, deadline):
        txids = self._call(node, "getrawmempool", [], deadline)
        if (not isinstance(txids, list) or len(txids) > 1000
            or any(not isinstance(txid, str) or not _HASH.fullmatch(txid) for txid in txids)):
            raise ZakuraRegtestError("getrawmempool returned something other than transaction IDs")
        pool = {}
        for txid in sorted(set(txids)):
            entry = self._call(node, "getrawtransaction", [txid, 1], deadline)
            if not isinstance(entry, dict) or entry.get("txid") != txid:
                raise ZakuraRegtestError("getrawtransaction returned another transaction")
            pool[txid] = _hex(entry.get("hex"), "mempool transaction")
        return pool

    def _wait_for_mempool(self, txids, deadline):
        while True:
            pool = self._mempool("node", deadline)
            if set(txids) <= set(pool):
                return pool
            _pause(deadline, f"transactions did not reach the mempool: {sorted(set(txids) - set(pool))}")

    def _settled_mempool(self, previous, deadline):
        """The mempool once every `previous` transaction is back or it stopped changing."""
        last, quiet_since = None, time.monotonic()
        while True:
            pool = self._mempool("node", deadline)
            if last is None or set(pool) != set(last):
                last, quiet_since = pool, time.monotonic()
            if set(previous) <= set(pool) or time.monotonic() - quiet_since >= SETTLE_SECONDS:
                return pool
            _pause(deadline, "the mempool did not settle after the reorg", seconds=0.25)

    def _wait_for_tip(self, height, block_hash, deadline):
        while True:
            if (_number(self.rpc("getblockcount", deadline=deadline), "node height") == height
                and _hash(self.rpc("getbestblockhash", deadline=deadline), "node tip hash") == block_hash):
                return
            _pause(deadline, f"the main node did not fall back to block {height}", seconds=0.05)

    @staticmethod
    def _hashes(value, count):
        if not isinstance(value, list) or len(value) != count:
            raise ZakuraRegtestError(f"generate did not return {count} block hashes")
        return [_hash(item, "generated block hash") for item in value]

    # Docker

    def _start_node(self, role, deadline):
        """Create and start the main or second node; return what it answered first."""
        name, alias = (self.node_name, "zakura") if role == "node" else (self.donor_name, "zakura-donor")
        port = self._lease(role)
        self._create("container", name, [
            "create", "--name", name, *self._label_args(), "--network", self.network_name,
            "--network-alias", alias, "--publish", f"127.0.0.1:{port}:{NODE_RPC_PORT}",
            "--mount", f"type=bind,src={self.config_path},dst=/config/zakurad.toml,readonly",
            "--env", "CONFIG_FILE_PATH=/config/zakurad.toml", ZAKURA_IMAGE, "zakurad", "start",
        ], deadline, lease=role)
        self._docker(["start", name], deadline)
        self._check_published(name, NODE_RPC_PORT, port, deadline)
        self._urls[role] = f"http://127.0.0.1:{port}"
        last_error, checked = None, time.monotonic()
        while True:
            try:
                info = self._call(role, "getblockchaininfo", [], deadline)
                if isinstance(info, dict):
                    return {"blockchain": info, "best_hash": _hash(self._call(role, "getbestblockhash", [], deadline),
                                                                   "best block hash")}
            except ZakuraRegtestError as error:
                last_error = error
            if time.monotonic() - checked >= 2:
                if (self._inspect("container", name, deadline).get("State") or {}).get("Running") is not True:
                    raise ZakuraRegtestError(f"{name} stopped before its RPC answered: {last_error}")
                checked = time.monotonic()
            if time.monotonic() >= deadline:
                raise ZakuraRegtestError(f"{name} RPC did not answer: {last_error}", 124)
            time.sleep(min(0.1, max(0.0, deadline - time.monotonic())))

    def _lease(self, role):
        lease = lease_native_ports(0, self.run_id[:10], port_names=(role,))
        self._leases[role] = lease
        return lease.ports[role]

    def _create(self, kind, name, args, deadline, *, lease=None):
        self._attempted[name] = kind
        if lease is not None:
            # Free the reserved socket so Docker can publish the port; the lock stays.
            self._leases[lease].release_sockets()
        created = self._docker(args, deadline).stdout.strip()
        if not created or (kind == "volume" and created != name):
            raise ZakuraRegtestError(f"docker did not create {kind} {name}")
        self._ids[name] = created
        if self._owned_id(kind, name, deadline) is None:
            raise ZakuraRegtestError(f"{kind} {name} vanished after it was created")

    def _remove(self, kind, name, deadline):
        """Remove an owned resource; return its ID, or None when it was never there."""
        resource = self._owned_id(kind, name, deadline)
        if resource is not None:
            self._docker([kind, "rm", *(["--force"] if kind == "container" else []), resource], deadline)
            if self._present(kind, name, deadline):
                raise ZakuraRegtestError(f"{kind} {name} is still present after removal")
        self._attempted.pop(name, None)
        self._ids.pop(name, None)
        return resource

    def _owned_id(self, kind, name, deadline):
        """The resource's ID when it exists and carries this run's labels, else None if absent."""
        if not self._present(kind, name, deadline):
            return None
        inspected = self._inspect(kind, name, deadline)
        labels = (inspected.get("Config") or {}).get("Labels") if kind == "container" else inspected.get("Labels")
        if not isinstance(labels, dict) or any(labels.get(key) != value for key, value in self.labels.items()):
            raise ZakuraRegtestError(f"{kind} {name} does not carry this run's labels")
        resource = inspected.get("Name") if kind == "volume" else inspected.get("Id")
        if not isinstance(resource, str) or self._ids.get(name, resource) != resource:
            raise ZakuraRegtestError(f"{kind} {name} is not the one this run created")
        return resource

    def _present(self, kind, name, deadline):
        command = {"container": ["container", "ls", "--all", "--filter", f"name={name}", "--format", "{{.Names}}"],
                   "network": ["network", "ls", "--filter", f"name={name}", "--format", "{{.Name}}"],
                   "volume": ["volume", "ls", "--filter", f"name={name}", "--format", "{{.Name}}"]}[kind]
        return name in self._docker(command, deadline).stdout.split()

    def _inspect(self, kind, name, deadline):
        try:
            inspected = json.loads(self._docker([kind, "inspect", name], deadline).stdout)
        except ValueError as error:
            raise ZakuraRegtestError(f"docker {kind} inspect returned invalid JSON") from error
        if not isinstance(inspected, list) or len(inspected) != 1 or not isinstance(inspected[0], dict):
            raise ZakuraRegtestError(f"docker {kind} inspect did not return one {kind}")
        return inspected[0]

    def _check_image(self, reference, deadline):
        image = self._docker(["image", "inspect", "--format", "{{.Id}}", reference], deadline).stdout.strip()
        if image != reference.rsplit("@", 1)[1]:
            raise ZakuraRegtestError(f"the local image is not the pinned one: {reference}")
        return {"reference": reference, "id": image}

    def _check_published(self, name, container_port, port, deadline):
        published = self._docker(["port", name, f"{container_port}/tcp"], deadline).stdout.split()
        if published != [f"127.0.0.1:{port}"]:
            raise ZakuraRegtestError(f"{name} did not publish only 127.0.0.1:{port}")

    def _require_containers(self, deadline):
        for name in (self.node_name, self.lwd_name):
            if name in self._ids and (self._inspect("container", name, deadline).get("State") or {}).get(
                    "Running") is not True:
                raise ZakuraRegtestError(f"container {name} stopped")

    def _diagnose(self, label):
        """Save each container's state and log; a failure here never replaces the original error."""
        deadline = time.monotonic() + min(self.timeout, 10.0)
        for role, name in (("node", self.node_name), ("donor", self.donor_name), ("lightwalletd", self.lwd_name)):
            if name not in self._ids:
                continue
            try:
                self._write_json(f"{label}-{role}-inspect.json", self._inspect("container", name, deadline))
                logs = self._docker(["logs", self._ids[name]], deadline, check=False)
                self._write(f"{label}-{role}.log", logs.stdout + logs.stderr)
            except Exception as error:
                try:
                    self._write(f"{label}-{role}-diagnostic-error.txt", str(error))
                except Exception:
                    pass

    def _label_args(self):
        return [argument for key, value in self.labels.items() for argument in ("--label", f"{key}={value}")]

    def _docker(self, args, deadline, *, check=True):
        return self._run(["docker", *args], timeout=_remaining(deadline), check=check)

    @staticmethod
    def _run(command, *, timeout, check=True):
        try:
            completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ZakuraRegtestError(f"{' '.join(command[:3])} failed: {error}") from error
        if check and completed.returncode != 0:
            detail = (completed.stderr.strip() or completed.stdout.strip())[:500]
            raise ZakuraRegtestError(f"{' '.join(command[:3])} exited {completed.returncode}: {detail}")
        return completed

    # Plumbing

    def _call(self, node, method, params, deadline):
        self._require_running()
        url = self._urls.get(node)
        if url is None:
            raise ZakuraRegtestError(f"the {node} RPC is not running")
        if not isinstance(method, str) or not method or not isinstance(params, (list, type(None))):
            raise ZakuraRegtestError("an RPC needs a method name and a parameter list")
        remaining = _remaining(self._deadline(deadline))
        body = json.dumps({"jsonrpc": "2.0", "id": self.run_id, "method": method, "params": params or []})
        try:
            payload = json.loads(self._post(url, body.encode(),
                                            remaining if method in _MUTATIONS else min(5.0, remaining)))
        except (OSError, ValueError) as error:
            raise ZakuraRegtestError(f"RPC {method} failed: {error}") from error
        if not isinstance(payload, dict) or payload.get("id") != self.run_id:
            raise ZakuraRegtestError(f"RPC {method} answered another request")
        if payload.get("error") is not None:
            raise ZakuraRegtestError(f"RPC {method} failed: {payload['error']}")
        if "result" not in payload:
            raise ZakuraRegtestError(f"RPC {method} returned no result")
        return payload["result"]

    @staticmethod
    def _post(url, body, timeout):
        """POST a JSON-RPC request and return the response body, also for an HTTP error status."""
        request = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"},
                                         method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            # Zakura reports some RPC errors with an HTTP error status.
            return error.read()

    def _grpc(self, method, payload, deadline, *, stream):
        self._require_running()
        if not isinstance(method, str) or not re.fullmatch(r"[A-Za-z]+", method):
            raise ZakuraRegtestError("a gRPC method is a plain name")
        if payload is not None and not isinstance(payload, dict):
            raise ZakuraRegtestError("a gRPC payload is an object")
        if self.lightwalletd_url is None:
            raise ZakuraRegtestError("lightwalletd is not running")
        remaining = _remaining(self._deadline(deadline))
        # A unary call that hangs must not use up a sync wait's whole deadline.
        limit = remaining if stream else min(10.0, remaining)
        command = [str(self.grpcurl), "-plaintext", *(["-emit-defaults"] if stream else []),
                   "-max-time", f"{limit:.3f}", "-import-path", str(self.proto_dir),
                   "-proto", self.service_proto.name, "-d", json.dumps(payload or {}),
                   self.lightwalletd_url, f"{GRPC_SERVICE}/{method}"]
        return self._run(command, timeout=limit + 1).stdout

    def _deadline(self, deadline):
        return time.monotonic() + self.timeout if deadline is None else deadline

    def _require_running(self):
        if not self._started or self.closed or self.retained:
            raise ZakuraRegtestError("the regtest chain is not running")

    def _write_config(self):
        activation = '"NU6.3" = 1' if self.activation_height == 1 else '"NU6.2" = 1\n"NU6.3" = 500'
        self._write(self.config_path.name, f"""[network]
network = "Regtest"
listen_addr = "0.0.0.0:18233"
p2p_stack = "legacy"
cache_dir = false
initial_testnet_peers = []

[network.testnet_parameters.activation_heights]
{activation}

[[network.testnet_parameters.lockbox_disbursements]]
address = "{LOCKBOX_ADDRESS}"
amount = 0

[rpc]
listen_addr = "0.0.0.0:{NODE_RPC_PORT}"
enable_cookie_auth = false
parallel_cpu_threads = 1

[sync]
parallel_cpu_threads = 1

[state]
ephemeral = false
cache_dir = "/home/zebra/.cache/zakura"
should_backup_non_finalized_state = true

[mempool]
# Without this the mempool waits for a sync that never comes on Regtest.
debug_enable_at_height = 0

[mining]
internal_miner = false
miner_address = "{self.miner_address}"

[tracing]
use_color = false
""")
        # The node runs as another user inside its container.
        os.chmod(self.config_path, 0o644)

    def _write_json(self, name, payload):
        self._write(name, json.dumps(payload, indent=2, sort_keys=True) + "\n")

    def _write_file(self, name, text):
        temporary = self.artifacts / f".{name}.{uuid.uuid4().hex}.tmp"
        temporary.write_text(text, encoding="utf-8")
        os.replace(temporary, self.artifacts / name)


def _inspect_image(command, timeout):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RunnerError(f"docker image inspect could not run: {error}") from error


def _local_image_id(reference, inspect):
    completed = inspect(["docker", "image", "inspect", "--format", "{{.Id}}", reference],
                        _INSPECT_TIMEOUT_SECONDS)
    if completed.returncode == 0:
        return completed.stdout.strip()
    if "No such image" in completed.stderr:
        return None
    raise RunnerError(f"docker image inspect failed for {reference}: {completed.stderr.strip()[:200]}")


def ensure_pinned_images(log_dir, *, cancel_event, out=print, inspect=_inspect_image, pull=None):
    """Pull, by digest, any pinned image the Docker daemon lacks.

    The images carry no tag, so `docker image prune` removes them, and then
    every case fails when it starts its node. A pull by digest restores the
    same bytes; each case still checks the image identity when it starts.
    Returns whether each image was present or pulled.
    """
    log_dir = Path(log_dir)
    if pull is None:
        def pull(reference, log_path):
            return run_logged_command(["docker", "pull", reference], cwd=log_dir, env=dict(os.environ),
                                      log_path=log_path, timeout=_PULL_TIMEOUT_SECONDS,
                                      cancel_event=cancel_event).returncode
    status = {}
    for index, reference in enumerate(PINNED_IMAGES):
        found = _local_image_id(reference, inspect)
        if found is None:
            log_path = log_dir / f"pinned-image-pull-{index}.log"
            out(f"Pulling pinned Docker image {reference}; log: {log_path}")
            if pull(reference, log_path) != 0:
                raise RunnerError(f"docker pull failed for {reference}; see {log_path}")
            found = _local_image_id(reference, inspect)
            status[reference] = "pulled"
        else:
            status[reference] = "present"
        if found != reference.rsplit("@", 1)[1]:
            raise RunnerError(f"local image identity does not match pinned digest: {reference}")
    return status
