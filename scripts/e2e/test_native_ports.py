"""Host-only port ownership tests; no app, simulator, or fixture is launched."""

from __future__ import annotations

import fcntl
import importlib.util
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location(
    "native_ports", Path(__file__).with_name("native_ports.py")
)
assert SPEC is not None and SPEC.loader is not None
PORTS = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PORTS
SPEC.loader.exec_module(PORTS)


class NativePortsTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="vizor-native-ports-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.locks = self.root / "ports"

    def acquire(self, worker_id: int = 0):
        lease = PORTS.lease_native_ports(worker_id, "a1b2c3d4e5", lock_root=self.locks)
        self.addCleanup(lease.close)
        return lease

    def test_five_workers_hold_fifteen_distinct_loopback_ports(self):
        leases = [self.acquire(index) for index in range(5)]
        ports = [port for lease in leases for port in lease.ports.values()]
        self.assertEqual(len(set(ports)), 15)
        for lease in leases:
            self.assertEqual(set(lease.ports), {"rpc", "lwd", "proxy"})
            self.assertTrue(all(item.getsockname()[0] == "127.0.0.1" for item in lease.sockets))
        for port in ports:
            with socket.socket() as probe:
                with self.assertRaises(OSError):
                    probe.bind(("127.0.0.1", port))

    def test_service_handoff_keeps_lock_until_lease_closes(self):
        lease = self.acquire()
        port = lease.ports["rpc"]
        lease.release_sockets()
        with socket.socket() as service:
            service.bind(("127.0.0.1", port))
        path = self.locks / f"{port}.lock"
        descriptor = os.open(path, os.O_RDWR)
        try:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lease.close()
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(descriptor)
        self.assertTrue(path.exists(), "lock inode must survive release")

    def test_separate_process_cannot_take_a_handed_off_port_lock(self):
        lease = self.acquire()
        lease.release_sockets()
        path = self.locks / f"{lease.ports['rpc']}.lock"
        source = (
            "import fcntl,os,sys; fd=os.open(sys.argv[1],os.O_RDWR)\n"
            "try: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)\n"
            "except BlockingIOError: sys.exit(23)\n"
            "finally: os.close(fd)\n"
        )
        self.assertEqual(
            subprocess.run([sys.executable, "-c", source, str(path)], timeout=5).returncode,
            23,
        )
        lease.close()
        self.assertEqual(
            subprocess.run([sys.executable, "-c", source, str(path)], timeout=5).returncode,
            0,
        )

    def test_closing_one_worker_does_not_release_sibling_ports(self):
        first, second = self.acquire(0), self.acquire(1)
        first.close()
        for port in second.ports.values():
            with socket.socket() as probe:
                with self.assertRaises(OSError):
                    probe.bind(("127.0.0.1", port))

    def test_releasing_and_closing_are_idempotent(self):
        lease = self.acquire()
        lease.release_sockets()
        lease.release_sockets()
        lease.close()
        lease.close()
        self.assertEqual(lease.sockets, [])
        self.assertEqual(lease.lock_descriptors, [])

    def test_lock_directory_and_files_are_private(self):
        lease = self.acquire()
        self.assertEqual(self.locks.stat().st_mode & 0o777, 0o700)
        for port in lease.ports.values():
            path = self.locks / f"{port}.lock"
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertIn("run_id=a1b2c3d4e5", path.read_text())

    def test_default_lock_root_is_shared_per_uid_not_per_run(self):
        with patch.object(PORTS.tempfile, "gettempdir", return_value=str(self.root)):
            lease = PORTS.lease_native_ports(0, "a1b2c3d4e5")
        self.addCleanup(lease.close)
        expected = self.root / f"vizor-wallet-native-e2e-{os.getuid()}" / "ports"
        self.assertTrue(all((expected / f"{port}.lock").exists() for port in lease.ports.values()))

    def test_unsafe_lock_file_cannot_overwrite_a_symlink_target(self):
        self.locks.mkdir(mode=0o700)
        target = self.root / "foreign-evidence"
        target.write_text("must survive")
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            port = reserved.getsockname()[1]
            (self.locks / f"{port}.lock").symlink_to(target)
            wrapped = Mock(wraps=reserved)
            wrapped.bind.side_effect = lambda _address: None
            with patch.object(PORTS.socket, "socket", return_value=wrapped):
                with self.assertRaises(OSError):
                    PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
            self.assertEqual(reserved.fileno(), -1)
        self.assertEqual(target.read_text(), "must survive")

    def test_cleanup_failure_releases_other_handles_and_never_becomes_a_pass(self):
        lease = PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
        descriptors = list(lease.lock_descriptors)
        reserved = list(lease.sockets)
        flock = PORTS.fcntl.flock

        def fail_first_unlock(descriptor, operation):
            if descriptor == descriptors[0]:
                raise OSError("injected unlock failure")
            return flock(descriptor, operation)

        with patch.object(PORTS.fcntl, "flock", side_effect=fail_first_unlock):
            with self.assertRaisesRegex(PORTS.NativePortError, "cleanup unproven"):
                lease.close()
        self.assertTrue(all(item.fileno() == -1 for item in reserved))
        for descriptor in descriptors:
            with self.assertRaises(OSError):
                os.fstat(descriptor)
        with self.assertRaisesRegex(PORTS.NativePortError, "cleanup unproven"):
            lease.close()

    def test_invalid_identity_fails_before_creating_locks(self):
        for worker_id in (True, -1, 1_000_001, "0"):
            with self.assertRaises(PORTS.NativePortError):
                PORTS.lease_native_ports(worker_id, "a1b2c3d4e5", lock_root=self.locks)
        for run_id in (None, "", "A1B2C3D4E5", "a1b2c3d4e5\n"):
            with self.assertRaises(PORTS.NativePortError):
                PORTS.lease_native_ports(0, run_id, lock_root=self.locks)
        self.assertFalse(self.locks.exists())

    def test_symlinked_directory_is_rejected_without_changing_target(self):
        target = self.root / "other"
        target.mkdir(mode=0o700)
        self.locks.symlink_to(target, target_is_directory=True)
        with self.assertRaises(PORTS.NativePortError):
            PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
        self.assertEqual(list(target.iterdir()), [])

    def test_relative_and_nonprivate_lock_directories_are_rejected(self):
        with self.assertRaises(PORTS.NativePortError):
            PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=Path("ports"))
        self.locks.mkdir(mode=0o755)
        self.locks.chmod(0o755)
        with self.assertRaises(PORTS.NativePortError):
            PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
        self.assertEqual(self.locks.stat().st_mode & 0o777, 0o755)

    def test_partial_acquisition_failure_releases_prior_owned_handles(self):
        reserve = PORTS._reserve_port
        acquired = []

        def fail_second(*arguments):
            if acquired:
                raise PORTS.NativePortError("injected allocation failure")
            value = reserve(*arguments)
            acquired.append(value)
            return value

        with patch.object(PORTS, "_reserve_port", side_effect=fail_second):
            with self.assertRaisesRegex(PORTS.NativePortError, "allocation failure"):
                PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
        _, reserved, descriptor = acquired[0]
        self.assertEqual(reserved.fileno(), -1)
        with self.assertRaises(OSError):
            os.fstat(descriptor)

    def test_interrupt_during_acquisition_releases_prior_owned_handles(self):
        reserve = PORTS._reserve_port
        acquired = []

        def interrupt_second(*arguments):
            if acquired:
                raise KeyboardInterrupt
            value = reserve(*arguments)
            acquired.append(value)
            return value

        with patch.object(PORTS, "_reserve_port", side_effect=interrupt_second):
            with self.assertRaises(KeyboardInterrupt):
                PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
        self.assertEqual(acquired[0][1].fileno(), -1)
        with self.assertRaises(OSError):
            os.fstat(acquired[0][2])

    def test_rollback_failure_does_not_hide_an_interrupt(self):
        with patch.object(PORTS, "_reserve_port", side_effect=KeyboardInterrupt), patch.object(
            PORTS.NativePortLease,
            "close",
            side_effect=PORTS.NativePortError("injected release failure"),
        ):
            with self.assertRaisesRegex(KeyboardInterrupt, "rollback failed") as failure:
                PORTS.lease_native_ports(0, "a1b2c3d4e5", lock_root=self.locks)
        self.assertIsInstance(failure.exception.__cause__, PORTS.NativePortError)
        self.assertIn("release failure", str(failure.exception))


if __name__ == "__main__":
    unittest.main()
