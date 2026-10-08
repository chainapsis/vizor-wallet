"""Bind owned process launches and their teardown to one native E2E case."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
import dataclasses
import math
import os
import threading
from typing import Any

import e2e_runtime as runtime
from native_workspace import NativeCaseWorkspace, NativeWorkspaceError


@dataclasses.dataclass(frozen=True)
class CaseProcessCleanup:
    """Historical process/output observation, NOT native-storage cleanup authority.

    Exit codes retain execution outcomes. External zombie PIDs are observations,
    never future signal targets. No receipt grants permission to delete state.
    """

    namespace: str
    workspace: str
    exit_codes: tuple[int, ...]
    external_zombie_pids: tuple[int, ...]


class NativeCaseLifecycle:
    """One cooperative, single-threaded owner for a case's process launches.

    Restarts use the same workspace. Final close seals future launches and
    retains all files; it owns no ports, native storage, or simulators. Processes
    must stay in the owned groups created by the shared process primitive.
    """

    def __init__(self, workspace: NativeCaseWorkspace):
        if not isinstance(workspace, NativeCaseWorkspace):
            raise NativeWorkspaceError("expected an owned native case workspace")
        workspace.claim_process_lifecycle()
        self._workspace = workspace
        self._processes: list[runtime.ManagedProcess] = []
        self._pending_launch: runtime.ManagedProcess | None = None
        self._sealed = False
        self._cleanup_errors: list[str] = []
        self._receipt: CaseProcessCleanup | None = None

    @property
    def workspace(self) -> NativeCaseWorkspace:
        return self._workspace

    @property
    def accepting_launches(self) -> bool:
        """False after final close or any unproven process cleanup."""
        return not self._sealed

    def _require_member(self, managed: runtime.ManagedProcess) -> None:
        if not any(managed is owned for owned in self._processes):
            raise runtime.RunnerError("process was not launched by this case")

    def _cleanup_failed(self, error: BaseException) -> None:
        self._sealed = True
        self._receipt = None
        detail = f"{type(error).__name__}: {error}"
        if detail not in self._cleanup_errors:
            self._cleanup_errors.append(detail)

    def start_process(
        self,
        command: Sequence[str],
        *,
        env: Mapping[str, str],
        stdin: Any = None,
    ) -> runtime.ManagedProcess:
        """Launch only with this case's identity, cwd, and an exclusive private log.

        Failure after entering the shared launch primitive returns no owned
        handle. Conservatively seal the case: do not infer teardown from an
        exception or retry with a new owner over the same mutable state.
        """
        if self._sealed:
            raise runtime.RunnerError("case process lifecycle is sealed")
        environment = self.workspace.launch_environment()
        supplied = dict(env)
        if any(key in supplied and supplied[key] != value for key, value in environment.items()):
            raise runtime.RunnerError("caller environment conflicts with case launch identity")
        log_path = self.workspace.root / f"process-{len(self._processes):04d}.log"
        try:
            descriptor = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            os.close(descriptor)
        except OSError as error:
            raise runtime.RunnerError("cannot reserve an exclusive case process log") from error
        managed = None
        try:
            managed = runtime.start_logged_process(
                command, cwd=self.workspace.root, env={**supplied, **environment},
                log_path=log_path, stdin=stdin,
            )
            self._processes.append(managed)
        except BaseException as error:
            self._cleanup_failed(error)
            if managed is not None:
                self._pending_launch = managed
                # Registration itself can be interrupted after launch returns.
                # We still own this group even without a tracked-list entry.
                try:
                    runtime.terminate_process(managed)
                except BaseException as cleanup:
                    self._cleanup_failed(cleanup)
                    raise error from cleanup
            raise
        return managed

    def wait_process(
        self,
        managed: runtime.ManagedProcess,
        *,
        timeout: float,
        cancel_event: threading.Event,
    ) -> int:
        """Preserve exit code, timeout, cancellation, and interruption semantics."""
        self._require_member(managed)
        try:
            return runtime.wait_managed_process(managed, timeout=timeout, cancel_event=cancel_event)
        except BaseException as error:
            if not managed.cleanup_completed:
                self._cleanup_failed(error)
            raise

    def stop_process(self, managed: runtime.ManagedProcess, *, timeout: float = 5.0) -> None:
        """Stop a phase's owned group without discarding same-case restart state."""
        self._require_member(managed)
        try:
            runtime.terminate_process(managed, timeout=timeout)
        except BaseException as error:
            self._cleanup_failed(error)
            raise

    def close(self, *, timeout: float = 5.0) -> CaseProcessCleanup:
        """Seal launches and attempt every owned group, with a budget per group.

        Cleanup failure is sticky even if later attempts physically release the
        remaining resources. Filesystem failure must not prevent process stop.
        This is not a test PASS or proof of native storage/simulator cleanup.
        """
        if (
            isinstance(timeout, bool) or not isinstance(timeout, (int, float))
            or not math.isfinite(timeout) or timeout <= 0
        ):
            raise runtime.RunnerError("timeout must be positive and finite")
        self._sealed = True
        interruption = None
        owned = tuple(self._processes)
        if self._pending_launch is not None and not any(self._pending_launch is item for item in owned):
            owned += (self._pending_launch,)
        for managed in reversed(owned):
            try:
                runtime.terminate_process(managed, timeout=timeout)
                if not managed.cleanup_completed:
                    raise runtime.RunnerError("owned process teardown did not complete")
            except BaseException as error:
                self._cleanup_failed(error)
                if not isinstance(error, Exception) and interruption is None:
                    interruption = error
        try:
            self.workspace.verify_owned()
        except (OSError, ValueError, RuntimeError) as error:
            self._cleanup_failed(error)
        if interruption is not None:
            raise interruption
        if self._cleanup_errors:
            raise runtime.RunnerError("case process cleanup unproven: " + "; ".join(self._cleanup_errors))
        if self._receipt is None:
            self._receipt = CaseProcessCleanup(
                self.workspace.namespace, str(self.workspace.root),
                tuple(managed.process.returncode for managed in owned),
                tuple(sorted({pid for managed in owned for pid in managed.unreaped_zombie_pids})),
            )
        return self._receipt
