"""Read-only Simulator artifact capture and strict native output validation.

No SDK/app launch or deletion API is exposed here. Captured files and receipts
are observations, not case/device ownership or source/build provenance.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
import sys
import uuid
from xml.parsers.expat import ExpatError

import e2e_runtime as runtime


_BUNDLE = "com.keplr.vizor"
_CAPTURE_TOKEN = object()
_HOST_PLATFORM = sys.platform
_MAX_EXECUTABLE = 64 * 1024 * 1024
_MAX_RECEIPT = 16_384


class IosCleanupError(runtime.RunnerError):
    """Simulator cleanup observations are unavailable or do not match."""


def _regular_bytes(path: Path, limit: int) -> tuple[bytes, tuple[int, int]]:
    if path.resolve(strict=True) != path:
        raise IosCleanupError("Simulator artifact path is not canonical")
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o022 or info.st_nlink != 1 or info.st_size > limit
        ):
            raise IosCleanupError("Simulator artifact file is not bounded, regular and owned")
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise IosCleanupError("Simulator artifact file exceeds its limit")
        return data, (info.st_dev, info.st_ino)


def _simulator_rights(data: bytes) -> tuple[str, dict]:
    """Read thin executable architecture, platform and embedded Simulator rights.

    Xcode's ad-hoc codesign entitlement dictionary can be empty. Never substitute
    that empty dictionary for the Mach-O __TEXT,__entitlements rights.
    """
    if len(data) < 32 or len(data) > _MAX_EXECUTABLE:
        raise IosCleanupError("invalid Simulator executable size")
    magic, cpu, _, kind, count, size = struct.unpack_from("<6I", data)
    architecture = {0x0100000C: "arm64", 0x01000007: "x86_64"}.get(cpu)
    if magic != 0xFEEDFACF or architecture is None or kind != 2 or not 0 < count <= 4096:
        raise IosCleanupError("expected a thin 64-bit Simulator executable")
    if size > 1024 * 1024 or size > len(data) - 32:
        raise IosCleanupError("invalid Simulator load-command bounds")
    end, offset, payload, platform = 32 + size, 32, None, None
    for _ in range(count):
        if offset > end - 8:
            raise IosCleanupError("truncated Simulator load command")
        command, length = struct.unpack_from("<2I", data, offset)
        if length < 8 or length % 8 or length > end - offset:
            raise IosCleanupError("invalid Simulator load-command length")
        if command == 0x32:  # LC_BUILD_VERSION
            if length < 24 or platform is not None:
                raise IosCleanupError("ambiguous Simulator platform")
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        if command == 0x19:  # LC_SEGMENT_64
            if length < 72:
                raise IosCleanupError("truncated Simulator segment")
            sections = struct.unpack_from("<I", data, offset + 64)[0]
            if sections > (length - 72) // 80:
                raise IosCleanupError("truncated Simulator section table")
            segment = data[offset + 8:offset + 24].rstrip(b"\0")
            for index in range(sections):
                section = offset + 72 + 80 * index
                name = data[section:section + 16].rstrip(b"\0")
                owner = data[section + 16:section + 32].rstrip(b"\0")
                if name == b"__entitlements" and owner == segment == b"__TEXT":
                    amount = struct.unpack_from("<Q", data, section + 40)[0]
                    start = struct.unpack_from("<I", data, section + 48)[0]
                    if payload is not None or not 0 < amount <= 16_384 or start < end or start > len(data) - amount:
                        raise IosCleanupError("invalid Simulator entitlement bounds")
                    payload = data[start:start + amount]
        offset += length
    if offset != end or platform != 7 or payload is None:  # PLATFORM_IOSSIMULATOR
        raise IosCleanupError("missing Simulator platform or embedded access rights")
    try:
        rights = plistlib.loads(payload)
    except (ValueError, TypeError, plistlib.InvalidFileException, ExpatError) as error:
        raise IosCleanupError("invalid Simulator access-right plist") from error
    if not isinstance(rights, dict):
        raise IosCleanupError("Simulator access rights must be a dictionary")
    return architecture, rights


def _application_identifier(rights: dict, *, helper: bool) -> str:
    identifier = rights.get("application-identifier")
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Z0-9]{10}\.com\.keplr\.vizor", identifier):
        raise IosCleanupError("invalid Simulator application identifier")
    if rights.get("com.apple.developer.team-identifier", identifier[:10]) != identifier[:10]:
        raise IosCleanupError("Simulator team does not match application identifier")
    if rights.get("keychain-access-groups", [identifier]) != [identifier]:
        raise IosCleanupError("Simulator artifact has extra Keychain access groups")
    allowed = {
        "application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups",
        "get-task-allow", "com.apple.security.get-task-allow",
    }
    if helper and not set(rights) <= allowed:
        raise IosCleanupError("Simulator helper has unexpected access rights")
    for key in ("get-task-allow", "com.apple.security.get-task-allow"):
        if key in rights and type(rights[key]) is not bool:
            raise IosCleanupError("Simulator debug access flag must be boolean")
    return identifier


def _codesign(*arguments: str) -> subprocess.CompletedProcess:
    try:
        result = subprocess.run(
            ["/usr/bin/codesign", *arguments], capture_output=True, timeout=15, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise IosCleanupError("cannot inspect Simulator artifact signature") from error
    if result.returncode != 0:
        raise IosCleanupError("Simulator artifact signature inspection failed")
    return result


@dataclasses.dataclass(frozen=True)
class _SimulatorApp:
    path: Path
    executable: Path
    application_identifier: str
    architecture: str
    files: tuple[tuple[str, int, int, str], ...]
    directory_ids: tuple[tuple[int, int], ...]


def _inspect_app(path: Path, *, helper: bool) -> _SimulatorApp:
    if _HOST_PLATFORM != "darwin":
        raise IosCleanupError("Simulator artifact capture requires macOS")
    if not isinstance(path, Path) or not path.is_absolute() or path.suffix != ".app":
        raise IosCleanupError("expected an absolute Simulator app bundle")
    try:
        directories = (path, path / "_CodeSignature")
        identities = []
        for directory in directories:
            info = directory.lstat()
            if (
                not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o022 or directory.resolve(strict=True) != directory
            ):
                raise IosCleanupError("Simulator artifact directory is not canonical and owned")
            identities.append((info.st_dev, info.st_ino))
        info_bytes, info_identity = _regular_bytes(path / "Info.plist", 64 * 1024)
        info = plistlib.loads(info_bytes)
        if not isinstance(info, dict):
            raise IosCleanupError("Simulator artifact Info.plist must be a dictionary")
        name = info.get("CFBundleExecutable")
        marker = "VizorE2eIosCleanup" if helper else "VizorE2eIosCohort"
        if (
            info.get("CFBundleIdentifier") != _BUNDLE or info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"]
            or info.get(marker) is not True or not isinstance(name, str)
            or not re.fullmatch(r"[A-Za-z0-9_-]+", name)
            or (helper and name != "vizor-ios-cleanup")
            or (not helper and name in {"vizor-ios-cleanup", "vizor-ios-cleanup-smoke"})
        ):
            raise IosCleanupError("Simulator artifact role/build identity mismatch")
        executable = path / name
        if not os.access(executable, os.X_OK):
            raise IosCleanupError("Simulator artifact is not executable")
        files = [(str(path / "Info.plist"), *info_identity, hashlib.sha256(info_bytes).hexdigest())]
        for file, limit in ((executable, _MAX_EXECUTABLE),
                            (path / "_CodeSignature/CodeResources", 4 * 1024 * 1024)):
            content, (device, inode) = _regular_bytes(file, limit)
            files.append((str(file), device, inode, hashlib.sha256(content).hexdigest()))
            if file == executable:
                architecture, rights = _simulator_rights(content)
        identifier = _application_identifier(rights, helper=helper)
        _codesign("--verify", "--strict", "--deep", str(path))
        metadata = _codesign("--display", "--verbose=4", str(path)).stderr.decode("utf-8")
        fields = {}
        for line in metadata.splitlines():
            if line.startswith(("Identifier=", "Signature=", "TeamIdentifier=")):
                key, value = line.split("=", 1)
                if key in fields:
                    raise IosCleanupError("ambiguous Simulator signature metadata")
                fields[key] = value
        # This isolated build contract uses Xcode's Sign to Run Locally. The
        # embedded application identifier, not an ad-hoc certificate/team field,
        # declares the Simulator's default Keychain identity.
        if fields != {"Identifier": _BUNDLE, "Signature": "adhoc", "TeamIdentifier": "not set"}:
            raise IosCleanupError("expected the ad-hoc Simulator build signature")
        signed_data = _codesign("--display", "--entitlements", "-", "--xml", str(path)).stdout
        # codesign documents empty output when the signature has no entitlement
        # blob (not an error). Embedded Simulator rights remain mandatory.
        signed_rights = {} if signed_data == b"" else plistlib.loads(signed_data)
        if not isinstance(signed_rights, dict) or (signed_rights and signed_rights != rights):
            raise IosCleanupError("signed and embedded Simulator access rights disagree")
        for file, device, inode, digest in files:
            content, identity = _regular_bytes(Path(file), _MAX_EXECUTABLE)
            if identity != (device, inode) or hashlib.sha256(content).hexdigest() != digest:
                raise IosCleanupError("Simulator artifact changed during capture")
        for directory, identity in zip(directories, identities):
            info = directory.lstat()
            if (
                (info.st_dev, info.st_ino) != identity or not stat.S_ISDIR(info.st_mode)
                or info.st_uid != os.getuid() or info.st_mode & 0o022
                or directory.resolve(strict=True) != directory
            ):
                raise IosCleanupError("Simulator artifact directory changed during capture")
        return _SimulatorApp(path, executable, identifier, architecture, tuple(files), tuple(identities))
    except IosCleanupError:
        raise
    except (OSError, ValueError, TypeError, UnicodeError, plistlib.InvalidFileException, ExpatError) as error:
        raise IosCleanupError("Simulator artifact capture failed") from error


@dataclasses.dataclass(frozen=True)
class CapturedIosCleanupHelper:
    """Read-only capture; builder supplies trusted sources, never arbitrary apps."""

    _helper: _SimulatorApp = dataclasses.field(repr=False)
    _cohort: _SimulatorApp = dataclasses.field(repr=False)
    _capture_token: object = dataclasses.field(repr=False)

    @property
    def application_identifier(self) -> str:
        return self._cohort.application_identifier

    @property
    def team(self) -> str:
        return self.application_identifier[:10]

    @property
    def architecture(self) -> str:
        return self._cohort.architecture

    def verify_unchanged(self) -> None:
        if self._capture_token is not _CAPTURE_TOKEN:
            raise IosCleanupError("expected a captured Simulator cleanup helper")
        for app, helper in ((self._helper, True), (self._cohort, False)):
            if _inspect_app(app.path, helper=helper) != app:
                raise IosCleanupError("captured Simulator artifact identity changed")


def capture_ios_cleanup_helper(helper_app: Path, *, cohort_app: Path) -> CapturedIosCleanupHelper:
    """Capture original signed file identities without running/installing an app."""
    helper = _inspect_app(helper_app, helper=True)
    cohort = _inspect_app(cohort_app, helper=False)
    if (
        helper.path == cohort.path or helper.application_identifier != cohort.application_identifier
        or helper.architecture != cohort.architecture
    ):
        raise IosCleanupError("Simulator helper does not match actual cohort identity/architecture")
    return CapturedIosCleanupHelper(helper, cohort, _CAPTURE_TOKEN)


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise IosCleanupError("Simulator cleanup receipt has duplicate fields")
        result[key] = value
    return result


def _fields(value: object, expected: set[str]) -> dict:
    if not isinstance(value, dict) or set(value) != expected:
        raise IosCleanupError("Simulator cleanup receipt fields are invalid")
    return value


def _services(namespace: str) -> list[str]:
    wallet = f"com.keplr.vizor.regtest.secure_store.e2e.{namespace}"
    return [wallet, wallet + ".accessibility-migration-v1",
            f"com.zcash.wallet.biometric-unlock.e2e.{namespace}",
            f"com.keplr.vizor.ironwood-migration-background.v1.e2e.{namespace}",
            f"com.keplr.vizor.ironwood-migration-outbox-key.v1.e2e.{namespace}"]


def _validate_receipt(lines: tuple[str, ...], *, namespace: str, udid: str,
                      owner_nonce: str, application_identifier: str, mode: str) -> None:
    """Validate complete captured output; never use external JSON as authority."""
    try:
        match = re.fullmatch(r"vizor_[0-9a-f]{10}_w(0|[1-9][0-9]{0,6})_(0|[1-9][0-9]{0,6})", namespace)
        if (
            match is None or any(int(index) > 1_000_000 for index in match.groups())
            or str(uuid.UUID(udid)).upper() != udid
            or not re.fullmatch(r"[0-9a-f]{16}", owner_nonce)
            or not re.fullmatch(r"[A-Z0-9]{10}\.com\.keplr\.vizor", application_identifier)
            or mode not in {"verify", "delete"}
        ):
            raise IosCleanupError("invalid expected Simulator observation scope")
        text = "".join(lines)
        if len(text.encode("utf-8")) > _MAX_RECEIPT:
            raise IosCleanupError("Simulator cleanup receipt exceeds its limit")
        value = _fields(json.loads(text, object_pairs_hook=_unique_object), {
            "schema_version", "platform", "mode", "namespace", "simulator_udid", "owner_nonce",
            "expected_team", "keychain_scope", "identity", "keychain", "preferences", "notifications", "completed",
        })
        expected = {
            "schema_version": 1, "platform": "ios", "mode": mode, "namespace": namespace,
            "simulator_udid": udid, "owner_nonce": owner_nonce, "expected_team": application_identifier[:10],
            "keychain_scope": "application_accessible", "completed": True,
        }
        if type(value["schema_version"]) is not int or value["completed"] is not True or any(value[key] != item for key, item in expected.items()):
            raise IosCleanupError("Simulator cleanup receipt does not match this launch")
        identity = _fields(value["identity"], {"bundle_id", "simulator_udid", "cleanup_build_marker", "application_identifier"})
        if identity != {"bundle_id": _BUNDLE, "simulator_udid": udid,
                        "cleanup_build_marker": True, "application_identifier": application_identifier} or identity["cleanup_build_marker"] is not True:
            raise IosCleanupError("Simulator cleanup receipt identity mismatch")
        if not isinstance(value["keychain"], list) or len(value["keychain"]) != 5:
            raise IosCleanupError("incomplete Simulator Keychain observations")
        for observed, service in zip(value["keychain"], _services(namespace)):
            fields = {"service", "before_status", "after_status"} | ({"delete_status"} if mode == "delete" else set())
            item = _fields(observed, fields)
            if (
                item["service"] != service or any(type(item[key]) is not int for key in fields - {"service"})
                or item["before_status"] not in ((0, -25300) if mode == "delete" else (-25300,))
                or (mode == "delete" and item["delete_status"] not in (0, -25300)) or item["after_status"] != -25300
            ):
                raise IosCleanupError("Simulator Keychain absence is unproven")
        if not isinstance(value["preferences"], list) or len(value["preferences"]) != 2:
            raise IosCleanupError("incomplete Simulator preference observations")
        for observed, domain, prefix in zip(value["preferences"], [_BUNDLE, f"{_BUNDLE}.regtest.e2e.{namespace}"],
                                            [f"flutter.vizor_e2e_{namespace}.", None]):
            # Swift omits an optional nil prefix for the dedicated suite.
            fields = {"domain", "before_count", "removed_count", "after_count", "synchronized"} | ({"prefix"} if prefix is not None else set())
            item = _fields(observed, fields)
            if (
                item["domain"] != domain or item.get("prefix") != prefix
                or any(type(item[key]) is not int for key in ("before_count", "removed_count", "after_count"))
                or item["before_count"] < 0 or (mode == "verify" and item["before_count"] != 0)
                or item["removed_count"] != item["before_count"] or item["after_count"] != 0
                or item["synchronized"] is not True
            ):
                raise IosCleanupError("Simulator preference absence is unproven")
        notifications = _fields(value["notifications"], {
            "prefix", "pending_before_count", "delivered_before_count", "pending_removed_count",
            "delivered_removed_count", "pending_after_count", "delivered_after_count",
        })
        if notifications["prefix"] != f"vizor_e2e_{namespace}.":
            raise IosCleanupError("Simulator notification scope mismatch")
        for kind in ("pending", "delivered"):
            before, removed, after = (notifications[f"{kind}_{part}_count"] for part in ("before", "removed", "after"))
            if any(type(item) is not int for item in (before, removed, after)) or before < 0 or (mode == "verify" and before != 0) or removed != before or after != 0:
                raise IosCleanupError("Simulator notification absence is unproven")
    except IosCleanupError:
        raise
    except (ValueError, TypeError, KeyError, UnicodeError, RecursionError, AttributeError) as error:
        raise IosCleanupError("invalid Simulator cleanup receipt") from error
