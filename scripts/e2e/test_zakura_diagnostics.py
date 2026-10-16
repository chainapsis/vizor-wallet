"""Session lock probe, app lookup, stack samples and stall timing."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_diagnostics as DIAGNOSTICS


def ioreg(users, returncode=0):
    payload = plistlib.dumps({"IOConsoleUsers": users})
    return lambda *_args, **_kwargs: subprocess.CompletedProcess([], returncode, stdout=payload)


class SessionLockTests(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(DIAGNOSTICS.sys, "platform", "darwin")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_reads_the_lock_of_this_users_console_session(self):
        unlocked = {"kCGSSessionUserIDKey": 501, "kCGSSessionOnConsoleKey": True}
        cases = (([{**unlocked, "CGSSessionScreenIsLocked": True}], True),
                 ([unlocked], False),
                 ([{**unlocked, "kCGSSessionOnConsoleKey": False}], True),
                 ([{**unlocked, "kCGSSessionUserIDKey": 502, "CGSSessionScreenIsLocked": True}], None))
        for users, locked in cases:
            with self.subTest(users=users):
                self.assertIs(DIAGNOSTICS.session_locked(run=ioreg(users), uid=501), locked)

    def test_an_unanswered_probe_does_not_claim_a_lock(self):
        def fails(*_args, **_kwargs):
            raise subprocess.TimeoutExpired("ioreg", 10)

        garbage = lambda *_args, **_kwargs: subprocess.CompletedProcess([], 0, stdout=b"not a plist")
        for run in (ioreg([], returncode=1), fails, garbage):
            self.assertIsNone(DIAGNOSTICS.session_locked(run=run, uid=501))
        with patch.object(DIAGNOSTICS.sys, "platform", "linux"):
            self.assertIsNone(DIAGNOSTICS.session_locked(run=ioreg([]), uid=501))


class AppPidTests(unittest.TestCase):
    LISTING = "\n".join((
        " 101 /private/tmp/w/vizor/build/macos/Build/Products/Debug/Vizor.app/Contents/MacOS/Vizor",
        " 102 /tmp/w/vizor/build/macos/Build/Products/Debug/Vizor.app/Contents/MacOS/Vizor --flag",
        " 103 /Users/u/other/vizor/build/macos/Build/Products/Debug/Vizor.app/Contents/MacOS/Vizor",
        " 104 /private/tmp/w/vizor/build/macos/Build/Intermediates.noindex/tool",
        " 201 /Users/u/Library/Developer/CoreSimulator/Devices/UDID-1/data/Containers/Bundle/"
        "Application/A/Runner.app/Runner",
        " 203 /Users/u/Library/Developer/CoreSimulator/Devices/UDID-1/data/Containers/Bundle/"
        "Application/A/Runner.app/PlugIns/SyncWidgetExtension.appex/SyncWidgetExtension",
        " 202 /Users/u/Library/Developer/CoreSimulator/Devices/UDID-2/data/Containers/Bundle/"
        "Application/B/Runner.app/Runner",
    ))

    def listing(self, *_args, **_kwargs):
        return subprocess.CompletedProcess([], 0, stdout=self.LISTING)

    def test_finds_only_this_worktrees_macos_app(self):
        self.assertEqual(DIAGNOSTICS.app_pids("macos", source_root="/private/tmp/w/vizor", device="macos",
                                              run=self.listing), [101, 102])

    def test_finds_the_app_on_the_runs_simulator(self):
        self.assertEqual(DIAGNOSTICS.app_pids("ios", source_root="/private/tmp/w/vizor", device="UDID-1",
                                              run=self.listing), [201])


class SampleTests(unittest.TestCase):
    def test_writes_one_file_per_pid_and_skips_failures(self):
        calls = []

        def sample(command, **_kwargs):
            calls.append(command)
            if command[1] == "2":
                raise OSError("no such process")
            Path(command[-1]).write_text("stacks")
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as directory:
            stacks = Path(directory) / "stacks"
            written = DIAGNOSTICS.sample_stacks([1, 2], stacks, "phase-1-deadline", run=sample)
            self.assertEqual(written, [stacks / "phase-1-deadline-1.txt"])
        self.assertEqual(calls[0], [DIAGNOSTICS.SAMPLE, "1", str(DIAGNOSTICS.SAMPLE_SECONDS),
                                    str(DIAGNOSTICS.SAMPLE_INTERVAL_MS), "-file",
                                    str(stacks / "phase-1-deadline-1.txt")])


class StallRecorderTests(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.labels = []
        self.recorder = DIAGNOSTICS.StallRecorder(Path("/model/stacks"), lambda: [7], label="phase-2",
            clock=lambda: self.now,
            sample=lambda pids, _directory, label: self.labels.append((label, pids)))

    def at(self, seconds, output_count):
        self.now = seconds
        self.recorder.observe(output_count)
        self.recorder.join()

    def test_samples_after_quiet_output_at_most_twice(self):
        self.at(10, 5)
        self.at(10 + DIAGNOSTICS.STALL_SECONDS - 1, 5)
        self.assertEqual(self.labels, [])
        self.at(10 + DIAGNOSTICS.STALL_SECONDS, 5)
        self.assertEqual(self.labels, [("phase-2-stall-1", [7])])
        self.at(10 + 2 * DIAGNOSTICS.STALL_SECONDS, 5)
        self.at(10 + 4 * DIAGNOSTICS.STALL_SECONDS, 5)
        self.assertEqual([label for label, _ in self.labels], ["phase-2-stall-1", "phase-2-stall-2"])

    def test_new_output_restarts_the_quiet_period(self):
        self.at(10, 5)
        self.at(10 + DIAGNOSTICS.STALL_SECONDS - 1, 6)
        self.at(10 + DIAGNOSTICS.STALL_SECONDS + 1, 6)
        self.assertEqual(self.labels, [])

    def test_deadline_samples_immediately(self):
        self.recorder.record_now("deadline")
        self.assertEqual(self.labels, [("phase-2-deadline", [7])])


if __name__ == "__main__":
    unittest.main()
