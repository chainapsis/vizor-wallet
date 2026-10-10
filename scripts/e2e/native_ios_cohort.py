"""Read-only capture of the built iOS Simulator cohort app.

No SDK/app launch or deletion API is exposed here. Captured file identities are
continuity observations, not provenance, ownership or cleanup authority.
"""

from __future__ import annotations

import dataclasses
import hashlib
import os
from pathlib import Path
import plistlib
import stat
import struct
import subprocess
import sys
from xml.parsers.expat import ExpatError

import e2e_runtime as runtime


_BUNDLE = "com.keplr.vizor"
# Matches the unified-log predicate that binds the app's VM endpoint.
_EXECUTABLE = "Runner"
_CAPTURE_TOKEN = object()
_HOST_PLATFORM = sys.platform
_MAX_EXECUTABLE = 64 * 1024 * 1024
_SIGNATURE_TIMEOUT = 15


class IosCohortError(runtime.RunnerError):
    """The Simulator cohort capture is unavailable or no longer matches."""


def _regular_bytes(path: Path, limit: int) -> tuple[bytes, tuple[int, int]]:
    if path.resolve(strict=True) != path:
        raise IosCohortError("Simulator cohort path is not canonical")
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o022 or info.st_nlink != 1 or info.st_size > limit
        ):
            raise IosCohortError("Simulator cohort file is not bounded, regular and owned")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise IosCohortError("Simulator cohort file exceeds its limit")
        return data, (info.st_dev, info.st_ino)


def _simulator_architecture(data: bytes) -> str:
    """Read a thin Simulator executable's architecture from its Mach-O header."""
    if len(data) < 32 or len(data) > _MAX_EXECUTABLE:
        raise IosCohortError("invalid Simulator executable size")
    magic, cpu, _, kind, count, size = struct.unpack_from("<6I", data)
    architecture = {0x0100000C: "arm64", 0x01000007: "x86_64"}.get(cpu)
    if magic != 0xFEEDFACF or architecture is None or kind != 2 or not 0 < count <= 4096:
        raise IosCohortError("expected a thin 64-bit Simulator executable")
    if size > 1024 * 1024 or size > len(data) - 32:
        raise IosCohortError("invalid Simulator load-command bounds")
    end, offset, platform = 32 + size, 32, None
    for _ in range(count):
        if offset > end - 8:
            raise IosCohortError("truncated Simulator load command")
        command, length = struct.unpack_from("<2I", data, offset)
        if length < 8 or length % 8 or length > end - offset:
            raise IosCohortError("invalid Simulator load-command length")
        if command == 0x32:  # LC_BUILD_VERSION
            if length < 24 or platform is not None:
                raise IosCohortError("ambiguous Simulator platform")
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        offset += length
    if offset != end or platform != 7:  # PLATFORM_IOSSIMULATOR
        raise IosCohortError("missing Simulator platform")
    return architecture


@dataclasses.dataclass(frozen=True)
class _SimulatorApp:
    path: Path
    executable: Path
    architecture: str
    files: tuple[tuple[str, int, int, str], ...]
    directory_ids: tuple[tuple[int, int], ...]


def _inspect_app(path: Path) -> _SimulatorApp:
    if _HOST_PLATFORM != "darwin":
        raise IosCohortError("Simulator cohort capture requires macOS")
    if not isinstance(path, Path) or not path.is_absolute() or path.suffix != ".app":
        raise IosCohortError("expected an absolute Simulator app bundle")
    try:
        directories = (path, path / "_CodeSignature")
        identities = []
        for directory in directories:
            info = directory.lstat()
            if (
                not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o022 or directory.resolve(strict=True) != directory
            ):
                raise IosCohortError("Simulator cohort directory is not canonical and owned")
            identities.append((info.st_dev, info.st_ino))
        info_bytes, info_identity = _regular_bytes(path / "Info.plist", 64 * 1024)
        info = plistlib.loads(info_bytes)
        if not isinstance(info, dict):
            raise IosCohortError("Simulator cohort Info.plist must be a dictionary")
        if (
            info.get("CFBundleIdentifier") != _BUNDLE
            or info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"]
            or info.get("CFBundleExecutable") != _EXECUTABLE
        ):
            raise IosCohortError("Simulator cohort bundle identity mismatch")
        executable = path / _EXECUTABLE
        if not os.access(executable, os.X_OK):
            raise IosCohortError("Simulator cohort is not executable")
        files = [(str(path / "Info.plist"), *info_identity, hashlib.sha256(info_bytes).hexdigest())]
        for file, limit in ((executable, _MAX_EXECUTABLE),
                            (path / "_CodeSignature/CodeResources", 4 * 1024 * 1024)):
            content, (device, inode) = _regular_bytes(file, limit)
            files.append((str(file), device, inode, hashlib.sha256(content).hexdigest()))
            if file == executable:
                architecture = _simulator_architecture(content)
        for file, device, inode, digest in files:
            content, identity = _regular_bytes(Path(file), _MAX_EXECUTABLE)
            if identity != (device, inode) or hashlib.sha256(content).hexdigest() != digest:
                raise IosCohortError("Simulator cohort changed during capture")
        for directory, identity in zip(directories, identities):
            info = directory.lstat()
            if (
                (info.st_dev, info.st_ino) != identity or not stat.S_ISDIR(info.st_mode)
                or info.st_uid != os.getuid() or info.st_mode & 0o022
                or directory.resolve(strict=True) != directory
            ):
                raise IosCohortError("Simulator cohort directory changed during capture")
        return _SimulatorApp(path, executable, architecture, tuple(files), tuple(identities))
    except IosCohortError:
        raise
    except (OSError, ValueError, TypeError, UnicodeError, plistlib.InvalidFileException, ExpatError) as error:
        raise IosCohortError("Simulator cohort capture failed") from error


def _verify_signature(path: Path) -> None:
    try:
        result = subprocess.run(
            ["/usr/bin/codesign", "--verify", "--strict", "--deep", str(path)],
            capture_output=True, timeout=_SIGNATURE_TIMEOUT, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise IosCohortError("cannot verify the Simulator cohort signature") from error
    if result.returncode != 0:
        raise IosCohortError("Simulator cohort signature verification failed")


@dataclasses.dataclass(frozen=True)
class CapturedIosCohort:
    """Read-only capture; the builder supplies the actual app, never an arbitrary one."""

    _cohort: _SimulatorApp = dataclasses.field(repr=False)
    _capture_token: object = dataclasses.field(repr=False)

    @property
    def path(self) -> Path:
        return self._cohort.path

    @property
    def architecture(self) -> str:
        return self._cohort.architecture

    def verify_unchanged(self) -> None:
        """Recheck the captured file identities; no signature check runs here."""
        if self._capture_token is not _CAPTURE_TOKEN:
            raise IosCohortError("expected a captured Simulator cohort")
        if _inspect_app(self._cohort.path) != self._cohort:
            raise IosCohortError("captured Simulator cohort identity changed")


def capture_ios_cohort(cohort_app: Path) -> CapturedIosCohort:
    """Capture original file identities around one OS signature verification.

    Nothing is installed or launched. The files must be identical before and
    after `codesign --verify`; later continuity checks compare files only.
    """
    cohort = _inspect_app(cohort_app)
    _verify_signature(cohort.path)
    if _inspect_app(cohort.path) != cohort:
        raise IosCohortError("Simulator cohort changed during capture")
    return CapturedIosCohort(cohort, _CAPTURE_TOKEN)
