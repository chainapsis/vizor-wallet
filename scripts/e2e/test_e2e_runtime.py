"""Host-only lifecycle checks using disposable, explicitly owned Python children."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch


SPEC = importlib.util.spec_from_file_location(
    "e2e_runtime", Path(__file__).with_name("e2e_runtime.py")
)
assert SPEC is not None and SPEC.loader is not None
RUNTIME = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RUNTIME
SPEC.loader.exec_module(RUNTIME)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-e2e-process-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.started = []
        self.addCleanup(self.cleanup_children)

    def cleanup_children(self):
        for managed in reversed(self.started):
            try:
                RUNTIME.terminate_process(managed)
            except RUNTIME.RunnerError:
                # Injected cleanup errors are sticky, even after physical release.
                self.assertTrue(managed._capture.closed)
            self.assertIsNotNone(managed.process.poll())
            self.assertFalse(managed.pump_thread.is_alive())
            with self.assertRaises(ProcessLookupError):
                os.killpg(managed.process.pid, 0)

    def start(self, source, **kwargs):
        managed = RUNTIME.start_logged_process(
            [sys.executable, "-c", source], cwd=self.root, env=os.environ.copy(),
            log_path=self.root / f"child-{len(self.started)}.log", **kwargs,
        )
        self.started.append(managed)
        return managed

    def wait(self, managed, *, timeout=3, cancel_event=None):
        return RUNTIME.wait_managed_process(
            managed, timeout=timeout, cancel_event=cancel_event or threading.Event(),
        )

    def wait_for_log(self, managed, text="ready"):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if managed.log_path.exists() and text in managed.log_path.read_text():
                return
            time.sleep(0.01)
        self.fail("owned fixture did not become ready")

    def assert_released(self, managed):
        self.assertIsNotNone(managed.process.poll())
        self.assertFalse(managed.pump_thread.is_alive())
        self.assertTrue(managed._capture.finished.is_set())
        self.assertTrue(managed.process.stdout.closed)
        self.assertTrue(managed.cleanup_completed)
        with self.assertRaises(ProcessLookupError):
            os.killpg(managed.process.pid, 0)

    def test_success_and_nonzero_codes_keep_complete_stdout_and_stderr(self):
        for code in (0, 7):
            lines = []
            managed = self.start(
                f"import sys; print('out',flush=True); print('err',file=sys.stderr); sys.exit({code})",
                raw_lines=lines,
            )
            self.assertEqual(self.wait(managed), code)
            self.assertEqual(lines, ["out\n", "err\n"])
            self.assertEqual(managed.log_path.read_text(), "out\nerr\n")
            self.assert_released(managed)

    def test_file_input_and_logged_command_result(self):
        request = self.root / "request.json"
        request.write_text('{"amount_zatoshi":100000000}')
        with request.open() as stdin:
            result = RUNTIME.run_logged_command(
                [sys.executable, "-c", "import json,sys; print(json.load(sys.stdin)['amount_zatoshi'])"],
                cwd=self.root, env=os.environ.copy(), log_path=self.root / "result.log",
                timeout=3, cancel_event=threading.Event(), stdin=stdin,
            )
        self.assertEqual(result, RUNTIME.CommandResult(0, ("100000000\n",)))
        self.assertEqual((self.root / "result.log").read_text(), "100000000\n")

    def test_empty_argument_is_valid_and_unrequested_raw_output_is_not_retained(self):
        managed = RUNTIME.start_logged_process(
            [sys.executable, "-c", "import sys; print(repr(sys.argv[1]))", ""],
            cwd=self.root, env=os.environ.copy(), log_path=self.root / "empty-argument.log",
        )
        self.started.append(managed)
        self.assertEqual(self.wait(managed), 0)
        self.assertEqual(managed.log_path.read_text(), "''\n")
        self.assertIsNone(managed._capture.lines)
        self.assert_released(managed)

    def test_known_markers_are_redacted_only_in_persisted_log(self):
        lines = []
        managed = self.start(
            "print('Mnemonic: dummy'); print('UNIFIED SPENDING KEY dummy'); "
            "print('\"seed_hex\":\"dummy\"'); print('ordinary')", raw_lines=lines,
        )
        self.assertEqual(self.wait(managed), 0)
        self.assertEqual(managed.log_path.read_text(), "[redacted regtest credential]\n" * 3 + "ordinary\n")
        self.assertEqual(lines[0], "Mnemonic: dummy\n")

    def test_pre_cancelled_command_reaps_child_and_pump(self):
        managed = self.start("import time; time.sleep(60)")
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaises(RUNTIME.Cancelled) as failure:
            self.wait(managed, cancel_event=cancelled)
        self.assertEqual(failure.exception.exit_code, 130)
        self.assert_released(managed)

    def test_timeout_reaps_child_and_pump(self):
        managed = self.start("import time; print('ready',flush=True); time.sleep(60)")
        self.wait_for_log(managed)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "timed out") as failure:
            self.wait(managed, timeout=0.05)
        self.assertEqual(failure.exception.exit_code, 124)
        self.assert_released(managed)

    def test_cancellation_reaps_descendant_but_preserves_sibling(self):
        sibling = self.start("import time; print('ready',flush=True); time.sleep(60)")
        managed = self.start(
            "import subprocess,sys,time; "
            "subprocess.Popen([sys.executable,'-c',\"import time; print('ready',flush=True); time.sleep(60)\"]); "
            "time.sleep(60)"
        )
        self.wait_for_log(managed)
        cancelled = threading.Event()
        cancelled.set()
        with self.assertRaises(RUNTIME.Cancelled):
            self.wait(managed, cancel_event=cancelled)
        self.assert_released(managed)
        self.assertIsNone(sibling.process.poll())
        self.assertTrue(sibling.pump_thread.is_alive())
        self.assertFalse(sibling.cleanup_completed)

    def test_keyboard_interrupt_reaps_started_group(self):
        managed = self.start(
            "import subprocess,sys,time; "
            "subprocess.Popen([sys.executable,'-c',\"import time; print('ready',flush=True); time.sleep(60)\"]); "
            "time.sleep(60)"
        )
        self.wait_for_log(managed)
        cancelled = Mock()
        cancelled.is_set.side_effect = KeyboardInterrupt
        with self.assertRaises(KeyboardInterrupt):
            self.wait(managed, cancel_event=cancelled)
        self.assert_released(managed)

    def test_parent_exit_does_not_hide_descendant_holding_stdout(self):
        managed = self.start(
            "import subprocess,sys; "
            "subprocess.Popen([sys.executable,'-c',\"import time; print('ready',flush=True); time.sleep(60)\"])"
        )
        self.wait_for_log(managed)
        self.assertEqual(managed.process.wait(timeout=3), 0)
        self.assertTrue(managed.pump_thread.is_alive())
        with self.assertRaises(RUNTIME.RunnerError) as failure:
            self.wait(managed, timeout=0.05)
        self.assertEqual(failure.exception.exit_code, 124)
        self.assert_released(managed)

    def test_output_eof_does_not_hide_live_descendant(self):
        managed = self.start(
            "import subprocess,sys; "
            "child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'],"
            "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); print(child.pid,flush=True)"
        )
        self.assertEqual(managed.process.wait(timeout=3), 0)
        managed.pump_thread.join(timeout=3)
        self.assertFalse(managed.pump_thread.is_alive())
        os.killpg(managed.process.pid, 0)
        with self.assertRaises(RUNTIME.RunnerError) as failure:
            self.wait(managed, timeout=0.05)
        self.assertEqual(failure.exception.exit_code, 124)
        self.assert_released(managed)

    def test_sigterm_resistant_child_is_killed_within_cleanup_budget(self):
        managed = self.start(
            "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            "print('ready',flush=True); time.sleep(60)"
        )
        self.wait_for_log(managed)
        before = time.monotonic()
        RUNTIME.terminate_process(managed, timeout=0.4)
        self.assertLess(time.monotonic() - before, 2)
        self.assertEqual(managed.process.returncode, -signal.SIGKILL)
        self.assert_released(managed)

    def test_sigkill_reaches_resistant_descendant_after_parent_exits(self):
        managed = self.start(
            "import subprocess,sys; "
            "subprocess.Popen([sys.executable,'-c',\"import signal,time; "
            "signal.signal(signal.SIGTERM,signal.SIG_IGN); print('ready',flush=True); time.sleep(60)\"])"
        )
        self.wait_for_log(managed)
        self.assertEqual(managed.process.wait(timeout=3), 0)
        RUNTIME.terminate_process(managed, timeout=0.4)
        self.assert_released(managed)

    def test_closed_handle_never_signals_a_reused_numeric_group(self):
        managed = self.start("print('done')")
        self.wait(managed)
        with patch.object(RUNTIME.os, "killpg", side_effect=AssertionError("must not signal")):
            RUNTIME.terminate_process(managed)
            self.assertEqual(self.wait(managed), 0)
        self.assertTrue(managed.cleanup_completed)

    def test_foreign_process_and_forged_handle_are_rejected_before_signalling(self):
        foreign = Mock(pid=os.getpid())
        forged = RUNTIME.ManagedProcess(
            foreign, self.root / "foreign.log", Mock(), Mock(), foreign.pid, object(),
        )
        with patch.object(RUNTIME.os, "killpg") as kill:
            for handle in (foreign, forged):
                with self.assertRaisesRegex(RUNTIME.RunnerError, "handle created"):
                    RUNTIME.terminate_process(handle)
                with self.assertRaises(RUNTIME.RunnerError):
                    self.wait(handle)
            kill.assert_not_called()

    def test_output_open_failure_is_not_a_successful_command(self):
        log_directory = self.root / "bad-log"
        log_directory.mkdir()
        managed = RUNTIME.start_logged_process(
            [sys.executable, "-c", "print('data')"], cwd=self.root,
            env=os.environ.copy(), log_path=log_directory,
        )
        self.started.append(managed)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "output capture failed"):
            self.wait(managed)
        self.assertFalse(managed.cleanup_completed)
        self.assertTrue(managed._capture.closed)
        self.assertIsInstance(managed._capture.errors[0], IsADirectoryError)

    def test_invalid_output_encoding_is_reported_and_child_is_reaped(self):
        managed = self.start("import sys,time; sys.stdout.buffer.write(b'\\xff\\n'); sys.stdout.flush(); time.sleep(60)")
        with self.assertRaisesRegex(RUNTIME.RunnerError, "output capture failed"):
            self.wait(managed)
        self.assertTrue(managed._capture.closed)
        self.assertFalse(managed.cleanup_completed)
        self.assertIsInstance(managed._capture.errors[0], UnicodeDecodeError)

    def test_live_output_pump_after_group_exit_is_sticky_cleanup_failure(self):
        release = threading.Event()
        original_pump = RUNTIME._pump_output

        def delayed_pump(capture):
            release.wait(timeout=3)
            original_pump(capture)

        with patch.object(RUNTIME, "_pump_output", side_effect=delayed_pump):
            managed = self.start("print('finished')")
        try:
            managed.process.wait(timeout=3)
            with self.assertRaisesRegex(RUNTIME.RunnerError, "output pump did not finish"):
                RUNTIME.terminate_process(managed, timeout=0.05)
            self.assertFalse(managed.cleanup_completed)
            self.assertTrue(managed.pump_thread.is_alive())
        finally:
            release.set()
            managed.pump_thread.join(timeout=3)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "output pump did not finish"):
            RUNTIME.terminate_process(managed)
        self.assertTrue(managed._capture.closed)
        self.assertFalse(managed.cleanup_completed)

    def test_signal_failure_is_not_hidden_by_later_successful_cleanup(self):
        managed = self.start("import time; print('ready',flush=True); time.sleep(60)")
        sibling = self.start("import time; time.sleep(60)")
        self.wait_for_log(managed)
        with patch.object(RUNTIME, "_signal_group", side_effect=PermissionError("injected signal failure")):
            with self.assertRaisesRegex(RUNTIME.RunnerError, "injected signal failure"):
                RUNTIME.terminate_process(managed, timeout=0.05)
        self.assertIsNone(managed.process.poll())
        self.assertIsNone(sibling.process.poll())
        self.assertFalse(managed.cleanup_completed)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "injected signal failure"):
            RUNTIME.terminate_process(managed)
        self.assertTrue(managed._capture.closed)
        self.assertFalse(managed.cleanup_completed)

    def test_permission_error_never_counts_as_group_absence(self):
        managed = self.start("print('finished')")
        managed.process.wait(timeout=3)
        managed.pump_thread.join(timeout=3)
        with patch.object(RUNTIME.os, "killpg", side_effect=PermissionError("injected probe failure")):
            with self.assertRaisesRegex(RUNTIME.RunnerError, "injected probe failure"):
                RUNTIME.terminate_process(managed, timeout=0.05)
        self.assertFalse(managed._capture.group_gone)
        self.assertFalse(managed.cleanup_completed)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "injected probe failure"):
            RUNTIME.terminate_process(managed)
        self.assertTrue(managed._capture.closed)

    def test_output_join_exception_remains_failed_after_retry(self):
        managed = self.start("print('finished')")
        managed.process.wait(timeout=3)
        managed.pump_thread.join(timeout=3)
        with patch.object(managed.pump_thread, "join", side_effect=RuntimeError("injected join failure")):
            with self.assertRaisesRegex(RuntimeError, "injected join failure"):
                RUNTIME.terminate_process(managed)
        self.assertFalse(managed.cleanup_completed)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "injected join failure"):
            RUNTIME.terminate_process(managed)
        self.assertTrue(managed._capture.closed)

    def test_invalid_wait_timeout_still_cleans_an_already_started_child(self):
        managed = self.start("import time; time.sleep(60)")
        with self.assertRaisesRegex(RUNTIME.RunnerError, "timeout must be"):
            self.wait(managed, timeout=0)
        self.assert_released(managed)

    def test_thread_start_failure_rolls_back_started_process_and_pipe(self):
        real_popen = RUNTIME.subprocess.Popen
        processes = []

        def capture_process(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            processes.append(process)
            return process

        with patch.object(RUNTIME.subprocess, "Popen", side_effect=capture_process), patch.object(
            RUNTIME.threading.Thread, "start", side_effect=RuntimeError("injected thread start failure"),
        ):
            with self.assertRaisesRegex(RuntimeError, "injected thread start failure"):
                self.start("import time; time.sleep(60)")
        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].poll())
        self.assertTrue(processes[0].stdout.closed)
        with self.assertRaises(ProcessLookupError):
            os.killpg(processes[0].pid, 0)

    def test_thread_start_interrupt_rolls_back_started_process(self):
        real_popen = RUNTIME.subprocess.Popen
        processes = []

        def capture_process(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            processes.append(process)
            return process

        with patch.object(RUNTIME.subprocess, "Popen", side_effect=capture_process), patch.object(
            RUNTIME.threading.Thread, "start", side_effect=KeyboardInterrupt,
        ):
            with self.assertRaises(KeyboardInterrupt):
                self.start("import time; time.sleep(60)")
        self.assertIsNotNone(processes[0].poll())
        self.assertTrue(processes[0].stdout.closed)

    def test_cleanup_error_preserves_primary_classification_and_cause(self):
        for primary, expected_type, code in (
            (KeyboardInterrupt(), KeyboardInterrupt, None),
            (RUNTIME.Cancelled(), RUNTIME.Cancelled, 130),
            (RUNTIME.RunnerError("timed out", 124), RUNTIME.RunnerError, 124),
            (RUNTIME.RunnerError("original failure", 37), RUNTIME.RunnerError, 37),
        ):
            with self.subTest(primary=type(primary).__name__, code=code):
                for cleanup_type in (RUNTIME.RunnerError, RuntimeError, KeyboardInterrupt):
                    cleanup = cleanup_type("injected cleanup failure")
                    with patch.object(RUNTIME, "terminate_process", side_effect=cleanup):
                        with self.assertRaisesRegex(expected_type, "cleanup failed after") as failure:
                            try:
                                raise primary
                            except BaseException as error:
                                RUNTIME._cleanup_after_error(Mock(), error)
                    self.assertIs(failure.exception.__cause__, cleanup)
                    self.assertIs(cleanup.__context__, primary)
                    if code is not None:
                        self.assertEqual(failure.exception.exit_code, code)

    def test_invalid_arguments_fail_before_spawn(self):
        with patch.object(RUNTIME.subprocess, "Popen") as spawn:
            for command in ([], "not-an-argv", [""], [None], ["a\0b"]):
                with self.assertRaises(RUNTIME.RunnerError):
                    RUNTIME.start_logged_process(command, cwd=self.root, env={}, log_path=self.root / "unused")
            for timeout in (True, 0, -1, float("nan"), float("inf"), "1"):
                with self.assertRaises(RUNTIME.RunnerError):
                    RUNTIME.run_logged_command(
                        ["unused"], cwd=self.root, env={}, log_path=self.root / "unused",
                        timeout=timeout, cancel_event=threading.Event(),
                    )
            with self.assertRaises(RUNTIME.RunnerError):
                self.start("unused", stdin=subprocess.PIPE)
            spawn.assert_not_called()

    def test_spawn_failure_keeps_the_original_os_error(self):
        with self.assertRaisesRegex(RUNTIME.RunnerError, "failed to start") as failure:
            RUNTIME.start_logged_process(
                [str(self.root / "missing-program")], cwd=self.root,
                env=os.environ.copy(), log_path=self.root / "unused",
            )
        self.assertIsInstance(failure.exception.__cause__, FileNotFoundError)
        self.assertEqual(failure.exception.exit_code, 1)


if __name__ == "__main__":
    unittest.main()
