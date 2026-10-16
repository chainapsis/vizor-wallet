"""Old publications in the E2E build cache, `.regtest-logs/build-cache`.

Each cache kind, such as `funder-v1`, holds immutable publications named by
the SHA-256 of their build inputs, each with a `<key>.lock` that a run holds
while it reads or publishes the entry. Pruning keeps every kind's newest
publications and never touches one whose lock a run holds.
"""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import re
import secrets
import shutil
import stat

DEFAULT_KEEP = 2
_KIND = re.compile(r"[a-z][a-z0-9-]*-v[0-9]+")
_KEY = re.compile(r"[0-9a-f]{64}")
_PRUNED = re.compile(r"\.pruned-[0-9a-f]{12}-[0-9a-f]{8}")


def _directories(parent, pattern):
    return [path for path in parent.iterdir()
            if pattern.fullmatch(path.name) and stat.S_ISDIR(path.lstat().st_mode)]


def _size(path):
    """Regular-file bytes below `path`, without following links; hard links count once."""
    seen, total = set(), 0
    for directory, _, files in os.walk(path):
        for name in files:
            details = os.lstat(os.path.join(directory, name))
            if stat.S_ISREG(details.st_mode) and (details.st_dev, details.st_ino) not in seen:
                seen.add((details.st_dev, details.st_ino))
                total += details.st_size
    return total


def plan(cache, keep=DEFAULT_KEEP):
    """(kind, name, bytes, action) for each publication; the `keep` newest of each kind stay.

    Publications are immutable, so a directory's mtime is when it was
    published; a cache hit does not refresh it.
    """
    items = []
    for kind in sorted(_directories(cache, _KIND)):
        entries = sorted(_directories(kind, _KEY), key=lambda path: (path.lstat().st_mtime, path.name),
                         reverse=True)
        for index, entry in enumerate(entries):
            items.append((kind.name, entry.name, _size(entry), "keep" if index < keep else "delete"))
        # A prune that stopped between renaming and deleting leaves these.
        items.extend((kind.name, leftover.name, _size(leftover), "delete")
                     for leftover in sorted(_directories(kind, _PRUNED)))
    return items


def _remove(path):
    # Publications are read-only; their directories must be writable to empty them.
    for directory, _, _ in os.walk(path):
        os.chmod(directory, 0o700)
    shutil.rmtree(path)


def _delete(kind, name):
    """Remove one publication unless a run holds its lock; return what happened."""
    if name.startswith(".pruned-"):
        _remove(kind / name)
        return "deleted"
    lock = os.open(kind / (name + ".lock"), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return "skipped: a run is using it"
        # Runs only read key-named entries, so none ever loads a half-removed one.
        pruned = kind / f".pruned-{name[:12]}-{secrets.token_hex(4)}"
        os.rename(kind / name, pruned)
        _remove(pruned)
        return "deleted"
    finally:
        os.close(lock)


def prune(cache, *, keep=DEFAULT_KEEP, apply=False, out=print):
    """List the cache's publications; with `apply`, remove all but each kind's newest `keep`.

    Returns the exit status: 1 when a removal failed.
    """
    cache = Path(cache)
    if not cache.is_dir() or cache.is_symlink():
        out(f"No build cache at {cache}; nothing to prune.")
        return 0
    items = plan(cache, keep)
    out(("Pruning" if apply else "Dry run, nothing changes; --apply prunes") + f" the build cache in {cache}")
    failed = removed = 0
    for kind, name, size, action in items:
        result = action
        if action == "delete" and apply:
            try:
                result = _delete(cache / kind, name)
            except OSError as error:
                result = f"failed: {error}"
            failed += result.startswith("failed")
            removed += size if result == "deleted" else 0
        out(f"  {result:<8} {kind}/{name[:12]}  {size / 2**20:.0f} MiB")
    deletable = sum(size for _, _, size, action in items if action == "delete")
    out(f"Removed {removed / 2**20:.0f} MiB" if apply else f"{deletable / 2**20:.0f} MiB would be removed")
    return 1 if failed else 0
