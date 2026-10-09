"""Real owned files/children/ports; no Rust wallet or Docker scenario models."""
from pathlib import Path
import os
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_worker_lifecycle as WORKER


class RustStorageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="rust-storage-model-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.workers = []
        self.addCleanup(self.retain_workers)
        original = WORKER.lease_native_ports
        ports = patch.object(WORKER, "lease_native_ports", side_effect=lambda worker, run:
            original(worker, run, lock_root=self.root / "ports"))
        ports.start()
        self.addCleanup(ports.stop)

    def retain_workers(self):
        for worker in self.workers:
            if worker.workspace.exists():
                worker.retain(timeout=3)

    def worker(self, index=0):
        worker = WORKER.prepare_native_worker_lifecycle(self.root, run_id="a1b2c3d4e5", worker_id=index)
        self.workers.append(worker)
        return worker

    def case(self, worker):
        return worker.prepare_case(platform="rust", scenario_id="rust.receive.sync",
            case_index=1, activation_height=1, timeout=3)

    def test_private_wallet_storage_original_writer_join_and_evidence_retention(self):
        worker = self.worker()
        session = self.case(worker)
        wallet = session.storage.path
        self.assertEqual(wallet.stat().st_mode & 0o777, 0o700)
        (wallet / "db").write_text("modeled wallet")
        child = session.case.start_process([sys.executable, "-B", "-c", "import time; time.sleep(30)"], env=os.environ)
        observation = session.close(timeout=3)
        self.assertTrue(child.cleanup_completed)
        self.assertTrue(observation["wallet_storage_absent"])
        worker.close()
        self.assertFalse(wallet.exists())
        self.assertFalse(worker.workspace.exists())
        self.assertTrue(session.case.workspace.manifest_path.exists())
        self.assertFalse(session.lease.sockets or session.lease.lock_descriptors)

    def test_sibling_and_external_link_targets_are_preserved(self):
        first, second = self.worker(0), self.worker(1)
        case, sibling = self.case(first), self.case(second)
        sentinel = sibling.storage.path / "keep"
        sentinel.write_text("preserve")
        (case.storage.path / "external-link").symlink_to(sibling.storage.path, target_is_directory=True)
        case.close(timeout=3)
        first.close()
        self.assertEqual(sentinel.read_text(), "preserve")
        sibling.close(timeout=3)
        second.close()

    def test_replaced_wallet_root_is_not_removed(self):
        worker = self.worker()
        session = self.case(worker)
        original = session.storage.path
        original.rename(original.with_name("retained-original"))
        original.mkdir(mode=0o700)
        sentinel = original / "replacement"
        sentinel.write_text("preserve")
        with self.assertRaises(WORKER.runtime.RunnerError):
            session.close(timeout=3)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertTrue(worker.workspace.exists())

    def test_unproven_writer_stop_retains_wallet_and_port_locks(self):
        worker = self.worker()
        session = self.case(worker)
        sentinel = session.storage.path / "db"
        sentinel.write_text("preserve")
        with patch.object(session.case, "close", side_effect=WORKER.runtime.RunnerError("writer stop unproven")):
            with self.assertRaises(WORKER.runtime.RunnerError):
                session.close(timeout=3)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertTrue(session.lease.lock_descriptors)

    def test_failed_case_retains_wallet_without_claiming_cleanup(self):
        worker = self.worker()
        session = self.case(worker)
        (session.storage.path / "db").write_text("failed evidence")
        session.retain(timeout=3)
        self.assertFalse(session._completed)
        self.assertTrue(session.storage.path.exists())
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.close()

    def test_rust_rejects_native_helper_before_case_allocation(self):
        worker = self.worker()
        with self.assertRaises(WORKER.NativeWorkerError):
            worker.prepare_case(platform="rust", scenario_id="rust.receive.sync", case_index=1,
                activation_height=1, helper=object())
        self.assertEqual(worker._cases, [])
        worker.close()


if __name__ == "__main__":
    unittest.main()
