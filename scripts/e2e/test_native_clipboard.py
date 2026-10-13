"""Real cooperative locks; no app or user clipboard writes."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e2e_runtime as runtime
from native_clipboard import ClipboardLeaseError, NativeClipboardLease


class ClipboardTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-clipboard-model-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve() / "locks"
        self.cancel = threading.Event()
        self.lease = NativeClipboardLease(lock_root=self.root)
        self.addCleanup(lambda: self.lease.release() if self.lease.held else None)

    def acquire(self, lease=None, timeout=1):
        (lease or self.lease).acquire(deadline=time.monotonic()+timeout,
            cancel_event=self.cancel)

    def test_siblings_cannot_release_or_reenter_an_original_lease(self):
        self.acquire()
        with self.assertRaises(ClipboardLeaseError):
            self.acquire()
        sibling = NativeClipboardLease(lock_root=self.root)
        with self.assertRaises(ClipboardLeaseError):
            sibling.release()
        with self.assertRaisesRegex(ClipboardLeaseError, "deadline"):
            self.acquire(sibling, timeout=0.03)
        self.assertTrue(self.lease.held)
        self.assertFalse(sibling.held)
        self.lease.release()
        self.acquire(sibling)
        sibling.release()

    def test_different_runner_processes_lock_the_same_inode(self):
        self.acquire()
        code = "import fcntl,os,sys; f=os.open(sys.argv[1],os.O_RDWR); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)"
        result = subprocess.run([sys.executable,"-c",code,str(self.root/"host.lock")],
            capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"BlockingIOError", result.stderr)
        self.lease.release()
        result = subprocess.run([sys.executable,"-c",code,str(self.root/"host.lock")],
            capture_output=True, timeout=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root/"host.lock").is_file())

    def test_cancellation_does_not_release_a_sibling_or_leak_a_descriptor(self):
        self.acquire()
        sibling = NativeClipboardLease(lock_root=self.root)
        self.cancel.set()
        with self.assertRaises(runtime.Cancelled):
            self.acquire(sibling)
        self.assertTrue(self.lease.held)
        self.assertFalse(sibling.held)

    def test_wrong_thread_cannot_release(self):
        self.acquire()
        errors = []
        def release():
            try:
                self.lease.release()
            except ClipboardLeaseError as error:
                errors.append(error)
        thread = threading.Thread(target=release)
        thread.start()
        thread.join(timeout=1)
        self.assertEqual(len(errors), 1)
        self.assertTrue(self.lease.held)

    def test_links_and_shared_permissions_are_rejected(self):
        self.root.mkdir(mode=0o700)
        target = self.root.parent/"other"
        target.write_text("untouched")
        (self.root/"host.lock").symlink_to(target)
        with self.assertRaises(OSError):
            self.acquire()
        self.assertEqual(target.read_text(), "untouched")
        (self.root/"host.lock").unlink()
        (self.root/"host.lock").write_text("shared")
        (self.root/"host.lock").chmod(0o644)
        with self.assertRaises(ClipboardLeaseError):
            self.acquire()


if __name__ == "__main__":
    unittest.main()
