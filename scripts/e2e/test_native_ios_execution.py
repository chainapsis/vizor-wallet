"""Model SDK/app/Driver transports with real original groups and private trees."""
import json
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_ios_execution as EXECUTE
import test_native_worker_lifecycle as FIXTURES


class ExecutionFixture(unittest.TestCase):
    scenario_id = "flutter.ios.import-sync"
    activation_height = 1
    def setUp(self):
        self.model = FIXTURES.IosWorkerTests()
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.worker = self.model.worker
        self.session = self.worker.prepare_case(platform="ios", scenario_id=self.scenario_id,
            case_index=0, activation_height=self.activation_height, helper=self.model.native.cohort,
            runtime_identifier=FIXTURES.IOS_FIXTURES.RUNTIME_ID,
            device_type_identifier=FIXTURES.IOS_FIXTURES.DEVICE_ID, timeout=15)
        front, query = FIXTURES.MacWorkerTests.front_model(self.model, self.session)
        self.source = front.source
        self.driver = self.source/"test_driver/native_owned_case.dart"
        self.driver.parent.mkdir()
        self.driver.write_text("// model Driver\n")
        with patch.object(self.session.case,"start_process",side_effect=front.launch), \
             patch.object(EXECUTE.runtime,"start_logged_process",side_effect=self.model.native.real_start), \
             patch.object(FIXTURES.WORKER.zakura_front.OwnedNativeZakuraFront,"_query",side_effect=query):
            self.session.prepare_zakura_front(dart=Path(sys.executable).resolve(),source_root=self.source)
        self.session.prepare_zakura_control()
        self.original_start = self.session.case.start_process
        self.mode = "success"
        self.log_lines = None
        self.log_reader = None
        self.driver_started = False

    def launch(self, command, **kwargs):
        if command[:3] == ["/usr/bin/xcrun", "simctl", "spawn"]:
            self.assertEqual(command[3], self.session.storage.simulator.udid)
            self.assertEqual(command[4:9], ["log", "stream", "--style", "ndjson", "--level"])
            self.assertIn('processImagePath ENDSWITH "/Runner"', command[-1])
            self.assertIn('eventMessage BEGINSWITH "flutter:"', command[-1])
            self.assertEqual(kwargs["max_output_bytes"], 8*1024*1024)
            self.log_lines = kwargs["raw_lines"]
            self.log_reader = self.session.case._start_process(
                [sys.executable, "-u", "-c", "import time; time.sleep(60)"], **kwargs)
            return self.log_reader
        if str(self.driver) in command:
            self.driver_started = True
            code = "import json,os; value={'case_manifest':json.loads(os.environ['VIZOR_E2E_CASE_MANIFEST']),'pid':int(os.environ['VIZOR_E2E_APP_PID'])}; "
            if "VIZOR_E2E_IOS_PHASE" in kwargs["env"]:
                code += "value['ios_phase']=os.environ['VIZOR_E2E_IOS_PHASE']; "
            if self.mode == "wrong-phase":
                code += "value['ios_phase']='resume'; "
            if self.mode == "console-pid":
                code += "value['pid']="+str(self.session.storage._active.console.process.pid)+"; "
            if self.mode == "failure":
                code += "raise SystemExit(1)"
            else:
                code += "print('VIZOR_E2E_RESULT='+json.dumps(value),flush=True)"
            return self.session.case._start_process([sys.executable,"-u","-c",code], **kwargs)
        managed = self.original_start(command, **kwargs)
        # The endpoint is an SDK unified-log event, not app-console stdout.
        # Keep the modeled native app distinct from the original console job.
        pid = self.model.native.model.writers[self.session.storage.simulator.udid].process.pid
        if self.mode == "log-console-pid":
            pid = managed.process.pid
        if self.mode == "flutter-logs":
            self.log_lines.append(json.dumps({"eventMessage": "flutter: [E2E] ordinary diagnostic", "processID": pid}) + "\n")
        message = "The Dart VM service is listening on http://127.0.0.1:12345/model/"
        event = json.dumps({"eventMessage": message, "processID": pid}) + "\n"
        phase = kwargs["env"].get("SIMCTL_CHILD_VIZOR_E2E_IOS_PHASE")
        if self.mode == "late-vm" or (self.mode == "late-resume-vm" and phase == "resume"):
            self.vm_event = event
        else:
            self.log_lines.append(event)
        return managed

    def execute(self, timeout=15, **kwargs):
        with patch.object(self.session.case,"start_process",side_effect=self.launch), \
             patch.object(EXECUTE.runtime,"start_logged_process",side_effect=lambda command,**options:
                 self.model.native.real_start(command,**options) if command[0] == sys.executable
                 else self.model.native.start_sdk_console(command,**options)):
            return EXECUTE.execute_native_ios_case(self.session,dart=Path(sys.executable).resolve(),
                source_root=self.source,timeout=timeout,**kwargs)


class ExecutionTests(ExecutionFixture):
    def start_budgets(self):
        budgets = []
        original = self.session.storage.start_app
        def start_app(**options):
            budgets.append(options["timeout"])
            return original(**options)
        return budgets, patch.object(self.session.storage, "start_app", side_effect=start_app)

    def test_app_start_budget_is_the_launch_deadline_inside_the_case_budget(self):
        self.assertEqual(EXECUTE.IOS_LAUNCH_TIMEOUT_SECONDS, 120)
        budgets, start = self.start_budgets()
        with start:
            self.assertTrue(self.execute(timeout=300, launch_timeout=90)["assertions_passed"])
        self.assertEqual(len(budgets), 1)
        self.assertTrue(60 < budgets[0] <= 90)
        self.session.close(timeout=15)
        self.worker.close()

    def test_a_shorter_case_budget_still_bounds_the_launch(self):
        budgets, start = self.start_budgets()
        with start:
            self.assertTrue(self.execute(timeout=20, launch_timeout=90)["assertions_passed"])
        self.assertTrue(0 < budgets[0] <= 20)
        self.session.close(timeout=15)
        self.worker.close()

    def test_vm_event_inside_the_launch_deadline_is_accepted(self):
        self.mode = "late-vm"
        clock = [EXECUTE.time.monotonic()]
        pumps = [0]
        def publish_vm(**options):
            pumps[0] += 1
            if pumps[0] == 1:
                clock[0] += 35
            elif pumps[0] == 2:
                self.log_lines.append(self.vm_event)
            else:
                threading.Event().wait(0.005)
        with patch.object(EXECUTE, "time", SimpleNamespace(monotonic=lambda: clock[0])), \
             patch.object(self.session._control, "pump", side_effect=publish_vm):
            self.assertTrue(self.execute(timeout=120, launch_timeout=60)["assertions_passed"])
        self.session.close(timeout=15)
        self.worker.close()

    def test_missing_vm_event_expires_at_the_launch_deadline_with_case_budget_left(self):
        self.mode = "late-vm"
        clock = [EXECUTE.time.monotonic()]
        ready = []
        def advance(**options):
            clock[0] += 61
        with patch.object(EXECUTE, "time", SimpleNamespace(monotonic=lambda: clock[0])), \
             patch.object(self.session._control, "pump", side_effect=advance):
            with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "within the launch deadline") as raised:
                self.execute(timeout=600, launch_timeout=60, on_launch_ready=lambda: ready.append(True))
        self.assertEqual(raised.exception.exit_code, 124)
        self.assertEqual(ready, [])
        self.assertFalse(self.driver_started)
        self.session.retain(timeout=15)

    def test_missing_vm_event_still_expires_at_an_earlier_case_deadline(self):
        self.mode = "late-vm"
        clock = [EXECUTE.time.monotonic()]
        def exhaust_budget(**options):
            clock[0] += 121
        with patch.object(EXECUTE, "time", SimpleNamespace(monotonic=lambda: clock[0])), \
             patch.object(self.session._control, "pump", side_effect=exhaust_budget):
            with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "integration deadline expired") as raised:
                self.execute(timeout=120, launch_timeout=300)
        self.assertEqual(raised.exception.exit_code, 124)
        self.session.retain(timeout=15)

    def test_control_requests_keep_the_case_deadline_while_waiting_for_the_vm_url(self):
        self.mode = "late-vm"
        now = EXECUTE.time.monotonic()
        deadlines = []
        def pump(**options):
            deadlines.append(options["deadline"])
            if len(deadlines) == 2:
                self.log_lines.append(self.vm_event)
            threading.Event().wait(0.005)
        with patch.object(EXECUTE, "time", SimpleNamespace(monotonic=lambda: now)), \
             patch.object(self.session._control, "pump", side_effect=pump):
            self.assertTrue(self.execute(timeout=120, launch_timeout=30)["assertions_passed"])
        self.assertGreaterEqual(len(deadlines), 2)
        self.assertEqual(set(deadlines), {now + 120})
        self.session.close(timeout=15)
        self.worker.close()

    def test_launch_readiness_runs_once_after_the_vm_url_and_before_the_driver(self):
        timings, calls = {}, []
        def ready():
            calls.append((set(timings), self.driver_started))
        self.assertTrue(self.execute(timings=timings, on_launch_ready=ready)["assertions_passed"])
        self.assertEqual(calls, [({"app_launch_started", "vm_url_ready"}, False)])
        self.assertTrue(self.driver_started)
        self.assertIn("driver_finished", timings)
        self.session.close(timeout=15)
        self.worker.close()

    def test_launch_readiness_is_not_reported_for_a_launch_that_fails_before_its_vm_url(self):
        self.mode = "log-console-pid"
        ready = []
        with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "VM endpoint"):
            self.execute(on_launch_ready=lambda: ready.append(True))
        self.assertEqual(ready, [])
        self.assertFalse(self.driver_started)
        self.session.retain(timeout=15)

    def test_invalid_launch_budget_or_callback_is_refused_before_launch(self):
        count = self.session.case.launched_process_count
        for options in ({"launch_timeout": 0}, {"launch_timeout": -1}, {"launch_timeout": float("nan")},
                        {"launch_timeout": True}, {"on_launch_ready": "not callable"}):
            with self.subTest(options=options), self.assertRaises(EXECUTE.runtime.RunnerError):
                self.execute(**options)
        self.assertEqual(self.session.case.launched_process_count, count)

    def test_flutter_diagnostics_do_not_replace_the_original_vm_binding(self):
        self.mode = "flutter-logs"
        result = self.execute()
        self.assertTrue(result["assertions_passed"])
        self.assertIn("ordinary diagnostic", self.log_lines[0])
        self.session.close(timeout=15)
        self.worker.close()

    def test_original_native_pid_differs_from_console_and_cleanup_is_composed(self):
        result = self.execute()
        self.assertNotEqual(result["app_pid"], result["console_pid"])
        self.assertNotEqual(result["app_pid"], result["driver_pid"])
        self.assertEqual(result["unified_log_pid"], self.log_reader.process.pid)
        self.assertIsNotNone(self.log_reader.process.poll())
        self.session.close(timeout=15)
        self.assertTrue(self.session.backend.closed)
        self.assertNotIn(result["simulator_udid"],self.model.native.model.devices)
        self.worker.close()

    def test_vm_endpoint_from_console_pid_is_rejected(self):
        self.mode = "log-console-pid"
        with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "VM endpoint.*original native app PID"):
            self.execute()
        self.session.retain(timeout=15)
        self.assertIsNotNone(self.log_reader.process.poll())

    def test_console_pid_cannot_satisfy_native_app_result(self):
        self.mode = "console-pid"
        with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError,"original native app/case"):
            self.execute()
        self.session.retain(timeout=15)
        self.assertFalse(self.session._completed)

    def test_assertion_failure_remains_failure(self):
        self.mode = "failure"
        with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError,"failing assertions"):
            self.execute()
        self.session.retain(timeout=15)

    def test_precancellation_does_not_launch_an_app(self):
        cancel = threading.Event()
        cancel.set()
        count = self.session.case.launched_process_count
        with self.assertRaises(EXECUTE.runtime.Cancelled):
            self.execute(cancel_event=cancel)
        self.assertEqual(self.session.case.launched_process_count,count)


class RestartExecutionTests(ExecutionFixture):
    scenario_id = "flutter.ios.ironwood-migration-restart"
    activation_height = 500

    def test_two_phases_keep_original_container_and_case_but_change_native_pid(self):
        with patch.object(self.session.backend, "mine", wraps=self.session.backend.mine) as mine:
            result = self.execute()
        before, after = result["prepare"], result["resume"]
        self.assertEqual(before["ios_phase"], "prepare")
        self.assertEqual(after["ios_phase"], "resume")
        self.assertEqual(before["simulator_udid"], after["simulator_udid"])
        self.assertEqual(before["namespace"], after["namespace"])
        self.assertNotEqual(before["app_pid"], after["app_pid"])
        mine.assert_called_once_with(50)
        self.session.close(timeout=15)
        self.worker.close()

    def test_readiness_is_prepare_only_and_resume_keeps_the_launch_deadline(self):
        timings, calls, budgets = {}, [], []
        original = self.session.storage.start_app
        def start_app(**options):
            budgets.append((options["phase"], options["timeout"]))
            return original(**options)
        with patch.object(self.session.storage, "start_app", side_effect=start_app):
            self.execute(timeout=300, launch_timeout=45, timings=timings,
                         on_launch_ready=lambda: calls.append(set(timings)))
        self.assertEqual(calls, [{"prepare_app_launch_started", "prepare_vm_url_ready"}])
        self.assertEqual([phase for phase, _ in budgets], ["prepare", "resume"])
        self.assertTrue(all(0 < budget <= 45 for _, budget in budgets))
        self.session.close(timeout=15)
        self.worker.close()

    def test_resume_launch_expires_at_its_own_launch_deadline(self):
        self.mode = "late-resume-vm"
        clock = [EXECUTE.time.monotonic()]
        def pump(**options):
            if len(self.session.storage._launches) == 2:
                clock[0] += 50  # Only the resume launch waits for its VM URL.
            threading.Event().wait(0.005)
        with patch.object(EXECUTE, "time", SimpleNamespace(monotonic=lambda: clock[0])), \
             patch.object(self.session._control, "pump", side_effect=pump):
            with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "within the launch deadline") as raised:
                self.execute(timeout=600, launch_timeout=45)
        self.assertEqual(raised.exception.exit_code, 124)
        self.assertEqual(len(self.session.storage._launches), 2)
        self.session.retain(timeout=15)

    def test_wrong_prepare_phase_cannot_advance_chain_or_credit_restart(self):
        self.mode = "wrong-phase"
        with patch.object(self.session.backend, "mine") as mine:
            with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "restart phase"):
                self.execute()
            mine.assert_not_called()
        self.session.retain(timeout=15)

    def test_invalid_restart_phase_launches_nothing(self):
        count = self.session.case.launched_process_count
        with self.assertRaisesRegex(EXECUTE.NativeIosExecutionError, "restart phase"):
            self.execute(_phase="vote")
        self.assertEqual(self.session.case.launched_process_count, count)


if __name__ == "__main__":
    unittest.main()
