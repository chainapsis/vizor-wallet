"""Exclusive case directories and schema-1 launch identity for native E2E."""

from __future__ import annotations

from collections.abc import Mapping
import contextlib
import dataclasses
import json
import os
from pathlib import Path
import re
import secrets
import stat


_OWNERSHIP_TOKEN = object()
_RUN_ID_RE = re.compile(r"[a-f0-9]{10}\Z")
_PORT_KEYS = {"rpc", "lwd", "proxy"}
_MARKER_NAME = "workspace-owner.json"
_MANIFEST_NAME = "case-manifest.json"
_MAX_MANIFEST_BYTES = 2048


class NativeWorkspaceError(RuntimeError):
    """Case allocation or ownership verification failed; retain its evidence."""


@dataclasses.dataclass
class _Verification:
    error: str | None = None


@dataclasses.dataclass(frozen=True)
class NativeCaseWorkspace:
    """Use prepare_native_case_workspace(); existing directories are never adopted.

    This handle owns only case directory/launch metadata, not native storage,
    processes, ports, or simulators. It deliberately has no deletion operation.
    Verification is single-owner and cooperative, not a security boundary.
    """

    root: Path
    namespace: str
    context_path: str
    _run_root: Path = dataclasses.field(repr=False)
    _directory_ids: tuple[tuple[int, int], ...] = dataclasses.field(repr=False)
    _file_ids: tuple[tuple[int, int], ...] = dataclasses.field(repr=False)
    _marker_bytes: bytes = dataclasses.field(repr=False)
    _manifest_bytes: bytes = dataclasses.field(repr=False)
    _verification: _Verification = dataclasses.field(repr=False)
    _ownership_token: object = dataclasses.field(repr=False)

    @property
    def marker_path(self) -> Path:
        return self.root / _MARKER_NAME

    @property
    def manifest_path(self) -> Path:
        return self.root / _MANIFEST_NAME

    def launch_environment(self) -> dict[str, str]:
        """Recheck ownership before every phase; emit JSON, not a manifest filename."""
        self.verify_owned()
        return {
            "VIZOR_E2E_NAMESPACE": self.namespace,
            "VIZOR_E2E_CASE_MANIFEST": self._manifest_bytes.decode("ascii"),
        }

    def verify_owned(self) -> None:
        """Verify original directories and metadata; this is not cleanup proof."""
        if self._ownership_token is not _OWNERSHIP_TOKEN:
            raise NativeWorkspaceError("expected a handle from prepare_native_case_workspace")
        if self._verification.error is not None:
            raise NativeWorkspaceError(self._verification.error)
        try:
            if (
                _canonical_root(self._run_root) != self._run_root
                or self.root != self._run_root / "e2e" / self.namespace
            ):
                raise NativeWorkspaceError("case path no longer matches its original root")
            with contextlib.ExitStack() as stack:
                run_fd = _open_private_directory(stack, self._run_root)
                cases_fd = _open_private_directory(stack, "e2e", dir_fd=run_fd)
                case_fd = _open_private_directory(stack, self.namespace, dir_fd=cases_fd)
                actual = tuple(_identity(os.fstat(fd)) for fd in (run_fd, cases_fd, case_fd))
                if actual != self._directory_ids:
                    raise NativeWorkspaceError("case directory identity changed")
                for name, payload, identity in (
                    (_MARKER_NAME, self._marker_bytes, self._file_ids[0]),
                    (_MANIFEST_NAME, self._manifest_bytes, self._file_ids[1]),
                ):
                    data, current_id = _read_private_file(case_fd, name, len(payload) + 1)
                    if current_id != identity or data != payload:
                        raise NativeWorkspaceError(f"case metadata changed: {name}")
        except (OSError, ValueError, RuntimeError) as error:
            self._verification.error = f"case workspace ownership unproven: {error}"
            raise NativeWorkspaceError(self._verification.error) from error


def _identity(details: os.stat_result) -> tuple[int, int]:
    return details.st_dev, details.st_ino


def _canonical_root(path: Path) -> Path:
    try:
        if not isinstance(path, Path) or not path.is_absolute() or path.resolve(strict=True) != path:
            raise ValueError("noncanonical root")
    except (OSError, ValueError, RuntimeError) as error:
        raise NativeWorkspaceError("run root must be an existing absolute canonical directory") from error
    return path


def _open_private_directory(
    stack: contextlib.ExitStack, path: Path | str, *, dir_fd: int | None = None,
) -> int:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dir_fd)
    stack.callback(os.close, descriptor)
    details = os.fstat(descriptor)
    if (
        not stat.S_ISDIR(details.st_mode)
        or details.st_uid != os.getuid()
        or stat.S_IMODE(details.st_mode) & 0o077
    ):
        raise NativeWorkspaceError(f"directory must be private and owned: {path}")
    return descriptor


def _private_file_identity(descriptor: int, name: str) -> tuple[int, int]:
    details = os.fstat(descriptor)
    if (
        not stat.S_ISREG(details.st_mode)
        or details.st_uid != os.getuid()
        or stat.S_IMODE(details.st_mode) & 0o077
        or details.st_nlink != 1
    ):
        raise NativeWorkspaceError(f"case metadata must be private, regular and owned: {name}")
    return _identity(details)


def _write_new_file(directory_fd: int, name: str, data: bytes) -> tuple[int, int]:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    with os.fdopen(os.open(name, flags, 0o600, dir_fd=directory_fd), "wb") as stream:
        identity = _private_file_identity(stream.fileno(), name)
        stream.write(data)
        stream.flush()
        return identity


def _read_private_file(directory_fd: int, name: str, limit: int) -> tuple[bytes, tuple[int, int]]:
    # NONBLOCK prevents a replaced FIFO from hanging before the regular-file check.
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(name, flags, dir_fd=directory_fd), "rb") as stream:
        identity = _private_file_identity(stream.fileno(), name)
        return stream.read(limit), identity


def _bounded_integer(value: int, name: str, maximum: int, *, minimum: int = 0) -> None:
    if type(value) is not int or not minimum <= value <= maximum:
        raise NativeWorkspaceError(f"{name} must be an integer from {minimum} through {maximum}")


def prepare_native_case_workspace(
    run_root: Path,
    *,
    platform: str,
    scenario_id: str,
    run_id: str,
    worker_id: int,
    case_index: int,
    ports: Mapping[str, int],
    activation_height: int,
) -> NativeCaseWorkspace:
    """Allocate one new case without copying sources or deleting existing state.

    The caller supplies a private run root, fresh run identity, and independently
    leased ports. Failed/partial allocations stay on disk and cannot be adopted
    by a retry. Restarts reuse this handle; a rerun needs a fresh run identity.
    """
    if os.name != "posix":
        raise NativeWorkspaceError("native case workspace ownership requires a POSIX host")
    if not isinstance(run_id, str) or not _RUN_ID_RE.fullmatch(run_id):
        raise NativeWorkspaceError("run_id must contain exactly ten lowercase hexadecimal characters")
    _bounded_integer(worker_id, "worker_id", 1_000_000)
    _bounded_integer(case_index, "case_index", 1_000_000)
    _bounded_integer(activation_height, "activation_height", 4_294_967_295, minimum=1)
    if platform not in ("macos", "ios") or not isinstance(scenario_id, str) or not re.fullmatch(
        rf"flutter\.{platform}\.[a-z0-9]+(?:-[a-z0-9]+)*", scenario_id,
    ):
        raise NativeWorkspaceError("scenario_id must match the selected macos or ios platform")
    if not isinstance(ports, Mapping) or set(ports) != _PORT_KEYS:
        raise NativeWorkspaceError("ports must contain exactly rpc, lwd and proxy")
    selected_ports = dict(ports)
    for name, port in selected_ports.items():
        _bounded_integer(port, name, 65535, minimum=1)
    if len(set(selected_ports.values())) != 3:
        raise NativeWorkspaceError("case ports must be distinct")

    run_root = _canonical_root(run_root)
    namespace = f"vizor_{run_id}_w{worker_id}_{case_index}"
    root = run_root / "e2e" / namespace
    context_path = "app-support" if platform == "ios" else str(root / "native-context.json")
    manifest = {
        "schema_version": 1,
        "scenario_id": scenario_id,
        "run_id": run_id,
        "worker_id": worker_id,
        "case_index": case_index,
        "namespace": namespace,
        "context_path": context_path,
        "lightwalletd_port": selected_ports["lwd"],
        "primary_proxy_port": selected_ports["proxy"],
        "zcashd_rpc_port": selected_ports["rpc"],
        "regtest_ironwood_activation_height": activation_height,
    }
    manifest_bytes = json.dumps(manifest, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode("ascii")
    if len(manifest_bytes) > _MAX_MANIFEST_BYTES:
        raise NativeWorkspaceError("case manifest exceeds the native 2048-byte limit")
    marker_bytes = (json.dumps({
        "schema_version": 1,
        "workspace": str(root),
        "namespace": namespace,
        "owner_nonce": secrets.token_hex(16),
    }, ensure_ascii=True, sort_keys=True) + "\n").encode("ascii")
    try:
        with contextlib.ExitStack() as stack:
            run_fd = _open_private_directory(stack, run_root)
            try:
                os.mkdir("e2e", 0o700, dir_fd=run_fd)
            except FileExistsError:
                pass  # Only the shared parent can preexist; it is checked below.
            cases_fd = _open_private_directory(stack, "e2e", dir_fd=run_fd)
            os.mkdir(namespace, 0o700, dir_fd=cases_fd)
            case_fd = _open_private_directory(stack, namespace, dir_fd=cases_fd)
            directory_ids = tuple(_identity(os.fstat(fd)) for fd in (run_fd, cases_fd, case_fd))
            marker_id = _write_new_file(case_fd, _MARKER_NAME, marker_bytes)
            manifest_id = _write_new_file(case_fd, _MANIFEST_NAME, manifest_bytes)
        workspace = NativeCaseWorkspace(
            root, namespace, context_path, run_root, directory_ids,
            (marker_id, manifest_id), marker_bytes, manifest_bytes,
            _Verification(), _OWNERSHIP_TOKEN,
        )
        workspace.verify_owned()
        return workspace
    except (OSError, ValueError, RuntimeError) as error:
        raise NativeWorkspaceError(f"case allocation failed; existing/partial state retained at {root}: {error}") from error
