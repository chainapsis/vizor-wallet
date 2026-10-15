"""Raw backend ownership models; no Docker or wallet PASS is inferred here."""
from __future__ import annotations

import json
import ipaddress
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_zakura_backend as BACKEND
    import native_workspace as WORKSPACE
    import zakura_regtest as REGTEST
finally:
    sys.path.pop(0)


class RegtestModel:
    """Built by the backend in place of ZakuraRegtest; starts no Docker resource."""
    instances = []

    def __init__(self, artifacts, grpcurl, proto_dir, *, run_id, miner_address, activation_height,
                 network_subnet, labels, write_text, timeout):
        RegtestModel.instances.append(self)
        self.artifacts = artifacts
        self.run_id = run_id.hex
        self.timeout, self.miner_address, self.activation_height = timeout, miner_address, activation_height
        self.network_subnet = network_subnet
        # Same names and labels as ZakuraRegtest's constructor.
        prefix = "vizor-zakura-" + self.run_id[:12]
        self.network_name, self.node_name, self.donor_name = prefix + "-net", prefix + "-node", prefix + "-donor"
        self.lwd_name, self.lwd_volume = prefix + "-lwd", prefix + "-lwd-data"
        self.labels = {REGTEST.RUN_LABEL: self.run_id, **labels}
        self._write_text = write_text
        self.closed = self.retained = False
        self.started = self.close_calls = self.retain_calls = 0

    def start(self):
        self.started += 1
        self._write_text("start.json", json.dumps({"run_id": self.run_id}))
        return {"identity": {"run_id": self.run_id}, "activation_height": self.activation_height}

    def rpc(self, method, params=None, *, deadline=None):
        return {"method": method, "params": params, "deadline": deadline}

    grpc = grpc_stream = rpc

    def mine(self, count):
        return {"count": count}

    def wait_synced(self, *, deadline=None):
        return {"synced": True, "deadline": deadline}

    def replace_tip_holding(self, required_txids, *, deadline=None):
        return {"required_txids": required_txids, "deadline": deadline}

    def replace_fork_holding(self, required_txids, *, fork_height, deadline=None):
        return {"required_txids": required_txids, "fork_height":fork_height, "deadline":deadline}

    def release_held_transactions(self, txids, *, deadline=None):
        return {"released_txids": txids, "deadline": deadline}

    def close(self):
        self.close_calls += 1
        self.closed = True
        return {"complete": True, "run_id": self.run_id, "errors": []}

    def retain(self):
        self.retain_calls += 1
        self.retained = True
        return {"complete": True, "run_id": self.run_id, "errors": []}


def prepare(case, **updates):
    return BACKEND.prepare_native_zakura_backend(case, grpcurl=Path("unused-grpcurl"), proto_dir=Path("unused-protos"),
        miner_address="explicit-regtest-miner-model", **updates)


class BackendTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-zakura-owner-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cases, self.backends = [], []
        self.addCleanup(self.stop_models)
        # Tests that model node behaviour replace this class.
        self.model_class = RegtestModel
        regtest = patch.object(BACKEND, "ZakuraRegtest", lambda *args, **kwargs: self.model_class(*args, **kwargs))
        regtest.start()
        self.addCleanup(regtest.stop)

    def case(self, activation=500, root=None):
        workspace = WORKSPACE.prepare_native_case_workspace(root or self.root, platform="macos",
            scenario_id="flutter.macos.backend-probe", run_id="a1b2c3d4e5", worker_id=0,
            case_index=len(self.cases), ports={"rpc": 28232, "lwd": 29067, "proxy": 29068},
            activation_height=activation)
        case = BACKEND.NativeCaseLifecycle(workspace)
        self.cases.append(case)
        return case

    def backend(self, case=None):
        owner = prepare(case or self.case())
        self.backends.append(owner)
        return owner

    def stop_models(self):
        for case in self.cases:
            try:
                case.close()
            except BACKEND.runtime.RunnerError:
                pass  # Tests deliberately invalidate original workspace attachment.
        for backend in self.backends:
            if backend._directory_fd is not None:
                backend.retain()

    def test_construct_only_captures_private_directory_and_activation_height(self):
        for activation in (1, 500):
            with self.subTest(activation=activation):
                owner = self.backend(self.case(activation))
                self.assertEqual(owner._regtest.started, 0)
                self.assertEqual(owner._regtest.activation_height, activation)
                self.assertEqual(owner._regtest.miner_address, "explicit-regtest-miner-model")
                subnet = ipaddress.IPv4Network(owner._regtest.network_subnet, strict=True)
                self.assertEqual(subnet.prefixlen, 28)
                self.assertTrue(subnet.subnet_of(ipaddress.IPv4Network("10.0.0.0/8")))
                run_bytes = bytes.fromhex(owner._regtest.run_id)
                self.assertEqual(str(subnet), f"10.{run_bytes[0]}.{run_bytes[1]}.{run_bytes[2] & 0xf0}/28")
                self.assertEqual(owner.root.stat().st_mode & 0o777, 0o700)
                record = owner.root / "regtest-identity.json"
                self.assertEqual(record.stat().st_mode & 0o777, 0o600)

    def test_regtest_identity_and_vizor_labels_are_recorded_before_docker_starts(self):
        suite = self.root / "native-suite-0a1b2c3d4e" / "repetition-0"
        suite.mkdir(parents=True, mode=0o700)
        for root, expected in ((None, {}), (suite, {"com.keplr.vizor.e2e.suite-run": "0a1b2c3d4e"})):
            with self.subTest(root=root):
                owner = self.backend(self.case(root=root))
                regtest = owner._regtest
                self.assertEqual(regtest.started, 0)
                labels = {REGTEST.RUN_LABEL: regtest.run_id,
                          "com.keplr.vizor.e2e.namespace": owner._case.workspace.namespace, **expected}
                self.assertEqual(regtest.labels, labels)
                record = owner.root / "regtest-identity.json"
                self.assertEqual(record.stat().st_mode & 0o777, 0o600)
                prefix = "vizor-zakura-" + regtest.run_id[:12]
                self.assertEqual(json.loads(record.read_text()), {"schema_version": 1, "run_id": regtest.run_id,
                    "names": {"network": prefix + "-net", "node": prefix + "-node",
                        "donor": prefix + "-donor", "lightwalletd": prefix + "-lwd",
                        "lightwalletd_volume": prefix + "-lwd-data"},
                    "network_subnet": regtest.network_subnet, "labels": labels})
        self.assertEqual(owner.retained_resources(), {"regtest_run_id": owner._regtest.run_id,
                                                      "stopped": False, "identity": None})
        owner._case.close()
        owner.retain()
        self.assertEqual(owner.retained_resources()["stopped"], True)

    def test_the_chain_creates_and_ownership_checks_with_the_vizor_labels(self):
        self.model_class = REGTEST.ZakuraRegtest
        tools = self.root / "tools"
        (tools / "protos").mkdir(parents=True)
        (tools / "protos" / "service.proto").write_text('syntax = "proto3";\n')
        (tools / "grpcurl").write_text("#!/bin/sh\n")
        (tools / "grpcurl").chmod(0o700)
        owner = BACKEND.prepare_native_zakura_backend(self.case(), grpcurl=tools / "grpcurl",
            proto_dir=tools / "protos", miner_address="tmJymvcUCn1ctbghvTJpXBwHiMEB8P6wxNV")
        self.backends.append(owner)
        regtest = owner._regtest
        namespace = owner._case.workspace.namespace
        self.assertIn("com.keplr.vizor.e2e.namespace=" + namespace, regtest._label_args())
        self.assertEqual(json.loads((owner.root / "regtest-identity.json").read_text())["labels"], regtest.labels)
        def inspected(labels):
            def docker(args, deadline, check=True):
                output = (regtest.network_name if args[1] == "ls" else
                          json.dumps([{"Id": "network-id", "Name": regtest.network_name, "Labels": labels}]))
                return subprocess.CompletedProcess(args, 0, output, "")
            return patch.object(regtest, "_docker", side_effect=docker)
        deadline = time.monotonic() + 5
        with inspected({REGTEST.RUN_LABEL: regtest.run_id}):
            with self.assertRaisesRegex(REGTEST.ZakuraRegtestError, "does not carry this run's labels"):
                regtest._owned_id("network", regtest.network_name, deadline)
        with inspected(dict(regtest.labels)):
            self.assertEqual(regtest._owned_id("network", regtest.network_name, deadline), "network-id")

    def test_running_operations_forward_without_exposing_internal_ready_proof(self):
        owner = self.backend()
        ready = owner.start()
        ready["identity"]["run_id"] = "external-mutation"
        self.assertEqual(owner._ready["identity"]["run_id"], owner._regtest.run_id)
        self.assertEqual(owner.rpc("getblock", [1], deadline=42)["deadline"], 42)
        self.assertEqual(owner.grpc("service", {"height": 1})["params"], {"height": 1})
        self.assertEqual(owner.grpc_stream("range")["method"], "range")
        self.assertEqual(owner.mine(2), {"count": 2})
        self.assertEqual(owner.wait_synced(deadline=43), {"synced": True, "deadline": 43})
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.start()

    def test_reorg_operations_require_original_running_unsealed_case(self):
        owner = self.backend()
        for method in (owner.replace_tip_holding, owner.release_held_transactions):
            with self.assertRaises(BACKEND.NativeZakuraError):
                method(["12"*32])
        owner.start()
        self.assertEqual(owner.replace_tip_holding(["12"*32], deadline=42),
                         {"required_txids":["12"*32],"deadline":42})
        self.assertEqual(owner.release_held_transactions(["12"*32], deadline=43),
                         {"released_txids":["12"*32],"deadline":43})
        owner._case.close()
        for method in (owner.replace_tip_holding, owner.release_held_transactions):
            with self.assertRaises(BACKEND.NativeZakuraError):
                method(["12"*32])

    def test_no_adoption_or_chain_for_invalid_case_or_timeout(self):
        built = len(RegtestModel.instances)
        for timeout in (False, 0, -1, float("inf"), float("nan"), "60"):
            with self.subTest(timeout=timeout), self.assertRaises(BACKEND.NativeZakuraError):
                prepare(self.case(), timeout=timeout)
        with self.assertRaises(BACKEND.NativeZakuraError):
            prepare(object())
        self.assertEqual(len(RegtestModel.instances), built)

    def test_duplicate_directory_is_not_adopted_or_modified(self):
        owner = self.backend()
        original = (owner.root / "regtest-identity.json").read_bytes()
        with self.assertRaises(FileExistsError):
            prepare(owner._case)
        self.assertEqual((owner.root / "regtest-identity.json").read_bytes(), original)

    def test_sealed_case_cannot_start_execute_or_allocate_backend(self):
        owner = self.backend()
        owner._case.close()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.start()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.mine(1)
        with patch.object(owner._regtest, "wait_synced") as wait:
            with self.assertRaises(BACKEND.NativeZakuraError):
                owner.wait_synced()
            wait.assert_not_called()
        with self.assertRaises(BACKEND.NativeZakuraError):
            prepare(owner._case)
        self.assertEqual(owner._regtest.started, 0)

    def test_only_original_successful_case_stop_allows_backend_deletion(self):
        owner = self.backend()
        owner.start()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()
        owner._case._cleanup_failed(RuntimeError("writer stop unproven"))
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()
        self.assertEqual(owner._regtest.close_calls, 0)
        owner.retain()

    def test_close_releases_original_handle_and_preserves_evidence(self):
        owner = self.backend()
        owner.start()
        record = owner.root / "regtest-identity.json"
        original = record.read_bytes()
        descriptor = owner._directory_fd
        owner._case.close()
        owner.close()
        self.assertTrue(owner.closed)
        self.assertIsNone(owner._directory_fd)
        with self.assertRaises(OSError):
            os.fstat(descriptor)
        self.assertEqual(record.read_bytes(), original)
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()

    def test_complete_returned_json_cannot_replace_the_chains_closed_flag(self):
        owner = self.backend()
        owner._case.close()
        with patch.object(owner._regtest, "close", return_value={
                "complete": True, "run_id": owner._regtest.run_id, "errors": []}):
            with self.assertRaises(BACKEND.NativeZakuraError):
                owner.close()
        self.assertFalse(owner.closed)
        owner.retain()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()

    def test_returned_cleanup_proof_must_match_original_identity_and_errors(self):
        for changes in ({"run_id": "foreign"}, {"errors": ["unproven"]}, {"complete": False}):
            owner = self.backend()
            owner._case.close()
            owner._regtest.closed = True
            with patch.object(owner._regtest, "close", return_value={
                    "complete": True, "run_id": owner._regtest.run_id, "errors": [], **changes}):
                with self.assertRaises(BACKEND.NativeZakuraError):
                    owner.close()
            self.assertFalse(owner.closed)
            owner.retain()

    def test_retention_is_terminal_cached_and_never_deletes(self):
        owner = self.backend()
        owner.start()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.retain()
        owner._case.close()
        proof = owner.retain()
        proof["complete"] = False
        self.assertTrue(owner.retain()["complete"])
        self.assertEqual(owner._regtest.retain_calls, 1)
        self.assertEqual(owner._regtest.close_calls, 0)
        self.assertTrue(owner.root.exists())
        self.assertFalse(owner.closed)
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.mine(1)
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.wait_synced()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()

    def test_retention_failure_is_sticky_without_retaining_twice(self):
        for result in (RuntimeError("transport failed"), {"complete": False},
                       {"complete": True, "run_id": "foreign", "errors": []}):
            owner = self.backend()
            owner._case.close()
            with patch.object(owner._regtest, "retain", side_effect=result if isinstance(result, Exception) else None,
                              return_value=result) as retain:
                with self.assertRaises((RuntimeError, BACKEND.NativeZakuraError)):
                    owner.retain()
                with self.assertRaises(BACKEND.NativeZakuraError):
                    owner.retain()
                self.assertEqual(retain.call_count, 1)
            self.assertIsNone(owner._directory_fd)
            self.assertTrue(owner.root.exists())

    def test_successful_startup_rollback_does_not_retain_an_already_removed_chain(self):
        owner = self.backend()
        def failed_start():
            owner._regtest.closed = True
            raise RuntimeError("original start failure")
        with patch.object(owner._regtest, "start", side_effect=failed_start):
            with self.assertRaisesRegex(RuntimeError, "original start failure"):
                owner.start()
        owner._case.close()
        owner.retain()
        self.assertEqual(owner._regtest.retain_calls, 0)
        self.assertFalse(owner.closed)
        self.assertTrue(owner.root.exists())

    def test_directory_replacement_refuses_writes_but_stops_original_resources(self):
        owner = self.backend()
        moved = owner.root.with_name("original-backend-evidence")
        owner.root.rename(moved)
        owner.root.mkdir(mode=0o700)
        sentinel = owner.root / "regtest-identity.json"
        sentinel.write_text("replacement-preserve")
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner._write_text("regtest-identity.json", "must-not-write")
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.start()
        owner._case.close()
        owner.retain()
        self.assertEqual(owner._regtest.retain_calls, 1)
        self.assertEqual(sentinel.read_text(), "replacement-preserve")
        self.assertEqual(json.loads((moved / "regtest-identity.json").read_text())["run_id"], owner._regtest.run_id)

    def test_artifact_escape_rejected_and_replaced_links_never_write_shared_target(self):
        owner = self.backend()
        for name in ("../outside", "child/file", ".", "..", "", 1):
            with self.subTest(name=name), self.assertRaises(BACKEND.NativeZakuraError):
                owner._write_text(name, "bad")
        target = self.root / "shared-original"
        target.write_text("preserve")
        (owner.root / "symlink.log").symlink_to(target)
        os.link(target, owner.root / "hardlink.log")
        for name in ("symlink.log", "hardlink.log"):
            owner._write_text(name, "owned-replacement")
            self.assertEqual((owner.root / name).read_text(), "owned-replacement")
            self.assertEqual((owner.root / name).stat().st_mode & 0o777, 0o600)
        self.assertEqual(target.read_text(), "preserve")


if __name__ == "__main__":
    unittest.main()
