"""Read-only installed compiler inputs, distinct from owned build outputs."""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import sys
import tomllib

import e2e_runtime as runtime
import native_owned_tree as tree


class ToolInputError(runtime.RunnerError):
    """Installed compiler identity or source bounds are unproven."""


def configured_tool_inputs(environment, configurations, cwd):
    """Bind referenced programs, not just configuration text; never execute them.

    Conservatively include all configured targets/precedence layers. A missing
    unselected target tool is recorded as missing; if selected, only the original
    successful producer could ever authorize publishing its artifact.
    """
    tools, configs, seen, requests = {}, {}, set(), []
    searches = {(environment.get("PATH", os.defpath), cwd)}
    def program(value, base, *, arguments=False):
        if len(requests) >= 4096:
            raise ToolInputError("configured build tools exceed their bound")
        requests.append((value, base, arguments))

    def record_program(value, base, arguments):
        if value == "":
            return
        if isinstance(value, list) and value and all(isinstance(item, str) for item in value):
            names = value[:1]
        elif isinstance(value, str):
            names = shlex.split(value)[:1] if arguments else [value]
            if arguments:
                words = shlex.split(value)
                if len(words) > 1 and Path(words[0]).name in {"ccache", "sccache", "distcc", "icecc"}:
                    names.append(words[1])
        else:
            raise ToolInputError("configured build program must be a string or argument list")
        for name in names:
            if not name:
                raise ToolInputError("configured build program is empty")
            if "/" in name:
                path = Path(name)
                paths = {path if path.is_absolute() else base/path}
            else:
                paths = set()
                for value, origin in searches:
                    search = os.pathsep.join(str(Path(entry) if Path(entry).is_absolute() else origin/entry)
                        for entry in value.split(os.pathsep))
                    found = shutil.which(name, path=search)
                    if found is not None:
                        paths.add(Path(found))
                if not paths:
                    tools["unresolved:"+name] = None
                    continue
            for path in paths:
                if not path.exists() and not path.is_symlink():
                    tools[str(path)] = None
                    continue
                path = path.resolve(strict=True)
                tools[str(path)] = file_record(path, executable=True)[1]

    def flags(value, base, *, encoded=False):
        words = (value.split("\x1f") if encoded else shlex.split(value)) if isinstance(value, str) else value
        if not isinstance(words, list) or not all(isinstance(word, str) for word in words):
            raise ToolInputError("configured Rust flags must be strings")
        for index, word in enumerate(words):
            setting = (words[index+1] if word == "-C" and index+1 < len(words) else
                       word[2:] if word.startswith("-C") else "")
            if setting.startswith("linker="):
                program(setting.removeprefix("linker="), base)

    def env_tools(values, base):
        direct = {"RUSTC", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTDOC",
            "CARGO_BUILD_RUSTC", "CARGO_BUILD_RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WORKSPACE_WRAPPER"}
        for name, value in values.items():
            if name in direct or re.fullmatch(r"CARGO_TARGET_[A-Z0-9_]+_LINKER", name):
                program(value, base)
            elif re.fullmatch(r"(?:(?:HOST|TARGET)_)?(?:CC|CXX|AR|LD|AS|RANLIB)(?:_[A-Za-z0-9_-]+)?", name):
                program(value, base, arguments=True)
            elif (name in {"RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_BUILD_RUSTFLAGS"}
                  or re.fullmatch(r"CARGO_TARGET_[A-Z0-9_]+_RUSTFLAGS", name)):
                flags(value, base, encoded=name == "CARGO_ENCODED_RUSTFLAGS")
    env_tools(environment, cwd)

    def configuration(path, depth=0):
        if depth > 16 or len(seen) >= 128:
            raise ToolInputError("Cargo configuration includes exceed their bound")
        if not path.exists() and not path.is_symlink():
            return
        path = path.resolve(strict=True)
        if path in seen:
            return
        seen.add(path)
        before = file_record(path, limit=1024*1024)
        with path.open("rb") as source:
            payload = tomllib.load(source)
        if file_record(path, limit=1024*1024) != before:
            raise ToolInputError("Cargo configuration changed during inspection")
        configs[str(path)] = before[1]
        includes = payload.get("include", [])
        if not isinstance(includes, list):
            raise ToolInputError("Cargo configuration includes must be a list")
        for item in includes:
            name = item if isinstance(item, str) else item.get("path") if isinstance(item, dict) else None
            if not isinstance(name, str):
                raise ToolInputError("Cargo configuration include must identify a path")
            configuration(path.parent/name, depth+1)
        base = path.parent.parent
        build = payload.get("build", {})
        for name in ("rustc", "rustc-wrapper", "rustc-workspace-wrapper", "rustdoc"):
            if name in build:
                program(build[name], base)
        if "rustflags" in build:
            flags(build["rustflags"], base)
        for target in payload.get("target", {}).values():
            if "linker" in target:
                program(target["linker"], base)
            if "rustflags" in target:
                flags(target["rustflags"], base)
        for name, item in payload.get("env", {}).items():
            value = item if isinstance(item, str) else item.get("value") if isinstance(item, dict) else None
            origin = base if isinstance(item, dict) and item.get("relative") else cwd
            if name == "PATH":
                if not isinstance(value, str) or len(searches) >= 128:
                    raise ToolInputError("configured Cargo PATH is invalid or exceeds its bound")
                searches.add((str(origin/value) if origin == base else value, cwd))
                for tool in ("rustc", "cargo", "cc", "clang", "ld", "ar"):
                    program(tool, cwd)
            env_tools({name:value}, origin)
    for path in sorted(configurations):
        configuration(path)
    for value, base, arguments in requests:
        record_program(value, base, arguments)
    return {"executables_sha256":tools, "configuration_sha256":configs}


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


def rust_toolchain_inputs(command, rustc, cancel):
    lines = tuple(line.rstrip("\r\n") for line in command([str(rustc), "--print", "sysroot"]))
    if len(lines) != 1 or not Path(lines[0]).is_absolute():
        raise ToolInputError("selected Rust sysroot must be absolute")
    root = Path(lines[0]).resolve(strict=True)
    libraries = root/"lib"
    if not libraries.is_dir() or libraries.resolve(strict=True) != libraries:
        raise ToolInputError("selected Rust sysroot libraries must be canonical")
    # Conservatively bind every installed target, including host compiler
    # runtime libraries; never reuse a key after a target-library repair.
    return {"root":str(root), "source_trees_sha256":{
        str(libraries):tree_digest(libraries, cancel, ignore_generated=False,
                                  max_bytes=4*1024*1024*1024)}}


def rust_inputs_unchanged(inputs, cancel):
    return _trees_unchanged(inputs, cancel, 4*1024*1024*1024)


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
