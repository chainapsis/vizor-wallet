"""Worker models compose existing native fixtures with real files/children/ports.

Native observations/signatures and Simulator SDK transport remain modeled. These
are not wallet, backend, build-publication or financial scenario results.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_worker_lifecycle as WORKER
    import test_native_mac_case_storage as MAC_FIXTURES
    import test_native_ios_case_storage as IOS_FIXTURES
finally:
    sys.path.pop(0)


class MacWorkerTests(unittest.TestCase):
    def setUp(self):
        self.native = MAC_FIXTURES.MacCaseStorageTests()
        self.native.setUp()
        self.addCleanup(self.native.doCleanups)
        self.root = self.native.host.root / "worker-artifacts"
        self.root.mkdir(mode=0o700)
        original = WORKER.lease_native_ports
        lease_patch = patch.object(WORKER, "lease_native_ports", side_effect=lambda worker, run:
                                   original(worker, run, lock_root=self.root / "test-ports"))
        lease_patch.start()
        self.addCleanup(lease_patch.stop)
        self.workers = []
        self.addCleanup(self.retain_workers)

    def retain_workers(self):
        for worker in self.workers:
            if worker.workspace.exists():
                worker.retain(timeout=3)

    def worker(self, index=0):
        result = WORKER.prepare_native_worker_lifecycle(self.root, run_id="a1b2c3d4e5", worker_id=index)
        self.workers.append(result)
        return result

    def case(self, worker, index=0):
        return worker.prepare_case(platform="macos", scenario_id="flutter.macos.worker-probe",
            case_index=index, activation_height=500, helper=self.native.host.capture(), timeout=3)

    def app(self, session):
        managed = session.storage.start_app(env=os.environ)
        session.case.wait_process(managed, timeout=3, cancel_event=threading.Event())
        return managed

    def test_exclusive_private_worker_has_separate_evidence_and_mutable_trees(self):
        worker = self.worker()
        for path in (worker.root, worker.workspace, worker.evidence):
            self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertEqual((worker.root / WORKER._MARKER).stat().st_mode & 0o777, 0o600)
        with self.assertRaises(FileExistsError):
            self.worker()
        observed = worker.close()
        self.assertEqual(observed.namespaces, ())
        self.assertFalse(worker.workspace.exists())
        self.assertTrue(worker.evidence.exists())
        self.assertTrue((worker.root / WORKER._MARKER).exists())

    def test_native_case_closes_then_worker_removes_only_mutable_storage(self):
        worker = self.worker()
        session = self.case(worker)
        (session.mutable_directory / "chain.bin").write_text("owned-chain-model")
        self.app(session)
        session.close(timeout=3)
        self.assertTrue(session._completed)
        evidence = {file.name: file.read_bytes() for file in session.case.workspace.root.iterdir() if file.is_file()}
        observed = worker.close()
        self.assertFalse(worker.workspace.exists())
        self.assertEqual(observed.namespaces, (session.case.workspace.namespace,))
        self.assertEqual(evidence, {file.name: file.read_bytes() for file in session.case.workspace.root.iterdir() if file.is_file()})
        self.assertFalse(session.storage.path.exists())
        self.assertFalse(session.lease.sockets or session.lease.lock_descriptors)

    def test_workspace_links_unlink_only_not_shared_cache_targets(self):
        worker = self.worker()
        shared = self.native.host.root / "shared-cache"
        shared.mkdir(mode=0o700)
        (shared / "original").write_text("preserve")
        (worker.workspace / "cache-link").symlink_to(shared, target_is_directory=True)
        (worker.workspace / "dangling-link").symlink_to(shared / "missing")
        worker.close()
        self.assertEqual((shared / "original").read_text(), "preserve")

    def test_completed_one_worker_does_not_touch_active_sibling_worker(self):
        first, other = self.worker(0), self.worker(1)
        self.native.app_code = "time.sleep(30)"
        self.native.install_scripts()
        a, b = self.case(first), self.case(other)
        writer = b.storage.start_app(env=os.environ)
        a.close(timeout=3)
        first.close()
        self.assertTrue(other.workspace.exists())
        self.assertTrue(b.storage.path.exists())
        self.assertIsNone(writer.process.poll())
        self.assertTrue(b.lease.lock_descriptors)

    def test_failed_scenario_stops_writers_retains_all_state_and_blocks_assignment(self):
        worker = self.worker()
        self.native.app_code = "time.sleep(30)"
        self.native.install_scripts()
        session = self.case(worker)
        writer = session.storage.start_app(env=os.environ)
        session.retain(timeout=3)
        self.assertIsNotNone(writer.process.poll())
        self.assertTrue(worker.workspace.exists())
        self.assertTrue(session.storage.path.exists())
        self.assertTrue(session.case.workspace.root.exists())
        with self.assertRaises(WORKER.NativeWorkerError):
            self.case(worker, 1)
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.close()

    def test_close_with_active_case_stops_writers_and_retains_workspace(self):
        worker = self.worker()
        self.native.app_code = "time.sleep(30)"
        self.native.install_scripts()
        session = self.case(worker)
        writer = session.storage.start_app(env=os.environ)
        with self.assertRaisesRegex(WORKER.NativeWorkerError, "incomplete"):
            worker.close()
        self.assertIsNotNone(writer.process.poll())
        self.assertTrue(worker.workspace.exists())
        self.assertTrue(session.storage.path.exists())
        self.assertFalse(session._completed)

    def test_bad_native_receipt_retains_workspace_and_never_completes_case(self):
        worker = self.worker()
        self.native.helper_code = "value['completed']=False"
        self.native.install_scripts()
        session = self.case(worker)
        self.app(session)
        with self.assertRaises(WORKER.mac_storage.MacCaseStorageError):
            session.close(timeout=3)
        self.assertFalse(session._completed)
        self.assertTrue(worker.workspace.exists())
        self.assertTrue(session.storage.path.exists())
        self.assertFalse(session.lease.lock_descriptors)
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.close()

    def test_native_preparation_failure_is_registered_retained_and_releases_safe_ports(self):
        worker = self.worker()
        self.native.verify_updates = {"completed": False}
        self.native.install_scripts()
        with self.assertRaises(WORKER.mac_storage.MacCaseStorageError):
            self.case(worker)
        self.assertEqual(len(worker._cases), 1)
        session = worker._cases[0]
        self.assertTrue(session.mutable_directory.exists())
        self.assertTrue(session.case.workspace.root.exists())
        self.assertFalse(session.lease.sockets or session.lease.lock_descriptors)
        self.assertFalse(session.case.accepting_launches)
        with self.assertRaises(WORKER.NativeWorkerError):
            self.case(worker, 1)

    def test_original_marker_change_prevents_removal_and_stops_live_case(self):
        worker = self.worker()
        self.native.app_code = "time.sleep(30)"
        self.native.install_scripts()
        session = self.case(worker)
        writer = session.storage.start_app(env=os.environ)
        (worker.root / WORKER._MARKER).write_text("changed")
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.close()
        self.assertTrue(worker.workspace.exists())
        self.assertIsNotNone(writer.process.poll())

    def test_same_worker_root_replacement_is_not_adopted(self):
        worker = self.worker()
        moved = worker.root.with_name("moved-original-worker")
        worker.root.rename(moved)
        worker.root.mkdir(mode=0o700)
        worker.workspace.mkdir(mode=0o700)
        worker.evidence.mkdir(mode=0o700)
        (worker.root / WORKER._MARKER).write_bytes(worker._marker_bytes)
        (worker.root / WORKER._MARKER).chmod(0o600)
        (worker.workspace / "replacement").write_text("preserve")
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.close()
        self.assertEqual((worker.workspace / "replacement").read_text(), "preserve")
        self.assertTrue((moved / "workspace").exists())

    def test_mutable_hardlink_is_refused_before_any_removal(self):
        worker = self.worker()
        external = self.native.host.root / "shared"
        external.write_text("preserve")
        os.link(external, worker.workspace / "unsafe-hardlink")
        (worker.workspace / "owned").write_text("preserve-on-failure")
        with self.assertRaises(WORKER.tree.OwnedTreeError):
            worker.close()
        self.assertEqual(external.read_text(), "preserve")
        self.assertTrue((worker.workspace / "owned").exists())

    def test_case_cancelled_preparation_retains_original_classification(self):
        worker = self.worker()
        cancellation = threading.Event()
        cancellation.set()
        with self.assertRaises(WORKER.runtime.Cancelled):
            worker.prepare_case(platform="macos", scenario_id="flutter.macos.worker-probe",
                case_index=0, activation_height=500, helper=self.native.host.capture(),
                timeout=3, cancel_event=cancellation)
        self.assertTrue(worker.workspace.exists())
        self.assertFalse(worker._cases[0].lease.lock_descriptors)

    def test_external_cleanup_boolean_or_json_is_not_an_api(self):
        worker = self.worker()
        session = self.case(worker)
        with self.assertRaises(TypeError):
            worker.close(state_cleanup_proven=True)
        with self.assertRaises(TypeError):
            session.close(receipt={"completed": True})
        self.assertFalse(session._completed)
        self.assertTrue(worker.workspace.exists())

    def test_replaced_case_mutable_directory_is_not_adopted_for_cleanup(self):
        worker = self.worker()
        session = self.case(worker)
        moved = worker.workspace / "moved-original-case"
        session.mutable_directory.rename(moved)
        session.mutable_directory.mkdir(mode=0o700)
        sentinel = session.mutable_directory / "replacement"
        sentinel.write_text("preserve")
        with self.assertRaisesRegex(WORKER.NativeWorkerError, "identity changed"):
            session.close(timeout=3)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertTrue(moved.exists())
        self.assertFalse(session._completed)

    def test_port_cleanup_failure_keeps_worker_failed_without_repeating_native_cleanup(self):
        worker = self.worker()
        session = self.case(worker)
        original = session.lease.close
        with patch.object(session.lease, "close", side_effect=RuntimeError("port release failed")):
            with self.assertRaisesRegex(RuntimeError, "port release failed"):
                session.close(timeout=3)
        self.assertTrue(session._native_finalized)
        self.assertFalse(session.storage.path.exists())
        self.assertFalse(session._completed)
        self.assertTrue(worker.workspace.exists())
        original()
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.close()

    def test_unproven_writer_stop_keeps_cooperative_port_reservations(self):
        worker = self.worker()
        session = self.case(worker)
        with patch.object(session.case, "close", side_effect=WORKER.runtime.RunnerError("writer stop unproven")):
            with self.assertRaises(WORKER.runtime.RunnerError):
                session.retain(timeout=3)
        self.assertTrue(session.lease.sockets)
        self.assertTrue(session.lease.lock_descriptors)
        self.assertTrue(session.storage.path.exists())
        self.assertFalse(session._completed)


class IosWorkerTests(unittest.TestCase):
    def setUp(self):
        self.native = IOS_FIXTURES.IosCaseStorageTests()
        self.native.setUp()
        self.addCleanup(self.native.doCleanups)
        self.root = self.native.root / "worker-artifacts"
        self.root.mkdir(mode=0o700)
        self.worker = WORKER.prepare_native_worker_lifecycle(self.root, run_id="a1b2c3d4e5", worker_id=0)
        self.addCleanup(self.worker.retain, timeout=15)
        original = WORKER.lease_native_ports
        lease_patch = patch.object(WORKER, "lease_native_ports", side_effect=lambda worker, run:
                                  original(worker, run, lock_root=self.root / "test-ports"))
        lease_patch.start()
        self.addCleanup(lease_patch.stop)
        launch = self.native.start_sdk_console
        def register_launch(command, **options):
            udid = command[4]
            self.native.simulators[udid] = next(case.simulator for case in self.worker._cases
                                              if case.simulator is not None and case.simulator.udid == udid)
            return launch(command, **options)
        sdk_patch = patch.object(WORKER.runtime, "start_logged_process", side_effect=register_launch)
        sdk_patch.start()
        self.addCleanup(sdk_patch.stop)

    def case(self):
        return self.worker.prepare_case(platform="ios", scenario_id="flutter.ios.worker-probe",
            case_index=0, activation_height=500, helper=self.native.helper,
            runtime_identifier=IOS_FIXTURES.RUNTIME_ID, device_type_identifier=IOS_FIXTURES.DEVICE_ID,
            timeout=15)

    def test_native_ios_restart_teardown_then_worker_cleanup_preserves_evidence(self):
        session = self.case()
        first = session.storage.start_app(timeout=15)
        session.storage.stop_app(first, timeout=15)
        second = session.storage.start_app(timeout=15)
        self.assertNotEqual(first.pid, second.pid)
        session.close(timeout=15)
        self.assertNotIn(session.simulator.udid, self.native.model.devices)
        self.worker.close()
        self.assertFalse(self.worker.workspace.exists())
        self.assertTrue(session.case.workspace.root.exists())
        self.assertTrue((session.case.workspace.root / "ios-storage-relocation-0001.json").exists())

    def test_failed_ios_case_shuts_down_only_its_uuid_and_retains_workspace(self):
        session = self.case()
        session.storage.start_app(timeout=15)
        session.retain(timeout=15)
        self.assertEqual(self.native.model.devices[session.simulator.udid]["state"], "Shutdown")
        self.assertTrue(session.storage.path.exists())
        self.assertTrue(self.worker.workspace.exists())
        self.assertFalse(any(call[0] == "delete" for call in self.native.model.calls))

    def test_failed_ios_receipt_keeps_native_owner_device_and_worker_state(self):
        self.native.bad_receipt = lambda value, mode: value.update(completed=False)
        with self.assertRaises(WORKER.ios_native.IosCleanupError):
            self.case()
        session = self.worker._cases[0]
        self.assertIsNotNone(session.simulator._state.native_owner)
        self.assertEqual(self.native.model.devices[session.simulator.udid]["state"], "Shutdown")
        self.assertTrue(session.mutable_directory.exists())
        self.assertFalse(any(call[0] == "delete" for call in self.native.model.calls))


if __name__ == "__main__":
    unittest.main()
