"""Raw backend ownership models; no Docker or wallet PASS is inferred here."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_zakura_backend as BACKEND
    import native_workspace as WORKSPACE
finally:
    sys.path.pop(0)


class FixtureModel:
    """Constructed by the adapter, not adopted from an external fixture/receipt."""
    def __init__(self, artifacts, grpcurl, proto_dir, *, timeout, run_id, miner_address, profile):
        self.artifacts = artifacts
        self.run_id = run_id.hex
        self.timeout, self.miner_address, self.profile = timeout, miner_address, profile
        self._closed = self._retained = False
        self.started = self.close_calls = self.retain_calls = 0

    def start(self):
        self.started += 1
        self._write_text("start-proof.json", json.dumps({"run_id": self.run_id}))
        return {"identity": {"run_id": self.run_id}, "profile": self.profile}

    def rpc(self, method, params=None, *, deadline=None):
        return {"method": method, "params": params, "deadline": deadline}

    grpc = grpc_stream = rpc

    def mine(self, count):
        return {"count": count}

    def close(self):
        self.close_calls += 1
        self._closed = True
        return {"complete": True, "run_id": self.run_id, "errors": []}

    def retain(self):
        self.retain_calls += 1
        self._retained = True
        return {"complete": True, "run_id": self.run_id, "errors": []}


def modeled_source(fixture_class=FixtureModel):
    return types.SimpleNamespace(fixture_class=fixture_class,
                                 identity=lambda: {"repository": "modeled", "commit": "captured"})


def prepare(case, **updates):
    return BACKEND.prepare_native_zakura_backend(case, tooling_root=Path("unused-source"),
        grpcurl=Path("unused-grpcurl"), proto_dir=Path("unused-protos"),
        miner_address="explicit-regtest-miner-model", **updates)


class BackendTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-zakura-owner-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cases, self.backends = [], []
        self.addCleanup(self.stop_models)
        source = patch.object(BACKEND, "load_zakura_fixture_source", return_value=modeled_source())
        self.loader = source.start()
        self.addCleanup(source.stop)

    def case(self, activation=500):
        workspace = WORKSPACE.prepare_native_case_workspace(self.root, platform="macos",
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

    def test_construct_only_captures_source_private_directory_and_explicit_profile(self):
        for activation, profile in ((1, "zakura-direct-height1"), (500, "zakura-direct-activation500")):
            with self.subTest(activation=activation):
                owner = self.backend(self.case(activation))
                self.assertEqual(owner._fixture.started, 0)
                self.assertEqual(owner._fixture.profile, profile)
                self.assertEqual(owner._fixture.miner_address, "explicit-regtest-miner-model")
                self.assertEqual(owner.root.stat().st_mode & 0o777, 0o700)
                source_file = owner.root / "source-identity.json"
                self.assertEqual(source_file.stat().st_mode & 0o777, 0o600)
                self.assertEqual(json.loads(source_file.read_text()), modeled_source().identity())

    def test_running_operations_forward_without_exposing_internal_ready_proof(self):
        owner = self.backend()
        ready = owner.start()
        ready["identity"]["run_id"] = "external-mutation"
        self.assertEqual(owner._ready["identity"]["run_id"], owner._fixture.run_id)
        self.assertEqual(owner.rpc("getblock", [1], deadline=42)["deadline"], 42)
        self.assertEqual(owner.grpc("service", {"height": 1})["params"], {"height": 1})
        self.assertEqual(owner.grpc_stream("range")["method"], "range")
        self.assertEqual(owner.mine(2), {"count": 2})
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.start()

    def test_no_adoption_or_source_import_for_invalid_case_or_timeout(self):
        for timeout in (False, 0, -1, float("inf"), float("nan"), "60"):
            with self.subTest(timeout=timeout), self.assertRaises(BACKEND.NativeZakuraError):
                prepare(self.case(), timeout=timeout)
        with self.assertRaises(BACKEND.NativeZakuraError):
            prepare(object())
        self.loader.assert_not_called()

    def test_duplicate_directory_is_not_adopted_or_modified(self):
        owner = self.backend()
        original = (owner.root / "source-identity.json").read_bytes()
        with self.assertRaises(FileExistsError):
            prepare(owner._case)
        self.assertEqual((owner.root / "source-identity.json").read_bytes(), original)

    def test_sealed_case_cannot_start_execute_or_allocate_backend(self):
        owner = self.backend()
        owner._case.close()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.start()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.mine(1)
        with self.assertRaises(BACKEND.NativeZakuraError):
            prepare(owner._case)
        self.assertEqual(owner._fixture.started, 0)

    def test_only_original_successful_case_stop_allows_backend_deletion(self):
        owner = self.backend()
        owner.start()
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()
        owner._case._cleanup_failed(RuntimeError("writer stop unproven"))
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()
        self.assertEqual(owner._fixture.close_calls, 0)
        owner.retain()

    def test_close_releases_original_handle_and_preserves_evidence(self):
        owner = self.backend()
        owner.start()
        source_file = owner.root / "source-identity.json"
        original = source_file.read_bytes()
        descriptor = owner._directory_fd
        owner._case.close()
        owner.close()
        self.assertTrue(owner.closed)
        self.assertIsNone(owner._directory_fd)
        with self.assertRaises(OSError):
            os.fstat(descriptor)
        self.assertEqual(source_file.read_bytes(), original)
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()

    def test_complete_returned_json_cannot_replace_original_helper_closed_flag(self):
        owner = self.backend()
        owner._case.close()
        with patch.object(owner._fixture, "close", return_value={
                "complete": True, "run_id": owner._fixture.run_id, "errors": []}):
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
            owner._fixture._closed = True
            with patch.object(owner._fixture, "close", return_value={
                    "complete": True, "run_id": owner._fixture.run_id, "errors": [], **changes}):
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
        self.assertEqual(owner._fixture.retain_calls, 1)
        self.assertEqual(owner._fixture.close_calls, 0)
        self.assertTrue(owner.root.exists())
        self.assertFalse(owner.closed)
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.mine(1)
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.close()

    def test_retention_failure_is_sticky_without_reinvoking_helper(self):
        for result in (RuntimeError("transport failed"), {"complete": False},
                       {"complete": True, "run_id": "foreign", "errors": []}):
            owner = self.backend()
            owner._case.close()
            with patch.object(owner._fixture, "retain", side_effect=result if isinstance(result, Exception) else None,
                              return_value=result) as retain:
                with self.assertRaises((RuntimeError, BACKEND.NativeZakuraError)):
                    owner.retain()
                with self.assertRaises(BACKEND.NativeZakuraError):
                    owner.retain()
                self.assertEqual(retain.call_count, 1)
            self.assertIsNone(owner._directory_fd)
            self.assertTrue(owner.root.exists())

    def test_successful_startup_rollback_does_not_retain_already_deleted_fixture(self):
        owner = self.backend()
        def failed_start():
            owner._fixture._closed = True
            raise RuntimeError("original start failure")
        with patch.object(owner._fixture, "start", side_effect=failed_start):
            with self.assertRaisesRegex(RuntimeError, "original start failure"):
                owner.start()
        owner._case.close()
        owner.retain()
        self.assertEqual(owner._fixture.retain_calls, 0)
        self.assertFalse(owner.closed)
        self.assertTrue(owner.root.exists())

    def test_directory_replacement_refuses_writes_but_stops_original_resources(self):
        owner = self.backend()
        moved = owner.root.with_name("original-backend-evidence")
        owner.root.rename(moved)
        owner.root.mkdir(mode=0o700)
        sentinel = owner.root / "source-identity.json"
        sentinel.write_text("replacement-preserve")
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner._write_text("source-identity.json", "must-not-write")
        with self.assertRaises(BACKEND.NativeZakuraError):
            owner.start()
        owner._case.close()
        owner.retain()
        self.assertEqual(owner._fixture.retain_calls, 1)
        self.assertEqual(sentinel.read_text(), "replacement-preserve")
        self.assertEqual(json.loads((moved / "source-identity.json").read_text()), modeled_source().identity())

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
