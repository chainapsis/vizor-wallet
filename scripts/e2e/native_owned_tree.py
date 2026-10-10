"""Anchored owned-tree inspection/removal; no independent cleanup authority.

Callers prove their resource writers/state and original attachment. Workspace
links may be unlinked, never traversed; native support rejects links by default.
"""
from __future__ import annotations

import contextlib
import dataclasses
import os
import stat


class OwnedTreeError(RuntimeError):
    """Original tree ownership or attachment is unproven."""


@dataclasses.dataclass(frozen=True)
class Entry:
    name: str
    identity: tuple[int, ...]
    children: tuple[Entry, ...] | None


def identity(details: os.stat_result) -> tuple[int, ...]:
    basic = (details.st_dev, details.st_ino, details.st_uid, details.st_mode)
    return basic if stat.S_ISDIR(details.st_mode) else basic + (
        details.st_nlink, details.st_size, details.st_mtime_ns,
    )


def check(details: os.stat_result, *, directory: bool, private=False, allow_links=False):
    link = not directory and allow_links and stat.S_ISLNK(details.st_mode)
    valid_type = stat.S_ISDIR(details.st_mode) if directory else stat.S_ISREG(details.st_mode) or link
    if (not valid_type or details.st_uid != os.getuid()
        or (not link and details.st_mode & (0o077 if private else 0o022))
        or (not directory and details.st_nlink != 1)):
        raise OwnedTreeError("tree entry must have its original owned regular identity")


def open_directory(stack: contextlib.ExitStack, path, *, dir_fd=None, private=False):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dir_fd)
    stack.callback(os.close, descriptor)
    check(os.fstat(descriptor), directory=True, private=private)
    return descriptor


def scan(directory_fd: int, depth=0, *, allow_links=False, marker="") -> tuple[Entry, ...]:
    if depth > 64:
        raise OwnedTreeError("tree depth exceeds cleanup bound")
    entries = []
    # Keep the caller's original marker until all other entries are removed.
    for name in sorted(os.listdir(directory_fd), key=lambda item: (item == marker, item)):
        details = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        directory = stat.S_ISDIR(details.st_mode)
        check(details, directory=directory, allow_links=allow_links)
        children = None
        if directory:
            with contextlib.ExitStack() as stack:
                child_fd = open_directory(stack, name, dir_fd=directory_fd)
                if identity(os.fstat(child_fd)) != identity(details):
                    raise OwnedTreeError("tree child changed during inspection")
                children = scan(child_fd, depth + 1, allow_links=allow_links, marker=marker)
        entries.append(Entry(name, identity(details), children))
    return tuple(entries)


def remove_entries(directory_fd: int, entries: tuple[Entry, ...], verify_attachment):
    if set(os.listdir(directory_fd)) != {entry.name for entry in entries}:
        raise OwnedTreeError("tree entries changed after inspection")
    for entry in entries:
        verify_attachment()
        current = os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)
        if identity(current) != entry.identity:
            raise OwnedTreeError("tree child changed before removal")
        if entry.children is not None:
            with contextlib.ExitStack() as stack:
                child_fd = open_directory(stack, entry.name, dir_fd=directory_fd)
                if identity(os.fstat(child_fd)) != entry.identity:
                    raise OwnedTreeError("tree child changed during removal")
                def verify_child_attachment():
                    verify_attachment()
                    attached = os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)
                    if identity(attached) != entry.identity:
                        raise OwnedTreeError("tree child attachment changed during removal")
                remove_entries(child_fd, entry.children, verify_child_attachment)
            verify_attachment()
            if identity(os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)) != entry.identity:
                raise OwnedTreeError("tree directory changed before removal")
            os.rmdir(entry.name, dir_fd=directory_fd)
        else:
            # Owned workspace symlinks are entries only, never target authority.
            os.unlink(entry.name, dir_fd=directory_fd)
