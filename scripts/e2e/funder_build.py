"""Produce a reusable offline signer from one exact, frozen Git Rust subtree.

This is a cooperative original producer, not cache lookup, native app publication,
network containment, external artifact adoption or a wallet/scenario PASS.
"""
from __future__ import annotations

import contextlib
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import tarfile
import threading

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree


_TOKEN = object()
_COMMIT = re.compile(r"[0-9a-f]{40}\Z")
_MAX_SOURCE_BYTES = 128 * 1024 * 1024
_MAX_SOURCE_FILES = 10_000
_MAX_BINARY_BYTES = 512 * 1024 * 1024
_REQUIRED = {"rust/Cargo.toml", "rust/Cargo.lock", "rust/examples/regtest_direct_funder.rs"}


class FunderBuildError(runtime.RunnerError):
    """Source, build completion or original artifact attachment is unproven."""


def _relative(name):
    if not isinstance(name, str):
        raise FunderBuildError("source member name is not a string")
    path = PurePosixPath(name)
    if (not name or not path.parts or path.is_absolute()
        or path.as_posix() != name or any(part in {".", ".."} for part in path.parts)
        or path.parts[0] != "rust" or "\x00" in name):
        raise FunderBuildError("source member escaped the Rust subtree")
    return path


def _file_record(path, *, executable=False, limit=_MAX_SOURCE_BYTES):
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise FunderBuildError("artifact path is not canonical")
    with contextlib.ExitStack() as stack:
        parent = tree.open_directory(stack, path.parent)
        descriptor = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
        stack.callback(os.close, descriptor)
        before = os.fstat(descriptor)
        tree.check(before, directory=False)
        if before.st_size > limit or (executable and not before.st_mode & stat.S_IXUSR):
            raise FunderBuildError("artifact size or executable mode is invalid")
        digest = hashlib.sha256()
        with os.fdopen(os.dup(descriptor), "rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        if tree.identity(os.fstat(descriptor)) != tree.identity(before):
            raise FunderBuildError("artifact changed while capturing its bytes")
        return tree.identity(before), digest.hexdigest()


class ProducedRegtestFunder:
    """Original successfully joined producer; never construct from a receipt."""
    def __init__(self, case, root, root_id, binary, binary_record, source_records,
                 source_directories, binary_parents, provenance, token):
        if token is not _TOKEN:
            raise FunderBuildError("use build_regtest_funder")
        self._case, self._root, self._root_id = case, root, root_id
        self._binary = binary
        self._binary_record = binary_record
        self._source_records = source_records
        self._source_directories = source_directories
        self._binary_parents = binary_parents
        self._provenance = provenance
        self._failed = False

    @property
    def binary(self):
        return self._binary

    def verify_unchanged(self):
        if self._failed:
            raise FunderBuildError("original funder publication already failed verification")
        try:
            self._case.workspace.verify_owned()
            if self._case.accepting_launches or self._case._receipt is None:
                raise FunderBuildError("original build writers were not positively joined")
            if self._root != self._case.workspace.root / "funder-build":
                raise FunderBuildError("original build attachment changed")
            with contextlib.ExitStack() as stack:
                fd = tree.open_directory(stack, self._root, private=True)
                if tree.identity(os.fstat(fd)) != self._root_id:
                    raise FunderBuildError("original build directory changed")
            for path, expected in self._binary_parents.items():
                with contextlib.ExitStack() as stack:
                    fd = tree.open_directory(stack, path)
                    if tree.identity(os.fstat(fd)) != expected:
                        raise FunderBuildError("original executable parent changed")
            if _file_record(self.binary, executable=True, limit=_MAX_BINARY_BYTES) != self._binary_record:
                raise FunderBuildError("original funder executable changed")
            _verify_source(self._root / "source", self._source_records, self._source_directories)
        except BaseException:
            self._failed = True
            raise

    def identity(self):
        self.verify_unchanged()
        # Identity describes this producer, not a portable cache attestation.
        return json.loads(json.dumps(self._provenance))


def _verify_root(case, root, expected):
    case.workspace.verify_owned()
    if root != case.workspace.root / "funder-build":
        raise FunderBuildError("build path is not the original case attachment")
    with contextlib.ExitStack() as stack:
        descriptor = tree.open_directory(stack, root, private=True)
        if tree.identity(os.fstat(descriptor)) != expected:
            raise FunderBuildError("original build directory identity changed")


def _source_directories(root):
    result = {}
    for directory, children, _ in os.walk(root, followlinks=False):
        for path in (Path(directory), *(Path(directory) / name for name in children)):
            with contextlib.ExitStack() as stack:
                fd = tree.open_directory(stack, path, private=True)
                result[path.relative_to(root).as_posix()] = tree.identity(os.fstat(fd))
    return result


def _verify_source(root, records, directories):
    if _source_directories(root) != directories:
        raise FunderBuildError("original frozen-source directories changed")
    observed = set()
    for directory, children, files in os.walk(root, followlinks=False):
        for child in children:
            with contextlib.ExitStack() as stack:
                tree.open_directory(stack, Path(directory) / child, private=True)
        for name in files:
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if relative not in records or _file_record(path) != records[relative]:
                raise FunderBuildError("frozen Rust source changed")
            observed.add(relative)
    if observed != set(records):
        raise FunderBuildError("frozen Rust source is incomplete")


def _snapshot(archive, source, expected):
    """No tar extraction API: admit exact regular Git blobs before any writes."""
    _file_record(archive)
    descriptor = os.open(archive, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as data, tarfile.open(fileobj=data, mode="r:") as bundle:
        members = bundle.getmembers()
        files = {}
        total = 0
        for member in members:
            name = member.name.rstrip("/") if member.isdir() else member.name
            _relative(name)
            if member.isdir():
                continue
            if not member.isfile() or name in files or name not in expected:
                raise FunderBuildError("archive contains an untracked, duplicate or nonregular member")
            total += member.size
            if total > _MAX_SOURCE_BYTES or len(files) >= _MAX_SOURCE_FILES:
                raise FunderBuildError("Rust source archive exceeds its bound")
            payload = bundle.extractfile(member).read()
            blob = hashlib.sha1(f"blob {len(payload)}\0".encode() + payload).hexdigest()
            if blob != expected[name][1]:
                raise FunderBuildError("archive bytes differ from the exact Git blob")
            files[name] = payload
        if set(files) != set(expected):
            raise FunderBuildError("Git archive omitted a Rust source blob")
        source.mkdir(mode=0o700)
        records = {}
        for name, payload in files.items():
            path = source / name
            parent = source
            for part in _relative(name).parts[:-1]:
                parent = parent / part
                parent.mkdir(mode=0o700, exist_ok=True)
                with contextlib.ExitStack() as stack:
                    tree.open_directory(stack, parent, private=True)
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o500 if expected[name][0] == "100755" else 0o400)
            with os.fdopen(descriptor, "wb") as output:
                output.write(payload)
            records[name] = _file_record(path)
        return records


def _copy_cargo_executable(source, destination):
    """Copy only a joined original Cargo output; publication stays single-link.

    Cargo may hard-link its named and hashed artifacts. Those original inputs
    are not the published artifact and never relax shared owned-tree checks.
    """
    with contextlib.ExitStack() as stack:
        parent = tree.open_directory(stack, source.parent)
        descriptor = os.open(source.name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
        stack.callback(os.close, descriptor)
        before = os.fstat(descriptor)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
            or before.st_mode & 0o022 or before.st_nlink < 1
            or not before.st_mode & stat.S_IXUSR or before.st_size > _MAX_BINARY_BYTES):
            raise FunderBuildError("original Cargo executable is not an owned regular output")
        output_fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o500)
        digest = hashlib.sha256()
        count = 0
        with os.fdopen(os.dup(descriptor), "rb") as reader, os.fdopen(output_fd, "wb") as writer:
            for chunk in iter(lambda: reader.read(1024 * 1024), b""):
                count += len(chunk)
                if count > _MAX_BINARY_BYTES:
                    raise FunderBuildError("Cargo executable grew beyond publication bound")
                digest.update(chunk)
                writer.write(chunk)
        if tree.identity(os.fstat(descriptor)) != tree.identity(before):
            raise FunderBuildError("Cargo executable changed during publication")
        record = _file_record(destination, executable=True, limit=_MAX_BINARY_BYTES)
        if record[1] != digest.hexdigest():
            raise FunderBuildError("published executable differs from original Cargo bytes")
        return record


def build_regtest_funder(case: NativeCaseLifecycle, *, source_root: Path,
                        source_commit: str, jobs: int = 4, timeout: float = 1200.0,
                        cancel_event=None):
    """One dedicated fresh producer case; close it before returning a handle.

    All failure evidence/source/target storage remains. Never adopt prior roots,
    execute checkout files, reset a source repo or accept external build receipts.
    """
    if (not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches
        or case.launched_process_count != 0):
        raise FunderBuildError("build requires a fresh dedicated original process owner")
    if not isinstance(source_commit, str) or not _COMMIT.fullmatch(source_commit):
        raise FunderBuildError("source_commit must be one full immutable Git SHA")
    if type(jobs) is not int or not 1 <= jobs <= 8:
        raise FunderBuildError("Cargo build jobs must be 1 through 8")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise FunderBuildError("build timeout must be positive and finite")
    source_root = Path(source_root).resolve(strict=True)
    cancellation = cancel_event if cancel_event is not None else threading.Event()
    case.workspace.verify_owned()
    root = case.workspace.root / "funder-build"
    root.mkdir(mode=0o700)
    root_id = tree.identity(root.stat())
    environment = {**os.environ, "GIT_ALLOW_PROTOCOL": ""}
    def command(arguments, *, env=environment):
        _verify_root(case, root, root_id)
        if cancellation.is_set():
            raise runtime.Cancelled()
        result = case.run_command(arguments, env=env, timeout=timeout, cancel_event=cancellation)
        if result.returncode != 0:
            raise FunderBuildError("owned build phase failed; preserve its original process log", result.returncode)
        _verify_root(case, root, root_id)
        return tuple(line.rstrip("\r\n") for line in result.lines)
    git = ["git", "--no-replace-objects", "-C", str(source_root)]
    try:
        if tuple(command([*git, "cat-file", "-t", source_commit])) != ("commit",):
            raise FunderBuildError("source identity is not an original Git commit")
        expected = {}
        for line in command([*git, "ls-tree", "-r", "--full-tree", source_commit, "--", "rust"]):
            metadata, name = line.split("\t", 1)
            mode, kind, blob = metadata.split()
            _relative(name)
            if mode not in {"100644", "100755"} or kind != "blob" or not _COMMIT.fullmatch(blob):
                raise FunderBuildError("Rust input must be an exact regular Git blob")
            if name in expected or len(expected) >= _MAX_SOURCE_FILES:
                raise FunderBuildError("Rust input inventory exceeds its bound or repeats paths")
            expected[name] = (mode, blob)
        if not _REQUIRED <= expected.keys():
            raise FunderBuildError("source commit lacks the offline funding tool/locked package")
        archive = root / "source.tar"
        command([*git, "archive", "--format=tar", f"--output={archive}", source_commit, "rust"])
        records = _snapshot(archive, root / "source", expected)
        source_directories = _source_directories(root / "source")
        compiler_entry = shutil.which(environment.get("RUSTC") or "rustc", path=environment.get("PATH"))
        if compiler_entry is None:
            raise FunderBuildError("selected Rust compiler is not executable")
        compiler = Path(compiler_entry).resolve(strict=True)
        if compiler.name == "rustup":
            paths = command([str(compiler), "which", "rustc"])
            if len(paths) != 1 or not Path(paths[0]).is_absolute():
                raise FunderBuildError("rustup did not identify one absolute compiler")
            compiler = Path(paths[0]).resolve(strict=True)
        if not compiler.is_file() or not os.access(compiler, os.X_OK):
            raise FunderBuildError("selected Rust compiler is not executable")
        rustc = command([str(compiler), "-vV"])
        cargo = command(["cargo", "-V"])
        hosts = [line.removeprefix("host: ") for line in rustc if line.startswith("host: ")]
        if len(hosts) != 1 or not re.fullmatch(r"[A-Za-z0-9_]+(?:-[A-Za-z0-9_]+)+", hosts[0]):
            raise FunderBuildError("Rust compiler did not identify one host target")
        host = hosts[0]
        target = root / "target"
        target.mkdir(mode=0o700)
        build_env = {**os.environ, "CARGO_TARGET_DIR": str(target), "CARGO_BUILD_JOBS": str(jobs),
                     "RUSTC": str(compiler), "RUSTC_WRAPPER": "", "RUSTC_WORKSPACE_WRAPPER": ""}
        lines = command(["cargo", "build", "--offline", "--locked", "--manifest-path",
            str(root / "source/rust/Cargo.toml"), "--example", "regtest_direct_funder",
            "--target", host, "--message-format=json"], env=build_env)
        candidates, completed = [], False
        for line in lines:
            if not line.lstrip().startswith("{"):
                continue  # Cargo stderr progress shares the owned capture with JSON stdout.
            message = json.loads(line)
            if message.get("reason") == "build-finished":
                completed = message.get("success") is True
            if (message.get("reason") == "compiler-artifact" and message.get("executable") is not None
                and message.get("target", {}).get("name") == "regtest_direct_funder"
                and message["target"].get("kind") == ["example"]
                and message["target"].get("src_path") == str(root / "source/rust/examples/regtest_direct_funder.rs")
                and message.get("profile", {}).get("test") is False):
                candidates.append(Path(message["executable"]))
        if not completed or len(candidates) != 1:
            raise FunderBuildError("Cargo did not prove one completed funding executable")
        cargo_binary = candidates[0]
        if not cargo_binary.is_absolute() or cargo_binary.resolve(strict=True) != cargo_binary:
            raise FunderBuildError("Cargo executable path is not canonical")
        cargo_binary.relative_to(target)
        _verify_source(root / "source", records, source_directories)
        case.close()
        _verify_root(case, root, root_id)
        publication = root / "publication"
        publication.mkdir(mode=0o700)
        binary = publication / "regtest_direct_funder"
        binary_record = _copy_cargo_executable(cargo_binary, binary)
        binary_parents = {}
        for parent in binary.parents:
            if parent == root:
                break
            with contextlib.ExitStack() as stack:
                fd = tree.open_directory(stack, parent)
                binary_parents[parent] = tree.identity(os.fstat(fd))
        provenance = {"schema_version": 1, "source_commit": source_commit,
            "rust_blobs": {name: {"git_blob": expected[name][1], "sha256": record[1]}
                           for name, record in sorted(records.items())},
            "binary": str(binary), "binary_sha256": binary_record[1],
            "rustc": list(rustc), "rustc_binary": str(compiler), "cargo": list(cargo), "offline": True,
            "host_target": host, "jobs": jobs, "producer_namespace": case.workspace.namespace}
        artifact = ProducedRegtestFunder(case, root, root_id, binary, binary_record, records,
                                        source_directories, binary_parents, provenance, _TOKEN)
        artifact.verify_unchanged()
        return artifact
    except BaseException as primary:
        try:
            case.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
