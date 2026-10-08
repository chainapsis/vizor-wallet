"""Fresh case-owned iOS simulators; no device adoption or native app cleanup."""

from __future__ import annotations

import dataclasses
import json
import math
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import threading
import time
import uuid

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle


_HOST_PLATFORM = sys.platform
_OWNERSHIP_TOKEN = object()
_INTENT = "simulator-allocation.json"
_OWNER = "simulator-owner.json"
_RUNTIME_RE = re.compile(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+)*\Z")
_DEVICE_RE = re.compile(r"com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\Z")


class NativeSimulatorError(runtime.RunnerError):
    """Simulator ownership, readiness, or teardown could not be proven."""


def _deadline(timeout: float) -> float:
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise NativeSimulatorError("timeout must be positive and finite")
    return time.monotonic() + timeout


def _encode(value: dict) -> bytes:
    return (json.dumps(value, ensure_ascii=True, sort_keys=True) + "\n").encode("ascii")


def _identity(descriptor: int) -> tuple[int, int]:
    details = os.fstat(descriptor)
    if (
        not stat.S_ISREG(details.st_mode) or details.st_uid != os.getuid()
        or details.st_mode & 0o077 or details.st_nlink != 1
    ):
        raise NativeSimulatorError("simulator metadata must be private, regular and owned")
    return details.st_dev, details.st_ino


def _publish(path: Path, payload: bytes) -> tuple[int, int]:
    with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "wb") as stream:
        identity = _identity(stream.fileno())
        stream.write(payload)
        stream.flush()
        return identity


def _verify_file(path: Path, payload: bytes, identity: tuple[int, int]) -> None:
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        if _identity(stream.fileno()) != identity or stream.read(len(payload) + 1) != payload:
            raise NativeSimulatorError("simulator owner metadata changed")


def _udid(value: object) -> str:
    if not isinstance(value, str):
        raise NativeSimulatorError("simctl returned an invalid device UUID")
    try:
        parsed = str(uuid.UUID(value)).upper()
    except ValueError as error:
        raise NativeSimulatorError("simctl returned an invalid device UUID") from error
    if value.upper() != parsed:
        raise NativeSimulatorError("simctl device UUID must have canonical syntax")
    return parsed


def _devices(raw: dict) -> dict[str, tuple[str, dict]]:
    groups = raw.get("devices")
    if not isinstance(groups, dict):
        raise NativeSimulatorError("invalid simulator device inventory")
    inventory = {}
    for identifier, entries in groups.items():
        if not isinstance(identifier, str) or not isinstance(entries, list):
            raise NativeSimulatorError("invalid simulator device inventory")
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("name"), str):
                raise NativeSimulatorError("invalid simulator device inventory")
            device = _udid(entry.get("udid"))
            if device in inventory:
                raise NativeSimulatorError("duplicate simulator device identity")
            inventory[device] = (identifier, entry)
    return inventory


@dataclasses.dataclass
class _Commands:
    case: NativeCaseLifecycle
    nonce: str
    count: int = 0
    unproven_commands: list[str] = dataclasses.field(default_factory=list)

    def run(self, arguments: list[str], *, deadline: float, cancel_event: threading.Event) -> str:
        self.case.workspace.verify_owned()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NativeSimulatorError("simulator operation timed out", 124)
        log = self.case.workspace.root / f"simulator-{self.nonce}-{self.count:04d}.log"
        self.count += 1
        os.close(os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600))
        try:
            result = runtime.run_logged_command(
                ["/usr/bin/xcrun", "simctl", *arguments], cwd=self.case.workspace.root,
                env={key: value for key, value in os.environ.items() if not key.startswith("SIMCTL_CHILD_")},
                log_path=log, timeout=remaining, cancel_event=cancel_event,
            )
        except BaseException as error:
            # The convenience runner returns no handle on failure. We cannot
            # infer child/group/output cleanup from an exception alone.
            self.unproven_commands.append(f"{arguments[0]}: {type(error).__name__}: {error}")
            raise
        if result.returncode != 0:
            raise NativeSimulatorError(
                f"simctl {arguments[0]} failed ({result.returncode}); see {log.name}", result.returncode,
            )
        return "".join(result.lines)

    def inventory(self, kind: str, *, deadline: float, cancel_event: threading.Event) -> dict:
        try:
            raw = json.loads(self.run(["list", kind, "--json"], deadline=deadline, cancel_event=cancel_event))
        except (ValueError, UnicodeError) as error:
            raise NativeSimulatorError(f"invalid simctl {kind} JSON") from error
        if not isinstance(raw, dict):
            raise NativeSimulatorError(f"invalid simctl {kind} inventory")
        return raw


@dataclasses.dataclass(frozen=True)
class SimulatorCleanup:
    """Deletion of a fresh pre-app device, NOT native wallet cleanup evidence."""

    namespace: str
    udid: str
    runtime_identifier: str


@dataclasses.dataclass
class _State:
    ownership_error: str | None = None
    cleanup_errors: list[str] = dataclasses.field(default_factory=list)
    receipt: SimulatorCleanup | None = None


@dataclasses.dataclass(frozen=True)
class OwnedIosSimulator:
    """Use acquire_ios_simulator(); operations are cooperative and single-owner."""

    case: NativeCaseLifecycle
    name: str
    udid: str
    runtime_identifier: str
    device_type_identifier: str
    _commands: _Commands = dataclasses.field(repr=False)
    _intent_bytes: bytes = dataclasses.field(repr=False)
    _owner_bytes: bytes = dataclasses.field(repr=False)
    _marker_ids: tuple[tuple[int, int], tuple[int, int]] = dataclasses.field(repr=False)
    _state: _State = dataclasses.field(repr=False)
    _ownership_token: object = dataclasses.field(repr=False)

    def _owned_device(self, *, deadline: float, cancel_event: threading.Event) -> dict | None:
        if self._ownership_token is not _OWNERSHIP_TOKEN:
            raise NativeSimulatorError("expected a newly acquired simulator handle")
        if self._state.ownership_error is not None:
            raise NativeSimulatorError(self._state.ownership_error)
        try:
            self.case.workspace.verify_owned()
            expected = {
                "schema_version": 1, "namespace": self.case.workspace.namespace,
                "workspace": str(self.case.workspace.root), "name": self.name,
                "runtime_identifier": self.runtime_identifier, "device_type_identifier": self.device_type_identifier,
                "owner_nonce": self._commands.nonce, "udid": self.udid,
            }
            if self._commands.case is not self.case or self._owner_bytes != _encode(expected):
                raise NativeSimulatorError("simulator handle identity changed")
            for name, payload, identity in (
                (_INTENT, self._intent_bytes, self._marker_ids[0]),
                (_OWNER, self._owner_bytes, self._marker_ids[1]),
            ):
                _verify_file(self.case.workspace.root / name, payload, identity)
            entry = _devices(self._commands.inventory("devices", deadline=deadline, cancel_event=cancel_event)).get(self.udid)
            if entry is None:
                return None
            identifier, device = entry
            if (
                identifier != self.runtime_identifier or device.get("name") != self.name
                or device.get("deviceTypeIdentifier") != self.device_type_identifier
                or device.get("isAvailable") is not True
            ):
                raise NativeSimulatorError("created simulator identity changed")
            return device
        except (OSError, ValueError, RuntimeError, KeyboardInterrupt) as error:
            self._state.ownership_error = f"simulator ownership unproven: {error}"
            if isinstance(error, (runtime.Cancelled, KeyboardInterrupt)):
                raise
            raise NativeSimulatorError(self._state.ownership_error, getattr(error, "exit_code", 1)) from error

    def boot(self, *, timeout: float = 120.0, cancel_event: threading.Event | None = None) -> None:
        deadline = _deadline(timeout)
        if self._state.receipt is not None or not self.case.accepting_launches or self._commands.unproven_commands:
            raise NativeSimulatorError("simulator lifecycle is closed")
        cancellation = cancel_event if cancel_event is not None else threading.Event()
        device = self._owned_device(deadline=deadline, cancel_event=cancellation)
        if device is None:
            self._state.ownership_error = "owned simulator disappeared before boot"
            raise NativeSimulatorError(self._state.ownership_error)
        if device.get("state") == "Shutdown":
            self._commands.run(["boot", self.udid], deadline=deadline, cancel_event=cancellation)
        elif device.get("state") != "Booted":
            raise NativeSimulatorError("owned simulator is not in a bootable state")
        self._commands.run(["bootstatus", self.udid], deadline=deadline, cancel_event=cancellation)
        current = self._owned_device(deadline=deadline, cancel_event=cancellation)
        if current is None or current.get("state") != "Booted":
            raise NativeSimulatorError("owned simulator boot readiness was not proven")

    def close(self, *, timeout: float = 30.0) -> SimulatorCleanup:
        """Close case groups with their default per-group budget, then bound simctl.

        The timeout covers simulator commands, not an aggregate process budget.
        Any case launch retains the device until native cleanup is implemented.
        """
        _deadline(timeout)  # Validate before process or simulator mutations.
        if self._ownership_token is not _OWNERSHIP_TOKEN:
            raise NativeSimulatorError("expected a newly acquired simulator handle")
        if self._state.receipt is not None:
            return self._state.receipt
        if self._commands.unproven_commands:
            self._state.cleanup_errors.append("simctl process cleanup unproven: " + "; ".join(self._commands.unproven_commands))
        cancellation = threading.Event()  # Teardown must not inherit execution cancellation.
        primary = None
        try:
            process_cleanup = self.case.close()
            if process_cleanup.exit_codes:
                raise NativeSimulatorError("case launches exist; native state cleanup is unimplemented; simulator retained")
        except BaseException as error:
            self._state.cleanup_errors.append(f"case teardown: {type(error).__name__}: {error}")
            if not isinstance(error, Exception):
                primary = error
        deadline = _deadline(timeout)
        try:
            device = self._owned_device(deadline=deadline, cancel_event=cancellation)
            if device is None:
                raise NativeSimulatorError("owned simulator is missing without completed deletion proof")
            if device.get("state") != "Shutdown":
                self._commands.run(["shutdown", self.udid], deadline=deadline, cancel_event=cancellation)
                while True:
                    device = self._owned_device(deadline=deadline, cancel_event=cancellation)
                    if device is None:
                        raise NativeSimulatorError("owned simulator disappeared before shutdown proof")
                    if device.get("state") == "Shutdown":
                        break
                    time.sleep(min(0.1, max(0.0, deadline - time.monotonic())))
            if device.get("state") != "Shutdown":
                raise NativeSimulatorError("owned simulator shutdown was not proven")
            if not self._state.cleanup_errors:
                self._commands.run(["delete", self.udid], deadline=deadline, cancel_event=cancellation)
                if self._owned_device(deadline=deadline, cancel_event=cancellation) is not None:
                    raise NativeSimulatorError("owned simulator still exists after delete")
        except BaseException as error:
            self._state.cleanup_errors.append(f"device teardown: {type(error).__name__}: {error}")
            if not isinstance(error, Exception) and primary is None:
                primary = error
        if primary is not None:
            raise primary
        if self._state.cleanup_errors:
            raise NativeSimulatorError("simulator cleanup unproven: " + "; ".join(self._state.cleanup_errors))
        self._state.receipt = SimulatorCleanup(self.case.workspace.namespace, self.udid, self.runtime_identifier)
        return self._state.receipt


def acquire_ios_simulator(
    case: NativeCaseLifecycle,
    *,
    runtime_identifier: str,
    device_type_identifier: str,
    timeout: float = 30.0,
    cancel_event: threading.Event | None = None,
) -> OwnedIosSimulator:
    """Create, never adopt; retain incomplete allocation evidence after failure.

    Runtime/type selection is explicit and checked against installed support.
    No app is installed or launched. Any case launch prevents device deletion
    until a future native-state cleanup implementation supplies real proof.
    """
    if _HOST_PLATFORM != "darwin":
        raise NativeSimulatorError("iOS simulator allocation requires a macOS host")
    deadline = _deadline(timeout)
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches:
        raise NativeSimulatorError("expected an open owned case lifecycle")
    manifest = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    if not manifest["scenario_id"].startswith("flutter.ios.") or manifest["context_path"] != "app-support":
        raise NativeSimulatorError("simulator allocation requires an iOS case")
    if (
        not isinstance(runtime_identifier, str) or not _RUNTIME_RE.fullmatch(runtime_identifier)
        or not isinstance(device_type_identifier, str) or not _DEVICE_RE.fullmatch(device_type_identifier)
    ):
        raise NativeSimulatorError("explicit iOS runtime and device type identifiers are required")
    commands = _Commands(case, secrets.token_hex(8))
    cancellation = cancel_event if cancel_event is not None else threading.Event()
    runtimes = commands.inventory("runtimes", deadline=deadline, cancel_event=cancellation).get("runtimes")
    if not isinstance(runtimes, list):
        raise NativeSimulatorError("invalid iOS runtime inventory")
    matches = [item for item in runtimes if isinstance(item, dict) and item.get("identifier") == runtime_identifier]
    if len(matches) != 1 or matches[0].get("platform") != "iOS" or matches[0].get("isAvailable") is not True:
        raise NativeSimulatorError("selected iOS runtime is not uniquely available")
    supported = matches[0].get("supportedDeviceTypes")
    if not isinstance(supported, list) or not any(isinstance(item, dict) and item.get("identifier") == device_type_identifier for item in supported):
        raise NativeSimulatorError("selected device type is not supported by the iOS runtime")
    before = _devices(commands.inventory("devices", deadline=deadline, cancel_event=cancellation))
    name = f"Vizor E2E {case.workspace.namespace}"
    if any(device.get("name") == name for _, device in before.values()):
        raise NativeSimulatorError("case simulator name already exists; it cannot be adopted")
    payload = {
        "schema_version": 1, "namespace": case.workspace.namespace, "workspace": str(case.workspace.root),
        "name": name, "runtime_identifier": runtime_identifier, "device_type_identifier": device_type_identifier,
        "owner_nonce": commands.nonce,
    }
    intent = _encode(payload)
    created = None
    try:
        intent_id = _publish(case.workspace.root / _INTENT, intent)
        created = _udid(commands.run(["create", name, device_type_identifier, runtime_identifier], deadline=deadline, cancel_event=cancellation).strip())
        if created in before:
            raise NativeSimulatorError("simctl create returned a pre-existing device; it cannot be adopted")
        owner = _encode({**payload, "udid": created})
        owner_id = _publish(case.workspace.root / _OWNER, owner)
        simulator = OwnedIosSimulator(
            case, name, created, runtime_identifier, device_type_identifier, commands,
            intent, owner, (intent_id, owner_id), _State(), _OWNERSHIP_TOKEN,
        )
        device = simulator._owned_device(deadline=deadline, cancel_event=cancellation)
        if device is None or device.get("state") != "Shutdown":
            raise NativeSimulatorError("new simulator was not verified in Shutdown state")
        return simulator
    except (OSError, ValueError, RuntimeError) as error:
        if isinstance(error, runtime.Cancelled):
            raise
        raise NativeSimulatorError(
            f"simulator allocation failed; existing/partial state retained (created UUID: {created or 'unproven'}): {error}",
            getattr(error, "exit_code", 1),
        ) from error
