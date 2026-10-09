"""Real original case/groups/files; modeled Dart/RPC transport, not wallet PASS."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_zakura_front as FRONT
    import native_zakura_backend as BACKEND
    import native_workspace as WORKSPACE
    from zakura_genesis import create_zakura_genesis_proof
    from test_zakura_genesis import GenesisFixture, HASH
    from test_native_zakura_backend import modeled_source, prepare
finally:
    sys.path.pop(0)


class FrontFixture(GenesisFixture):
    def grpc(self, method, payload=None, *, deadline=None):
        if method == "GetLightdInfo":
            return {"chainName": "test", "blockHeight": "1", "build": "modeled"}
        if method == "GetLatestBlock":
            return {"height": "1", "hash": "modeled-block-id"}
        if method == "GetTreeState":
            return {"network": "test", "height": "1", "hash": "34" * 32,
                    "saplingTree": "010203", "orchardTree": "040506", "ironwoodTree": "070809"}
        raise AssertionError(method)

    def wait_synced(self, *, deadline=None):
        return {"height": 1, "hash": "34" * 32}


class FrontTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-front-owner-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source = self.root / "source"
        self.source.mkdir(mode=0o700)
        for name in FRONT._SOURCE_FILES:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// modeled source\n")
        (self.source / ".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": "zcash_wallet", "rootUri": "../"}]}))
        source = patch.object(BACKEND, "load_zakura_fixture_source", return_value=modeled_source(FrontFixture))
        source.start()
        self.addCleanup(source.stop)
        workspace = WORKSPACE.prepare_native_case_workspace(self.root, platform="macos",
            scenario_id="flutter.macos.front-model", run_id="a1b2c3d4e5", worker_id=0,
            case_index=0, ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=1)
        self.case = BACKEND.NativeCaseLifecycle(workspace)
        self.backend = prepare(self.case)
        self.backend.start()
        self.genesis = create_zakura_genesis_proof(self.case, self.backend)
        self.addCleanup(self.stop_models)
        self.commands = []

    def stop_models(self):
        self.case.close()
        if self.backend._directory_fd is not None:
            self.backend.retain()

    def prepare(self, **kwargs):
        return FRONT.prepare_native_zakura_front(self.case, self.backend, self.genesis,
            dart=Path(sys.executable).resolve(), source_root=self.source, **kwargs)

    def launch(self, command, **kwargs):
        self.commands.append(command)
        process = self.original_start([sys.executable, "-u", "-c",
            "import json,os,signal,sys,time\n"
            "sequence=0\n"
            "def availability(sig,frame):\n"
            " global sequence\n"
            " sequence+=1\n"
            " print(json.dumps({'event':'zakura-lwd-shim-availability',"
            "'fixture_run_id':sys.argv[1],'pid':os.getpid(),"
            "'available':sig==signal.SIGUSR2,'sequence':sequence}),flush=True)\n"
            "signal.signal(signal.SIGTERM,lambda *args:sys.exit(0))\n"
            "signal.signal(signal.SIGUSR1,availability)\n"
            "signal.signal(signal.SIGUSR2,availability)\n"
            "print('modeled-front-ready',flush=True)\n"
            "time.sleep(30)\n", command[-1]], **kwargs)
        deadline = time.monotonic() + 2
        while "modeled-front-ready" not in process.log_path.read_text():
            if time.monotonic() >= deadline:
                self.fail("original modeled daemon did not finish startup")
            time.sleep(0.005)
        return process

    def query(self, method, payload, deadline, cancel):
        if method == "GetLightdInfo":
            return dict(self.backend.grpc(method), chainName="regtest")
        if method == "GetTreeState" and payload == {"height": "0"}:
            return self.genesis.tree_state()
        return self.backend.grpc(method, payload)

    def patches(self, query=None):
        self.original_start = self.case.start_process
        return patch.object(self.case, "start_process", side_effect=self.launch), patch.object(
            FRONT.OwnedNativeZakuraFront, "_query", side_effect=query or self.query)

    def test_registers_once_before_launch_then_proves_exact_adaptation(self):
        owner = self.prepare()
        self.assertIs(self.backend._front, owner)
        self.assertEqual(self.case.launched_process_count, 0)
        with self.assertRaises(FRONT.NativeZakuraFrontError):
            self.prepare()
        first, second = self.patches()
        with first, second:
            observed = owner.start()
        self.assertEqual(observed["lightwalletd_url"], "http://127.0.0.1:29067")
        self.assertEqual(observed["raw_port"], 39067)
        self.assertIs(observed["wallet_or_catalog_pass"], False)
        self.assertIn("--listen-port", self.commands[0])
        self.assertEqual(owner.process._capture.max_output_bytes, FRONT._OUTPUT_BYTES)
        owner.assert_running()
        with self.assertRaises(FRONT.NativeZakuraFrontError):
            owner.start()
        owner.stop()
        self.assertTrue(owner.process.cleanup_completed)
        self.assertEqual(owner.process.process.poll(), 0)
        with self.assertRaises(FRONT.NativeZakuraFrontError):
            owner.assert_running()

    def test_wrong_case_external_proof_and_invalid_timeout_cannot_launch(self):
        for proof in (object(), {"complete": True}):
            with self.assertRaises(FRONT.NativeZakuraFrontError):
                FRONT.prepare_native_zakura_front(self.case, self.backend, proof,
                    dart=Path(sys.executable), source_root=self.source)
        for timeout in (False, 0, -1, float("inf"), float("nan"), "30"):
            with self.assertRaises(FRONT.NativeZakuraFrontError):
                self.prepare(timeout=timeout)
        self.assertEqual(self.case.launched_process_count, 0)

    def start_owner(self):
        owner = self.prepare()
        first, second = self.patches()
        with first, second:
            owner.start()
        return owner

    def test_outage_acknowledges_original_pid_and_preserves_sibling_and_backend(self):
        owner = self.start_owner()
        sibling = self.case.start_process([sys.executable, "-c", "import time; time.sleep(30)"], env=os.environ)
        original_pid = owner.process.process.pid
        self.assertEqual(owner.set_available(False)["sequence"], 1)
        with patch.object(FRONT.runtime, "_signal_group") as send:
            self.assertEqual(owner.set_available(False)["sequence"], 1)
            send.assert_not_called()
        self.assertEqual(owner.set_available(True)["sequence"], 2)
        self.assertEqual(owner.process.process.pid, original_pid)
        self.assertIsNone(sibling.process.poll())
        self.assertFalse(self.backend.closed)
        owner.assert_running()

    def test_unready_invalid_or_cancelled_outage_sends_no_signal(self):
        owner = self.prepare()
        with patch.object(FRONT.runtime, "_signal_group") as send:
            with self.assertRaises(FRONT.NativeZakuraFrontError):
                owner.set_available(False)
            send.assert_not_called()
        first, second = self.patches()
        with first, second:
            owner.start()
        cancel = threading.Event()
        cancel.set()
        with patch.object(FRONT.runtime, "_signal_group") as send:
            with self.assertRaises(FRONT.runtime.Cancelled):
                owner.set_available(False, cancel_event=cancel)
            for value in (None, 0, 1, "false"):
                with self.assertRaises(FRONT.NativeZakuraFrontError):
                    owner.set_available(value)
            send.assert_not_called()

    def test_foreign_or_replayed_outage_acknowledgement_cannot_credit_availability(self):
        owner = self.start_owner()
        original = {"event":"zakura-lwd-shim-availability", "fixture_run_id":owner._ready["fixture_run_id"],
            "pid":owner.process.process.pid, "available":False, "sequence":1}
        for field, value in (("pid", 1), ("fixture_run_id", "foreign"), ("available", 0),
                             ("available", True), ("sequence", 0), ("sequence", True), ("extra", True)):
            forged = dict(original, **{field:value})
            with patch.object(FRONT.runtime, "_signal_group",
                    side_effect=lambda *_args, **_kwargs: owner._lines.append(json.dumps(forged))):
                with self.assertRaisesRegex(FRONT.NativeZakuraFrontError, "acknowledgement differs"):
                    owner.set_available(False)
            self.assertIs(owner._available, True)

    def test_missing_outage_ack_times_out_and_exited_original_cannot_be_signalled(self):
        owner = self.start_owner()
        with patch.object(FRONT.runtime, "_signal_group") as send:
            with self.assertRaisesRegex(FRONT.NativeZakuraFrontError, "timed out"):
                owner.set_available(False, timeout=0.03)
            send.assert_called_once()
        owner.stop()
        with patch.object(FRONT.runtime, "_signal_group") as send:
            with self.assertRaises(FRONT.NativeZakuraFrontError):
                owner.set_available(False)
            send.assert_not_called()

    def test_package_binding_cannot_escape_source_root(self):
        (self.source / ".dart_tool/package_config.json").write_text(json.dumps({
            "packages": [{"name": "zcash_wallet", "rootUri": "../../"}]}))
        with self.assertRaisesRegex(FRONT.NativeZakuraFrontError, "binding escaped"):
            self.prepare()
        self.assertIsNone(self.backend._front)

    def test_malformed_package_config_is_not_a_binding(self):
        path = self.source / ".dart_tool/package_config.json"
        for value in ([], {}, {"packages": None}, {"packages": [False]},
                      {"packages": [{"name": "zcash_wallet", "rootUri": None}]}):
            with self.subTest(value=value):
                path.write_text(json.dumps(value))
                with self.assertRaises(FRONT.NativeZakuraFrontError):
                    self.prepare()
                self.assertIsNone(self.backend._front)

    def test_precancellation_and_changed_source_do_not_launch(self):
        owner = self.prepare()
        cancel = threading.Event()
        cancel.set()
        with self.assertRaises(FRONT.runtime.Cancelled):
            owner.start(cancel_event=cancel)
        self.assertEqual(self.case.launched_process_count, 0)
        with self.assertRaises(FRONT.NativeZakuraFrontError):
            owner.start()

    def test_changed_source_before_start_is_not_an_adopted_launch(self):
        owner = self.prepare()
        (self.source / FRONT._SOURCE_FILES[0]).write_text("changed source")
        with self.assertRaisesRegex(FRONT.NativeZakuraFrontError, "source/tool changed"):
            owner.start()
        self.assertEqual(self.case.launched_process_count, 0)

    def test_corrupt_parity_stops_only_new_front_not_existing_case_child(self):
        sibling = self.case.start_process([sys.executable, "-c", "import time; time.sleep(30)"], env=os.environ)
        owner = self.prepare()
        def query(method, payload, deadline, cancel):
            value = self.query(method, payload, deadline, cancel)
            if method == "GetTreeState" and payload != {"height": "0"}:
                value["orchardTree"] = "000000"
            return value
        first, second = self.patches(query)
        with first, second, self.assertRaisesRegex(FRONT.NativeZakuraFrontError, "nonzero TreeState"):
            owner.start()
        self.assertTrue(owner.process.cleanup_completed)
        self.assertIsNone(sibling.process.poll())
        self.assertTrue(self.case.accepting_launches)
        self.assertFalse(self.backend.closed)

    def assert_bad_ready(self, kind):
        owner = self.prepare()
        def query(method, payload, deadline, cancel):
            value = self.query(method, payload, deadline, cancel)
            if kind == "genesis" and method == "GetTreeState" and payload == {"height": "0"}:
                value["hash"] = "0" * 64
            elif kind == "network" and method == "GetLightdInfo":
                value["build"] = "changed"
            elif kind == "latest" and method == "GetLatestBlock":
                value["hash"] = "changed"
            return value
        first, second = self.patches(query)
        with first, second, self.assertRaises(FRONT.NativeZakuraFrontError):
            owner.start()
        self.assertTrue(owner.process.cleanup_completed)

    def test_bad_genesis_is_not_readiness(self):
        self.assert_bad_ready("genesis")

    def test_changed_lightd_info_is_not_readiness(self):
        self.assert_bad_ready("network")

    def test_changed_latest_block_is_not_readiness(self):
        self.assert_bad_ready("latest")

    def test_cancel_after_launch_preserves_primary_and_joins(self):
        owner = self.prepare()
        cancel = threading.Event()
        def query(*args):
            cancel.set()
            return self.query(*args)
        first, second = self.patches(query)
        with first, second, self.assertRaises(FRONT.runtime.Cancelled):
            owner.start(cancel_event=cancel)
        self.assertTrue(owner.process.cleanup_completed)

    def test_source_drift_during_readiness_stops_original_child(self):
        owner = self.prepare()
        def query(*args):
            (self.source / FRONT._SOURCE_FILES[0]).write_text("source changed during launch")
            return self.query(*args)
        first, second = self.patches(query)
        with first, second, self.assertRaisesRegex(FRONT.NativeZakuraFrontError, "source/tool changed"):
            owner.start()
        self.assertTrue(owner.process.cleanup_completed)

    def test_interrupted_child_handoff_joins_original_registered_child(self):
        owner = self.prepare()
        self.original_start = self.case.start_process
        primary = KeyboardInterrupt("interrupted after original launch")
        def interrupted(*args, **kwargs):
            self.launch(*args, **kwargs)
            raise primary
        with patch.object(self.case, "start_process", side_effect=interrupted):
            with self.assertRaises(KeyboardInterrupt) as caught:
                owner.start()
        self.assertIs(caught.exception, primary)
        self.assertTrue(self.case._processes[-1].cleanup_completed)

    def test_case_final_close_joins_front_before_backend_deletion(self):
        owner = self.prepare()
        first, second = self.patches()
        with first, second:
            owner.start()
        self.case.close()
        self.assertTrue(owner.process.cleanup_completed)
        self.backend.close()
        self.assertTrue(self.backend.closed)


if __name__ == "__main__":
    unittest.main()
