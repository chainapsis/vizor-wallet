"""Model SDK/app/Driver transports with real original groups and private trees."""
import json
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_ios_execution as EXECUTE
import test_native_worker_lifecycle as FIXTURES


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.model = FIXTURES.IosWorkerTests()
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.worker = self.model.worker
        self.session = self.worker.prepare_case(platform="ios", scenario_id="flutter.ios.import-sync",
            case_index=0, activation_height=1, helper=self.model.native.helper,
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

    def launch(self, command, **kwargs):
        if command[:3] == ["/usr/bin/xcrun", "simctl", "spawn"]:
            self.assertEqual(command[3], self.session.storage.simulator.udid)
            self.assertEqual(command[4:9], ["log", "stream", "--style", "ndjson", "--level"])
            self.log_lines = kwargs["raw_lines"]
            self.log_reader = self.session.case._start_process(
                [sys.executable, "-u", "-c", "import time; time.sleep(60)"], **kwargs)
            return self.log_reader
        if str(self.driver) in command:
            code = "import json,os; value={'case_manifest':json.loads(os.environ['VIZOR_E2E_CASE_MANIFEST']),'pid':int(os.environ['VIZOR_E2E_APP_PID'])}; "
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
        if "--mode" not in command:
            pid = self.model.native.model.writers[self.session.storage.simulator.udid].process.pid
            if self.mode == "log-console-pid":
                pid = managed.process.pid
            message = "The Dart VM service is listening on http://127.0.0.1:12345/model/"
            self.log_lines.append(json.dumps({"eventMessage": message, "processID": pid}) + "\n")
        return managed

    def execute(self, **kwargs):
        with patch.object(self.session.case,"start_process",side_effect=self.launch), \
             patch.object(EXECUTE.runtime,"start_logged_process",side_effect=lambda command,**options:
                 self.model.native.real_start(command,**options) if command[0] == sys.executable
                 else self.model.native.start_sdk_console(command,**options)):
            return EXECUTE.execute_native_ios_case(self.session,dart=Path(sys.executable).resolve(),
                source_root=self.source,timeout=15,**kwargs)

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


if __name__ == "__main__":
    unittest.main()
