"""Own one fresh Simulator's app/native lifecycle; never adopt user devices.

Successful scenarios compose cleanup internally; failed scenarios stop writers
and retain state. Native receipts/context/PIDs grant no independent authority.
"""

from __future__ import annotations

from collections.abc import Sequence
import contextlib
import dataclasses
import json
import os
from pathlib import Path
import pwd
import re
import stat
import threading
import time
import uuid

import e2e_runtime as runtime
from native_case_lifecycle import CaseProcessCleanup
import native_ios_cleanup as native
import native_ios_simulator as simulator_api


_TOKEN = object()
_BUNDLE = "com.keplr.vizor"
_MARKER = "ios-storage-owner.json"
_ENV = {"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"}


class IosCaseStorageError(runtime.RunnerError):
    """Owned app/native teardown is unproven; retain state and evidence."""


@dataclasses.dataclass(frozen=True)
class IosAppLaunch:
    """Historical owned SDK/app identity, not a global PID signalling target."""
    namespace: str
    udid: str
    pid: int
    console: runtime.ManagedProcess


@dataclasses.dataclass(frozen=True)
class IosCaseStorageCleanup:
    """Internally observed deletion, not scenario PASS or external authority."""
    namespace: str
    udid: str
    support_directory: str
    application_identifier: str
    process_cleanup: CaseProcessCleanup


def _home() -> Path:
    return Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(strict=True)


def _directory(stack: contextlib.ExitStack, path, *, dir_fd=None, allow_group_write=False) -> int:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dir_fd)
    stack.callback(os.close, descriptor)
    details = os.fstat(descriptor)
    forbidden = 0o002 if allow_group_write else 0o022
    if not stat.S_ISDIR(details.st_mode) or details.st_uid != os.getuid() or details.st_mode & forbidden:
        raise IosCaseStorageError("Simulator support directory is not canonical and owned")
    return descriptor


def _chain(stack, home: Path, path: Path, *, create: bool):
    if home.resolve(strict=True) != home or not home.is_absolute():
        raise IosCaseStorageError("Simulator home is not canonical")
    parts = path.relative_to(home).parts
    descriptor = _directory(stack, home)
    identities = []
    details = os.fstat(descriptor)
    identities.append((details.st_dev, details.st_ino))
    private_ancestor = not details.st_mode & 0o077
    for index, part in enumerate(parts):
        if create and index >= len(parts) - 3:
            try:
                os.mkdir(part, 0o700, dir_fd=descriptor)
            except FileExistsError:
                if index == len(parts) - 1:
                    raise IosCaseStorageError("pre-existing iOS support cases are never adopted")
        # CoreSimulator creates Devices/<UUID>/data group-writable. Do not
        # chmod SDK state or allow arbitrary writable ancestors. Only this
        # SDK component may be group-writable, behind an already opened owned
        # directory that denies all group/other traversal (normally Library).
        sdk_data = index == 5 and parts[:4] == ("Library", "Developer", "CoreSimulator", "Devices") and part == "data"
        descriptor = _directory(stack, part, dir_fd=descriptor,
                                allow_group_write=sdk_data and private_ancestor)
        details = os.fstat(descriptor)
        if index == len(parts) - 1 and details.st_mode & 0o077:
            raise IosCaseStorageError("case support directory must remain private")
        identities.append((details.st_dev, details.st_ino))
        private_ancestor = private_ancestor or not details.st_mode & 0o077
    return descriptor, tuple(identities)


def _read_file(directory: int, name: str, limit: int):
    with os.fdopen(os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory), "rb") as stream:
        info = os.fstat(stream.fileno())
        if (
            not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o022 or info.st_nlink != 1 or info.st_size > limit
        ):
            raise IosCaseStorageError("Simulator support file is not bounded, owned and regular")
        value = stream.read(limit + 1)
        if len(value) > limit:
            raise IosCaseStorageError("Simulator support file exceeds its limit")
        return value, (info.st_dev, info.st_ino)


def _app_jobs(text: str) -> list[int]:
    """Read documented launchctl list columns, not diagnostic print/procinfo text.

    UIKit application label syntax is a supported-SDK observation. Unexpected
    formats fail closed instead of converting an unknown listing to absence.
    """
    if len(text.encode("utf-8")) > 512 * 1024:
        raise IosCaseStorageError("Simulator job inventory exceeds its limit")
    lines = text.splitlines()
    if not lines or lines[0].split() != ["PID", "Status", "Label"]:
        raise IosCaseStorageError("Simulator job inventory header unavailable")
    pids, labels = [], set()
    for line in lines[1:]:
        fields = line.split()
        if len(fields) != 3 or not re.fullmatch(r"-|[1-9][0-9]*", fields[0]) or not re.fullmatch(r"-?[0-9]+", fields[1]):
            raise IosCaseStorageError("invalid Simulator job inventory row")
        pid, _, label = fields
        if label in labels:
            raise IosCaseStorageError("duplicate Simulator job identity")
        labels.add(label)
        if _BUNDLE in label:
            if not re.fullmatch(r"UIKitApplication:com\.keplr\.vizor(?:\[[^\]\s]+\])*", label):
                raise IosCaseStorageError("unexpected Vizor Simulator job label")
            if pid != "-":
                pids.append(int(pid))
    if len(pids) > 1:
        raise IosCaseStorageError("multiple Vizor Simulator apps are running")
    return pids


def _helper_stdout(lines: Sequence[str]) -> tuple[str]:
    """Separate the supported SDK console envelope from one helper JSON line.

    simctl --console combines application output with its own bundle: PID line.
    The SDK line may be buffered until the application exits. Accept only that
    exact two-line envelope, never select JSON out of arbitrary diagnostics.
    Its PID is transport metadata, not independent signalling authority.
    """
    text = "".join(lines)
    if len(text.encode("utf-8")) > 16 * 1024:
        raise IosCaseStorageError("Simulator helper console output exceeds its limit")
    records = text.splitlines()
    if len(records) != 2:
        raise IosCaseStorageError("unexpected Simulator helper console envelope")
    sdk_line = re.compile(r"com\.keplr\.vizor: [1-9][0-9]*")
    if sdk_line.fullmatch(records[0]):
        receipt = records[1]
    elif sdk_line.fullmatch(records[1]):
        receipt = records[0]
    else:
        raise IosCaseStorageError("Simulator helper launch identity is unavailable")
    return (receipt,)


class OwnedIosCaseStorage:
    """One cooperative app/native owner. Use prepare_ios_case_storage()."""

    def __init__(self, simulator, helper, home: Path, token):
        if token is not _TOKEN:
            raise IosCaseStorageError("use the fresh Simulator storage preparation API")
        self.simulator = simulator
        self.case = simulator.case
        self.helper = helper
        self._home = home
        self.path: Path | None = None
        self._container: Path | None = None
        self._ids = None
        self._marker_bytes = None
        self._marker_identity = None
        self._launches: list[IosAppLaunch] = []
        self._pending_console: runtime.ManagedProcess | None = None
        self._failure: str | None = None
        self._finished = False
        self._launch_attempted = False
        self._active: IosAppLaunch | None = None
        self._native_cleanup_completed = False
        self._cohort_installed = False
        self._relocations = 0

    def _guard(self, *, deadline: float, cancel_event: threading.Event) -> None:
        if self.simulator._state.native_owner is not self or self._failure is not None:
            raise IosCaseStorageError(self._failure or "Simulator storage owner changed")
        if self.simulator._state.cleanup_errors or self.simulator._commands.unproven_commands:
            raise IosCaseStorageError("prior Simulator teardown/command cleanup is unproven")
        device = self.simulator._owned_device(deadline=deadline, cancel_event=cancel_event)
        if device is None or device.get("state") != "Booted":
            raise IosCaseStorageError("owned Simulator is not ready")

    def _jobs(self, *, deadline, cancel_event):
        self._guard(deadline=deadline, cancel_event=cancel_event)
        text = self.simulator._commands.run(["spawn", self.simulator.udid, "launchctl", "list"],
                                            deadline=deadline, cancel_event=cancel_event)
        return _app_jobs(text)

    def _install(self, *, helper: bool, deadline, cancel_event):
        self._guard(deadline=deadline, cancel_event=cancel_event)
        if self.path is not None:
            self._verify_owned(deadline=deadline, cancel_event=cancel_event)
        if self._jobs(deadline=deadline, cancel_event=cancel_event):
            raise IosCaseStorageError("cannot replace a running case app")
        self.helper.verify_unchanged()
        app = self.helper._helper if helper else self.helper._cohort
        self.simulator._commands.run(["install", self.simulator.udid, str(app.path)],
                                     deadline=deadline, cancel_event=cancel_event)
        self.helper.verify_unchanged()
        if self.path is not None:
            self._observe_install_relocation(deadline=deadline, cancel_event=cancel_event)

    def _observe_install_relocation(self, *, deadline, cancel_event):
        """A scoped SDK update may rename, never replace, the original tree.

        Only called immediately after our captured install, with ownership
        checked before it. Every anchored inode and original marker must remain
        identical. The original marker/context are not rewritten to fit a move.
        Ordinary observations never follow changed SDK container paths.
        """
        container = self._data_container(deadline=deadline, cancel_event=cancel_event)
        if container == self._container:
            self._verify_owned(deadline=deadline, cancel_event=cancel_event)
            return
        path = container / "Library/Application Support/e2e" / self.case.workspace.namespace
        with contextlib.ExitStack() as stack:
            descriptor, identities = _chain(stack, self._home, path, create=False)
            data, identity = _read_file(descriptor, _MARKER, len(self._marker_bytes) + 1)
            if identities != self._ids or data != self._marker_bytes or identity != self._marker_identity:
                raise IosCaseStorageError("SDK install replaced original Simulator support identities")
        try:
            self._container.lstat()
        except FileNotFoundError:
            pass
        else:
            raise IosCaseStorageError("SDK install did not exclusively relocate the original container")
        # Historical transport evidence, never a caller-supplied capability.
        evidence = self.case.workspace.root / f"ios-storage-relocation-{self._relocations:04d}.json"
        payload = simulator_api._encode({"namespace": self.case.workspace.namespace,
            "simulator_udid": self.simulator.udid, "owner_nonce": self.simulator._commands.nonce,
            "previous_support_directory": str(self.path), "support_directory": str(path),
            "original_directory_identities": self._ids, "original_marker_identity": self._marker_identity})
        descriptor = os.open(evidence, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
        self._relocations += 1
        self.path, self._container = path, container
        self._verify_owned(deadline=deadline, cancel_event=cancel_event)

    def _data_container(self, *, deadline, cancel_event) -> Path:
        self._guard(deadline=deadline, cancel_event=cancel_event)
        text = self.simulator._commands.run(["get_app_container", self.simulator.udid, _BUNDLE, "data"],
                                            deadline=deadline, cancel_event=cancel_event)
        lines = text.splitlines()
        if len(lines) != 1 or len(lines[0].encode("utf-8")) > 4096:
            raise IosCaseStorageError("invalid SDK app-container observation")
        path = Path(lines[0])
        parent = self._home / "Library/Developer/CoreSimulator/Devices" / self.simulator.udid / "data/Containers/Data/Application"
        if (
            not path.is_absolute() or path.parent != parent or str(uuid.UUID(path.name)).upper() != path.name
            or path.resolve(strict=True) != path
        ):
            raise IosCaseStorageError("SDK app-container does not belong to the owned Simulator")
        return path

    def _helper_observation(self, mode: str, *, final: bool, deadline, cancel_event):
        self._install(helper=True, deadline=deadline, cancel_event=cancel_event)
        remaining = deadline - time.monotonic() - runtime.DEFAULT_PROCESS_CLEANUP_TIMEOUT
        if remaining <= 0:
            raise IosCaseStorageError("native command budget exhausted after reserving cleanup", 124)
        command = ["/usr/bin/xcrun", "simctl", "launch", "--console", self.simulator.udid, _BUNDLE,
                   "--mode", mode, "--namespace", self.case.workspace.namespace,
                   "--simulator", self.simulator.udid, "--owner-nonce", self.simulator._commands.nonce,
                   "--team", self.helper.team]
        method = self.case.run_final_command if final else self.case.run_command
        result = method(command, env=_ENV, timeout=remaining, cancel_event=cancel_event)
        if result.returncode != 0:
            raise IosCaseStorageError("owned Simulator helper command failed; retain evidence", result.returncode)
        self.helper.verify_unchanged()
        native._validate_receipt(_helper_stdout(result.lines), namespace=self.case.workspace.namespace,
                                 udid=self.simulator.udid, owner_nonce=self.simulator._commands.nonce,
                                 application_identifier=self.helper.application_identifier, mode=mode)
        if self._jobs(deadline=deadline, cancel_event=cancel_event):
            raise IosCaseStorageError("native helper app completion is unproven")

    def _verify_owned(self, *, deadline, cancel_event) -> None:
        self._guard(deadline=deadline, cancel_event=cancel_event)
        if self.path is None or self._container is None:
            raise IosCaseStorageError("Simulator support allocation is incomplete")
        if self._data_container(deadline=deadline, cancel_event=cancel_event) != self._container:
            raise IosCaseStorageError("Simulator app-container changed")
        with contextlib.ExitStack() as stack:
            descriptor, identities = _chain(stack, self._home, self.path, create=False)
            data, identity = _read_file(descriptor, _MARKER, len(self._marker_bytes) + 1)
            if identities != self._ids or data != self._marker_bytes or identity != self._marker_identity:
                raise IosCaseStorageError("Simulator support ownership metadata changed")

    def _verify_context(self, pid: int) -> None:
        with contextlib.ExitStack() as stack:
            descriptor, identities = _chain(stack, self._home, self.path, create=False)
            if identities != self._ids:
                raise IosCaseStorageError("Simulator support identity changed")
            data, _ = _read_file(descriptor, "native-context.json", 8192)
        value = native._fields(json.loads(data, object_pairs_hook=native._unique_object), {
            "schema_version", "namespace", "pid", "support_directory", "secure_store_services",
            "preferences_prefix", "native_preferences_suite", "notification_identifier_prefix",
            "os_background_scheduling_enabled", "storage_cleanup_completed",
        })
        namespace = self.case.workspace.namespace
        if (
            type(value["schema_version"]) is not int or value["schema_version"] != 1
            or type(value["pid"]) is not int or value["pid"] != pid or value["namespace"] != namespace
            or value["support_directory"] != str(self.path) or value["secure_store_services"] != native._services(namespace)
            or value["preferences_prefix"] != f"flutter.vizor_e2e_{namespace}."
            or value["native_preferences_suite"] != f"{_BUNDLE}.regtest.e2e.{namespace}"
            or value["notification_identifier_prefix"] != f"vizor_e2e_{namespace}."
            or value["os_background_scheduling_enabled"] is not False or value["storage_cleanup_completed"] is not False
        ):
            raise IosCaseStorageError("app context does not match the owned Simulator/app/support scope")

    def start_app(self, arguments: Sequence[str] = (), *, timeout: float = 30.0,
                  cancel_event: threading.Event | None = None,
                  raw_lines: list[str] | None = None,
                  max_output_bytes: int | None = None, phase: str | None = None,
                  send_recipient: str | None = None) -> IosAppLaunch:
        deadline = simulator_api._deadline(timeout)
        cancellation = cancel_event if cancel_event is not None else threading.Event()
        if self._finished or self._active is not None or not self.case.accepting_launches:
            raise IosCaseStorageError("case app lifecycle is not open for launch")
        if isinstance(arguments, (str, bytes)) or any(not isinstance(item, str) for item in arguments):
            raise IosCaseStorageError("app arguments must be a sequence of strings")
        name = json.loads(self.case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])["scenario_id"]
        if phase is not None and (not isinstance(phase, str) or phase not in {"prepare", "resume"} or name not in {
                "flutter.ios.ironwood-migration-restart", "flutter.ios.ironwood-background-restart"}):
            raise IosCaseStorageError("iOS phase requires an original mobile restart case")
        if send_recipient is not None and (name != "flutter.ios.ironwood-pre-migration-send"
            or not isinstance(send_recipient, str) or not send_recipient.startswith("uregtest1")
            or not send_recipient.isascii() or not send_recipient.isalnum() or len(send_recipient) > 4096):
            raise IosCaseStorageError("iOS recipient requires the original pre-migration send fixture")
        try:
            self._verify_owned(deadline=deadline, cancel_event=cancellation)
            if not self._cohort_installed:
                self._install(helper=False, deadline=deadline, cancel_event=cancellation)
                self._cohort_installed = True
            else:
                self.helper.verify_unchanged()
            self._verify_owned(deadline=deadline, cancel_event=cancellation)
            environment = {**_ENV, **{f"SIMCTL_CHILD_{key}": value for key, value in self.case.workspace.launch_environment().items()}}
            if phase is not None:
                environment["SIMCTL_CHILD_VIZOR_E2E_IOS_PHASE"] = phase
            if send_recipient is not None:
                environment["SIMCTL_CHILD_VIZOR_E2E_IOS_SEND_RECIPIENT"] = send_recipient
            self._launch_attempted = True
            console = self.case.start_process(
                ["/usr/bin/xcrun", "simctl", "launch", "--console", self.simulator.udid, _BUNDLE, *arguments],
                env=environment,
                raw_lines=raw_lines, max_output_bytes=max_output_bytes,
            )
            self._pending_console = console
            while True:
                jobs = self._jobs(deadline=deadline, cancel_event=cancellation)
                if jobs:
                    try:
                        self._verify_context(jobs[0])
                    except FileNotFoundError:
                        pass  # Atomic context publication has not happened yet.
                    except IosCaseStorageError:
                        if not self._launches:
                            raise
                        # Only a fully matching context from our previous owned
                        # generation may remain during atomic restart publication.
                        self._verify_context(self._launches[-1].pid)
                    else:
                        launch = IosAppLaunch(self.case.workspace.namespace, self.simulator.udid, jobs[0], console)
                        self._launches.append(launch)
                        self._active = launch
                        self._pending_console = None
                        return launch
                if console.process.poll() is not None:
                    raise IosCaseStorageError("case app exited before owned startup/context was proven")
                time.sleep(0.05)
        except BaseException:
            self._failure = "owned Simulator app launch/startup unproven"
            raise

    def _stop_native_app(self, *, deadline, cancel_event):
        jobs = self._jobs(deadline=deadline, cancel_event=cancel_event)
        if jobs:
            if not self._launches or jobs != [self._launches[-1].pid]:
                raise IosCaseStorageError("running Simulator app is not the latest owned launch")
            self.simulator._commands.run(["terminate", self.simulator.udid, _BUNDLE],
                                         deadline=deadline, cancel_event=cancel_event)
        while self._jobs(deadline=deadline, cancel_event=cancel_event):
            time.sleep(0.05)

    def stop_app(self, launch: IosAppLaunch, *, timeout: float = 30.0) -> None:
        deadline = simulator_api._deadline(timeout)
        if self._finished or launch is not self._active:
            raise IosCaseStorageError("expected this case's active owned app launch")
        cancellation = threading.Event()
        try:
            self._verify_owned(deadline=deadline, cancel_event=cancellation)
            self._verify_context(launch.pid)
            self._stop_native_app(deadline=deadline, cancel_event=cancellation)
            self.case.stop_process(launch.console)
            self._active = None
        except BaseException:
            self._failure = "owned Simulator app stop unproven"
            raise

    def _shutdown(self, *, deadline: float) -> None:
        # A failed native observation does not remove original simulator
        # ownership. Stop only its exact UUID, retaining all state/evidence.
        cancellation = threading.Event()
        device = self.simulator._owned_device(deadline=deadline, cancel_event=cancellation)
        if device is None:
            raise IosCaseStorageError("owned Simulator disappeared before shutdown proof")
        if device.get("state") != "Shutdown":
            self.simulator._commands.run(["shutdown", self.simulator.udid], deadline=deadline, cancel_event=cancellation)
        while True:
            device = self.simulator._owned_device(deadline=deadline, cancel_event=cancellation)
            if device is None:
                raise IosCaseStorageError("owned Simulator disappeared during shutdown")
            if device.get("state") == "Shutdown":
                return
            time.sleep(0.05)

    def retain(self, *, timeout: float = 30.0) -> None:
        """Seal/stop case writers and shut down only its device; delete nothing."""
        simulator_api._deadline(timeout)
        self._finished = True
        primary = None
        try:
            self.case.close()
        except BaseException as error:
            primary = error
        try:
            self._shutdown(deadline=simulator_api._deadline(timeout))
        except BaseException as error:
            if primary is None:
                primary = error
        if primary is not None:
            self._failure = "failed-case writer/device shutdown unproven"
            raise primary

    def _delete_after_native_cleanup(self, *, deadline):
        if (
            not self._finished or not self._native_cleanup_completed or self._failure is not None
            or self.simulator._state.native_owner is not self
        ):
            raise IosCaseStorageError("owned native cleanup was not internally completed")
        self.case.close()
        if self.simulator._state.cleanup_errors or self.simulator._commands.unproven_commands:
            raise IosCaseStorageError("prior Simulator cleanup is unproven")
        self._shutdown(deadline=deadline)
        cancellation = threading.Event()
        self.simulator._commands.run(["delete", self.simulator.udid], deadline=deadline, cancel_event=cancellation)
        if self.simulator._owned_device(deadline=deadline, cancel_event=cancellation) is not None:
            raise IosCaseStorageError("owned Simulator still exists after deletion")
        for path in (self._container, self._home / "Library/Developer/CoreSimulator/Devices" / self.simulator.udid):
            try:
                path.lstat()
            except FileNotFoundError:
                continue
            raise IosCaseStorageError("owned Simulator data remains after SDK deletion")

    def close(self, *, timeout: float = 30.0,
              cancel_event: threading.Event | None = None) -> IosCaseStorageCleanup:
        """Complete one successful case; never accept external cleanup evidence.

        Stop groups with their per-group allowance, then use one SDK wait/cleanup
        budget for observations and a separate device shutdown/deletion budget.
        Calls are cooperative/single-owner; this is not one wall-clock SLA.
        """
        simulator_api._deadline(timeout)
        if self._finished:
            raise IosCaseStorageError("Simulator storage lifecycle is finished")
        self._finished = True
        cancellation = cancel_event if cancel_event is not None else threading.Event()
        try:
            self.case.close()
            deadline = simulator_api._deadline(timeout)
            self._verify_owned(deadline=deadline, cancel_event=cancellation)
            self._stop_native_app(deadline=deadline, cancel_event=cancellation)
            if self._launch_attempted and not self._launches:
                raise IosCaseStorageError("attempted app launch has no completed owned startup proof")
            if self._launches:
                self._verify_context(self._launches[-1].pid)
            self._helper_observation("delete", final=True, deadline=deadline, cancel_event=cancellation)
            self._verify_owned(deadline=deadline, cancel_event=cancellation)
            self._native_cleanup_completed = True
            self._delete_after_native_cleanup(deadline=simulator_api._deadline(timeout))
            return IosCaseStorageCleanup(self.case.workspace.namespace, self.simulator.udid,
                str(self.path), self.helper.application_identifier, self.case.close())
        except BaseException as primary:
            self._native_cleanup_completed = False
            self._failure = "successful-case native/device cleanup unproven"
            try:
                self._shutdown(deadline=simulator_api._deadline(timeout))
            except BaseException as cleanup:
                raise primary from cleanup
            raise


def prepare_ios_case_storage(simulator: simulator_api.OwnedIosSimulator,
                             helper: native.CapturedIosCleanupHelper, *, timeout: float = 120.0,
                             cancel_event: threading.Event | None = None) -> OwnedIosCaseStorage:
    """Claim a fresh unlaunched case; preflight native absence and own support.

    Existing native owners, app contexts or support namespaces are never adopted.
    A failed preparation stops only its owned groups/device and retains all files.
    """
    deadline = simulator_api._deadline(timeout)
    cancellation = cancel_event if cancel_event is not None else threading.Event()
    if not isinstance(simulator, simulator_api.OwnedIosSimulator) or not isinstance(helper, native.CapturedIosCleanupHelper):
        raise IosCaseStorageError("expected a newly owned Simulator and captured helper")
    simulator.case.workspace.verify_owned()
    if (
        not simulator.case.accepting_launches or simulator.case.launched_process_count
        or simulator._state.native_owner is not None or simulator._state.receipt is not None
        or simulator._state.cleanup_errors or simulator._commands.unproven_commands
    ):
        raise IosCaseStorageError("Simulator native preparation requires a fresh unclaimed case")
    helper.verify_unchanged()
    owner = OwnedIosCaseStorage(simulator, helper, _home(), _TOKEN)
    # Close the pre-app deletion route BEFORE any helper install/native launch.
    simulator._state.native_owner = owner
    try:
        simulator.boot(timeout=max(0.001, deadline - time.monotonic()), cancel_event=cancellation)
        owner._helper_observation("verify", final=False, deadline=deadline, cancel_event=cancellation)
        container = owner._data_container(deadline=deadline, cancel_event=cancellation)
        path = container / "Library/Application Support/e2e" / simulator.case.workspace.namespace
        payload = simulator_api._encode({
            "schema_version": 1, "namespace": simulator.case.workspace.namespace,
            "workspace": str(simulator.case.workspace.root), "simulator_udid": simulator.udid,
            "owner_nonce": simulator._commands.nonce, "application_identifier": helper.application_identifier,
            "support_directory": str(path),
        })
        owner.path, owner._container = path, container
        with contextlib.ExitStack() as stack:
            directory, identities = _chain(stack, owner._home, path, create=True)
            descriptor = os.open(_MARKER, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=directory)
            with os.fdopen(descriptor, "wb") as stream:
                details = os.fstat(stream.fileno())
                identity = (details.st_dev, details.st_ino)
                stream.write(payload)
                stream.flush()
            owner._ids, owner._marker_identity, owner._marker_bytes = identities, identity, payload
        owner._verify_owned(deadline=deadline, cancel_event=cancellation)
        return owner
    except BaseException as primary:
        owner._failure = "Simulator native preparation unproven"
        try:
            owner.retain(timeout=30.0)
        except BaseException as cleanup:
            raise primary from cleanup
        raise
