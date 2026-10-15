"""ZakuraRegtest against modeled Docker, Zakura nodes and lightwalletd; no container runs."""
from __future__ import annotations

import base64
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import zakura_regtest as REGTEST
    from e2e_runtime import RunnerError
finally:
    sys.path.pop(0)


MINER = "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX"


def digest(*parts):
    return hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()


class RpcError(Exception):
    pass


class World:
    """Blocks and transactions every modeled node can decode, like the shared wire format."""

    def __init__(self):
        self.transactions = {}
        genesis = {"hash": digest("genesis"), "height": 0, "prev": None, "txids": [], "time": 1_700_000_000}
        self.blocks = {genesis["hash"]: genesis}
        self.genesis = genesis["hash"]

    def transaction(self, name, *, anchor=None, expiry=None):
        txid = digest("transaction", name)
        self.transactions[txid] = {"raw": "aa" + txid, "anchor": anchor, "expiry": expiry}
        return txid

    def raw(self, txid):
        return self.transactions[txid]["raw"]

    def txid(self, raw):
        return next((txid for txid, tx in self.transactions.items() if tx["raw"] == raw), None)


class Node:
    """A Regtest Zakura node: mines its whole mempool, resets it when the chain switches."""

    def __init__(self, world, name):
        self.world, self.name = world, name
        self.chain = [world.genesis]
        self.mempool = {}
        self.reverifying = []
        self.peers = []
        self.coinbases = 0
        self.calls = []

    def tip(self):
        return self.chain[-1]

    def valid(self, txid):
        transaction = self.world.transactions[txid]
        mined = {item for block in self.chain for item in self.world.blocks[block]["txids"]}
        return (txid not in mined and (transaction["expiry"] is None or transaction["expiry"] >= len(self.chain))
                and (transaction["anchor"] is None or transaction["anchor"] in self.chain))

    def connect(self, block):
        self.chain.append(block["hash"])
        self.mempool = {txid: raw for txid, raw in self.mempool.items() if self.valid(txid)}

    def mine_block(self):
        height = len(self.chain)
        self.coinbases += 1
        coinbase = digest("coinbase", self.name, height, self.coinbases)
        self.world.transactions[coinbase] = {"raw": "cc" + coinbase, "anchor": None, "expiry": None}
        txids = [coinbase, *sorted(self.mempool)]
        block = {"hash": digest("block", self.tip(), *txids), "height": height, "prev": self.tip(),
                 "txids": txids, "time": self.world.blocks[self.tip()]["time"] + 1}
        self.world.blocks[block["hash"]] = block
        self.connect(block)
        return block["hash"]

    def poll(self):
        """Background re-verification after a reset lands after two mempool requests."""
        waiting = []
        for txid, left in self.reverifying:
            if left:
                waiting.append((txid, left - 1))
            elif self.valid(txid):
                self.mempool[txid] = self.world.raw(txid)
        self.reverifying = waiting

    def rpc(self, method, params):
        self.calls.append(method)
        if method in {"getrawmempool", "getrawtransaction", "sendrawtransaction"}:
            self.poll()
        if method == "getblockchaininfo":
            return {"chain": "regtest", "blocks": len(self.chain) - 1}
        if method == "getbestblockhash":
            return self.tip()
        if method == "getblockcount":
            return len(self.chain) - 1
        if method == "getblockhash":
            if not 0 <= params[0] < len(self.chain):
                raise RpcError("block height not in best chain")
            return self.chain[params[0]]
        if method == "getblock":
            block = self.world.blocks[params[0]]
            if params[1] == 0:
                return "b1" + block["hash"]
            return {"hash": block["hash"], "height": block["height"], "previousblockhash": block["prev"],
                    "tx": [{"txid": txid, "hex": self.world.raw(txid)} for txid in block["txids"]]}
        if method == "z_gettreestate":
            return tree(self.world.blocks[self.chain[int(params[0])]])
        if method == "generate":
            return [self.mine_block() for _ in range(params[0])]
        if method == "submitblock":
            block = self.world.blocks[params[0][2:]]
            if block["prev"] != self.tip():
                return "rejected"
            self.connect(block)
            return None
        if method == "invalidateblock":
            self.chain = self.chain[:self.chain.index(params[0])]
            # Zakura empties its mempool on a chain switch and re-verifies the old contents in the background.
            self.reverifying = [(txid, 2) for txid in sorted(self.mempool)]
            self.mempool = {}
            return None
        if method == "getrawmempool":
            return sorted(self.mempool)
        if method == "getrawtransaction":
            if params[0] not in self.mempool:
                raise RpcError("no such mempool transaction")
            return {"txid": params[0], "hex": self.mempool[params[0]], "height": 0, "confirmations": 0}
        if method == "sendrawtransaction":
            txid = self.world.txid(params[0])
            if txid is None or txid in self.mempool or not self.valid(txid):
                raise RpcError("transaction rejected")
            self.mempool[txid] = params[0]
            return txid
        if method == "getpeerinfo":
            return list(self.peers)
        raise AssertionError(method)


def tree(block):
    return {"height": block["height"], "hash": block["hash"], "time": block["time"],
            **{pool: {"commitments": {"finalState": f"{index:02x}" + block["hash"][:6]}}
               for index, pool in enumerate(("sapling", "orchard", "ironwood"))}}


class Docker:
    """The Docker CLI, grpcurl against lightwalletd, and node RPC over loopback ports."""

    def __init__(self, world, activation):
        self.world, self.activation = world, activation
        self.resources = {}
        self.nodes = {}
        self.ids = itertools.count(1)
        self.fail_start = None

    @property
    def main(self):
        return next(node for node in self.nodes.values() if node.name.endswith("-node"))

    def run(self, command, *, timeout, check=True):
        if command[0] != "docker":
            return self.grpcurl(command)
        args = command[1:]
        result = self.docker(args)
        returncode, stdout = (0, result) if isinstance(result, str) else result
        if check and returncode:
            raise REGTEST.ZakuraRegtestError(f"docker {args[0]} failed: {stdout}")
        return subprocess.CompletedProcess(command, returncode, stdout, "")

    def docker(self, args):
        if args[:2] == ["image", "inspect"]:
            return args[-1].rsplit("@", 1)[1]
        if args[1:2] == ["ls"]:
            pattern = args[args.index("--filter") + 1].removeprefix("name=")
            kind = args[0]
            return "\n".join(name for name, item in self.resources.items()
                             if item["kind"] == kind and pattern in name)
        if args[1:2] == ["create"] or args[0] == "create":
            return self.create(args)
        if args[0] == "start":
            item = self.resources[args[1]]
            if args[1] == self.fail_start:
                return 1, "start failed"
            item["running"] = True
            if item["image"] == REGTEST.ZAKURA_IMAGE:
                self.nodes[item["port"]] = Node(self.world, args[1])
            return args[1]
        if args[0] == "port":
            return f"127.0.0.1:{self.resources[args[1]]['port']}"
        if args[1:2] == ["inspect"]:
            item = self.resources.get(args[2])
            if item is None or item["kind"] != args[0]:
                return 1, "no such object"
            identity = {"Id": item["id"], "Name": args[2]}
            if args[0] == "container":
                return json.dumps([{**identity, "Config": {"Labels": item["labels"]},
                                    "State": {"Running": item["running"], "Paused": False, "Restarting": False}}])
            return json.dumps([{**identity, "Labels": item["labels"], "Driver": "local"}])
        if args[0] == "stop":
            self.by_id(args[-1])["running"] = False
            return args[-1]
        if args[1:2] == ["rm"]:
            name = next(name for name, item in self.resources.items() if item["id"] == args[-1])
            item = self.resources.pop(name)
            self.nodes.pop(item.get("port"), None)
            return args[-1]
        if args[0] == "logs":
            return "modeled log\n"
        raise AssertionError(args)

    def create(self, args):
        labels = dict(args[index + 1].split("=", 1) for index, value in enumerate(args) if value == "--label")
        if args[0] == "create":
            name = args[args.index("--name") + 1]
            image = next(value for value in args if value in REGTEST.PINNED_IMAGES)
            port = int(args[args.index("--publish") + 1].split(":")[1])
            item = {"kind": "container", "id": f"container-{next(self.ids)}", "labels": labels, "image": image,
                    "port": port, "running": False, "args": args}
        else:
            name = args[-1]
            identity = name if args[0] == "volume" else f"{args[0]}-{next(self.ids)}"
            item = {"kind": args[0], "id": identity, "labels": labels, "args": args}
        self.resources[name] = item
        return item["id"]

    def by_id(self, identity):
        return next(item for item in self.resources.values() if item["id"] == identity)

    def post(self, url, body, timeout):
        node = self.nodes.get(int(url.rsplit(":", 1)[1]))
        if node is None:
            raise ConnectionRefusedError("connection refused")
        request = json.loads(body)
        try:
            response = {"result": node.rpc(request["method"], request["params"])}
        except RpcError as error:
            response = {"error": {"code": -1, "message": str(error)}}
        return json.dumps({"jsonrpc": "2.0", "id": request["id"], **response}).encode()

    def grpcurl(self, command):
        lightwalletd = next((item for item in self.resources.values() if item.get("image") == REGTEST.LIGHTWALLETD_IMAGE
                             and item["running"]), None)
        if lightwalletd is None or command[-2] != f"127.0.0.1:{lightwalletd['port']}":
            return subprocess.CompletedProcess(command, 1, "", "connection refused")
        method = command[-1].rsplit("/", 1)[1]
        payload = json.loads(command[command.index("-d") + 1])
        node = self.main
        tip = self.world.blocks[node.tip()]
        if method == "GetLightdInfo":
            branch = REGTEST.NU63_BRANCH_ID if tip["height"] >= self.activation else REGTEST.NU62_BRANCH_ID
            body = {"chainName": "regtest", "blockHeight": str(tip["height"]), "consensusBranchId": branch}
        elif method == "GetLatestBlock":
            body = {"height": str(tip["height"]),
                    "hash": base64.b64encode(bytes.fromhex(tip["hash"])[::-1]).decode()}
        elif method == "GetTreeState":
            block = self.world.blocks[node.chain[int(payload["height"])]]
            state = tree(block)
            body = {"network": "regtest", "height": str(block["height"]), "hash": block["hash"],
                    "time": block["time"], "saplingTree": state["sapling"]["commitments"]["finalState"],
                    "orchardTree": state["orchard"]["commitments"]["finalState"],
                    "ironwoodTree": state["ironwood"]["commitments"]["finalState"]}
        else:
            raise AssertionError(method)
        return subprocess.CompletedProcess(command, 0, json.dumps(body), "")


class Lease:
    def __init__(self, ports):
        self.ports, self.released, self.closed = ports, False, False

    def release_sockets(self):
        self.released = True

    def close(self):
        self.closed = True


class RegtestTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="vizor-zakura-regtest-test-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.tools = self.root / "tools"
        (self.tools / "protos").mkdir(parents=True)
        (self.tools / "protos" / "service.proto").write_text('syntax = "proto3";\n')
        (self.tools / "grpcurl").write_text("#!/bin/sh\n")
        (self.tools / "grpcurl").chmod(0o700)
        (self.root / "evidence").mkdir(mode=0o700)
        self.world = World()
        self.leases = []
        ports = itertools.count(31000)

        def lease(worker, run, *, port_names):
            self.leases.append(Lease({port_names[0]: next(ports)}))
            return self.leases[-1]

        for name, value in (("lease_native_ports", lease), ("SETTLE_SECONDS", 0.2)):
            patcher = patch.object(REGTEST, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def regtest(self, activation=1):
        self.docker = Docker(self.world, activation)
        regtest = REGTEST.ZakuraRegtest(self.root / "evidence", self.tools / "grpcurl", self.tools / "protos",
            run_id=uuid.uuid4(), miner_address=MINER, activation_height=activation,
            network_subnet="10.1.2.0/28", labels={"com.keplr.vizor.e2e.namespace": "model"}, timeout=20)
        regtest._run, regtest._post = self.docker.run, self.docker.post
        return regtest

    def send(self, regtest, txid):
        self.assertEqual(regtest.rpc("sendrawtransaction", [self.world.raw(txid)]), txid)

    def block(self, block_hash):
        return self.world.blocks[block_hash]["txids"]

    def test_start_runs_a_labelled_node_and_lightwalletd_and_waits_for_the_first_block(self):
        regtest = self.regtest()
        proof = regtest.start()
        self.assertEqual(proof["tip"]["height"], 1)
        self.assertEqual(proof["tip"]["consensus_branch_id"], REGTEST.NU63_BRANCH_ID)
        self.assertEqual(proof["tip"]["trees"].keys(), {"sapling", "orchard", "ironwood"})
        self.assertEqual(proof["bootstrap"], [self.docker.main.tip()])
        resources = self.docker.resources
        self.assertEqual(set(resources), {regtest.network_name, regtest.lwd_volume, regtest.node_name,
                                          regtest.lwd_name})
        for item in resources.values():
            self.assertEqual(item["labels"], {REGTEST.RUN_LABEL: regtest.run_id,
                                              "com.keplr.vizor.e2e.namespace": "model"})
        self.assertIn("10.1.2.0/28", resources[regtest.network_name]["args"])
        node = resources[regtest.node_name]["args"]
        self.assertIn(f"127.0.0.1:{resources[regtest.node_name]['port']}:18232", node)
        self.assertIn(f"type=bind,src={regtest.config_path},dst=/config/zakurad.toml,readonly", node)
        self.assertIn(f"127.0.0.1:{resources[regtest.lwd_name]['port']}:9067", resources[regtest.lwd_name]["args"])
        config = regtest.config_path.read_text()
        self.assertIn('network = "Regtest"', config)
        self.assertIn('"NU6.3" = 1\n', config)
        self.assertIn(f'miner_address = "{MINER}"', config)
        self.assertEqual(regtest.config_path.stat().st_mode & 0o777, 0o644)
        self.assertTrue(all(lease.released and not lease.closed for lease in self.leases))
        self.assertTrue((self.root / "evidence" / "start.json").exists())

    def test_activation_500_reports_nu62_and_no_ironwood_tree_until_height_500(self):
        regtest = self.regtest(activation=500)
        regtest.start()
        self.assertIn('"NU6.2" = 1\n"NU6.3" = 500\n', regtest.config_path.read_text())
        tip = regtest.wait_synced()
        self.assertEqual((tip["consensus_branch_id"], set(tip["trees"])),
                         (REGTEST.NU62_BRANCH_ID, {"sapling", "orchard"}))
        tip = regtest.mine(499)["tip"]
        self.assertEqual((tip["height"], tip["consensus_branch_id"]), (500, REGTEST.NU63_BRANCH_ID))
        self.assertIn("ironwood", tip["trees"])

    def test_a_failed_start_removes_what_it_created_and_keeps_the_original_error(self):
        regtest = self.regtest()
        self.docker.fail_start = regtest.lwd_name
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "start failed"):
            regtest.start()
        self.assertTrue(regtest.closed)
        self.assertEqual(self.docker.resources, {})
        self.assertTrue(all(lease.closed for lease in self.leases))
        self.assertTrue((self.root / "evidence" / "start-failure-node.log").exists())
        with self.assertRaises(REGTEST.ZakuraRegtestError):
            regtest.rpc("getblockcount")

    def test_close_leaves_resources_whose_labels_changed(self):
        regtest = self.regtest()
        regtest.start()
        self.docker.resources[regtest.network_name]["labels"] = {"another": "owner"}
        proof = regtest.close()
        self.assertFalse(proof["complete"])
        self.assertFalse(regtest.closed)
        self.assertEqual(set(self.docker.resources), {regtest.network_name})
        self.docker.resources[regtest.network_name]["labels"] = dict(regtest.labels)
        self.assertTrue(regtest.close()["complete"])
        self.assertTrue(regtest.closed)
        self.assertEqual(self.docker.resources, {})
        self.assertTrue(all(lease.closed for lease in self.leases))

    def test_retain_stops_the_containers_and_keeps_everything(self):
        regtest = self.regtest()
        regtest.start()
        proof = regtest.retain()
        self.assertTrue(proof["complete"])
        self.assertEqual(regtest.retain(), proof)
        self.assertEqual({item["running"] for item in self.docker.resources.values() if item["kind"] == "container"},
                         {False})
        self.assertEqual(len(self.docker.resources), 4)
        self.assertFalse(any(lease.closed for lease in self.leases))
        with self.assertRaises(REGTEST.ZakuraRegtestError):
            regtest.mine(1)
        with self.assertRaises(REGTEST.ZakuraRegtestError):
            regtest.close()

    def test_mine_returns_the_tip_once_lightwalletd_serves_it(self):
        regtest = self.regtest()
        regtest.start()
        result = regtest.mine(5)
        self.assertEqual(result["tip"]["height"], 6)
        self.assertEqual(result["hashes"][-1], result["tip"]["hash"])
        self.assertEqual(result["tip"]["latest_block_hash_orientation"], "wire-reversed")

    def test_a_held_transaction_stays_pending_until_its_expiry(self):
        regtest = self.regtest()
        regtest.start()
        regtest.mine(10)
        held, other = self.world.transaction("held", expiry=14), self.world.transaction("other")
        self.send(regtest, held)
        tip = regtest.wait_synced()
        self.assertEqual(regtest.hold_pending_transactions([held], expiry_height=14),
                         {"initial_tip_height": 11, "initial_tip_hash": tip["hash"], "held_txids": [held],
                          "expiry_height": 14})
        self.send(regtest, other)
        first = regtest.mine(1)["hashes"][0]
        self.assertIn(other, self.block(first))
        self.assertNotIn(held, self.block(first))
        self.assertIn(held, self.docker.main.mempool)
        self.assertNotIn("generate", self.docker.main.calls[self.docker.main.calls.index("submitblock"):])
        for block_hash in regtest.mine(2)["hashes"]:
            self.assertNotIn(held, self.block(block_hash))
        self.assertNotIn(held, self.docker.main.mempool)
        self.docker.main.calls.clear()
        regtest.mine(1)
        self.assertIn("generate", self.docker.main.calls)

    def test_a_fork_replacement_brings_mined_transactions_back_and_holds_them_until_release(self):
        regtest = self.regtest(activation=500)
        regtest.start()
        regtest.mine(500)
        denomination = self.world.transaction("denomination")
        self.send(regtest, denomination)
        regtest.mine(1)
        main = self.docker.main
        child = self.world.transaction("child", anchor=main.tip())
        self.send(regtest, child)
        replaced = main.chain[501]
        result = regtest.replace_fork_holding([denomination], fork_height=500)
        self.assertEqual((result["old_tip_height"], result["new_tip_height"]), (502, 503))
        self.assertEqual(result["invalidated_hash"], replaced)
        self.assertEqual(len(result["replacement_hashes"]), 3)
        self.assertEqual(result["new_tip_hash"], main.tip())
        self.assertEqual(result["held_txids"], [denomination])
        self.assertEqual(result["reintroduced_txids"], [denomination])
        self.assertEqual(result["reintroduction"], {"resubmitted_txids": [denomination],
                                                    "preserved_pending_txids": [],
                                                    "invalidated_pending_txids": [child]})
        for block_hash in result["replacement_hashes"]:
            self.assertEqual(len(self.block(block_hash)), 1)
        self.assertNotIn(denomination, self.block(regtest.mine(1)["hashes"][0]))
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "release them first"):
            regtest.replace_fork_holding([], fork_height=500)
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "only held transactions"):
            regtest.release_held_transactions([child])
        released = regtest.release_held_transactions([denomination])
        self.assertEqual(released["released_txids"], [denomination])
        self.assertIn(denomination, self.block(regtest.mine(1)["hashes"][0]))
        second = regtest.replace_fork_holding([], fork_height=503)
        self.assertEqual(second["held_txids"], [])

    def test_a_tip_replacement_keeps_pending_transactions_through_the_mempool_reset(self):
        regtest = self.regtest(activation=500)
        regtest.start()
        regtest.mine(500)
        claim = self.world.transaction("claim")
        self.send(regtest, claim)
        result = regtest.replace_tip_holding([claim])
        self.assertEqual((result["fork_height"], result["old_tip_height"], result["new_tip_height"]),
                         (500, 501, 502))
        self.assertEqual(result["invalidated_hash"], result["old_tip_hash"])
        self.assertEqual(len(result["replacement_hashes"]), 2)
        self.assertEqual(result["replacement_hashes"][-1], result["new_tip_hash"])
        self.assertEqual(result["held_txids"], [claim])
        self.assertEqual(result["reintroduction"]["preserved_pending_txids"], [claim])
        self.assertEqual(result["reintroduction"]["resubmitted_txids"], [])
        self.assertEqual(regtest.release_held_transactions([claim])["released_txids"], [claim])
        self.assertIn(claim, self.block(regtest.mine(1)["hashes"][0]))

    def test_a_transaction_sent_while_the_second_node_starts_stays_pending(self):
        regtest = self.regtest(activation=500)
        regtest.start()
        regtest.mine(500)
        late = self.world.transaction("late")
        start_donor = regtest._start_donor

        def start_then_send(height, deadline):
            start_donor(height, deadline)
            self.send(regtest, late)

        with patch.object(regtest, "_start_donor", side_effect=start_then_send):
            result = regtest.replace_fork_holding([], fork_height=500)
        self.assertEqual(result["held_txids"], [late])
        self.assertEqual(result["reintroduction"]["preserved_pending_txids"], [late])

    def test_a_node_with_peers_cannot_hold_transactions(self):
        regtest = self.regtest()
        regtest.start()
        regtest.mine(3)
        held = self.world.transaction("held")
        self.send(regtest, held)
        self.docker.main.peers.append({"addr": "10.1.2.9:18233"})
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "has peers"):
            regtest.hold_pending_transactions([held])

    def test_holds_need_pending_transactions_and_reorgs_a_fork_below_the_tip(self):
        regtest = self.regtest()
        regtest.start()
        regtest.mine(3)
        missing = self.world.transaction("missing")
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "did not reach the mempool"):
            regtest.hold_pending_transactions([missing], deadline=time.monotonic() + 0.5)
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "cannot fork"):
            regtest.replace_fork_holding([], fork_height=4)
        with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "neither pending nor in the replaced blocks"):
            regtest.replace_fork_holding([missing], fork_height=2)


class PinnedImageTests(unittest.TestCase):
    """The daemon is modeled: present IDs come from a dict, pulls add them."""

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.logs = Path(directory.name)
        self.local = {reference: reference.rsplit("@", 1)[1] for reference in REGTEST.PINNED_IMAGES}
        self.pulled = []
        self.pull_code = 0
        self.messages = []

    def inspect(self, command, timeout):
        reference = command[-1]
        if reference in self.local:
            return subprocess.CompletedProcess(command, 0, self.local[reference] + "\n", "")
        return subprocess.CompletedProcess(command, 1, "", f"Error response from daemon: No such image: {reference}")

    def pull(self, reference, log_path):
        self.pulled.append((reference, log_path))
        if self.pull_code == 0:
            self.local[reference] = reference.rsplit("@", 1)[1]
        return self.pull_code

    def ensure(self):
        return REGTEST.ensure_pinned_images(self.logs, cancel_event=threading.Event(), out=self.messages.append,
                                            inspect=self.inspect, pull=self.pull)

    def test_present_images_are_not_pulled(self):
        self.assertEqual(self.ensure(), {reference: "present" for reference in REGTEST.PINNED_IMAGES})
        self.assertEqual(self.pulled, [])
        self.assertEqual(self.messages, [])

    def test_a_pruned_image_is_pulled_by_its_digest(self):
        del self.local[REGTEST.LIGHTWALLETD_IMAGE]
        self.assertEqual(self.ensure(), {REGTEST.ZAKURA_IMAGE: "present", REGTEST.LIGHTWALLETD_IMAGE: "pulled"})
        self.assertEqual(self.pulled, [(REGTEST.LIGHTWALLETD_IMAGE, self.logs / "pinned-image-pull-1.log")])
        self.assertIn(REGTEST.LIGHTWALLETD_IMAGE, self.messages[0])

    def test_a_failed_pull_stops_the_run(self):
        del self.local[REGTEST.ZAKURA_IMAGE]
        self.pull_code = 1
        with self.assertRaisesRegex(RunnerError, "docker pull failed"):
            self.ensure()

    def test_an_image_with_another_identity_is_rejected(self):
        self.local[REGTEST.LIGHTWALLETD_IMAGE] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(RunnerError, "does not match pinned digest"):
            self.ensure()
        self.assertEqual(self.pulled, [])

    def test_other_inspect_errors_are_not_treated_as_missing(self):
        def unavailable(command, timeout):
            return subprocess.CompletedProcess(command, 1, "", "Cannot connect to the Docker daemon")
        with self.assertRaisesRegex(RunnerError, "docker image inspect failed"):
            REGTEST.ensure_pinned_images(self.logs, cancel_event=threading.Event(), out=self.messages.append,
                                         inspect=unavailable, pull=self.pull)
        self.assertEqual(self.pulled, [])


if __name__ == "__main__":
    unittest.main()
