"""Host-only lifecycle checks using disposable, explicitly owned Python children."""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import textwrap
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
            self.assert_group_released(managed)

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
        self.assert_group_released(managed)

    def assert_group_released(self, managed):
        deadline = time.monotonic() + 1
        while True:
            try:
                os.killpg(managed.process.pid, 0)
            except ProcessLookupError:
                return
            self.assertEqual(sys.platform, "linux", "owned group still exists")
            self.assertTrue(managed._capture.group_quiescent, "group quiescence was not verified")
            self.assertTrue(managed.unreaped_zombie_pids, "no external zombies were recorded")
            snapshot = RUNTIME._linux_zombie_snapshot(managed.process.pid, deadline)
            if snapshot:
                self.assertLessEqual(
                    {member[0] for member in snapshot}, set(managed.unreaped_zombie_pids),
                    "remaining group contains unrecorded members",
                )
                return
            # An external parent can reap members during the inventory. Retry
            # the absence probe, but never accept a live/incomplete snapshot.
            if time.monotonic() >= deadline:
                self.fail("remaining group is not verifiably zombie-only")
            time.sleep(0.01)

    def test_release_helper_accepts_group_absence_without_zombie_proof(self):
        managed = Mock()
        with patch.object(RUNTIME.os, "killpg", side_effect=ProcessLookupError), patch.object(
            RUNTIME, "_linux_zombie_snapshot",
        ) as snapshot:
            self.assert_group_released(managed)
            snapshot.assert_not_called()

    def test_release_helper_accepts_only_remaining_recorded_zombies(self):
        managed = Mock()
        managed._capture.group_quiescent = True
        managed.unreaped_zombie_pids = (2002, 2004)
        snapshot = ((2002, 1, 12345, ((2002, 12345),)),)
        with patch.object(RUNTIME.sys, "platform", "linux"), patch.object(
            RUNTIME.os, "killpg", return_value=None,
        ), patch.object(RUNTIME, "_linux_zombie_snapshot", return_value=snapshot):
            # Already-reaped members need not remain in the current inventory.
            self.assert_group_released(managed)

    def test_release_helper_requires_recorded_quiescence(self):
        managed = Mock()
        with patch.object(RUNTIME.sys, "platform", "linux"), patch.object(
            RUNTIME.os, "killpg", return_value=None,
        ), patch.object(RUNTIME, "_linux_zombie_snapshot") as snapshot:
            for quiescent, zombies in ((False, (2002,)), (True, ())):
                with self.subTest(quiescent=quiescent, zombies=zombies):
                    managed._capture.group_quiescent = quiescent
                    managed.unreaped_zombie_pids = zombies
                    with self.assertRaises(AssertionError):
                        self.assert_group_released(managed)
            snapshot.assert_not_called()

    def test_release_helper_rejects_incomplete_or_unrecorded_members(self):
        managed = Mock()
        managed._capture.group_quiescent = True
        managed.unreaped_zombie_pids = (2002,)
        with patch.object(RUNTIME.sys, "platform", "linux"), patch.object(
            RUNTIME.os, "killpg", return_value=None,
        ):
            with patch.object(RUNTIME, "_linux_zombie_snapshot", return_value=None), patch.object(
                RUNTIME.time, "monotonic", side_effect=(0, 2),
            ):
                with self.assertRaisesRegex(AssertionError, "not verifiably zombie-only"):
                    self.assert_group_released(managed)
            unrecorded = ((2004, 1, 12345, ((2004, 12345),)),)
            with patch.object(RUNTIME, "_linux_zombie_snapshot", return_value=unrecorded):
                with self.assertRaisesRegex(AssertionError, "unrecorded members"):
                    self.assert_group_released(managed)

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

    def test_bounded_capture_stops_long_unterminated_line_and_continuous_stream(self):
        for source in ("import sys,time; sys.stdout.write('x'*5000); sys.stdout.flush(); time.sleep(30)",
                       "import os\nwhile True: os.write(1,b'x'*49+b'\\n')"):
            lines = []
            started = time.monotonic()
            managed = self.start(source, raw_lines=lines, max_output_bytes=1024)
            with self.subTest(source=source), self.assertRaises(RUNTIME.OutputLimitExceeded):
                self.wait(managed)
            self.assertLess(time.monotonic()-started, 2)
            self.assertLessEqual(sum(len(line.encode("utf-8")) for line in lines), 1024)
            self.assertLessEqual(managed.log_path.stat().st_size, 1024)
            self.assert_released(managed)

    def test_bounded_capture_preserves_split_utf8_crlf_and_final_partial_line(self):
        lines = []
        with patch.object(RUNTIME, "_OUTPUT_READ_BYTES", 1):
            managed = self.start("import sys; sys.stdout.buffer.write('안녕\\r\\n끝'.encode())",
                                 raw_lines=lines, max_output_bytes=32)
            self.assertEqual(self.wait(managed), 0)
        self.assertEqual(lines, ["안녕\n", "끝"])
        self.assertEqual(managed.log_path.read_text(), "안녕\n끝")
        self.assert_released(managed)

    def test_output_limit_validates_before_spawn(self):
        with patch.object(RUNTIME.subprocess, "Popen") as spawn:
            for value in (False, 0, -1, 1.5, "1024"):
                with self.assertRaises(RUNTIME.RunnerError):
                    self.start("pass", max_output_bytes=value)
            spawn.assert_not_called()

    def test_limit_error_arriving_after_wait_check_cannot_become_success(self):
        release = threading.Event()
        pump = RUNTIME._pump_output
        group = RUNTIME._group_active
        def delayed(capture):
            release.wait(timeout=3)
            pump(capture)
        with patch.object(RUNTIME, "_pump_output", side_effect=delayed):
            managed = self.start("import sys; sys.stdout.write('x'*4096)", max_output_bytes=512)
        try:
            managed.process.wait(timeout=3)
            def finish_pump_then_probe(owner, *, deadline=None):
                release.set()
                managed.pump_thread.join(timeout=3)
                return group(owner, deadline=deadline)
            with patch.object(RUNTIME, "_group_active", side_effect=finish_pump_then_probe):
                with self.assertRaises(RUNTIME.OutputLimitExceeded):
                    self.wait(managed)
            self.assert_released(managed)
        finally:
            release.set()
            managed.pump_thread.join(timeout=3)

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

    @unittest.skipUnless(sys.platform == "linux", "requires real Linux adoption/procfs")
    def test_external_reaper_zombies_are_recorded_without_signalling_again(self):
        observer = textwrap.dedent("""
            import os,sys,tempfile,threading,time
            from pathlib import Path
            import e2e_runtime as runtime
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = "import subprocess,sys; subprocess.Popen([sys.executable,'-c','import time; time.sleep(60)'])"
                managed = runtime.start_logged_process([sys.executable,'-c',source],
                    cwd=root,env=os.environ.copy(),log_path=root/'child.log')
                try:
                    try:
                        runtime.wait_managed_process(managed,timeout=.2,cancel_event=threading.Event())
                    except runtime.RunnerError as error:
                        assert error.exit_code == 124, str(error)
                    else:
                        raise AssertionError('live orphan counted as completed')
                    assert managed.cleanup_completed
                    assert managed.unreaped_zombie_pids
                    assert all(runtime._linux_task_state(Path('/proc')/str(pid)/'stat',pid)[0]=='Z'
                               for pid in managed.unreaped_zombie_pids)
                    def forbidden(*_args): raise AssertionError('signalled completed group')
                    original = os.killpg
                    os.killpg = forbidden
                    try: runtime.terminate_process(managed)
                    finally: os.killpg = original
                    print('external zombies explicitly recorded',flush=True)
                finally:
                    # Only this fixture's group; the holder retains zombie IDs
                    # until the observer exits, so those IDs cannot be reused.
                    if not managed._capture.group_gone:
                        try: os.killpg(managed.process.pid,9)
                        except ProcessLookupError: pass
                    managed.process.wait(timeout=2)
                    managed.pump_thread.join(timeout=2)
        """)
        self.run_external_reaper_fixture(observer)

    @unittest.skipUnless(sys.platform == "linux", "requires real Linux adoption/procfs")
    def test_natural_completion_with_external_zombies_preserves_exit_code(self):
        observer = textwrap.dedent("""
            import os,sys,tempfile,threading
            from pathlib import Path
            import e2e_runtime as runtime
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for code in (0,7):
                    source = "import os,subprocess,sys,time; child=subprocess.Popen([sys.executable,'-c','pass']); " + \
                        "time.sleep(.1); os._exit(%d)" % code
                    managed = runtime.start_logged_process([sys.executable,'-c',source],
                        cwd=root,env=os.environ.copy(),log_path=root/('child-%d.log'%code))
                    try:
                        assert runtime.wait_managed_process(managed,timeout=3,
                            cancel_event=threading.Event()) == code
                        assert managed.cleanup_completed
                        assert managed.unreaped_zombie_pids
                    finally:
                        if not managed._capture.group_gone:
                            try: os.killpg(managed.process.pid,9)
                            except ProcessLookupError: pass
                        managed.process.wait(timeout=2)
                        managed.pump_thread.join(timeout=2)
                print('natural completion retained both exit codes',flush=True)
        """)
        self.run_external_reaper_fixture(observer)

    @unittest.skipUnless(sys.platform == "linux", "requires real Linux threads/procfs")
    def test_zombie_leader_with_live_thread_is_not_quiescent(self):
        observer = textwrap.dedent("""
            import os,sys,tempfile,threading,time
            from pathlib import Path
            import e2e_runtime as runtime
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                ready = root/'ready'
                thread_source = "import ctypes,threading; from pathlib import Path; " + \
                    "threading.Thread(target=lambda: threading.Event().wait(60)).start(); " + \
                    "Path(%r).write_text('ready'); ctypes.CDLL(None).pthread_exit(None)" % str(ready)
                source = "import subprocess,sys; child=subprocess.Popen([sys.executable,'-c',%r]," % thread_source + \
                    "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); print(child.pid,flush=True)"
                lines=[]
                managed = runtime.start_logged_process([sys.executable,'-c',source],
                    cwd=root,env=os.environ.copy(),log_path=root/'child.log',raw_lines=lines)
                try:
                    managed.process.wait(timeout=2)
                    managed.pump_thread.join(timeout=2)
                    pid=int(lines[0])
                    deadline=time.monotonic()+2
                    while runtime._linux_task_state(Path('/proc')/str(pid)/'stat',pid)[0]!='Z':
                        assert time.monotonic()<deadline, 'thread leader did not exit'
                        time.sleep(.01)
                    assert runtime._group_active(managed,deadline=time.monotonic()+.5), 'live thread was ignored'
                    assert not managed.cleanup_completed
                    runtime.terminate_process(managed)
                    assert managed.cleanup_completed
                    print('live thread prevented quiescence',flush=True)
                finally:
                    if not managed._capture.group_gone:
                        try: os.killpg(managed.process.pid,9)
                        except ProcessLookupError: pass
                    managed.process.wait(timeout=2)
                    managed.pump_thread.join(timeout=2)
        """)
        self.run_external_reaper_fixture(observer)

    @unittest.skipUnless(sys.platform == "linux", "requires real Linux adoption/procfs")
    def test_release_helpers_with_external_reaper(self):
        observer = textwrap.dedent("""
            import sys,unittest
            from test_e2e_runtime import RuntimeTests
            names = (
                'test_cancellation_reaps_descendant_but_preserves_sibling',
                'test_keyboard_interrupt_reaps_started_group',
                'test_parent_exit_does_not_hide_descendant_holding_stdout',
                'test_output_eof_does_not_hide_live_descendant',
                'test_sigkill_reaches_resistant_descendant_after_parent_exits',
            )
            suite=unittest.TestSuite(RuntimeTests(name) for name in names)
            result=unittest.TextTestRunner(verbosity=2).run(suite)
            sys.exit(0 if result.wasSuccessful() else 1)
        """)
        self.run_external_reaper_fixture(observer)

    def run_external_reaper_fixture(self, observer):
        # PR_SET_CHILD_SUBREAPER affects only this owned fixture child, not the
        # test runner or unrelated subprocesses. It deliberately delays reap
        # until the observer has inspected externally parented zombies.
        module_root = str(Path(__file__).resolve().parent)
        holder = textwrap.dedent(f"""
            import ctypes,os,subprocess,sys
            result=ctypes.CDLL(None,use_errno=True).prctl(36,1,0,0,0)
            assert result==0, ctypes.get_errno()
            observer=subprocess.Popen([sys.executable,'-B','-c',{observer!r}],
                env={{**os.environ,'PYTHONPATH':{module_root!r}}})
            code=observer.wait(timeout=12)
            # Every child in this private fixture belongs to this test.
            while True:
                try: os.waitpid(-1,0)
                except ChildProcessError: break
            sys.exit(code)
        """)
        managed = self.start(holder)
        self.assertEqual(self.wait(managed, timeout=15), 0, managed.log_path.read_text())
        self.assert_released(managed)


class LinuxGroupProofTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-linux-group-proof-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.group = 2000
        self.parent = os.getpid() + 100000
        self.groups = {}
        process = Mock(pid=self.group)
        process.poll.return_value = 0
        self.capture = RUNTIME._Capture(self.root / "unused.log", None)
        self.managed = RUNTIME.ManagedProcess(
            process, self.capture.log_path, Mock(), self.capture,
            self.group, RUNTIME._OWNERSHIP_TOKEN,
        )
        for patcher in (
            patch.object(RUNTIME.sys, "platform", "linux"),
            patch.object(RUNTIME, "_LINUX_PROC_ROOT", self.root),
            patch.object(RUNTIME.os, "getpgid", side_effect=lambda pid: self.groups[pid]),
            patch.object(RUNTIME.os, "killpg", return_value=None),
            patch.object(RUNTIME.os, "waitpid", side_effect=ChildProcessError),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def add_member(self, pid, state="Z", *, parent=None, session=None, thread_state=None):
        self.groups[pid] = self.group
        tail = [b"0"] * 20
        tail[0] = state.encode()
        tail[1] = str(self.parent if parent is None else parent).encode()
        tail[2] = str(self.group).encode()
        tail[3] = str(self.group if session is None else session).encode()
        tail[19] = b"12345"
        raw = str(pid).encode() + b" (fixture ) (\xff) " + b" ".join(tail) + b"\n"
        entry = self.root / str(pid)
        task = entry / "task" / str(pid)
        task.mkdir(parents=True)
        (entry / "stat").write_bytes(raw)
        (task / "stat").write_bytes(raw)
        if thread_state is not None:
            tid = pid + 1
            thread = entry / "task" / str(tid)
            thread.mkdir()
            tail[0] = thread_state.encode()
            (thread / "stat").write_bytes(str(tid).encode() + b" (thread) " + b" ".join(tail))

    def active(self):
        return RUNTIME._group_active(self.managed, deadline=time.monotonic() + 1)

    def test_only_positive_stable_zombie_proof_finishes_group(self):
        self.add_member(2002)
        self.add_member(2004)
        self.assertFalse(self.active())
        self.assertFalse(self.capture.group_gone, "kernel records still exist")
        self.assertTrue(self.capture.group_quiescent)
        self.assertEqual(self.managed.unreaped_zombie_pids, (2002, 2004))

    def test_live_and_stopped_states_are_not_zombies(self):
        for state in ("R", "S", "D", "T", "t", "X", "I"):
            with self.subTest(state=state):
                with patch.object(RUNTIME, "_linux_task_state", return_value=(state, self.parent, self.group, self.group, 1)):
                    self.add_member(2002 + len(self.groups))
                    self.assertTrue(self.active())
                    self.assertFalse(self.capture.group_quiescent)

    def test_zombie_leader_with_live_thread_is_not_a_positive_proof(self):
        self.add_member(2002, thread_state="S")
        self.assertTrue(self.active())
        self.assertEqual(self.managed.unreaped_zombie_pids, ())

    def test_owned_zombies_must_be_reaped_not_recorded_as_external(self):
        self.add_member(2002, parent=os.getpid())
        self.assertTrue(self.active())
        self.assertFalse(self.capture.group_quiescent)

    def test_empty_or_missing_thread_inventory_is_uncertainty(self):
        self.add_member(2002)
        task = self.root / "2002" / "task" / "2002"
        (task / "stat").unlink()
        self.assertTrue(self.active())
        task.rmdir()
        self.assertTrue(self.active())
        self.assertFalse(self.capture.group_quiescent)

    def test_missing_procfs_and_unreadable_stats_are_errors_not_success(self):
        with patch.object(RUNTIME, "_LINUX_PROC_ROOT", self.root / "missing"):
            with self.assertRaises(FileNotFoundError):
                self.active()
        self.add_member(2002)
        with patch.object(RUNTIME, "_linux_task_state", side_effect=PermissionError("injected procfs denial")):
            with self.assertRaises(PermissionError):
                self.active()
        self.assertFalse(self.capture.group_quiescent)

    def test_malformed_stat_and_wrong_session_cannot_prove_completion(self):
        self.add_member(2002, session=9999)
        self.assertTrue(self.active())
        (self.root / "2002" / "stat").write_bytes(b"2002 (broken) Z")
        with self.assertRaises(RUNTIME.RunnerError):
            self.active()
        self.assertFalse(self.capture.group_quiescent)

    def test_changed_members_or_pid_birth_time_require_another_attempt(self):
        first = ((2002, self.parent, 12345, ((2002, 12345),)),)
        changed = ((2002, self.parent, 12346, ((2002, 12346),)),)
        with patch.object(RUNTIME, "_linux_zombie_snapshot", side_effect=(first, changed)):
            self.assertTrue(self.active())
        self.assertFalse(self.capture.group_quiescent)

    def test_reap_is_scoped_and_never_steals_the_popen_child_status(self):
        with patch.object(RUNTIME.os, "waitpid", side_effect=((2002, 0), (2004, 0), ChildProcessError)) as wait:
            self.active()
        self.assertEqual(wait.call_args_list, [unittest.mock.call(-self.group, os.WNOHANG)] * 3)
        self.managed.process.poll.return_value = None
        with patch.object(RUNTIME.os, "waitpid") as wait:
            self.assertTrue(self.active())
            wait.assert_not_called()

    def test_expired_proof_budget_does_not_mark_quiescence(self):
        self.add_member(2002)
        self.assertIsNone(RUNTIME._linux_zombie_snapshot(self.group, time.monotonic() - 1))
        self.assertFalse(self.capture.group_quiescent)


if __name__ == "__main__":
    unittest.main()
