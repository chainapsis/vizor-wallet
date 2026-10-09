"""Original-case genesis publication models; not Docker or wallet PASS."""
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import zakura_genesis as GENESIS
    import native_zakura_backend as BACKEND
    import native_workspace as WORKSPACE
    from test_native_zakura_backend import FixtureModel, modeled_source, prepare
finally:
    sys.path.pop(0)


HASH = "12" * 32


def observations():
    transaction = {"version": 1, "overwintered": False, "blockhash": HASH,
        "height": 0, "vin": [{"coinbase": "01"}], "vShieldedSpend": [],
        "vShieldedOutput": [], "vjoinsplit": [], "orchard": {"actions": []}}
    block = {"hash": HASH, "height": 0, "time": 1296688602, "nTx": 1,
        "tx": [transaction], "valuePools": [{"id": pool, "chainValueZat": 0,
        "valueDeltaZat": 0} for pool in ("sapling", "orchard", "ironwood")]}
    node_tree = {"hash": HASH, "height": 0, "time": 1296688602,
        **{pool: {"commitments": {}} for pool in ("sapling", "orchard", "ironwood")}}
    return block, node_tree


class GenesisFixture(FixtureModel):
    def start(self):
        ready = super().start()
        self._lightwalletd_url = "127.0.0.1:39067"
        ready["endpoints"] = {"lightwalletd_url": self._lightwalletd_url}
        self.calls = []
        self.block, self.node_tree = observations()
        return ready

    def rpc(self, method, params=None, *, deadline=None):
        self.calls.append((method, params, deadline))
        if method == "getblockhash":
            return HASH
        if method == "getblock":
            return copy.deepcopy(self.block)
        if method == "z_gettreestate":
            return copy.deepcopy(self.node_tree)
        raise AssertionError(method)


class GenesisTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-genesis-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cases, self.backends = [], []
        self.addCleanup(self.stop_models)
        source = patch.object(BACKEND, "load_zakura_fixture_source",
                              return_value=modeled_source(GenesisFixture))
        source.start()
        self.addCleanup(source.stop)

    def case(self):
        workspace = WORKSPACE.prepare_native_case_workspace(self.root, platform="macos",
            scenario_id="flutter.macos.genesis-probe", run_id="a1b2c3d4e5", worker_id=0,
            case_index=len(self.cases), ports={"rpc": 28232, "lwd": 29067, "proxy": 29068},
            activation_height=1)
        owner = BACKEND.NativeCaseLifecycle(workspace)
        self.cases.append(owner)
        return owner

    def backend(self, *, start=True):
        owner = prepare(self.case())
        self.backends.append(owner)
        if start:
            owner.start()
        return owner

    def stop_models(self):
        for case in self.cases:
            case.close()
        for backend in self.backends:
            if backend._directory_fd is not None:
                backend.retain()

    def create(self, backend, **kwargs):
        return GENESIS.create_zakura_genesis_proof(backend._case, backend, **kwargs)

    def test_original_node_genesis_publishes_readonly_bounded_handoff(self):
        backend = self.backend()
        backend.grpc = Mock(side_effect=AssertionError("raw LWD is not a genesis proof"))
        result = self.create(backend)
        handoff = result.handoff()
        path = Path(handoff["path"])
        data = path.read_bytes()
        proof = json.loads(data)
        self.assertEqual(path.stat().st_mode & 0o777, 0o400)
        self.assertLessEqual(len(data), GENESIS.MAX_PROOF_BYTES)
        self.assertEqual(hashlib.sha256(data).hexdigest(), handoff["sha256"])
        self.assertEqual(handoff["upstream_port"], 39067)  # Not the manifest front port.
        self.assertEqual(proof["identity"]["run_id"], handoff["fixture_run_id"])
        self.assertEqual(proof["source"], modeled_source(GenesisFixture).identity())
        self.assertEqual(proof["tree_state"], {"network": "regtest", "height": "0",
            "hash": HASH, "time": 1296688602, "saplingTree": "000000",
            "orchardTree": "000000", "ironwoodTree": "000000"})
        self.assertEqual(proof["empty_tree_codec"], GENESIS.EMPTY_TREE_CODEC)
        self.assertIs(proof["wallet_or_catalog_pass"], False)
        self.assertEqual([call[:2] for call in backend._fixture.calls], [
            ("getblockhash", [0]), ("getblock", [HASH, 2]),
            ("z_gettreestate", [HASH]), ("getblockhash", [0])])
        self.assertEqual(len({call[2] for call in backend._fixture.calls}), 1)
        self.assertEqual(backend._case.launched_process_count, 0)
        backend.grpc.assert_not_called()

    def test_rejects_unbound_nonempty_and_malformed_observations(self):
        mutations = [
            lambda b, t: b.update(height=False), lambda b, t: t.update(height=1),
            lambda b, t: t.update(hash="34" * 32), lambda b, t: t.update(time=1),
            lambda b, t: b.update(time=True), lambda b, t: b.update(nTx=True),
            lambda b, t: b["tx"][0].update(version=True),
            lambda b, t: b["tx"][0].update(height=False),
            lambda b, t: b["tx"][0].update(overwintered=True),
            lambda b, t: b["tx"][0].update(blockhash="34" * 32),
            lambda b, t: b["tx"][0].update(vin=[None]),
            lambda b, t: b["tx"][0].update(vShieldedOutput=[{}]),
            lambda b, t: b["tx"][0].update(orchard=None),
            lambda b, t: b["tx"][0].update(ironwood={"actions": [{}]}),
            lambda b, t: b["tx"][0].update(ironwood={}),
            lambda b, t: b["valuePools"][0].update(chainValueZat=False),
            lambda b, t: b["valuePools"][0].update(valueDeltaZat=1),
            lambda b, t: b["valuePools"].append(dict(b["valuePools"][0])),
            lambda b, t: b["valuePools"].pop(),
            lambda b, t: t["sapling"]["commitments"].update(finalState="000000"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(index=index):
                block, node_tree = observations()
                mutate(block, node_tree)
                with self.assertRaises(GENESIS.ZakuraGenesisError):
                    GENESIS._tree_state(HASH, block, node_tree)
        block, node_tree = observations()
        for value in (None, True, "0" * 64, "AB" * 32, "12"):
            with self.subTest(hash=value), self.assertRaises(GENESIS.ZakuraGenesisError):
                GENESIS._tree_state(value, block, node_tree)

    def test_hash_recheck_mismatch_never_publishes(self):
        backend = self.backend()
        original = backend.rpc
        calls = 0
        def rpc(method, params, **kwargs):
            nonlocal calls
            calls += 1
            return "34" * 32 if calls == 4 else original(method, params, **kwargs)
        with patch.object(backend, "rpc", side_effect=rpc):
            with self.assertRaisesRegex(GENESIS.ZakuraGenesisError, "identity changed"):
                self.create(backend)
        self.assertFalse((backend.root / "genesis-proof.json").exists())

    def test_wrong_case_unstarted_backend_or_sealed_case_is_not_accepted(self):
        backend = self.backend(start=False)
        with self.assertRaises(BACKEND.NativeZakuraError):
            self.create(backend)
        backend.start()
        with self.assertRaises(GENESIS.ZakuraGenesisError):
            GENESIS.create_zakura_genesis_proof(self.case(), backend)
        result = self.create(backend)
        backend._case.close()
        with self.assertRaises(BACKEND.NativeZakuraError):
            result.handoff()
        with self.assertRaises(GENESIS.ZakuraGenesisError):
            self.create(backend)

    def test_invalid_timeout_or_precancellation_does_not_call_rpc(self):
        backend = self.backend()
        for timeout in (False, 0, -1, float("inf"), float("nan"), "60"):
            with self.subTest(timeout=timeout), self.assertRaises(GENESIS.ZakuraGenesisError):
                self.create(backend, timeout=timeout)
        cancel = threading.Event()
        cancel.set()
        with self.assertRaises(GENESIS.runtime.Cancelled):
            self.create(backend, cancel_event=cancel)
        self.assertEqual(backend._fixture.calls, [])

    def test_cancellation_after_first_rpc_does_not_publish(self):
        backend = self.backend()
        cancel = threading.Event()
        original = backend.rpc
        def rpc(*args, **kwargs):
            result = original(*args, **kwargs)
            cancel.set()
            return result
        with patch.object(backend, "rpc", side_effect=rpc):
            with self.assertRaises(GENESIS.runtime.Cancelled):
                self.create(backend, cancel_event=cancel)
        self.assertEqual(len(backend._fixture.calls), 1)
        self.assertFalse((backend.root / "genesis-proof.json").exists())

    def test_deadline_after_rpc_does_not_publish(self):
        backend = self.backend()
        with patch.object(GENESIS.time, "monotonic", side_effect=[0, 0, 0, 2]):
            with self.assertRaises(GENESIS.ZakuraGenesisError) as caught:
                self.create(backend, timeout=1)
        self.assertEqual(caught.exception.exit_code, 124)
        self.assertFalse((backend.root / "genesis-proof.json").exists())

    def test_proof_is_exclusive_and_never_overwrites_an_existing_file(self):
        backend = self.backend()
        result = self.create(backend)
        handoff = result.handoff()
        original = Path(handoff["path"]).read_bytes()
        with self.assertRaises(FileExistsError):
            self.create(backend)
        self.assertEqual(Path(handoff["path"]).read_bytes(), original)
        self.assertEqual(result.handoff(), handoff)

    def test_replacing_original_file_with_equal_bytes_is_rejected(self):
        backend = self.backend()
        result = self.create(backend)
        path = Path(result.handoff()["path"])
        original = path.read_bytes()
        path.rename(backend.root / "original-genesis.json")
        path.write_bytes(original)
        path.chmod(0o400)
        with self.assertRaisesRegex(GENESIS.ZakuraGenesisError, "identity changed"):
            result.handoff()

    def test_same_inode_and_restored_metadata_still_require_original_hash(self):
        backend = self.backend()
        result = self.create(backend)
        path = Path(result.handoff()["path"])
        details, original = path.stat(), path.read_bytes()
        path.chmod(0o600)
        path.write_bytes(original.replace(b'"network":"regtest"', b'"network":"testnet"'))
        path.chmod(0o400)
        os.utime(path, ns=(details.st_atime_ns, details.st_mtime_ns))
        with self.assertRaisesRegex(GENESIS.ZakuraGenesisError, "bytes changed"):
            result.handoff()

    def test_symlink_writable_file_or_changed_backend_identity_is_rejected(self):
        for change in ("symlink", "writable", "run", "port"):
            with self.subTest(change=change):
                backend = self.backend()
                result = self.create(backend)
                path = Path(result.handoff()["path"])
                if change == "symlink":
                    original = backend.root / "original-genesis.json"
                    path.rename(original)
                    path.symlink_to(original)
                elif change == "writable":
                    path.chmod(0o600)
                elif change == "run":
                    backend._fixture.run_id = "f" * 32
                else:
                    backend._fixture._lightwalletd_url = "127.0.0.1:39068"
                with self.assertRaises((GENESIS.ZakuraGenesisError, OSError)):
                    result.handoff()

    def test_foreign_ready_endpoint_is_not_proof_authority(self):
        for change in ("run", "port", "host"):
            with self.subTest(change=change):
                backend = self.backend()
                if change == "run":
                    backend._ready["identity"]["run_id"] = "f" * 32
                else:
                    backend._ready["endpoints"]["lightwalletd_url"] = (
                        "127.0.0.1:39068" if change == "port" else "localhost:39067")
                with self.assertRaises(GENESIS.ZakuraGenesisError):
                    self.create(backend)
                self.assertEqual(backend._fixture.calls, [])

    def test_oversized_or_nonfinite_evidence_is_not_published(self):
        for value in ("x" * GENESIS.MAX_PROOF_BYTES, float("nan")):
            with self.subTest(value_type=type(value).__name__):
                backend = self.backend()
                backend._fixture.block["extra"] = value
                with self.assertRaises(GENESIS.ZakuraGenesisError):
                    self.create(backend)
                self.assertFalse((backend.root / "genesis-proof.json").exists())


if __name__ == "__main__":
    unittest.main()
