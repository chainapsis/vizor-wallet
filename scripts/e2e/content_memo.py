"""Run-scoped reuse of whole-file SHA-256 digests; never a substitute for file checks.

Callers look up a digest only after their pre-read checks and still run their
post-read identity checks; a hit skips the read alone. Keys include ctime,
which utime cannot restore. Nothing outlives the scope.
"""
from __future__ import annotations

import contextlib
import threading


_RACY_NS = 2_000_000_000  # Never store a file changed less than 2 s before its read began.
_MAX_ENTRIES = 1_000_000
_lock = threading.Lock()
_table = None  # Disabled unless run_scope() is active.


def _key(details):
    return (details.st_dev, details.st_ino, details.st_size, details.st_mtime_ns, details.st_ctime_ns, "sha256")


def lookup(details):
    table = _table
    return None if table is None else table.get(_key(details))


def store(before, after, digest, started_ns):
    table = _table
    if (table is None or _key(before) != _key(after)
        or started_ns - max(before.st_mtime_ns, before.st_ctime_ns) < _RACY_NS):
        return
    with _lock:
        if len(table) >= _MAX_ENTRIES:
            table.clear()
        table[_key(before)] = digest


@contextlib.contextmanager
def run_scope():
    global _table
    with _lock:
        if _table is not None:
            raise RuntimeError("content memo scope is already active")
        _table = {}
    try:
        yield
    finally:
        _table = None
