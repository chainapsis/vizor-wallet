"""Real native-case files and original groups; modeled SDK/signatures/app/driver."""
import os
import json
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
        self.session = self.worker.prepare_case(platform="macos",
            scenario_id=getattr(self, "scenario_id", "flutter.macos.worker-probe"),
            case_index=0, activation_height=500, helper=self.model.native.host.capture(), timeout=3)
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
            code += "phase=os.environ.get('VIZOR_E2E_PAYMENT_LINK_PHASE'); "
            code += "value.update({'payment_link_phase':phase} if phase is not None else {}); "
            if self.mode == "wrong-phase":
                code += "value['payment_link_phase']='other'; "
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


class GiftRestartExecutionTests(unittest.TestCase):
    def setUp(self):
        self.model = ExecutionTests()
        self.model.scenario_id = "flutter.macos.payment-link-recovery"
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.session = self.model.session
        self.cancel = threading.Event()
        self.wallet_identity = None
        self.mined = []

    def mine(self, blocks):
        # Real owned app/driver groups have joined; only fixture transport is modeled.
        self.assertEqual(len(self.session.storage._writers), 1)
        self.assertTrue(self.session.storage._writers[0].cleanup_completed)
        self.assertFalse(Path(self.session.case.workspace.context_path).exists())
        self.assertTrue((self.session.case.workspace.root/"native-context-before-restart.json").exists())
        wallet = self.session.storage.path/"wallet.db"
        self.wallet_identity = (wallet.stat().st_dev, wallet.stat().st_ino, wallet.read_bytes())
        self.mined.append(blocks)
        return {"tip":{"height":101+blocks}}

    def execute(self, mine=None):
        with patch.object(self.session.backend, "wait_synced", return_value={"height":101}), \
             patch.object(self.session.backend, "mine", side_effect=mine or self.mine):
            return self.model.execute(cancel_event=self.cancel)

    def test_same_original_wallet_chain_ports_and_distinct_apps_across_restart(self):
        backend, control = self.session.backend, self.session._control
        observed = self.execute()
        prepare, resume = observed["phases"]
        self.assertEqual([p["payment_link_phase"] for p in observed["phases"]], ["prepare", "resume"])
        self.assertNotEqual(prepare["app_pid"], resume["app_pid"])
        self.assertNotEqual(prepare["driver_pid"], resume["driver_pid"])
        self.assertEqual(self.mined, [5])
        wallet = self.session.storage.path/"wallet.db"
        self.assertEqual((wallet.stat().st_dev, wallet.stat().st_ino, wallet.read_bytes()), self.wallet_identity)
        self.assertIs(self.session.backend, backend)
        self.assertIs(self.session._control, control)
        self.assertTrue(self.session.case.accepting_launches)
        self.assertTrue(self.session.lease.lock_descriptors)
        archived = json.loads((self.session.case.workspace.root/"native-context-before-restart.json").read_text())
        final = json.loads(Path(self.session.case.workspace.context_path).read_text())
        self.assertEqual(archived["pid"], prepare["app_pid"])
        self.assertEqual(final["pid"], resume["app_pid"])
        self.session.close(timeout=3)
        self.model.worker.close()
        self.assertTrue(self.session._completed)

    def test_wrong_prepare_phase_never_mines_or_launches_resume(self):
        self.model.mode = "wrong-phase"
        with self.assertRaisesRegex(EXECUTE.NativeMacosExecutionError, "original app/case"):
            self.execute()
        self.assertEqual(self.mined, [])
        self.assertEqual(len(self.session.storage._writers), 1)
        self.session.retain(timeout=3)
        self.assertFalse(self.session._completed)

    def test_failing_resume_retains_same_case_and_original_failure(self):
        def mine(blocks):
            result = self.mine(blocks)
            self.model.mode = "failure"
            return result
        with self.assertRaisesRegex(EXECUTE.NativeMacosExecutionError, "failing assertions"):
            self.execute(mine)
        self.session.retain(timeout=3)
        self.assertEqual(len(self.session.storage._writers), 2)
        self.assertTrue(all(p.cleanup_completed for p in self.session.storage._writers))
        self.assertTrue((self.session.storage.path/"wallet.db").exists())
        self.assertTrue(self.session.backend._fixture._retained)
        self.assertFalse(self.session._completed)

    def test_cancellation_between_apps_does_not_launch_resume(self):
        def mine(blocks):
            result = self.mine(blocks)
            self.cancel.set()
            return result
        with self.assertRaises(EXECUTE.runtime.Cancelled):
            self.execute(mine)
        self.assertEqual(len(self.session.storage._writers), 1)
        self.session.retain(timeout=3)

    def test_driver_change_between_apps_is_not_adopted(self):
        def mine(blocks):
            result = self.mine(blocks)
            self.model.driver.write_text("// different source\n")
            return result
        with self.assertRaisesRegex(EXECUTE.NativeMacosExecutionError, "changed across restart"):
            self.execute(mine)
        self.assertEqual(len(self.session.storage._writers), 1)
        self.session.retain(timeout=3)


if __name__ == "__main__":
    unittest.main()
