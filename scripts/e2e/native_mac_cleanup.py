"""Bind a signed macOS cleanup helper's observations to one sealed owned case.

No filesystem deletion, app/context rewriting, simulator cleanup or report
recovery. The future artifact builder remains responsible for compiling these
trusted helper sources and the cohort profile; signing alone is not source
provenance. Handles and receipts are cooperative observations, not permissions.
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
import subprocess
import sys
import tempfile
import threading

import e2e_runtime as runtime
from native_case_lifecycle import CaseProcessCleanup, NativeCaseLifecycle


_CAPTURE_TOKEN = object()
_BUNDLE_ID = "com.keplr.vizor"
_TEAM = re.compile(r"[A-Z0-9]{10}\Z")
_MAX_RECEIPT_BYTES = 8192


class MacCleanupError(runtime.RunnerError):
    """Native cleanup is unproven; keep case state and failure evidence."""


@dataclasses.dataclass(frozen=True)
class _SignedApp:
    path: Path
    executable: Path
    team: str
    certificate_sha256: str
    profile_sha256: str
    entitlement_keys: frozenset[str]
    files: tuple[tuple[str, int, int, str], ...]
    directory_ids: tuple[tuple[int, int], ...]


@dataclasses.dataclass(frozen=True)
class CapturedMacCleanupHelper:
    """Use capture_mac_cleanup_helper(); never adopt caller-supplied identity."""

    _helper: _SignedApp = dataclasses.field(repr=False)
    _cohort: _SignedApp = dataclasses.field(repr=False)
    _capture_token: object = dataclasses.field(repr=False)

    @property
    def team(self) -> str:
        return self._cohort.team

    @property
    def executable(self) -> Path:
        return self._helper.executable

    @property
    def cohort_executable(self) -> Path:
        return self._cohort.executable

    def verify_unchanged(self) -> None:
        if self._capture_token is not _CAPTURE_TOKEN:
            raise MacCleanupError("expected a captured macOS cleanup helper")
        for captured in (self._helper, self._cohort):
            if _inspect_signed_app(captured.path) != captured:
                raise MacCleanupError("captured native artifact identity changed")


@dataclasses.dataclass(frozen=True)
class CaseMacCleanupObservation:
    """Historical helper/process observations, NOT wallet/run deletion authority."""

    namespace: str
    workspace: str
    helper_executable_sha256: str
    team: str
    process_cleanup: CaseProcessCleanup


def _regular_bytes(path: Path) -> tuple[bytes, tuple[int, int]]:
    if path.resolve(strict=True) != path:
        raise MacCleanupError("native artifact file is not canonical")
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        details = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(details.st_mode) or details.st_uid != os.getuid()
            or details.st_mode & 0o022 or details.st_nlink != 1
        ):
            raise MacCleanupError("native artifact file is not owned and regular")
        return stream.read(), (details.st_dev, details.st_ino)


def _codesign(*arguments: str) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(
            ["/usr/bin/codesign", *arguments], capture_output=True, timeout=15, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise MacCleanupError("cannot inspect native artifact signing") from error
    if result.returncode != 0:
        raise MacCleanupError("native artifact signing inspection failed")
    return result


def _inspect_signed_app(path: Path) -> _SignedApp:
    """Read actual OS signature/entitlements and public certificate, never defaults."""
    if sys.platform != "darwin":
        raise MacCleanupError("macOS native cleanup requires a macOS host")
    if not isinstance(path, Path) or not path.is_absolute() or path.suffix != ".app":
        raise MacCleanupError("native artifact must be an absolute app bundle")
    try:
        info_path = path / "Contents/Info.plist"
        info_bytes, _ = _regular_bytes(info_path)
        info = plistlib.loads(info_bytes)
        if not isinstance(info, dict):
            raise MacCleanupError("native artifact Info.plist is not a dictionary")
        name = info.get("CFBundleExecutable")
        if (
            info.get("CFBundleIdentifier") != _BUNDLE_ID
            or not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", name)
        ):
            raise MacCleanupError("native artifact bundle identity is invalid")
        executable = path / "Contents/MacOS" / name
        directories = (path, path / "Contents", executable.parent)
        directory_ids = []
        for directory in directories:
            details = directory.lstat()
            if (
                not stat.S_ISDIR(details.st_mode) or details.st_uid != os.getuid()
                or details.st_mode & 0o022 or directory.resolve(strict=True) != directory
            ):
                raise MacCleanupError("native artifact directory identity is invalid")
            directory_ids.append((details.st_dev, details.st_ino))
        files = []
        for file in (info_path, executable, path / "Contents/embedded.provisionprofile"):
            data, (device, inode) = _regular_bytes(file)
            files.append((str(file), device, inode, hashlib.sha256(data).hexdigest()))
        if not os.access(executable, os.X_OK):
            raise MacCleanupError("native artifact executable is not executable")
        _codesign("--verify", "--strict", "--deep", str(path))
        metadata = _codesign("--display", "--verbose=4", str(path)).stderr.decode("utf-8")
        fields = {}
        for line in metadata.splitlines():
            if line.startswith(("TeamIdentifier=", "Identifier=")):
                key, value = line.split("=", 1)
                if key in fields:
                    raise MacCleanupError("native signature identity is ambiguous")
                fields[key] = value
        team = fields.get("TeamIdentifier", "")
        if not _TEAM.fullmatch(team) or fields.get("Identifier") != _BUNDLE_ID:
            raise MacCleanupError("native signature identity is invalid")
        entitlement_bytes = _codesign("--display", "--entitlements", "-", "--xml", str(path)).stdout
        entitlements = plistlib.loads(entitlement_bytes)
        application_id = f"{team}.{_BUNDLE_ID}"
        if (
            not isinstance(entitlements, dict)
            or entitlements.get("com.apple.security.app-sandbox") is not True
            or entitlements.get("com.apple.developer.team-identifier") != team
            or entitlements.get("com.apple.application-identifier") != application_id
            or entitlements.get("keychain-access-groups") not in (None, [application_id])
        ):
            raise MacCleanupError("native artifact entitlements do not match its identity")
        # codesign exports public DER only into a directory this call creates.
        with tempfile.TemporaryDirectory(prefix="vizor-signing-observation-") as temporary:
            prefix = Path(temporary).resolve() / "certificate"
            _codesign("--display", f"--extract-certificates={prefix}", str(path))
            certificate, _ = _regular_bytes(Path(f"{prefix}0"))
            if not certificate:
                raise MacCleanupError("native artifact has no signing certificate")
        # Catch replacements/rewrites during the signing observation itself.
        for file, device, inode, digest in files:
            current, identity = _regular_bytes(Path(file))
            if identity != (device, inode) or hashlib.sha256(current).hexdigest() != digest:
                raise MacCleanupError("native artifact changed during capture")
        return _SignedApp(
            path, executable, team, hashlib.sha256(certificate).hexdigest(),
            files[2][3], frozenset(entitlements), tuple(files), tuple(directory_ids),
        )
    except MacCleanupError:
        raise
    except (OSError, ValueError, TypeError, AttributeError, plistlib.InvalidFileException) as error:
        raise MacCleanupError("native artifact identity inspection failed") from error


def capture_mac_cleanup_helper(helper_app: Path, *, cohort_app: Path) -> CapturedMacCleanupHelper:
    """Capture compiled trusted helper + actual cohort signing, without launching.

    The builder must supply its own background-only helper, not another wallet
    app or arbitrary executable. This boundary is not a build/cache publisher.
    """
    helper = _inspect_signed_app(helper_app)
    cohort = _inspect_signed_app(cohort_app)
    info, _ = _regular_bytes(helper_app / "Contents/Info.plist")
    if (
        plistlib.loads(info).get("LSBackgroundOnly") is not True
        or helper_app == cohort_app or helper.executable.name != "vizor-native-cleanup"
    ):
        raise MacCleanupError("cleanup requires a distinct background-only vizor-native-cleanup helper")
    if not helper.entitlement_keys <= {
        "com.apple.security.app-sandbox", "com.apple.application-identifier",
        "com.apple.developer.team-identifier", "keychain-access-groups",
    }:
        raise MacCleanupError("cleanup helper has unexpected entitlements")
    if (
        helper.team != cohort.team or helper.certificate_sha256 != cohort.certificate_sha256
        or helper.profile_sha256 != cohort.profile_sha256
    ):
        raise MacCleanupError("cleanup helper does not match actual cohort signing")
    return CapturedMacCleanupHelper(helper, cohort, _CAPTURE_TOKEN)


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise MacCleanupError("native cleanup receipt contains duplicate fields")
        result[key] = value
    return result


def _require_fields(value: object, fields: set[str]) -> dict:
    if not isinstance(value, dict) or set(value) != fields:
        raise MacCleanupError("native cleanup receipt fields are invalid")
    return value


def _validate_receipt(lines: tuple[str, ...], *, namespace: str, team: str, mode: str = "delete") -> None:
    if mode not in ("delete", "verify"):
        raise MacCleanupError("invalid expected native cleanup observation mode")
    try:
        text = "".join(lines)
        if len(text.encode("utf-8")) > _MAX_RECEIPT_BYTES:
            raise MacCleanupError("native cleanup receipt exceeds its limit")
        receipt = _require_fields(json.loads(text, object_pairs_hook=_unique_object), {
            "schema_version", "platform", "mode", "namespace", "expected_team",
            "identity", "keychain", "preferences", "completed",
        })
        if (
            type(receipt["schema_version"]) is not int or receipt["schema_version"] != 1
            or receipt["platform"] != "macos" or receipt["mode"] != mode
            or receipt["namespace"] != namespace or receipt["expected_team"] != team
            or receipt["completed"] is not True
        ):
            raise MacCleanupError("native cleanup receipt does not match this cleanup launch")
        identity = _require_fields(receipt["identity"], {"bundle_id", "team_id", "application_identifier"})
        if identity != {"bundle_id": _BUNDLE_ID, "team_id": team, "application_identifier": f"{team}.{_BUNDLE_ID}"}:
            raise MacCleanupError("native cleanup receipt signing identity does not match")
        services = [f"com.keplr.vizor.regtest.secure_store.e2e.{namespace}"]
        services.append(f"{services[0]}.mnemonic")
        if not isinstance(receipt["keychain"], list) or len(receipt["keychain"]) != 2:
            raise MacCleanupError("native cleanup Keychain observations are incomplete")
        for observed, service in zip(receipt["keychain"], services):
            fields = {"service", "before_status", "after_status"}
            if mode == "delete":
                fields.add("delete_status")
            item = _require_fields(observed, fields)
            if (
                item["service"] != service
                or any(type(item[key]) is not int for key in fields - {"service"})
                or item["before_status"] not in ((0, -25300) if mode == "delete" else (-25300,))
                or (mode == "delete" and item["delete_status"] not in (0, -25300))
                or item["after_status"] != -25300
            ):
                raise MacCleanupError("native cleanup Keychain absence is unproven")
        preferences = _require_fields(receipt["preferences"], {
            "prefix", "before_count", "removed_count", "after_count", "synchronized",
        })
        if (
            preferences["prefix"] != f"flutter.vizor_e2e_{namespace}."
            or any(type(preferences[key]) is not int for key in ("before_count", "removed_count", "after_count"))
            or preferences["before_count"] < 0
            or (mode == "verify" and preferences["before_count"] != 0)
            or preferences["removed_count"] != preferences["before_count"]
            or preferences["after_count"] != 0 or preferences["synchronized"] is not True
        ):
            raise MacCleanupError("native cleanup preference absence is unproven")
    except MacCleanupError:
        raise
    except (ValueError, TypeError, KeyError, UnicodeError, RecursionError) as error:
        raise MacCleanupError("native cleanup receipt is invalid") from error


def clean_mac_case(
    case: NativeCaseLifecycle, helper: CapturedMacCleanupHelper, *,
    timeout: float, cancel_event: threading.Event,
) -> CaseMacCleanupObservation:
    """Stop/seal owned writers, run captured helper once, validate complete output.

    Never consume a context PID, external log/JSON, or cleanup boolean. Normal
    phase launches remain sealed. Partial/nonzero/ambiguous results raise and
    retain evidence; success does not remove support/workspace files or grant
    recovery/deletion permission. The case owner must track every native writer.
    """
    if not isinstance(case, NativeCaseLifecycle) or not isinstance(helper, CapturedMacCleanupHelper):
        raise MacCleanupError("cleanup requires an owned case and captured helper")
    case.workspace.verify_owned()
    if json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])["scenario_id"].split(".")[1] != "macos":
        raise MacCleanupError("macOS cleanup cannot adopt an iOS case")
    helper.verify_unchanged()
    result = case.run_final_command(
        [str(helper._helper.executable), "--namespace", case.workspace.namespace, "--team", helper.team],
        # Never inherit caller loader/user-domain overrides (DYLD_*, HOME,
        # CFFIXED_USER_HOME, etc.) that could redirect native observations.
        env={"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"},
        timeout=timeout, cancel_event=cancel_event,
    )
    if result.returncode != 0:
        raise MacCleanupError("native cleanup helper failed; retain case evidence", result.returncode)
    helper.verify_unchanged()
    _validate_receipt(result.lines, namespace=case.workspace.namespace, team=helper.team)
    process_cleanup = case.close()
    return CaseMacCleanupObservation(
        case.workspace.namespace, str(case.workspace.root), helper._helper.files[1][3],
        helper.team, process_cleanup,
    )
