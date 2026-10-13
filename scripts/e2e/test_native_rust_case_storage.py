"""Real owned files/children/ports; no Rust wallet or Docker scenario models."""
from pathlib import Path
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_sequential as SEQUENTIAL


class RustStorageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="rust-storage-model-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        (self.root / "cases").mkdir(mode=0o700)
        self.sessions = []
        self.addCleanup(self.retain_sessions)
        original = SEQUENTIAL.lease_native_ports
        ports = patch.object(SEQUENTIAL, "lease_native_ports", side_effect=lambda worker, run:
            original(worker, run, lock_root=self.root / "ports"))
        ports.start()
        self.addCleanup(ports.stop)

    def retain_sessions(self):
        for session in self.sessions:
            if not session._finished:
                session.retain()

    def case(self, index=1):
        session = SEQUENTIAL.SequentialCase(self.root / "cases", run_id="a1b2c3d4e5", case_index=index,
            scenario_id="rust.receive.sync", platform="rust", activation_height=1)
        self.sessions.append(session)
        return session

    def test_private_wallet_storage_original_writer_join_and_evidence_retention(self):
        session = self.case()
        wallet = session.storage.path
        self.assertEqual(wallet.stat().st_mode & 0o777, 0o700)
        (wallet / "db").write_text("modeled wallet")
        child = session.case.start_process([sys.executable, "-B", "-c", "import time; time.sleep(30)"], env=os.environ)
        session.close(timeout=3)
        self.assertTrue(child.cleanup_completed)
        self.assertFalse(wallet.exists())
        self.assertTrue(session.case.workspace.manifest_path.exists())
        self.assertFalse(session.lease.sockets or session.lease.lock_descriptors)

    def test_sibling_and_external_link_targets_are_preserved(self):
        case, sibling = self.case(1), self.case(2)
        sentinel = sibling.storage.path / "keep"
        sentinel.write_text("preserve")
        (case.storage.path / "external-link").symlink_to(sibling.storage.path, target_is_directory=True)
        case.close(timeout=3)
        self.assertEqual(sentinel.read_text(), "preserve")
        sibling.close(timeout=3)

    def test_replaced_wallet_root_is_not_removed(self):
        session = self.case()
        original = session.storage.path
        original.rename(original.with_name("retained-original"))
        original.mkdir(mode=0o700)
        sentinel = original / "replacement"
        sentinel.write_text("preserve")
        with self.assertRaises(SEQUENTIAL.runtime.RunnerError):
            session.close(timeout=3)
        self.assertEqual(sentinel.read_text(), "preserve")

    def test_unproven_writer_stop_retains_wallet_and_port_locks(self):
        session = self.case()
        sentinel = session.storage.path / "db"
        sentinel.write_text("preserve")
        with patch.object(session.case, "close", side_effect=SEQUENTIAL.runtime.RunnerError("writer stop unproven")):
            with self.assertRaises(SEQUENTIAL.runtime.RunnerError):
                session.close(timeout=3)
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertTrue(session.lease.lock_descriptors)

    def test_failed_case_retains_wallet_without_claiming_cleanup(self):
        session = self.case()
        (session.storage.path / "db").write_text("failed evidence")
        session.retain()
        self.assertTrue(session.storage.path.exists())
        self.assertEqual(session.retained_resources()["wallet_files"], str(session.storage.path))


if __name__ == "__main__":
    unittest.main()
