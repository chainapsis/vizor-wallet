"""What the Flutter runner records about the host and a stalled app.

A locked macOS session stops the apps a run drives: the wallet's keychain
writes fail while the session is locked, and platform calls may never
return. `session_locked` lets the runner refuse to start a Flutter case
then. When a phase stops producing output or misses its deadline,
`StallRecorder` saves the app's thread stacks in the case evidence.
"""
from __future__ import annotations

import os
from pathlib import Path
import plistlib
import subprocess
import sys
import threading
import time

IOREG = "/usr/sbin/ioreg"
PS = "/bin/ps"
SAMPLE = "/usr/bin/sample"
STALL_SECONDS = 240
STALL_SAMPLES = 2
# A stuck app's stacks barely change; sampling every 1 ms (the default)
# writes 15+ MB for a macOS app with ~200 threads.
SAMPLE_SECONDS = 3
SAMPLE_INTERVAL_MS = 10


def session_locked(*, run=subprocess.run, uid=None):
    """True when this user's macOS session is locked or switched away from the console.

    None when it cannot tell: another platform, or `ioreg` gave no answer.
    """
    if sys.platform != "darwin":
        return None
    try:
        completed = run([IOREG, "-n", "Root", "-d1", "-a"], capture_output=True, timeout=10)
        root = plistlib.loads(completed.stdout) if completed.returncode == 0 else None
    except Exception:  # A probe that cannot answer must not stop the run.
        return None
    if not isinstance(root, dict):
        return None
    uid = os.getuid() if uid is None else uid
    for user in root.get("IOConsoleUsers") or ():
        if isinstance(user, dict) and user.get("kCGSSessionUserIDKey") == uid:
            return bool(user.get("CGSSessionScreenIsLocked")) or not user.get("kCGSSessionOnConsoleKey", True)
    return None


def app_pids(platform, *, source_root, device, run=subprocess.run):
    """PIDs of the app a Flutter phase drives: the worktree's macOS build, or the app on the run's simulator."""
    if platform == "macos":
        root = str(Path(source_root).resolve())
        markers = {f"{root}/build/macos/", f"{root.replace('/private/tmp/', '/tmp/', 1)}/build/macos/"}
        executable = "/Contents/MacOS/"
    else:
        markers = {f"/CoreSimulator/Devices/{device}/"}
        executable = ".app/"
    try:
        listing = run([PS, "-axo", "pid=,command="], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    pids = []
    for line in listing.splitlines():
        pid, _, command = line.strip().partition(" ")
        # App extensions, such as the iOS sync widget, live inside the app bundle.
        if (pid.isdigit() and executable in command and ".appex/" not in command
                and any(marker in command for marker in markers)):
            pids.append(int(pid))
    return pids


def sample_stacks(pids, directory, label, *, run=subprocess.run):
    """Save `sample` output for each PID as `<label>-<pid>.txt`; return the files written."""
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    written = []
    for pid in pids:
        path = directory / f"{label}-{pid}.txt"
        try:
            run([SAMPLE, str(pid), str(SAMPLE_SECONDS), str(SAMPLE_INTERVAL_MS), "-file", str(path)],
                capture_output=True, timeout=SAMPLE_SECONDS + 60)
        except (OSError, subprocess.SubprocessError):
            continue
        if path.exists():
            written.append(path)
    return written


class StallRecorder:
    """Samples the app when a phase's output stops for STALL_SECONDS, at most STALL_SAMPLES times.

    Stall samples run on a background thread so the control keeps serving
    requests; `record_now` samples synchronously, before a timed-out case
    is torn down.
    """

    def __init__(self, directory, find_pids, *, label, clock=time.monotonic, sample=None):
        self._directory, self._find_pids, self._label = directory, find_pids, label
        self._clock, self._sample = clock, sample
        self._count, self._since, self._taken = 0, clock(), 0
        self._threads = []

    def observe(self, output_count):
        now = self._clock()
        if output_count != self._count:
            self._count, self._since = output_count, now
        elif self._taken < STALL_SAMPLES and now - self._since >= STALL_SECONDS:
            self._taken += 1
            self._since = now
            label = f"{self._label}-stall-{self._taken}"
            thread = threading.Thread(target=self._record, args=(label,), daemon=True)
            thread.start()
            self._threads.append(thread)

    def record_now(self, reason):
        self.join()
        return self._record(f"{self._label}-{reason}")

    def join(self, timeout=SAMPLE_SECONDS + 90):
        for thread in self._threads:
            thread.join(timeout)

    def _record(self, label):
        try:
            return (self._sample or sample_stacks)(self._find_pids(), self._directory, label)
        except Exception:  # Diagnostics must not replace the phase's own outcome.
            return []
