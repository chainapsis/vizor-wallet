"""Model SDK transport with real private trees and separate children.

The fake app is NOT in the case console's group: console completion must not
substitute for native app stop. No actual simctl, Keychain or wallet is used.
"""

from __future__ import annotations

import copy
import os
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_ios_case_storage as STORAGE
    import native_ios_cohort as COHORT
    import native_ios_simulator as SIMULATOR
    import native_workspace as WORKSPACE
    from test_native_ios_cohort import executable
    from test_native_ios_simulator import SimctlModel, RUNTIME_ID, DEVICE_ID
finally:
    sys.path.pop(0)
RUNTIME = STORAGE.runtime


class StorageSimctlModel(SimctlModel):
    def __init__(self, home):
        super().__init__()
        self.home = home
        self.writers = {}
        self.keep_writer = False
        self.keep_device_directory = False
        self.job_output = None

    def device_root(self, udid):
        return self.home / "Library/Developer/CoreSimulator/Devices" / udid

    def run(self, command, **options):
        args = command[2:]
        operation, udid = args[0], args[1] if len(args) > 1 else None
        if operation not in {"install", "spawn", "terminate"}:
            if operation in {"shutdown", "delete"} and not self.failures.get(operation):
                writer = self.writers.get(udid)
                if writer and not self.keep_writer:
                    RUNTIME.terminate_process(writer)
                if (operation == "delete" and not self.keep_deleted and not self.keep_device_directory
                        and self.device_root(udid).exists()):
                    shutil.rmtree(self.device_root(udid))
            return super().run(command, **options)
        self.calls.append(tuple(args))
        if options["cancel_event"].is_set():
            raise RUNTIME.Cancelled()
        failure = self.failures.get(operation)
        if failure:
            options["log_path"].write_text("injected failure\n")
            return RUNTIME.CommandResult(failure, ("injected failure\n",))
        if operation == "install":
            # Installed app data lives below the SDK's device directory.
            (self.device_root(udid) / "data/Containers/Data/Application").mkdir(parents=True, exist_ok=True)
            output = ""
        elif operation == "spawn":
            writer = self.writers.get(udid)
            pid = writer.process.pid if writer and writer.process.poll() is None else None
            output = self.job_output or "PID\tStatus\tLabel\n"
            if self.job_output is None and pid:
                output += f"{pid}\t0\tUIKitApplication:com.keplr.vizor[fixture][RB-legacy]\n"
        else:
            writer = self.writers.get(udid)
            if writer and not self.keep_writer:
                RUNTIME.terminate_process(writer)
            output = ""
        options["log_path"].write_text(output)
        return RUNTIME.CommandResult(0, tuple(output.splitlines(keepends=True)))


class IosCaseStorageTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-ios-storage-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir(mode=0o700)
        self.run_root = self.root / "run"
        self.run_root.mkdir(mode=0o700)
        self.model = StorageSimctlModel(self.home)
        self.before = copy.deepcopy(self.model.devices)
        self.sdk_launches = []
        self.signature_checks = []
        self.app_starts = True
        self.real_start = RUNTIME.start_logged_process
        patches = [(SIMULATOR, "_HOST_PLATFORM", "darwin"), (COHORT, "_HOST_PLATFORM", "darwin"),
                   (STORAGE, "_home", lambda: self.home), (COHORT, "_verify_signature", self.signature_checks.append),
                   (RUNTIME, "run_logged_command", self.model.run),
                   (RUNTIME, "start_logged_process", self.start_sdk_console)]
        for target, name, value in patches:
            context = patch.object(target, name, value)
            context.start()
            self.addCleanup(context.stop)
        self.cohort = COHORT.capture_ios_cohort(self.make_app("Runner.app"))
        self.case = self.make_case()
        self.simulator = self.acquire(self.case)

    def make_case(self, index=17):
        workspace = WORKSPACE.prepare_native_case_workspace(self.run_root,
            platform="ios", scenario_id="flutter.ios.contract-probe", run_id="a1b2c3d4e5",
            worker_id=2, case_index=index, ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=500)
        case = SIMULATOR.NativeCaseLifecycle(workspace)
        self.addCleanup(case.close)
        return case

    def acquire(self, case):
        return SIMULATOR.acquire_ios_simulator(case, runtime_identifier=RUNTIME_ID,
                                               device_type_identifier=DEVICE_ID)

    def make_app(self, name):
        path = self.root / name
        path.mkdir(mode=0o700)
        (path / "_CodeSignature").mkdir(mode=0o700)
        info = {"CFBundleIdentifier": "com.keplr.vizor", "CFBundleExecutable": "Runner",
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"]}
        (path / "Info.plist").write_bytes(plistlib.dumps(info))
        (path / "Runner").write_bytes(executable())
        (path / "Runner").chmod(0o700)
        (path / "_CodeSignature/CodeResources").write_bytes(plistlib.dumps({}))
        return path

    def prepare(self, simulator=None):
        return STORAGE.prepare_ios_case_storage(simulator or self.simulator, self.cohort)

    def installs(self, udid=None):
        udid = udid or self.simulator.udid
        return [call for call in self.model.calls if call == ("install", udid, str(self.cohort.path))]

    def deletions(self):
        return [call for call in self.model.calls if call[0] == "delete"]

    def start_sdk_console(self, command, **options):
        self.assertEqual(command[:4], ["/usr/bin/xcrun", "simctl", "launch", "--console"])
        self.assertEqual(command[5], "com.keplr.vizor")
        self.sdk_launches.append((command, options["env"]))
        udid = command[4]
        if not self.app_starts:
            # The SDK console ends without ever publishing a UIKit app job.
            return self.real_start([sys.executable, "-u", "-c", "pass"], **options)
        writer = self.real_start([sys.executable, "-u", "-c", "import time; time.sleep(60)"], cwd=self.root,
            env={}, log_path=self.root / f"app-{udid}-{len(self.sdk_launches)}.log")
        self.addCleanup(RUNTIME.terminate_process, writer)
        self.model.writers[udid] = writer
        # This independently owned SDK console group does not own the fake app.
        return self.real_start([sys.executable, "-u", "-c", "import time; time.sleep(60)"], **options)

    def test_preparation_claims_boots_and_installs_the_cohort_once_without_launch(self):
        owner = self.prepare()
        self.assertIs(self.simulator._state.native_owner, owner)
        self.assertIs(owner.cohort, self.cohort)
        self.assertTrue(self.case.accepting_launches)
        self.assertEqual(len(self.installs()), 1)
        operations = [call[0] for call in self.model.calls if call[0] in {"boot", "bootstatus", "install"}]
        self.assertEqual(operations, ["boot", "bootstatus", "install"])
        self.assertEqual(self.sdk_launches, [])
        self.assertFalse(any(call[0] == "get_app_container" for call in self.model.calls))
        self.assertEqual(list(self.model.device_root(self.simulator.udid).rglob("e2e")), [])
        self.assertEqual(len(self.signature_checks), 1)  # Capture only; preparation reruns none.
        owner.retain()
        self.assertEqual(self.model.devices[self.simulator.udid]["state"], "Shutdown")
        self.assertTrue(self.model.device_root(self.simulator.udid).exists())
        self.assertEqual(self.deletions(), [])

    def test_owned_start_stop_restart_and_close_delete_only_its_device(self):
        owner = self.prepare()
        first = owner.start_app()
        self.assertEqual(len(self.installs()), 1)  # Launches never install.
        self.assertNotEqual(first.pid, first.console.process.pid)
        owner.stop_app(first)
        self.assertTrue(first.console.cleanup_completed)
        self.assertEqual(owner._jobs(deadline=SIMULATOR._deadline(30), cancel_event=STORAGE.threading.Event()), [])
        second = owner.start_app()
        self.assertNotEqual(second.pid, first.pid)
        self.assertEqual(len(self.installs()), 1)  # Restart never reinstalls.
        launches = len(self.sdk_launches)
        cleaned = owner.close()
        self.assertEqual(len(self.sdk_launches), launches)  # Close launches nothing.
        self.assertEqual(cleaned.udid, self.simulator.udid)
        self.assertEqual(cleaned.namespace, self.case.workspace.namespace)
        self.assertEqual(cleaned.device_directory, str(self.model.device_root(self.simulator.udid)))
        self.assertFalse(self.model.device_root(self.simulator.udid).exists())
        self.assertNotIn(self.simulator.udid, self.model.devices)
        self.assertEqual(self.model.devices, self.before)
        self.assertEqual(self.deletions(), [("delete", self.simulator.udid)])
        self.assertTrue(any(call[:3] == ("terminate", self.simulator.udid, "com.keplr.vizor") for call in self.model.calls))
        self.assertFalse(any(call[0] in {"get_app_container", "launch"} for call in self.model.calls))
        self.assertTrue(self.case.workspace.root.exists())
        self.assertTrue((self.case.workspace.root / SIMULATOR._OWNER).exists())
        self.assertEqual(list(self.case.workspace.root.glob("ios-storage-*.json")), [])
        self.assertEqual(len(self.signature_checks), 1)

    def test_console_group_completion_is_not_native_app_completion(self):
        owner = self.prepare()
        launch = owner.start_app()
        self.case.stop_process(launch.console)
        self.assertIsNone(self.model.writers[self.simulator.udid].process.poll())
        owner.close()
        self.assertIsNotNone(self.model.writers[self.simulator.udid].process.poll())
        self.assertTrue(any(call[0] == "terminate" for call in self.model.calls))

    def test_failed_scenario_retains_device_and_evidence(self):
        owner = self.prepare()
        launch = owner.start_app()
        owner.retain()
        self.assertTrue(launch.console.cleanup_completed)
        self.assertIsNotNone(self.model.writers[self.simulator.udid].process.poll())
        self.assertEqual(self.model.devices[self.simulator.udid]["state"], "Shutdown")
        self.assertTrue(self.model.device_root(self.simulator.udid).exists())
        self.assertTrue(self.case.workspace.root.exists())
        self.assertEqual(self.deletions(), [])

    def test_failed_preparation_retains_claimed_device_and_never_deletes(self):
        for index, operation in enumerate(("bootstatus", "install")):
            with self.subTest(operation=operation):
                case = self.make_case(30 + index)
                simulator = self.acquire(case)
                self.model.failures[operation] = 1
                with self.assertRaises(SIMULATOR.NativeSimulatorError):
                    self.prepare(simulator)
                del self.model.failures[operation]
                self.assertIsNotNone(simulator._state.native_owner)
                self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
                self.assertTrue(case.workspace.root.exists())
                self.assertEqual(len(self.installs(simulator.udid)), 1 if operation == "install" else 0)
        self.assertEqual(self.sdk_launches, [])
        self.assertEqual(self.deletions(), [])

    def test_unproven_deletion_fails_closed_without_retry(self):
        # (fault, error, whether the SDK inventory still lists the device)
        variants = (("nonzero delete", r"simctl delete failed", True),
                    ("keep_deleted", r"still exists after deletion", True),
                    ("keep_device_directory", r"device directory remains", False))
        for index, (fault, message, listed) in enumerate(variants):
            with self.subTest(fault=fault):
                case = self.make_case(40 + index)
                simulator = self.acquire(case)
                owner = self.prepare(simulator)
                owner.start_app()
                if fault == "nonzero delete":
                    self.model.failures["delete"] = 1
                else:
                    setattr(self.model, fault, True)
                try:
                    with self.assertRaisesRegex(RUNTIME.RunnerError, message):
                        owner.close()
                finally:
                    self.model.failures.pop("delete", None)
                    self.model.keep_deleted = self.model.keep_device_directory = False
                self.assertEqual(owner._failure, "successful-case device deletion unproven")
                with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "finished"):
                    owner.close()
                self.assertEqual(self.deletions().count(("delete", simulator.udid)), 1)
                self.assertTrue(self.model.device_root(simulator.udid).exists())
                if listed:
                    self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
                else:
                    self.assertNotIn(simulator.udid, self.model.devices)

    def test_a_previous_launch_pid_is_not_a_new_owned_startup(self):
        owner = self.prepare()
        first = owner.start_app()
        owner.stop_app(first)
        start = self.start_sdk_console

        def reuse_previous_job(command, **options):
            self.model.job_output = f"PID\tStatus\tLabel\n{first.pid}\t0\tUIKitApplication:com.keplr.vizor[old]\n"
            return start(command, **options)

        with patch.object(RUNTIME, "start_logged_process", side_effect=reuse_previous_job):
            with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "not a new owned launch"):
                owner.start_app()
        self.model.job_output = None
        owner.retain()
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertEqual(self.deletions(), [])

    def test_console_exit_before_an_app_job_fails_and_retains(self):
        owner = self.prepare()
        self.app_starts = False
        with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "exited before its owned job"):
            owner.start_app()
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner.close()  # The failed launch blocks successful cleanup.
        self.assertEqual(self.model.devices[self.simulator.udid]["state"], "Shutdown")
        self.assertEqual(self.deletions(), [])

    def test_changed_cohort_files_block_a_launch(self):
        owner = self.prepare()
        info = self.cohort.path / "Info.plist"
        info.write_bytes(plistlib.dumps({**plistlib.loads(info.read_bytes()), "changed": True}))
        with self.assertRaisesRegex(COHORT.IosCohortError, "identity changed"):
            owner.start_app()
        self.assertEqual(self.sdk_launches, [])
        owner.retain()
        self.assertEqual(self.deletions(), [])

    def test_changed_device_owner_marker_prevents_deletion(self):
        owner = self.prepare()
        owner.start_app()
        (self.case.workspace.root / SIMULATOR._OWNER).write_bytes(b"changed")
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            owner.close()
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertTrue(self.model.device_root(self.simulator.udid).exists())
        self.assertEqual(self.deletions(), [])

    def test_native_ownership_cannot_be_claimed_twice_or_forged_for_deletion(self):
        with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "captured cohort"):
            STORAGE.prepare_ios_case_storage(self.simulator, self.cohort.path)
        owner = self.prepare()
        with self.assertRaises(STORAGE.IosCaseStorageError):
            self.prepare()
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner._delete_owned_device(deadline=SIMULATOR._deadline(30))
        owner.start_app()
        owner.retain()
        # A retained failed case is finished without a proved stop/close.
        with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "successful closing owner"):
            owner._delete_owned_device(deadline=SIMULATOR._deadline(30))
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertEqual(self.deletions(), [])

    def test_caller_child_loader_overrides_are_not_inherited(self):
        with patch.dict(os.environ, {"SIMCTL_CHILD_DYLD_INSERT_LIBRARIES": "/not/a/library",
                                     "SIMCTL_CHILD_CFFIXED_USER_HOME": "/not/a/home"}):
            owner = self.prepare()
            owner.start_app()
        for _, environment in self.sdk_launches:
            self.assertNotIn("SIMCTL_CHILD_DYLD_INSERT_LIBRARIES", environment)
            self.assertNotIn("SIMCTL_CHILD_CFFIXED_USER_HOME", environment)
        app_env = self.sdk_launches[-1][1]
        self.assertEqual(app_env["SIMCTL_CHILD_VIZOR_E2E_NAMESPACE"], self.case.workspace.namespace)
        owner.retain()

    def test_other_owned_case_device_survives_cleanup(self):
        first = self.prepare()
        other_case = self.make_case(18)
        other_simulator = self.acquire(other_case)
        other = self.prepare(other_simulator)
        other_launch = other.start_app()
        first.start_app()
        first.close()
        self.assertNotIn(self.simulator.udid, self.model.devices)
        self.assertIn(other_simulator.udid, self.model.devices)
        self.assertTrue(self.model.device_root(other_simulator.udid).exists())
        self.assertIsNone(other_launch.console.process.poll())
        self.assertIsNone(self.model.writers[other_simulator.udid].process.poll())
        self.assertEqual(self.deletions(), [("delete", self.simulator.udid)])
        other.retain()


class AppJobFormatTests(unittest.TestCase):
    def test_only_supported_complete_rows_can_establish_native_app_absence(self):
        self.assertEqual(STORAGE._app_jobs("PID\tStatus\tLabel\n-\t0\tother.app\n"), [])
        self.assertEqual(STORAGE._app_jobs("PID\tStatus\tLabel\n123\t0\tUIKitApplication:com.keplr.vizor[a]\n"), [123])
        for raw in ("", "unavailable", "PID Status Label\n123 0 application.com.keplr.vizor\n",
                    "PID Status Label\n- ? unknown\n", "PID Status Label\n1 0 same\n2 0 same\n",
                    "PID Status Label\n1 0 UIKitApplication:com.keplr.vizor[a]\n2 0 UIKitApplication:com.keplr.vizor[b]\n"):
            with self.subTest(raw=raw), self.assertRaises(STORAGE.IosCaseStorageError):
                STORAGE._app_jobs(raw)


if __name__ == "__main__":
    unittest.main()
