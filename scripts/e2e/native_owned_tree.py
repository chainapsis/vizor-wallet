"""Anchored owned-tree inspection/removal; no independent cleanup authority.

Callers prove their resource writers/state and original attachment. Workspace
links may be unlinked, never traversed; native support rejects links by default.
Only the explicit build-output mode admits hard-linked or group-writable files.
"""
from __future__ import annotations

import contextlib
import dataclasses
import os
from pathlib import Path
import re
import stat


# Producer logs and these markers/proofs outlive their build intermediates.
BUILD_EVIDENCE = frozenset({"workspace-owner.json", "case-manifest.json", "build-proof.json"})
# A voting case regenerates its PIR data and vote chain home from its fixture;
# the logs, configs, ready file and tally beside them stay as evidence.
VOTING_DATA = ("pir-data", "vote-home")
_PRODUCER_RE = re.compile(r"vizor_[0-9a-f]{10}_w[0-9]+_[0-9]+\Z")


class OwnedTreeError(RuntimeError):
    """Original tree ownership or attachment is unproven."""


@dataclasses.dataclass(frozen=True)
class Entry:
    name: str
    identity: tuple[int, ...]
    children: tuple[Entry, ...] | None


def identity(details: os.stat_result, *, build_output=False) -> tuple[int, ...]:
    basic = (details.st_dev, details.st_ino, details.st_uid, details.st_mode)
    if stat.S_ISDIR(details.st_mode):
        return basic
    # Unlinking one hard-linked build output changes only its siblings' link
    # count, so build-output files are (dev, ino, uid, mode, size, mtime_ns).
    return basic + (() if build_output else (details.st_nlink,)) + (details.st_size, details.st_mtime_ns)


def check(details: os.stat_result, *, directory: bool, private=False, allow_links=False, build_output=False):
    link = not directory and allow_links and stat.S_ISLNK(details.st_mode)
    valid_type = stat.S_ISDIR(details.st_mode) if directory else stat.S_ISREG(details.st_mode) or link
    # Below a private build-output root no other user can reach an entry, so its
    # write bits grant nothing: Cargo hard-links its outputs, SDK files can be
    # group-writable and Xcode package checkouts create 0777 directories. Such
    # entries are unlinked or descended as names, never written through.
    output = build_output and not link
    if (not valid_type or details.st_uid != os.getuid()
        or (not link and not output and details.st_mode & (0o077 if private else 0o022))
        or (not directory and not output and details.st_nlink != 1)):
        raise OwnedTreeError("tree entry must have its original owned regular identity")


def open_directory(stack: contextlib.ExitStack, path, *, dir_fd=None, private=False, build_output=False):
    """Open an owned directory; one opened below dir_fd must be on dir_fd's filesystem.

    O_NOFOLLOW stops links, not mount points: a volume mounted inside a tree
    shows its own root, so scans and removals would otherwise walk into it.
    """
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dir_fd)
    stack.callback(os.close, descriptor)
    details = os.fstat(descriptor)
    check(details, directory=True, private=private, build_output=build_output)
    if dir_fd is not None and details.st_dev != os.fstat(dir_fd).st_dev:
        raise OwnedTreeError("tree directory crosses a filesystem boundary")
    return descriptor


def scan(directory_fd: int, depth=0, *, allow_links=False, marker="", build_output=False) -> tuple[Entry, ...]:
    if depth > 64:
        raise OwnedTreeError("tree depth exceeds cleanup bound")
    if build_output and depth == 0:  # write bits below are tolerated only under a private root
        check(os.fstat(directory_fd), directory=True, private=True)
    entries = []
    # Keep the caller's original marker until all other entries are removed.
    for name in sorted(os.listdir(directory_fd), key=lambda item: (item == marker, item)):
        details = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        directory = stat.S_ISDIR(details.st_mode)
        check(details, directory=directory, allow_links=allow_links, build_output=build_output)
        children = None
        if directory:
            with contextlib.ExitStack() as stack:
                child_fd = open_directory(stack, name, dir_fd=directory_fd, build_output=build_output)
                if identity(os.fstat(child_fd)) != identity(details):
                    raise OwnedTreeError("tree child changed during inspection")
                children = scan(child_fd, depth + 1, allow_links=allow_links, marker=marker,
                                build_output=build_output)
        entries.append(Entry(name, identity(details, build_output=build_output), children))
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


def _keeps(entry: Entry, keep) -> bool:
    if entry.children is None:
        return stat.S_ISREG(entry.identity[3]) and keep(entry.name)
    return any(_keeps(child, keep) for child in entry.children)


def remove_output(directory_fd: int, entries: tuple[Entry, ...], verify_attachment, keep=None,
                  removed=None, prefix=""):
    """Remove scan(build_output=True) entries, except files selected by keep(name).

    Kept regular files keep their parent directories. Each removed top-level
    path and entry is appended to removed as it goes, so errors stay accounted.
    """
    if set(os.listdir(directory_fd)) != {entry.name for entry in entries}:
        raise OwnedTreeError("tree entries changed after inspection")
    for entry in entries:
        kept = keep is not None and _keeps(entry, keep)
        if kept and entry.children is None:
            continue
        verify_attachment()
        current = os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)
        if identity(current, build_output=True) != entry.identity:
            raise OwnedTreeError("tree child changed before removal")
        if entry.children is not None:
            with contextlib.ExitStack() as stack:
                child_fd = open_directory(stack, entry.name, dir_fd=directory_fd, build_output=True)
                if identity(os.fstat(child_fd)) != entry.identity:
                    raise OwnedTreeError("tree child changed during removal")
                def verify_child_attachment():
                    verify_attachment()
                    attached = os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)
                    if identity(attached) != entry.identity:
                        raise OwnedTreeError("tree child attachment changed during removal")
                remove_output(child_fd, entry.children, verify_child_attachment, keep if kept else None,
                              removed if kept else None, prefix + entry.name + "/")
            if kept:
                continue
            verify_attachment()
            if identity(os.stat(entry.name, dir_fd=directory_fd, follow_symlinks=False)) != entry.identity:
                raise OwnedTreeError("tree directory changed before removal")
            os.rmdir(entry.name, dir_fd=directory_fd)
        else:
            os.unlink(entry.name, dir_fd=directory_fd)
        if removed is not None:
            removed.append((prefix + entry.name, entry))


def output_bytes(entries) -> int:
    """Regular-file bytes below build-output entries; hard links count once."""
    seen, total, pending = set(), 0, list(entries)
    while pending:
        entry = pending.pop()
        if entry.children is not None:
            pending.extend(entry.children)
        elif stat.S_ISREG(entry.identity[3]) and entry.identity[:2] not in seen:
            seen.add(entry.identity[:2])
            total += entry.identity[4]
    return total


def prune_voting_data(case_root: Path) -> dict:
    """Remove a finished case's regenerated voting data, keeping its evidence.

    The caller proves the case's processes have stopped. Errors are recorded,
    not raised.
    """
    record, removed = {"removed": [], "bytes": 0, "errors": []}, []
    try:
        with contextlib.ExitStack() as stack:
            case_fd = open_directory(stack, case_root, private=True)
            try:
                voting_fd = open_directory(stack, "voting", dir_fd=case_fd)
            except FileNotFoundError:
                return record
            voting_id = identity(os.fstat(voting_fd))
            for name in VOTING_DATA:
                try:
                    with contextlib.ExitStack() as data_stack:
                        try:
                            data_fd = open_directory(data_stack, name, dir_fd=voting_fd)
                        except FileNotFoundError:
                            continue
                        data_id = identity(os.fstat(data_fd))

                        def attached(name=name, data_id=data_id):
                            if (identity(os.stat("voting", dir_fd=case_fd, follow_symlinks=False)) != voting_id
                                or identity(os.stat(name, dir_fd=voting_fd, follow_symlinks=False)) != data_id):
                                raise OwnedTreeError("voting data attachment changed")

                        entries = scan(data_fd)
                        remove_entries(data_fd, entries, attached)
                    attached()
                    os.rmdir(name, dir_fd=voting_fd)
                    record["removed"].append("voting/" + name)
                    removed.extend(entries)
                except (OSError, OwnedTreeError) as error:
                    record["errors"].append(f"voting/{name}: {error}")
    except (OSError, OwnedTreeError) as error:
        record["errors"].append(str(error))
    record["bytes"] = _owned_bytes(removed)
    return record


def _owned_bytes(entries) -> int:
    """Regular-file bytes below default-mode entries, which admit no hard links."""
    total, pending = 0, list(entries)
    while pending:
        entry = pending.pop()
        if entry.children is not None:
            pending.extend(entry.children)
        elif stat.S_ISREG(entry.identity[3]):
            total += entry.identity[5]
    return total


def size_text(count) -> str:
    for unit in ("B", "KiB", "MiB"):
        if count < 1024:
            return f"{count:.0f} {unit}" if unit == "B" else f"{count:.1f} {unit}"
        count /= 1024
    return f"{count:.1f} GiB"


def _kept_build_file(name):
    return name in BUILD_EVIDENCE or name.endswith(".log")


def prune_build_outputs(builds: Path, *, expected=None, cancel=None) -> dict:
    """Remove producer intermediates below builds/e2e, keeping logs and markers.

    The caller proves no producer or case can still use them. Removal stays
    anchored to the original builds directory. Errors are recorded, not raised.
    """
    record, removed = {"removed": [], "bytes": 0, "errors": []}, []
    try:
        with contextlib.ExitStack() as stack:
            run_fd = open_directory(stack, builds.parent, private=True)
            builds_fd = open_directory(stack, builds.name, dir_fd=run_fd, private=True)
            builds_id = identity(os.fstat(builds_fd))
            if expected is not None and builds_id != expected:
                raise OwnedTreeError("run builds directory is not the original one")
            try:
                cases_fd = open_directory(stack, "e2e", dir_fd=builds_fd, private=True)
            except FileNotFoundError:
                return record
            cases_id = identity(os.fstat(cases_fd))

            def attached():
                if cancel is not None and cancel.is_set():
                    raise OwnedTreeError("build output removal was cancelled")
                for parent, name, original in ((run_fd, builds.name, builds_id), (builds_fd, "e2e", cases_id)):
                    if identity(os.stat(name, dir_fd=parent, follow_symlinks=False)) != original:
                        raise OwnedTreeError("build output attachment changed")
            for name in sorted(os.listdir(cases_fd)):
                done = []
                try:
                    attached()
                    if not _PRODUCER_RE.fullmatch(name):
                        raise OwnedTreeError("not a producer case workspace")
                    with contextlib.ExitStack() as case_stack:
                        case_fd = open_directory(case_stack, name, dir_fd=cases_fd, private=True)
                        case_id = identity(os.fstat(case_fd))
                        def case_attached():
                            attached()
                            if identity(os.stat(name, dir_fd=cases_fd, follow_symlinks=False)) != case_id:
                                raise OwnedTreeError("producer workspace attachment changed")
                        entries = scan(case_fd, allow_links=True, build_output=True)
                        remove_output(case_fd, entries, case_attached, _kept_build_file, done, "e2e/" + name + "/")
                except (OSError, OwnedTreeError) as error:
                    record["errors"].append(f"{name}: {error}")
                    if cancel is not None and cancel.is_set():
                        break
                finally:
                    record["removed"] += [path for path, _ in done]
                    removed += [entry for _, entry in done]
    except (OSError, OwnedTreeError) as error:
        record["errors"].append(str(error))
    record["bytes"] = output_bytes(removed)
    return record
