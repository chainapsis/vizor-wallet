"""Owned loopback port reservations for local native E2E workers (POSIX)."""

from __future__ import annotations

import dataclasses
import fcntl
import os
from pathlib import Path
import re
import socket
import stat
import tempfile


_RUN_ID_RE = re.compile(r"[a-f0-9]{10}\Z")
_PORT_NAMES = ("rpc", "lwd", "proxy")
_PORT_ROLE_RE = re.compile(r"[a-z][a-z0-9_]{0,31}\Z")


class NativePortError(RuntimeError):
    """A reservation could not be acquired or safely released."""


@dataclasses.dataclass
class NativePortLease:
    worker_id: int
    ports: dict[str, int]
    sockets: list[socket.socket]
    lock_descriptors: list[int]
    _cleanup_error: str | None = dataclasses.field(default=None, init=False, repr=False)

    def release_sockets(self) -> None:
        """Allow services to bind, retaining cooperative locks until close()."""
        errors: list[str] = []
        reserved, self.sockets = self.sockets, []
        for item in reserved:
            try:
                item.close()
            except OSError as error:
                errors.append(str(error))
        self._check_cleanup(errors)

    def close(self) -> None:
        """Release this lease's handles; do not delete shared lock files."""
        errors: list[str] = []
        try:
            self.release_sockets()
        except NativePortError as error:
            errors.append(str(error))
        descriptors, self.lock_descriptors = self.lock_descriptors, []
        for descriptor in descriptors:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_UN)
            except OSError as error:
                errors.append(str(error))
            finally:
                try:
                    os.close(descriptor)
                except OSError as error:
                    errors.append(str(error))
        self._check_cleanup(errors)

    def _check_cleanup(self, errors: list[str]) -> None:
        if errors:
            self._cleanup_error = "; ".join(errors)
        if self._cleanup_error is not None:
            raise NativePortError(f"native port lease cleanup unproven: {self._cleanup_error}")


def _safe_lock_directory(path: Path, *, private: bool = True) -> Path:
    if not path.is_absolute() or path.resolve() != path:
        raise NativePortError("port lock directory must be absolute and canonical")
    path.mkdir(mode=0o700, exist_ok=True)
    details = path.lstat()
    if (
        not stat.S_ISDIR(details.st_mode)
        or details.st_uid != os.getuid()
        or stat.S_IMODE(details.st_mode) & (0o077 if private else 0o022)
    ):
        requirement = "private" if private else "not writable by other users"
        raise NativePortError(f"port lock directory must be owned and {requirement}: {path}")
    return path


def _lock_port(lock_root: Path, run_id: str, port: int) -> int | None:
    """Take the per-UID cooperative lock for a port, or None if another run holds it."""
    flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
    descriptor = os.open(lock_root / f"{port}.lock", flags, 0o600)
    try:
        details = os.fstat(descriptor)
        if (
            not stat.S_ISREG(details.st_mode)
            or details.st_uid != os.getuid()
            or stat.S_IMODE(details.st_mode) & 0o077
            or details.st_nlink != 1
        ):
            raise NativePortError(f"native port lock file is unsafe: {port}")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(descriptor)
            return None
        os.ftruncate(descriptor, 0)
        os.write(descriptor, f"run_id={run_id}\npid={os.getpid()}\n".encode())
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _reserve_port(lock_root: Path, run_id: str) -> tuple[int, socket.socket, int]:
    for _ in range(100):
        reserved = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            reserved.bind(("127.0.0.1", 0))
            reserved.listen(1)
            port = int(reserved.getsockname()[1])
            descriptor = _lock_port(lock_root, run_id, port)
        except BaseException:
            reserved.close()
            raise
        if descriptor is None:
            reserved.close()
            continue
        return port, reserved, descriptor
    raise NativePortError("could not reserve a cooperatively locked native port")


def _accepts_connections(port: int) -> bool:
    """Whether anything accepts a loopback connection on `port`.

    A listener on a wildcard address, as Docker publishes ports, does not stop
    the reusable bind to 127.0.0.1 below on macOS.
    """
    for address in ("127.0.0.1", "::1"):
        try:
            with socket.create_connection((address, port), timeout=1.0):
                return True
        except OSError:
            continue
    return False


def _reserve_fixed_port(lock_root: Path, run_id: str, port: int) -> tuple[socket.socket, int]:
    if _accepts_connections(port):
        raise NativePortError(f"port {port} is in use; stop whatever listens on it")
    reserved = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        # A previous case's connections may still be in TIME_WAIT; a live
        # listener on the port still refuses the bind.
        reserved.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            reserved.bind(("127.0.0.1", port))
        except OSError as error:
            raise NativePortError(f"port {port} is in use; stop whatever listens on it") from error
        reserved.listen(1)
        descriptor = _lock_port(lock_root, run_id, port)
    except BaseException:
        reserved.close()
        raise
    if descriptor is None:
        reserved.close()
        raise NativePortError(f"port {port} is leased by another E2E run")
    return reserved, descriptor


def _port_lock_root(lock_root: Path | None) -> Path:
    if lock_root is None:
        parent = _safe_lock_directory(
            Path(tempfile.gettempdir()).resolve()
            / f"vizor-wallet-native-e2e-{os.getuid()}",
            private=False,
        )
        lock_root = parent / "ports"
    return _safe_lock_directory(lock_root)


def lease_native_ports(
    worker_id: int,
    run_id: str,
    *,
    lock_root: Path | None = None,
    port_names: tuple[str, ...] = _PORT_NAMES,
) -> NativePortLease:
    """Reserve named service sockets and retain per-UID cooperative locks."""
    if type(worker_id) is not int or not 0 <= worker_id <= 1_000_000:
        raise NativePortError("worker_id must be an integer from 0 through 1,000,000")
    if not isinstance(run_id, str) or not _RUN_ID_RE.fullmatch(run_id):
        raise NativePortError("run_id must contain exactly ten lowercase hexadecimal characters")
    if (not isinstance(port_names, tuple) or not 1 <= len(port_names) <= 16
        or any(not isinstance(name, str) or not _PORT_ROLE_RE.fullmatch(name) for name in port_names)
        or len(set(port_names)) != len(port_names)):
        raise NativePortError("port_names must contain one to sixteen unique service roles")
    safe_lock_root = _port_lock_root(lock_root)
    lease = NativePortLease(worker_id, {}, [], [])
    try:
        for name in port_names:
            port, reserved, descriptor = _reserve_port(safe_lock_root, run_id)
            lease.ports[name] = port
            lease.sockets.append(reserved)
            lease.lock_descriptors.append(descriptor)
    except BaseException as primary_error:
        try:
            lease.close()
        except NativePortError as cleanup_error:
            if isinstance(primary_error, KeyboardInterrupt):
                raise KeyboardInterrupt(
                    f"port acquisition interrupted; rollback failed: {cleanup_error}"
                ) from cleanup_error
            raise NativePortError(
                f"port acquisition failed ({type(primary_error).__name__}: {primary_error}); "
                f"rollback failed: {cleanup_error}"
            ) from primary_error
        raise
    return lease


def lease_fixed_ports(
    run_id: str,
    ports: dict[str, int],
    *,
    lock_root: Path | None = None,
) -> NativePortLease:
    """Reserve exact loopback ports, failing fast when one is already taken."""
    if not isinstance(run_id, str) or not _RUN_ID_RE.fullmatch(run_id):
        raise NativePortError("run_id must contain exactly ten lowercase hexadecimal characters")
    if (not isinstance(ports, dict) or not 1 <= len(ports) <= 16
        or any(not isinstance(name, str) or not _PORT_ROLE_RE.fullmatch(name) for name in ports)
        or any(type(port) is not int or not 1024 <= port <= 65535 for port in ports.values())
        or len(set(ports.values())) != len(ports)):
        raise NativePortError("ports must map one to sixteen roles to distinct unprivileged ports")
    safe_lock_root = _port_lock_root(lock_root)
    lease = NativePortLease(0, {}, [], [])
    try:
        for name, port in ports.items():
            reserved, descriptor = _reserve_fixed_port(safe_lock_root, run_id, port)
            lease.ports[name] = port
            lease.sockets.append(reserved)
            lease.lock_descriptors.append(descriptor)
    except BaseException:
        lease.close()
        raise
    return lease
