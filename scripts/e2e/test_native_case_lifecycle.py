"""Case-bound lifecycle checks using only private files and owned Python children."""

from __future__ import annotations

import dataclasses
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
try:
    import native_case_lifecycle as LIFECYCLE
    import native_workspace as WORKSPACE
finally:
    sys.path.pop(0)
RUNTIME = LIFECYCLE.runtime


class NativeCaseLifecycleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-case-lifecycle-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.run_root = self.root / "run"
        self.run_root.mkdir(mode=0o700)
        self.cases = []
        self.started = []
        self.addCleanup(self.cleanup_children)
        self.case = self.make_case()

    def make_case(self, *, case_index=17, platform="macos"):
        workspace = WORKSPACE.prepare_native_case_workspace(
            self.run_root, platform=platform, scenario_id=f"flutter.{platform}.contract-probe",
            run_id="a1b2c3d4e5", worker_id=2, case_index=case_index,
            ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=500,
        )
        case = LIFECYCLE.NativeCaseLifecycle(workspace)
        self.cases.append(case)
        return case

    def start(self, source, *, case=None, **updates):
        selected = self.case if case is None else case
        managed = selected.start_process([sys.executable, "-B", "-c", source], env=os.environ, **updates)
        self.started.append(managed)
        return managed

    def wait(self, managed, *, case=None, timeout=3, cancel_event=None):
        return (self.case if case is None else case).wait_process(
            managed, timeout=timeout, cancel_event=cancel_event or threading.Event(),
        )

    def ready(self, managed, marker="ready"):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if managed.log_path.exists() and marker in managed.log_path.read_text():
                return
            time.sleep(0.01)
        self.fail("owned fixture did not become ready")

    def assert_physically_released(self, managed):
        self.assertIsNotNone(managed.process.poll())
        self.assertFalse(managed.pump_thread.is_alive())
        self.assertTrue(managed.process.stdout.closed)
        self.assertTrue(managed._capture.closed)

    def cleanup_children(self):
        for case in self.cases:
            try:
                case.close()
            except RUNTIME.RunnerError:
                self.assertIsNone(case._receipt)
        for managed in self.started:
            try:
                RUNTIME.terminate_process(managed)
            except RUNTIME.RunnerError:
                self.assertFalse(managed.cleanup_completed)
            self.assert_physically_released(managed)

    def test_launch_binds_real_child_environment_cwd_and_private_log(self):
        source = (
            "import json,os; print(json.dumps({'cwd':os.getcwd(), "
            "'namespace':os.environ['VIZOR_E2E_NAMESPACE'], "
            "'manifest':json.loads(os.environ['VIZOR_E2E_CASE_MANIFEST'])})); "
            "print('mnemonic: disposable-fixture')"
        )
        managed = self.start(source)
        self.assertEqual(self.wait(managed), 0)
        lines = managed.log_path.read_text().splitlines()
        observed = json.loads(lines[0])
        self.assertEqual(observed["cwd"], str(self.case.workspace.root))
        self.assertEqual(observed["namespace"], self.case.workspace.namespace)
        expected = json.loads(self.case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
        self.assertEqual(observed["manifest"], expected)
        self.assertEqual(lines[1], "[redacted regtest credential]")
        self.assertEqual(managed.log_path.stat().st_mode & 0o777, 0o600)

    def test_ios_launch_keeps_app_support_identity(self):
        case = self.make_case(case_index=18, platform="ios")
        managed = self.start("import os; print(os.environ['VIZOR_E2E_CASE_MANIFEST'])", case=case)
        self.assertEqual(self.wait(managed, case=case), 0)
        observed = json.loads(managed.log_path.read_text())
        self.assertEqual(observed["context_path"], "app-support")
        self.assertFalse((case.workspace.root / "native-context.json").exists())

    def test_conflicting_identity_is_rejected_before_log_or_spawn(self):
        expected = self.case.workspace.launch_environment()
        for key in expected:
            with self.subTest(key=key), patch.object(RUNTIME, "start_logged_process") as started:
                with self.assertRaisesRegex(RUNTIME.RunnerError, "conflicts"):
                    self.case.start_process([sys.executable, "-c", "pass"], env={key: "wrong"})
                started.assert_not_called()
        self.assertFalse((self.case.workspace.root / "process-0000.log").exists())

    def test_matching_supplied_identity_is_accepted_without_mutating_input(self):
        environment = {**os.environ, **self.case.workspace.launch_environment()}
        original = environment.copy()
        managed = self.case.start_process([sys.executable, "-c", "pass"], env=environment)
        self.started.append(managed)
        self.assertEqual(self.wait(managed), 0)
        self.assertEqual(environment, original)

    def test_one_case_cannot_be_claimed_by_another_owner_or_clone(self):
        for workspace in (self.case.workspace, dataclasses.replace(self.case.workspace)):
            with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "already claimed"):
                LIFECYCLE.NativeCaseLifecycle(workspace)
        self.case.close()
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            LIFECYCLE.NativeCaseLifecycle(self.case.workspace)

    def test_invalid_or_forged_workspace_is_not_adopted(self):
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            LIFECYCLE.NativeCaseLifecycle(None)
        forged = dataclasses.replace(self.case.workspace, _ownership_token=object())
        with patch.object(WORKSPACE.os, "open") as opened:
            with self.assertRaises(WORKSPACE.NativeWorkspaceError):
                LIFECYCLE.NativeCaseLifecycle(forged)
            opened.assert_not_called()

    def test_real_restart_reuses_identity_without_resetting_state(self):
        source = (
            "import os; from pathlib import Path; p=Path('state'); "
            "n=int(p.read_text()) if p.exists() else 0; p.write_text(str(n+1)); "
            "print(os.environ['VIZOR_E2E_CASE_MANIFEST'])"
        )
        first = self.start(source)
        self.assertEqual(self.wait(first), 0)
        second = self.start(source)
        self.assertEqual(self.wait(second), 0)
        self.assertNotEqual(first.process.pid, second.process.pid)
        self.assertEqual(first.log_path.read_text(), second.log_path.read_text())
        self.assertEqual((self.case.workspace.root / "state").read_text(), "2")
        receipt = self.case.close()
        self.assertEqual(receipt.exit_codes, (0, 0))

    def test_individual_stop_allows_same_case_restart(self):
        first = self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.ready(first)
        self.case.stop_process(first)
        self.assert_physically_released(first)
        second = self.start("print('restarted')")
        self.assertEqual(self.wait(second), 0)
        self.assertEqual(len(self.case.close().exit_codes), 2)

    def test_final_close_stops_all_groups_and_preserves_files(self):
        children = [self.start("import time; print('ready',flush=True); time.sleep(30)") for _ in range(3)]
        for managed in children:
            self.ready(managed)
        state = self.case.workspace.root / "state"
        state.write_text("must survive")
        receipt = self.case.close()
        self.assertEqual(receipt.namespace, self.case.workspace.namespace)
        self.assertEqual(receipt.workspace, str(self.case.workspace.root))
        self.assertEqual(len(receipt.exit_codes), 3)
        for managed in children:
            self.assert_physically_released(managed)
            self.assertTrue(managed.cleanup_completed)
            self.assertTrue(managed.log_path.exists())
        self.assertEqual(state.read_text(), "must survive")
        self.assertTrue(self.case.workspace.marker_path.exists())
        self.assertTrue(self.case.workspace.manifest_path.exists())

    def test_case_close_does_not_stop_a_sibling_case(self):
        sibling = self.make_case(case_index=18)
        selected = self.start("import time; print('ready',flush=True); time.sleep(30)")
        other = self.start("import time; print('ready',flush=True); time.sleep(30)", case=sibling)
        self.ready(selected)
        self.ready(other)
        self.case.close()
        self.assert_physically_released(selected)
        self.assertIsNone(other.process.poll())
        sibling.workspace.verify_owned()

    def test_foreign_process_and_copied_handle_are_rejected_before_runtime_calls(self):
        sibling = self.make_case(case_index=18)
        foreign = self.start("print('other')", case=sibling)
        owned = self.start("print('owned')")
        for handle in (foreign, dataclasses.replace(owned), object()):
            with patch.object(RUNTIME, "terminate_process") as stop, patch.object(RUNTIME, "wait_managed_process") as wait:
                with self.assertRaisesRegex(RUNTIME.RunnerError, "not launched"):
                    self.case.stop_process(handle)
                with self.assertRaisesRegex(RUNTIME.RunnerError, "not launched"):
                    self.case.wait_process(handle, timeout=1, cancel_event=threading.Event())
                stop.assert_not_called()
                wait.assert_not_called()

    def test_close_is_idempotent_and_never_reopens_launches(self):
        managed = self.start("pass")
        self.assertEqual(self.wait(managed), 0)
        receipt = self.case.close()
        with patch.object(RUNTIME.os, "killpg", side_effect=AssertionError("retired group signalled")):
            self.assertIs(self.case.close(), receipt)
            self.case.stop_process(managed)
        with patch.object(RUNTIME, "start_logged_process") as started:
            with self.assertRaisesRegex(RUNTIME.RunnerError, "sealed"):
                self.start("pass")
            started.assert_not_called()

    def test_empty_case_receipt_is_not_native_storage_cleanup(self):
        context = self.case.workspace.root / "native-context.json"
        context.write_text('{"storage_cleanup_completed":false}')
        receipt = self.case.close()
        self.assertEqual(receipt.exit_codes, ())
        self.assertEqual(receipt.external_zombie_pids, ())
        self.assertFalse(hasattr(receipt, "storage_cleanup_completed"))
        self.assertEqual(context.read_text(), '{"storage_cleanup_completed":false}')

    def test_nonzero_execution_remains_nonzero_after_successful_cleanup(self):
        managed = self.start("raise SystemExit(23)")
        self.assertEqual(self.wait(managed), 23)
        self.assertEqual(self.case.close().exit_codes, (23,))

    def test_timeout_classification_survives_successful_process_cleanup(self):
        managed = self.start("import time; time.sleep(30)")
        with self.assertRaises(RUNTIME.RunnerError) as raised:
            self.wait(managed, timeout=0.06)
        self.assertEqual(raised.exception.exit_code, 124)
        self.assertTrue(managed.cleanup_completed)
        self.assertEqual(self.case.close().exit_codes, (managed.process.returncode,))

    def test_cancellation_classification_survives_successful_process_cleanup(self):
        managed = self.start("import time; time.sleep(30)")
        cancellation = threading.Event()
        cancellation.set()
        with self.assertRaises(RUNTIME.Cancelled) as raised:
            self.wait(managed, cancel_event=cancellation)
        self.assertEqual(raised.exception.exit_code, 130)
        self.assertTrue(managed.cleanup_completed)
        self.case.close()

    def test_descendant_after_parent_exit_is_stopped_before_case_receipt(self):
        source = (
            "import subprocess,sys; subprocess.Popen([sys.executable,'-c',"
            "\"import time; print('descendant-ready',flush=True); time.sleep(30)\"]); "
            "print('parent-exit',flush=True)"
        )
        managed = self.start(source)
        self.ready(managed, "descendant-ready")
        managed.process.wait(timeout=3)
        receipt = self.case.close()
        self.assertEqual(receipt.exit_codes, (0,))
        self.assertTrue(managed.cleanup_completed)
        self.assert_physically_released(managed)
        self.assertEqual(receipt.external_zombie_pids, managed.unreaped_zombie_pids)

    def test_sigterm_resistant_child_is_killed_within_phase_budget(self):
        managed = self.start(
            "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            "print('ready',flush=True); time.sleep(30)"
        )
        self.ready(managed)
        self.case.stop_process(managed, timeout=0.15)
        self.assertEqual(managed.process.returncode, -signal.SIGKILL)

    def test_cleanup_failure_attempts_other_groups_and_stays_failed(self):
        first = self.start("import time; print('ready',flush=True); time.sleep(30)")
        second = self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.ready(first)
        self.ready(second)
        real_stop = RUNTIME.terminate_process
        attempted = []

        def fail_one(managed, **kwargs):
            attempted.append(managed)
            real_stop(managed, **kwargs)
            if managed is second:
                raise RUNTIME.RunnerError("injected cleanup failure")

        with patch.object(RUNTIME, "terminate_process", side_effect=fail_one):
            with self.assertRaisesRegex(RUNTIME.RunnerError, "cleanup unproven"):
                self.case.close()
        self.assertEqual(attempted, [second, first])
        self.assertIsNone(self.case._receipt)
        for managed in (first, second):
            self.assert_physically_released(managed)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "injected cleanup failure"):
            self.case.close()
        with self.assertRaises(RUNTIME.RunnerError):
            self.start("pass")

    def test_missing_process_proof_cannot_issue_a_receipt(self):
        managed = self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.ready(managed)
        with patch.object(RUNTIME, "terminate_process", return_value=None):
            with self.assertRaisesRegex(RUNTIME.RunnerError, "did not complete"):
                self.case.close()
        self.assertIsNone(self.case._receipt)
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()
        self.assert_physically_released(managed)

    def test_workspace_failure_does_not_prevent_stopping_owned_groups(self):
        managed = self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.ready(managed)
        self.case.workspace.marker_path.write_bytes(b"changed")
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()
        self.assert_physically_released(managed)
        self.assertIsNone(self.case._receipt)
        self.assertEqual(self.case.workspace.marker_path.read_bytes(), b"changed")

    def test_ownership_failure_blocks_next_launch_without_hiding_existing_group(self):
        managed = self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.ready(managed)
        self.case.workspace.manifest_path.unlink()
        with patch.object(RUNTIME, "start_logged_process") as started:
            with self.assertRaises(WORKSPACE.NativeWorkspaceError):
                self.start("pass")
            started.assert_not_called()
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()
        self.assert_physically_released(managed)

    def test_exclusive_logs_never_overwrite_regular_files_or_symlink_targets(self):
        for index, kind in enumerate(("regular", "symlink")):
            case = self.make_case(case_index=30 + index)
            target = self.root / f"foreign-{index}"
            target.write_text("must survive")
            log = case.workspace.root / "process-0000.log"
            if kind == "symlink":
                log.symlink_to(target)
            else:
                log.write_text("must survive")
            with patch.object(RUNTIME, "start_logged_process") as started:
                with self.assertRaisesRegex(RUNTIME.RunnerError, "exclusive"):
                    self.start("pass", case=case)
                started.assert_not_called()
            self.assertEqual(target.read_text(), "must survive")
            self.assertEqual(log.read_text(), "must survive")

    def test_failed_launch_returns_primary_error_and_seals_unknown_teardown(self):
        primary = RUNTIME.RunnerError("injected start failure", 71)
        with patch.object(RUNTIME, "start_logged_process", side_effect=primary):
            with self.assertRaises(RUNTIME.RunnerError) as raised:
                self.start("pass")
        self.assertIs(raised.exception, primary)
        with self.assertRaisesRegex(RUNTIME.RunnerError, "sealed"):
            self.start("pass")
        with self.assertRaisesRegex(RUNTIME.RunnerError, "injected start failure"):
            self.case.close()
        self.assertTrue(self.case.workspace.marker_path.exists())

    def test_start_interrupt_preserves_classification_and_retains_evidence(self):
        with patch.object(RUNTIME, "start_logged_process", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.start("pass")
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()
        self.assertTrue((self.case.workspace.root / "process-0000.log").exists())

    def test_registration_interrupt_still_stops_the_just_created_owned_process(self):
        class InterruptedList(list):
            def append(self, item):
                self.started = item
                raise KeyboardInterrupt

        tracked = InterruptedList()
        self.case._processes = tracked
        with self.assertRaises(KeyboardInterrupt):
            self.start("import time; time.sleep(30)")
        self.started.append(tracked.started)
        self.assert_physically_released(tracked.started)
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()

    def test_close_interrupt_attempts_other_groups_and_preserves_keyboard_interrupt(self):
        first = self.start("import time; print('ready',flush=True); time.sleep(30)")
        second = self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.ready(first)
        self.ready(second)
        real_stop = RUNTIME.terminate_process

        def interrupt_one(managed, **kwargs):
            real_stop(managed, **kwargs)
            if managed is second:
                raise KeyboardInterrupt

        with patch.object(RUNTIME, "terminate_process", side_effect=interrupt_one):
            with self.assertRaises(KeyboardInterrupt):
                self.case.close()
        for managed in (first, second):
            self.assert_physically_released(managed)
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()

    def test_failed_registration_cleanup_keeps_the_known_launch_for_close_retry(self):
        class FailedList(list):
            def append(self, item):
                self.started = item
                raise ValueError("injected registration failure")

        tracked = FailedList()
        self.case._processes = tracked
        cleanup = RUNTIME.RunnerError("injected immediate cleanup failure")
        with patch.object(RUNTIME, "terminate_process", side_effect=cleanup):
            with self.assertRaisesRegex(ValueError, "registration failure") as raised:
                self.start("import time; print('ready',flush=True); time.sleep(30)")
        self.started.append(tracked.started)
        self.assertIs(raised.exception.__cause__, cleanup)
        self.assertIsNone(tracked.started.process.poll())
        with self.assertRaisesRegex(RUNTIME.RunnerError, "cleanup unproven"):
            self.case.close()
        self.assert_physically_released(tracked.started)
        self.assertIsNone(self.case._receipt)

    def test_output_capture_failure_is_not_case_cleanup_success(self):
        managed = self.start("import sys; sys.stdout.buffer.write(b'\\xff'); sys.stdout.flush()")
        with self.assertRaises(RUNTIME.RunnerError):
            self.wait(managed)
        with self.assertRaises(RUNTIME.RunnerError):
            self.case.close()
        self.assertFalse(managed.cleanup_completed)
        self.assert_physically_released(managed)

    def test_invalid_close_budget_fails_before_process_operations(self):
        for timeout in (True, 0, -1, float("nan"), float("inf"), "1"):
            with patch.object(RUNTIME, "terminate_process") as stop:
                with self.assertRaises(RUNTIME.RunnerError):
                    self.case.close(timeout=timeout)
                stop.assert_not_called()
        self.case.close()


if __name__ == "__main__":
    unittest.main()
