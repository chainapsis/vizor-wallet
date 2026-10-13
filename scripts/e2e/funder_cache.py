"""Immutable signer/test publications; never wallet state or external receipts."""
from __future__ import annotations

import contextlib
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time
import uuid

import e2e_runtime as runtime
import native_owned_tree as tree


class FunderCacheError(runtime.RunnerError):
    """An original cache publication, attachment or input is unproven."""


def _json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True, allow_nan=False).encode("ascii")


def _read(path, limit):
    with contextlib.ExitStack() as stack:
        parent = tree.open_directory(stack, path.parent, private=True)
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
        stack.callback(os.close, fd)
        before = os.fstat(fd)
        tree.check(before, directory=False, private=True)
        if before.st_size > limit or before.st_mode & 0o222:
            raise FunderCacheError("cache file is oversized or writable")
        with os.fdopen(os.dup(fd), "rb") as stream:
            payload = stream.read(limit + 1)
        if len(payload) > limit or tree.identity(os.fstat(fd)) != tree.identity(before):
            raise FunderCacheError("cache bytes changed during inspection")
        return payload


def _rename_exclusive(source, destination):
    libc = ctypes.CDLL(None, use_errno=True)
    if sys.platform == "darwin":
        function = libc.renamex_np
        function.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        code = function(os.fsencode(source), os.fsencode(destination), 4)
    elif sys.platform == "linux":
        function = libc.renameat2
        function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int,
                             ctypes.c_char_p, ctypes.c_uint]
        code = function(-100, os.fsencode(source), -100, os.fsencode(destination), 1)
    else:
        raise FunderCacheError("exclusive cache publication is unsupported on this host")
    if code:
        number = ctypes.get_errno()
        raise OSError(number, os.strerror(number), destination)


class FunderCacheLease:
    """One key's lock, immutable lookup and original-producer-only publication."""
    def __init__(self, root, inputs, names, *, timeout, cancel_event):
        self.root = Path(root)
        self.inputs = json.loads(_json(inputs))
        self.key = hashlib.sha256(_json(self.inputs)).hexdigest()
        self.names = tuple(sorted(names))
        if (not self.root.is_absolute() or self.root.parent.resolve(strict=True) != self.root.parent
            or not self.names or len(set(self.names)) != len(self.names)
            or any(not re.fullmatch(r"[a-z][a-z0-9_]+", name) for name in self.names)):
            raise FunderCacheError("cache root and executable inventory must be explicit")
        runtime._positive_timeout(timeout)
        self.deadline = time.monotonic() + timeout
        self.cancel = cancel_event
        self.fd = None
        self.root_id = None
        self.lock_id = None
        self.entry_id = None
        self.entry = self.root / self.key

    def _check(self):
        if self.cancel.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= self.deadline:
            raise FunderCacheError("cache lease deadline expired", 124)
        if self.root.resolve(strict=True) != self.root:
            raise FunderCacheError("original cache root is no longer canonical")
        with contextlib.ExitStack() as stack:
            fd = tree.open_directory(stack, self.root, private=True)
            if tree.identity(os.fstat(fd)) != self.root_id:
                raise FunderCacheError("original cache root changed")
        if (self.fd is None or tree.identity(os.fstat(self.fd)) != self.lock_id
            or tree.identity((self.root / (self.key + ".lock")).lstat()) != self.lock_id):
            raise FunderCacheError("original cache lock attachment changed")

    def __enter__(self):
        self.root.mkdir(mode=0o700, exist_ok=True)
        if self.root.resolve(strict=True) != self.root:
            raise FunderCacheError("cache root is not canonical")
        with contextlib.ExitStack() as stack:
            root = tree.open_directory(stack, self.root, private=True)
            self.root_id = tree.identity(os.fstat(root))
            self.fd = os.open(self.key + ".lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                              0o600, dir_fd=root)
        try:
            tree.check(os.fstat(self.fd), directory=False, private=True)
            self.lock_id = tree.identity(os.fstat(self.fd))
            while True:
                self._check()
                try:
                    fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    return self
                except BlockingIOError:
                    self.cancel.wait(min(0.05, max(0, self.deadline-time.monotonic())))
        except BaseException:
            os.close(self.fd)
            self.fd = None
            raise

    def __exit__(self, *_):
        if self.fd is not None:
            os.close(self.fd)
            self.fd = None

    def load(self):
        self._check()
        if not self.entry.exists() and not self.entry.is_symlink():
            return None
        with contextlib.ExitStack() as stack:
            fd = tree.open_directory(stack, self.entry, private=True)
            before = tree.identity(os.fstat(fd))
            if self.entry_id is not None and before != self.entry_id:
                raise FunderCacheError("original cache publication changed")
            self.entry_id = before
            if os.fstat(fd).st_mode & 0o222:
                raise FunderCacheError("published cache directory must be immutable")
            if set(os.listdir(fd)) != {"manifest.json", *self.names}:
                raise FunderCacheError("cache publication inventory differs")
        raw = json.loads(_read(self.entry / "manifest.json", 4*1024*1024))
        if (not isinstance(raw, dict) or set(raw) != {"schema", "inputs", "files"}
            or type(raw["schema"]) is not int or raw["schema"] != 1
            or raw["inputs"] != self.inputs or not isinstance(raw["files"], dict)
            or set(raw["files"]) != set(self.names)):
            raise FunderCacheError("cache publication does not bind the current build inputs")
        from funder_build import _file_record, _MAX_BINARY_BYTES
        paths = {}
        for name in self.names:
            self._check()
            path = self.entry / name
            if stat.S_IMODE(path.lstat().st_mode) != 0o500:
                raise FunderCacheError("cached executable mode changed")
            record = _file_record(path, executable=True, limit=_MAX_BINARY_BYTES)
            if raw["files"][name] != {"sha256": record[1], "size": path.stat().st_size}:
                raise FunderCacheError("cached executable bytes changed")
            paths[name] = path
        with contextlib.ExitStack() as stack:
            fd = tree.open_directory(stack, self.entry, private=True)
            if tree.identity(os.fstat(fd)) != before:
                raise FunderCacheError("cache publication attachment changed")
        self._check()
        return paths

    def publish(self, artifact):
        from funder_build import ProducedRegtestFunder, _copy_cargo_executable
        if not isinstance(artifact, ProducedRegtestFunder):
            raise FunderCacheError("only the original joined producer may publish")
        artifact.verify_unchanged()
        if artifact.identity().get("cache_inputs") != self.inputs:
            raise FunderCacheError("original producer did not bind these cache inputs")
        self._check()
        if self.entry.exists() or self.entry.is_symlink():
            raise FunderCacheError("cache publication already exists; never overwrite")
        staging = self.root / (".pending-" + uuid.uuid4().hex)
        staging.mkdir(mode=0o700)
        originals = {artifact.binary.name: artifact.binary,
                     **{name: pair[0] for name, pair in artifact._test_binaries.items()}}
        if artifact._wallet_addresses_binary is not None:
            originals["regtest_wallet_addresses"] = artifact.wallet_addresses_binary()
        if set(originals) != set(self.names):
            raise FunderCacheError("original producer did not publish every selected executable")
        files = {}
        for name, path in originals.items():
            self._check()
            record = _copy_cargo_executable(path, staging / name)
            files[name] = {"sha256": record[1], "size": (staging / name).stat().st_size}
        artifact.verify_unchanged()
        manifest = _json({"schema": 1, "inputs": self.inputs, "files": files})
        fd = os.open(staging / "manifest.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
        with os.fdopen(fd, "wb") as output:
            output.write(manifest)
            output.flush()
            os.fsync(output.fileno())
        staging.chmod(0o500)
        self._check()
        _rename_exclusive(staging, self.entry)
        self.load()
