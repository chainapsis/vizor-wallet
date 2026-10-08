"""Owned POSIX process groups and bounded output capture for local E2E runners."""

from __future__ import annotations

import dataclasses
import math
import os
from pathlib import Path
import signal
import subprocess
import threading
import time
from typing import Any, Sequence


_OWNERSHIP_TOKEN = object()
_POLL_INTERVAL = 0.02
_SENSITIVE_LOG_MARKERS = ("mnemonic:", "unified spending key", '"seed_hex"')


class RunnerError(RuntimeError):
    def __init__(self, message: str, exit_code: int = 1):
        super().__init__(message)
        self.exit_code = exit_code


class Cancelled(RunnerError):
    def __init__(self, message: str = "E2E command cancelled"):
        super().__init__(message, 130)


@dataclasses.dataclass(frozen=True)
class CommandResult:
    returncode: int
    lines: tuple[str, ...]


@dataclasses.dataclass
class _Capture:
    log_path: Path
    lines: list[str] | None
    stream: Any = None
    finished: threading.Event = dataclasses.field(default_factory=threading.Event)
    errors: list[BaseException] = dataclasses.field(default_factory=list)
    group_gone: bool = False
    closed: bool = False
    cleanup_errors: list[str] = dataclasses.field(default_factory=list)


@dataclasses.dataclass(frozen=True)
class ManagedProcess:
    """Use start_logged_process(); callers must not construct or adopt handles."""

    process: subprocess.Popen[str]
    log_path: Path
    pump_thread: threading.Thread
    _capture: _Capture = dataclasses.field(repr=False)
    _group_id: int = dataclasses.field(repr=False)
    _ownership_token: object = dataclasses.field(repr=False)

    @property
    def cleanup_completed(self) -> bool:
        """True only after group exit, child reap and error-free pump completion."""
        return self._capture.closed and not self._capture.cleanup_errors


def sanitize_log_line(line: str) -> str:
    """Redact the prototype's known credential markers, not every possible secret."""
    if any(marker in line.lower() for marker in _SENSITIVE_LOG_MARKERS):
        return "[redacted regtest credential]\n"
    return line


def _pump_output(capture: _Capture) -> None:
    try:
        with capture.stream, capture.log_path.open("w", encoding="utf-8") as log:
            for line in iter(capture.stream.readline, ""):
                if capture.lines is not None:
                    capture.lines.append(line)
                log.write(sanitize_log_line(line))
                log.flush()
    except BaseException as error:
        capture.errors.append(error)
    finally:
        capture.finished.set()


def _positive_timeout(timeout: float) -> None:
    if (
        isinstance(timeout, bool)
        or not isinstance(timeout, (int, float))
        or not math.isfinite(timeout)
        or timeout <= 0
    ):
        raise RunnerError("timeout must be positive and finite")


def _require_owned(managed: ManagedProcess) -> None:
    if (
        not isinstance(managed, ManagedProcess)
        or managed._ownership_token is not _OWNERSHIP_TOKEN
        or managed.process.pid != managed._group_id
    ):
        raise RunnerError("expected a process handle created by start_logged_process")


def _kill_group(managed: ManagedProcess, sig: int, *, deadline: float | None = None) -> bool:
    if managed._capture.group_gone:
        return False
    for attempt in range(2):
        try:
            os.killpg(managed._group_id, sig)
            return True
        except ProcessLookupError:
            # Never signal this numeric group ID again after observing absence.
            managed._capture.group_gone = True
            return False
        except PermissionError as error:
            # macOS can report EPERM for a dying/zombie group leader. Reap our
            # direct child and retry once; permission failure is NOT absence.
            if attempt:
                raise
            try:
                remaining = 0.0 if deadline is None else max(0.0, deadline - time.monotonic())
                managed.process.wait(timeout=remaining)
            except subprocess.TimeoutExpired:
                raise error


def _group_exists(managed: ManagedProcess, *, deadline: float | None = None) -> bool:
    return _kill_group(managed, 0, deadline=deadline)


def _signal_group(managed: ManagedProcess, sig: signal.Signals, *, deadline: float) -> None:
    _kill_group(managed, sig, deadline=deadline)


def _wait_group_exit(managed: ManagedProcess, deadline: float) -> bool:
    while True:
        # Reap the direct child, but do not confuse its exit with group exit.
        managed.process.poll()
        if not _group_exists(managed, deadline=deadline) and managed.process.poll() is not None:
            return True
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(_POLL_INTERVAL, remaining))


def terminate_process(managed: ManagedProcess, *, timeout: float = 5.0) -> None:
    """Stop only this launch's group and verify output closure within one budget.

    Descendants must stay in the session/group created by start_new_session.
    This is cooperative lifecycle ownership, not containment of daemonizing code.
    Cleanup is single-owner; do not wait/terminate a handle concurrently.
    """
    _require_owned(managed)
    _positive_timeout(timeout)
    try:
        _terminate_owned_process(managed, timeout)
    except BaseException as error:
        if not managed._capture.cleanup_errors:
            managed._capture.cleanup_errors.append(f"cleanup raised {type(error).__name__}: {error}")
        raise


def _terminate_owned_process(managed: ManagedProcess, timeout: float) -> None:
    capture = managed._capture
    if not capture.closed:
        errors: list[str] = []
        deadline = time.monotonic() + timeout
        grace_deadline = time.monotonic() + timeout / 2
        for sig, until in ((signal.SIGTERM, grace_deadline), (signal.SIGKILL, deadline)):
            try:
                if _group_exists(managed, deadline=until):
                    _signal_group(managed, sig, deadline=until)
                if _wait_group_exit(managed, until):
                    break
            except OSError as error:
                errors.append(f"process group verification/termination failed: {error}")
        else:
            errors.append(f"owned process group {managed._group_id} did not exit")

        if managed.pump_thread.ident is None:
            # Thread startup failed; there is no reader to own/close the pipe.
            try:
                capture.stream.close()
            except OSError as error:
                errors.append(f"output pipe close failed: {error}")
            capture.finished.set()
        else:
            managed.pump_thread.join(timeout=max(0.0, deadline - time.monotonic()))
        if managed.pump_thread.is_alive() or not capture.finished.is_set():
            errors.append("output pump did not finish")
        for error in capture.errors:
            errors.append(f"output capture failed ({type(error).__name__}: {error})")
        capture.closed = (
            capture.group_gone
            and managed.process.poll() is not None
            and not managed.pump_thread.is_alive()
            and capture.finished.is_set()
        )
        capture.cleanup_errors.extend(errors)
    if capture.cleanup_errors:
        raise RunnerError("owned process cleanup unproven: " + "; ".join(capture.cleanup_errors))


def _cleanup_after_error(managed: ManagedProcess, primary: BaseException) -> None:
    try:
        terminate_process(managed)
    except BaseException as cleanup:
        detail = type(primary).__name__
        if str(primary):
            detail += f": {primary}"
        message = f"cleanup failed after {detail}; cleanup error: {cleanup}"
        if isinstance(primary, KeyboardInterrupt):
            raise KeyboardInterrupt(message) from cleanup
        if isinstance(primary, Cancelled):
            raise Cancelled(message) from cleanup
        raise RunnerError(message, getattr(primary, "exit_code", 1)) from cleanup


def start_logged_process(
    command: Sequence[str],
    *,
    cwd: Path,
    env: dict[str, str],
    log_path: Path,
    raw_lines: list[str] | None = None,
    stdin: Any = None,
) -> ManagedProcess:
    """Create a new owned group; raw output stays in memory, logs are redacted."""
    if os.name != "posix":
        raise RunnerError("owned E2E process groups require a POSIX host")
    if isinstance(command, (str, bytes)) or not command or not command[0] or any(
        not isinstance(arg, str) or "\0" in arg for arg in command
    ):
        raise RunnerError("command must be a non-empty argument sequence")
    if stdin == subprocess.PIPE:
        raise RunnerError("stdin PIPE is unsupported; provide an input file instead")
    capture = _Capture(log_path, raw_lines)
    pump = threading.Thread(target=_pump_output, args=(capture,), daemon=True)
    try:
        process = subprocess.Popen(
            list(command), cwd=cwd, env=env, stdin=stdin,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", bufsize=1, start_new_session=True,
        )
    except OSError as error:
        raise RunnerError(f"failed to start {command[0]!r}: {error}") from error
    capture.stream = process.stdout
    managed = ManagedProcess(process, log_path, pump, capture, process.pid, _OWNERSHIP_TOKEN)
    try:
        pump.start()
    except BaseException as primary:
        _cleanup_after_error(managed, primary)
        raise
    return managed


def wait_managed_process(
    managed: ManagedProcess,
    *,
    timeout: float,
    cancel_event: threading.Event,
) -> int:
    """A command completes only after natural group exit and finished output.

    Timeout/cancellation/interrupt stops its group. Cleanup uncertainty remains
    a failure, preserving the primary timeout/cancellation classification.
    """
    _require_owned(managed)
    try:
        _positive_timeout(timeout)
        deadline = time.monotonic() + timeout
        while True:
            if cancel_event.is_set():
                raise Cancelled()
            if managed._capture.errors:
                raise RunnerError(f"output capture failed; see {managed.log_path}")
            code = managed.process.poll()
            if (
                code is not None
                and not _group_exists(managed)
                and managed._capture.finished.is_set()
                and not managed.pump_thread.is_alive()
            ):
                break
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RunnerError(f"command timed out after {timeout:g}s; see {managed.log_path}", 124)
            time.sleep(min(_POLL_INTERVAL, remaining))
    except BaseException as primary:
        _cleanup_after_error(managed, primary)
        raise
    terminate_process(managed)
    return code


def run_logged_command(
    command: Sequence[str],
    *,
    cwd: Path,
    env: dict[str, str],
    log_path: Path,
    timeout: float,
    cancel_event: threading.Event,
    stdin: Any = None,
) -> CommandResult:
    _positive_timeout(timeout)
    lines: list[str] = []
    managed = start_logged_process(
        command, cwd=cwd, env=env, log_path=log_path, raw_lines=lines, stdin=stdin,
    )
    code = wait_managed_process(managed, timeout=timeout, cancel_event=cancel_event)
    return CommandResult(code, tuple(lines))
