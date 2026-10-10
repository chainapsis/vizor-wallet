"""Read-only installed compiler inputs, distinct from owned build outputs."""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

import e2e_runtime as runtime
import native_owned_tree as tree


class ToolInputError(runtime.RunnerError):
    """Installed compiler identity or source bounds are unproven."""


def _json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def file_record(path, *, executable=False, limit=512*1024*1024, error_type=ToolInputError):
    """Read installed root/user-owned SDK inputs, never relax output ownership."""
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise error_type("native tool input must be canonical")
    with contextlib.ExitStack() as stack:
        parent = os.open(path.parent, os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        stack.callback(os.close, parent)
        parent_info = os.fstat(parent)
        if parent_info.st_uid not in {0, os.getuid()} or parent_info.st_mode & 0o002:
            raise error_type("native tool input parent is not protected: "+str(path.parent))
        descriptor = os.open(path.name, os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK, dir_fd=parent)
        stack.callback(os.close, descriptor)
        before = os.fstat(descriptor)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid not in {0, os.getuid()}
            or before.st_mode & 0o002 or before.st_nlink < 1 or before.st_size > limit
            or (executable and not before.st_mode & stat.S_IXUSR)):
            raise error_type("native tool input is not a protected bounded file: "+str(path))
        digest, size = hashlib.sha256(), 0
        with os.fdopen(os.dup(descriptor), "rb") as source:
            for chunk in iter(lambda:source.read(1024*1024), b""):
                size += len(chunk)
                if size > limit:
                    raise error_type("native tool input grew beyond its bound")
                digest.update(chunk)
        if (tree.identity(os.fstat(descriptor)) != tree.identity(before)
            or tree.identity(path.lstat()) != tree.identity(before)
            or tree.identity(path.parent.lstat()) != tree.identity(parent_info)):
            raise error_type("native tool input changed during inspection")
        return tree.identity(before), digest.hexdigest()


def tree_digest(root, cancel, *, capture=file_record, ignore_generated=True,
                max_bytes=1024*1024*1024, linked_files=frozenset(), linked_roots=frozenset(),
                error_type=ToolInputError):
    """Dependency source contents, not only lock versions or package-cache paths."""
    ignored = {".git", ".dart_tool", "build", "target", ".regtest-logs", "__pycache__"}
    digest, count, total = hashlib.sha256(), 0, 0
    for directory, children, files in os.walk(root, followlinks=False):
        children[:] = sorted(children)
        if ignore_generated and Path(directory) == root:
            children[:] = [name for name in children if name not in ignored]
        for name in sorted((*children, *files)):
            if cancel.is_set():
                from e2e_runtime import Cancelled
                raise Cancelled()
            path = Path(directory)/name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                target = os.readlink(path)
                resolved = path.resolve(strict=True)
                if Path(target).is_absolute() or (not resolved.is_relative_to(root)
                    and resolved not in linked_files
                    and not any(resolved.is_relative_to(other) for other in linked_roots)):
                    raise error_type("package source link escapes its package: "+str(path)+" -> "+target)
                value = [relative, "link", target]
            elif stat.S_ISDIR(info.st_mode):
                value = [relative, "directory"]
            else:
                value = [relative, "file", capture(path)[1], bool(info.st_mode & stat.S_IXUSR)]
                total += info.st_size
            count += 1
            if count > 100_000 or total > max_bytes:
                raise error_type("package source exceeds its bound: "+str(root))
            digest.update(_json(value)+b"\n")
    return digest.hexdigest()


def apple_linker_inputs(command, cancel):
    if sys.platform != "darwin":
        return None
    def selected(arguments):
        lines = tuple(line.rstrip("\r\n") for line in command(arguments))
        if len(lines) != 1 or not Path(lines[0]).is_absolute():
            raise ToolInputError("Apple linker input must resolve to one absolute path")
        return Path(lines[0]).resolve(strict=True)
    programs = {name:selected(["/usr/bin/xcrun", "--sdk", "macosx", "--find", name])
                for name in ("clang", "ld")}
    programs["cc"] = selected(["/usr/bin/which", "cc"])
    programs["xcrun"] = Path("/usr/bin/xcrun").resolve(strict=True)
    roots = {selected(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"])}
    roots.update(path.parent.parent/"lib" for path in programs.values() if path.name == "clang")
    if any(path.resolve(strict=True) != path or not path.is_dir() for path in roots):
        raise ToolInputError("selected Apple SDK/compiler library must be canonical")
    return {"executables":{name:{"path":str(path), "sha256":file_record(path, executable=True)[1]}
                           for name,path in sorted(programs.items())},
            "source_trees_sha256":{str(path):tree_digest(path, cancel, ignore_generated=False,
                                      max_bytes=4*1024*1024*1024)
                                   for path in sorted(roots)}}


def go_toolchain_inputs(command, go, cancel):
    payload = json.loads("".join(command([str(go), "env", "-json", "GOROOT", "GOTOOLDIR"])))
    if not isinstance(payload, dict) or any(not isinstance(payload.get(name), str)
        or not Path(payload[name]).is_absolute() for name in ("GOROOT", "GOTOOLDIR")):
        raise ToolInputError("selected Go SDK/tool directory must be absolute")
    root, tools = (Path(payload[name]).resolve(strict=True) for name in ("GOROOT", "GOTOOLDIR"))
    roots = {root/"src", root/"pkg", root/"lib", tools}
    roots = {path for path in roots if not any(parent in roots for parent in path.parents)}
    if any(not path.is_dir() for path in roots):
        raise ToolInputError("selected Go SDK/tool directory is missing")
    driver = root/"bin/go"
    return {"root":str(root), "tool_directory":str(tools),
            "selected_driver_sha256":file_record(driver, executable=True)[1],
            "source_trees_sha256":{str(path):tree_digest(path, cancel, ignore_generated=False)
                                   for path in sorted(roots)}}


def _trees_unchanged(inputs, cancel, max_bytes):
    return all(Path(path).is_dir() and Path(path).resolve(strict=True) == Path(path)
        and tree_digest(Path(path), cancel, ignore_generated=False, max_bytes=max_bytes) == digest
        for path,digest in inputs["source_trees_sha256"].items())


def apple_inputs_unchanged(inputs, cancel):
    if inputs is None:
        return True
    return all(file_record(Path(record["path"]), executable=True)[1] == record["sha256"]
               for record in inputs["executables"].values()) and _trees_unchanged(
                   inputs, cancel, 4*1024*1024*1024)


def go_inputs_unchanged(inputs, cancel):
    return (file_record(Path(inputs["root"])/"bin/go", executable=True)[1]
            == inputs["selected_driver_sha256"] and _trees_unchanged(inputs, cancel, 1024*1024*1024))
