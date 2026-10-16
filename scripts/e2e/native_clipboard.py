"""A short cross-run clipboard lease owned by an original case controller.

The lock file is cooperative, never a cleanup receipt. Do not remove it: other
runner processes must continue locking the same inode. A lost HTTP client does
not release a lease while its app can still write the host clipboard.
"""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import stat
import tempfile
import threading
import time

import e2e_runtime as runtime
from native_ports import _safe_lock_directory


class ClipboardLeaseError(runtime.RunnerError):
    pass


class NativeClipboardLease:
    def __init__(self, *, lock_root=None):
        self._owner = threading.get_ident()
        self._descriptor = None
        self._root = lock_root

    @property
    def held(self):
        return self._descriptor is not None

    def _require_owner(self):
        if threading.get_ident() != self._owner:
            raise ClipboardLeaseError("clipboard requires its original controller thread")

    def acquire(self, *, deadline, cancel_event):
        self._require_owner()
        if self.held:
            raise ClipboardLeaseError("clipboard lease is not reentrant")
        root = self._root
        if root is None:
            parent = _safe_lock_directory(Path(tempfile.gettempdir()).resolve()
                / f"vizor-wallet-native-e2e-{os.getuid()}", private=False)
            root = parent / "clipboard"
        root = _safe_lock_directory(Path(root))
        directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        descriptor = None
        try:
            if os.fstat(directory) != root.stat():
                raise ClipboardLeaseError("clipboard lock parent changed")
            descriptor = os.open("host.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                0o600, dir_fd=directory)
            details = os.fstat(descriptor)
            if (not stat.S_ISREG(details.st_mode) or details.st_uid != os.getuid()
                or stat.S_IMODE(details.st_mode) & 0o077 or details.st_nlink != 1):
                raise ClipboardLeaseError("clipboard lock file is unsafe")
            while True:
                if cancel_event.is_set():
                    raise runtime.Cancelled()
                if time.monotonic() >= deadline:
                    raise ClipboardLeaseError("clipboard acquisition deadline expired", 124)
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    cancel_event.wait(min(0.02, max(0, deadline - time.monotonic())))
            current = os.stat("host.lock", dir_fd=directory, follow_symlinks=False)
            if (current.st_dev, current.st_ino) != (details.st_dev, details.st_ino):
                raise ClipboardLeaseError("clipboard lock identity changed")
            self._descriptor, descriptor = descriptor, None
        finally:
            if descriptor is not None:
                os.close(descriptor)
            os.close(directory)

    def release(self):
        self._require_owner()
        if not self.held:
            raise ClipboardLeaseError("this controller does not hold the clipboard")
        descriptor = self._descriptor
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)
        self._descriptor = None
