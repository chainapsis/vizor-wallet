"""Real native-case files and original groups; modeled SDK/signatures/app/driver."""
import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_macos_execution as EXECUTE
    import test_native_worker_lifecycle as FIXTURES
finally:
    sys.path.pop(0)


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.model = FIXTURES.MacWorkerTests()
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.model.native.app_code = "print('The Dart VM service is listening on http://127.0.0.1:12345/model/',flush=True); time.sleep(30)"
        self.model.native.install_scripts()
        self.worker = self.model.worker()
        self.session = self.model.case(self.worker)
        front, query = self.model.front_model(self.session)
        self.source = front.source
        self.driver = self.source / "test_driver/native_owned_case.dart"
        self.driver.parent.mkdir()
        self.driver.write_text("// modeled driver transport\n")
        with patch.object(self.session.case,"start_process",side_effect=front.launch), patch.object(
                FIXTURES.WORKER.zakura_front.OwnedNativeZakuraFront,"_query",side_effect=query):
            self.session.prepare_zakura_front(dart=Path(sys.executable).resolve(),source_root=self.source)
        self.session.prepare_zakura_control()
        self.original = self.session.case.start_process
        self.mode = "success"

    def launch(self, command, **kwargs):
        if str(self.driver) in command:
            code = "import json,os; value={'case_manifest':json.loads(os.environ['VIZOR_E2E_CASE_MANIFEST']),'pid':int(os.environ['VIZOR_E2E_APP_PID'])}; "
            if self.mode == "wrong-pid":
                code += "value['pid']+=1; "
            if self.mode == "failure":
                code += "raise SystemExit(1)"
            else:
                code += "print('VIZOR_E2E_RESULT='+json.dumps(value),flush=True)"
            return self.original([sys.executable,"-u","-c",code], **kwargs)
        return self.original(command, **kwargs)

    def execute(self, **kwargs):
        with patch.object(self.session.case,"start_process",side_effect=self.launch):
            return EXECUTE.execute_native_macos_case(self.session,dart=Path(sys.executable).resolve(),
                source_root=self.source,timeout=3,**kwargs)

    def test_original_app_and_driver_are_distinct_and_result_precedes_owned_final_cleanup(self):
        observed = self.execute()
        self.assertNotEqual(observed["app_pid"],observed["driver_pid"])
        self.assertTrue(observed["assertions_passed"])
        self.assertTrue(observed["native_cleanup_pending"])
        self.session.close(timeout=3)
        self.assertTrue(self.session._control.closed)
        self.assertTrue(self.session.backend.closed)
        self.assertTrue(self.session._completed)
        self.worker.close()

    def test_different_app_result_is_not_pass(self):
        self.mode = "wrong-pid"
        with self.assertRaisesRegex(EXECUTE.NativeMacosExecutionError,"original app/case"):
            self.execute()
        self.session.retain(timeout=3)
        self.assertFalse(self.session._completed)
        self.assertTrue(self.session.backend._fixture._retained)

    def test_driver_assertion_failure_remains_failure(self):
        self.mode = "failure"
        with self.assertRaisesRegex(EXECUTE.NativeMacosExecutionError,"failing assertions"):
            self.execute()
        self.session.retain(timeout=3)
        self.assertFalse(self.session._completed)

    def test_precancellation_does_not_launch_app(self):
        count = self.session.case.launched_process_count
        cancel = threading.Event()
        cancel.set()
        with self.assertRaises(EXECUTE.runtime.Cancelled):
            self.execute(cancel_event=cancel)
        self.assertEqual(self.session.case.launched_process_count,count)


if __name__ == "__main__":
    unittest.main()
