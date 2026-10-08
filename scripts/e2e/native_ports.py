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


def _reserve_port(lock_root: Path, run_id: str) -> tuple[int, socket.socket, int]:
    for _ in range(100):
        reserved = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        descriptor: int | None = None
        try:
            reserved.bind(("127.0.0.1", 0))
            reserved.listen(1)
            port = int(reserved.getsockname()[1])
            flags = os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW
            descriptor = os.open(lock_root / f"{port}.lock", flags, 0o600)
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
                blocked_descriptor = descriptor
                descriptor = None
                os.close(blocked_descriptor)
                reserved.close()
                continue
            os.ftruncate(descriptor, 0)
            os.write(descriptor, f"run_id={run_id}\npid={os.getpid()}\n".encode())
            return port, reserved, descriptor
        except BaseException:
            try:
                if descriptor is not None:
                    os.close(descriptor)
            finally:
                reserved.close()
            raise
    raise NativePortError("could not reserve a cooperatively locked native port")


def lease_native_ports(
    worker_id: int,
    run_id: str,
    *,
    lock_root: Path | None = None,
) -> NativePortLease:
    """Reserve rpc/lwd/proxy sockets plus per-UID locks across cooperating runs."""
    if type(worker_id) is not int or not 0 <= worker_id <= 1_000_000:
        raise NativePortError("worker_id must be an integer from 0 through 1,000,000")
    if not isinstance(run_id, str) or not _RUN_ID_RE.fullmatch(run_id):
        raise NativePortError("run_id must contain exactly ten lowercase hexadecimal characters")
    if lock_root is None:
        parent = _safe_lock_directory(
            Path(tempfile.gettempdir()).resolve()
            / f"vizor-wallet-native-e2e-{os.getuid()}",
            private=False,
        )
        lock_root = parent / "ports"
    safe_lock_root = _safe_lock_directory(lock_root)
    lease = NativePortLease(worker_id, {}, [], [])
    try:
        for name in _PORT_NAMES:
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
