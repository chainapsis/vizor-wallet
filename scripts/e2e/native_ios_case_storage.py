"""Own one fresh Simulator's app lifecycle; never adopt user devices.

Successful scenarios prove cleanup by deleting their owned fresh device and
observing its inventory and device-directory absence. Failed scenarios stop
writers and retain the device, state and evidence. PIDs grant no authority.
"""

from __future__ import annotations

from collections.abc import Sequence
import dataclasses
import json
import os
from pathlib import Path
import pwd
import re
import threading
import time

import e2e_runtime as runtime
from native_case_lifecycle import CaseProcessCleanup
import native_ios_cohort as cohort_api
import native_ios_simulator as simulator_api


_TOKEN = object()
_BUNDLE = "com.keplr.vizor"
_ENV = {"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"}


class IosCaseStorageError(runtime.RunnerError):
    """Owned app/device teardown is unproven; retain state and evidence."""


@dataclasses.dataclass(frozen=True)
class IosAppLaunch:
    """Historical owned SDK/app identity, not a global PID signalling target."""
    namespace: str
    udid: str
    pid: int
    console: runtime.ManagedProcess


@dataclasses.dataclass(frozen=True)
class IosCaseStorageCleanup:
    """Internally observed device deletion, not scenario PASS or external authority."""
    namespace: str
    udid: str
    device_directory: str
    process_cleanup: CaseProcessCleanup


def _home() -> Path:
    return Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(strict=True)


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


class OwnedIosCaseStorage:
    """One cooperative app/device owner. Use prepare_ios_case_storage()."""

    def __init__(self, simulator, cohort, home: Path, token):
        if token is not _TOKEN:
            raise IosCaseStorageError("use the fresh Simulator storage preparation API")
        self.simulator = simulator
        self.case = simulator.case
        self.cohort = cohort
        self._home = home
        self._launches: list[IosAppLaunch] = []
        self._pending_console: runtime.ManagedProcess | None = None
        self._failure: str | None = None
        self._finished = False
        self._launch_attempted = False
        self._active: IosAppLaunch | None = None
        # Set only by close() after proving app absence; retain() never sets it.
        self._app_stop_proved = False

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

    def _install(self, *, deadline, cancel_event):
        # The fresh device's one cohort install; _jobs runs _guard first.
        if self._jobs(deadline=deadline, cancel_event=cancel_event):
            raise IosCaseStorageError("cannot install over a running case app")
        self.cohort.verify_unchanged()
        self.simulator._commands.run(["install", self.simulator.udid, str(self.cohort.path)],
                                     deadline=deadline, cancel_event=cancel_event)
        self.cohort.verify_unchanged()

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
            # Preparation installed the cohort; launches never reinstall it.
            if self._jobs(deadline=deadline, cancel_event=cancellation):
                raise IosCaseStorageError("a case app is already running")
            self.cohort.verify_unchanged()
            environment = {**_ENV, **{f"SIMCTL_CHILD_{key}": value for key, value in self.case.workspace.launch_environment().items()}}
            if phase is not None:
                environment["SIMCTL_CHILD_VIZOR_E2E_IOS_PHASE"] = phase
            if send_recipient is not None:
                environment["SIMCTL_CHILD_VIZOR_E2E_IOS_SEND_RECIPIENT"] = send_recipient
            previous = {launch.pid for launch in self._launches}
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
                    if jobs[0] in previous:
                        raise IosCaseStorageError("Simulator app job is not a new owned launch")
                    launch = IosAppLaunch(self.case.workspace.namespace, self.simulator.udid, jobs[0], console)
                    self._launches.append(launch)
                    self._active = launch
                    self._pending_console = None
                    return launch
                if console.process.poll() is not None:
                    raise IosCaseStorageError("case app exited before its owned job was observed")
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
            self._stop_native_app(deadline=deadline, cancel_event=cancellation)  # _jobs runs _guard
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

    def _delete_owned_device(self, *, deadline) -> Path:
        if (
            not self._finished or not self._app_stop_proved or self._failure is not None
            or self.simulator._state.native_owner is not self
        ):
            raise IosCaseStorageError("owned device deletion requires this successful closing owner")
        self.case.close()
        if self.simulator._state.cleanup_errors or self.simulator._commands.unproven_commands:
            raise IosCaseStorageError("prior Simulator cleanup is unproven")
        self._shutdown(deadline=deadline)
        cancellation = threading.Event()
        self.simulator._commands.run(["delete", self.simulator.udid], deadline=deadline, cancel_event=cancellation)
        if self.simulator._owned_device(deadline=deadline, cancel_event=cancellation) is not None:
            raise IosCaseStorageError("owned Simulator still exists after deletion")
        directory = self._home / "Library/Developer/CoreSimulator/Devices" / self.simulator.udid
        try:
            directory.lstat()
        except FileNotFoundError:
            return directory
        raise IosCaseStorageError("owned Simulator device directory remains after SDK deletion")

    def close(self, *, timeout: float = 30.0,
              cancel_event: threading.Event | None = None) -> IosCaseStorageCleanup:
        """Complete one successful case; never accept external cleanup evidence.

        Stop groups with their per-group allowance, then use one SDK budget to
        prove app absence and a separate device shutdown/deletion budget.
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
            self._stop_native_app(deadline=deadline, cancel_event=cancellation)  # _jobs runs _guard
            if self._launch_attempted and not self._launches:
                raise IosCaseStorageError("attempted app launch has no completed owned startup proof")
            self._app_stop_proved = True
            directory = self._delete_owned_device(deadline=simulator_api._deadline(timeout))
            return IosCaseStorageCleanup(self.case.workspace.namespace, self.simulator.udid,
                                         str(directory), self.case.close())
        except BaseException as primary:
            self._app_stop_proved = False
            self._failure = "successful-case device deletion unproven"
            try:
                self._shutdown(deadline=simulator_api._deadline(timeout))
            except BaseException as cleanup:
                raise primary from cleanup
            raise


def prepare_ios_case_storage(simulator: simulator_api.OwnedIosSimulator,
                             cohort: cohort_api.CapturedIosCohort, *, timeout: float = 120.0,
                             cancel_event: threading.Event | None = None) -> OwnedIosCaseStorage:
    """Claim a fresh unlaunched case device, boot it and install the cohort once.

    Existing native owners or devices are never adopted. A failed preparation
    stops only its owned groups/device and retains the device and all files.
    """
    deadline = simulator_api._deadline(timeout)
    cancellation = cancel_event if cancel_event is not None else threading.Event()
    if not isinstance(simulator, simulator_api.OwnedIosSimulator) or not isinstance(cohort, cohort_api.CapturedIosCohort):
        raise IosCaseStorageError("expected a newly owned Simulator and captured cohort")
    simulator.case.workspace.verify_owned()
    if (
        not simulator.case.accepting_launches or simulator.case.launched_process_count
        or simulator._state.native_owner is not None or simulator._state.receipt is not None
        or simulator._state.cleanup_errors or simulator._commands.unproven_commands
    ):
        raise IosCaseStorageError("Simulator native preparation requires a fresh unclaimed case")
    cohort.verify_unchanged()
    owner = OwnedIosCaseStorage(simulator, cohort, _home(), _TOKEN)
    # Close the pre-app deletion route BEFORE the cohort install.
    simulator._state.native_owner = owner
    try:
        simulator.boot(timeout=max(0.001, deadline - time.monotonic()), cancel_event=cancellation)
        owner._install(deadline=deadline, cancel_event=cancellation)
        owner._guard(deadline=deadline, cancel_event=cancellation)
        return owner
    except BaseException as primary:
        owner._failure = "Simulator native preparation unproven"
        try:
            owner.retain(timeout=30.0)
        except BaseException as cleanup:
            raise primary from cleanup
        raise
