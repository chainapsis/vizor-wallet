"""Model SDK transport/native output; real private trees and separate children.

The fake app is NOT in the case console's group: console completion must not
substitute for native app stop. No actual simctl, Keychain or wallet is used.
"""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_ios_case_storage as STORAGE
    import native_ios_cleanup as NATIVE
    import native_ios_simulator as SIMULATOR
    import native_workspace as WORKSPACE
    from test_native_ios_cleanup import executable, receipt, APP_ID
    from test_native_ios_simulator import SimctlModel, RUNTIME_ID, DEVICE_ID
finally:
    sys.path.pop(0)
RUNTIME = STORAGE.runtime


class StorageSimctlModel(SimctlModel):
    def __init__(self, home):
        super().__init__()
        self.home = home
        self.writers = {}
        self.supports = {}
        self.keep_writer = False
        self.job_output = None
        self.container_output = None
        self.container_names = {}
        self.installed = set()
        self.replace_on_install = False

    def device_root(self, udid):
        return self.home / "Library/Developer/CoreSimulator/Devices" / udid

    def container(self, udid):
        identifier = self.container_names.get(udid, str(uuid.UUID(int=1000 + uuid.UUID(udid).int)).upper())
        return self.device_root(udid) / "data/Containers/Data/Application" / identifier

    def run(self, command, **options):
        args = command[2:]
        operation, udid = args[0], args[1] if len(args) > 1 else None
        if operation not in {"install", "get_app_container", "spawn", "terminate"}:
            if operation in {"shutdown", "delete"}:
                writer = self.writers.get(udid)
                if writer and not self.keep_writer:
                    RUNTIME.terminate_process(writer)
                if operation == "delete" and not self.keep_deleted and self.device_root(udid).exists():
                    shutil.rmtree(self.device_root(udid))
            return super().run(command, **options)
        self.calls.append(tuple(args))
        if options["cancel_event"].is_set():
            raise RUNTIME.Cancelled()
        if operation == "install":
            if udid in self.installed:
                old = self.container(udid)
                self.container_names[udid] = str(uuid.uuid4()).upper()
                if self.replace_on_install:
                    shutil.copytree(old, self.container(udid))
                else:
                    old.rename(self.container(udid))  # SDK update preserves all inodes.
            self.installed.add(udid)
            (self.container(udid) / "Library").mkdir(mode=0o700, parents=True, exist_ok=True)
            (self.device_root(udid) / "data").chmod(0o775)  # Actual SDK default.
            output = ""
        elif operation == "get_app_container":
            output = (self.container_output or str(self.container(udid))) + "\n"
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
        self.bad_receipt = None
        self.bad_context = None
        self.context_delay = 0.0
        self.real_start = RUNTIME.start_logged_process
        patches = [(SIMULATOR, "_HOST_PLATFORM", "darwin"), (NATIVE, "_HOST_PLATFORM", "darwin"),
                   (STORAGE, "_home", lambda: self.home), (NATIVE, "_codesign", self.codesign),
                   (RUNTIME, "run_logged_command", self.model.run),
                   (RUNTIME, "start_logged_process", self.start_sdk_console)]
        for target, name, value in patches:
            context = patch.object(target, name, value)
            context.start()
            self.addCleanup(context.stop)
        self.helper = NATIVE.capture_ios_cleanup_helper(self.make_app("Helper.app", helper=True),
                                                        cohort_app=self.make_app("Runner.app", helper=False))
        self.case = self.make_case()
        self.simulator = SIMULATOR.acquire_ios_simulator(self.case, runtime_identifier=RUNTIME_ID,
                                                        device_type_identifier=DEVICE_ID)
        self.simulators = {self.simulator.udid: self.simulator}

    def make_case(self, index=17):
        workspace = WORKSPACE.prepare_native_case_workspace(self.run_root,
            platform="ios", scenario_id="flutter.ios.contract-probe", run_id="a1b2c3d4e5",
            worker_id=2, case_index=index, ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=500)
        case = SIMULATOR.NativeCaseLifecycle(workspace)
        self.addCleanup(case.close)
        return case

    def make_app(self, name, *, helper):
        path = self.root / name
        path.mkdir(mode=0o700)
        (path / "_CodeSignature").mkdir(mode=0o700)
        role = "vizor-ios-cleanup" if helper else "Runner"
        info = {"CFBundleIdentifier": "com.keplr.vizor", "CFBundleExecutable": role,
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
                "VizorE2eIosCleanup" if helper else "VizorE2eIosCohort": True}
        (path / "Info.plist").write_bytes(plistlib.dumps(info))
        (path / role).write_bytes(executable())
        (path / role).chmod(0o700)
        (path / "_CodeSignature/CodeResources").write_bytes(plistlib.dumps({}))
        return path

    def codesign(self, *arguments):
        if "--entitlements" in arguments:
            return subprocess.CompletedProcess(arguments, 0, b"", b"")
        metadata = b"Identifier=com.keplr.vizor\nSignature=adhoc\nTeamIdentifier=not set\n"
        return subprocess.CompletedProcess(arguments, 0, b"", metadata)

    def prepare(self, simulator=None):
        return STORAGE.prepare_ios_case_storage(simulator or self.simulator, self.helper)

    def start_sdk_console(self, command, **options):
        self.assertEqual(command[:4], ["/usr/bin/xcrun", "simctl", "launch", "--console"])
        self.sdk_launches.append((command, options["env"]))
        udid = command[4]
        simulator = self.simulators[udid]
        if "--mode" in command:
            mode = command[command.index("--mode") + 1]
            namespace = command[command.index("--namespace") + 1]
            nonce = command[command.index("--owner-nonce") + 1]
            value = receipt(mode)
            value.update(namespace=namespace, simulator_udid=udid, owner_nonce=nonce)
            value["identity"]["simulator_udid"] = udid
            for item, service in zip(value["keychain"], NATIVE._services(namespace)):
                item["service"] = service
            value["preferences"][0]["prefix"] = f"flutter.vizor_e2e_{namespace}."
            value["preferences"][1]["domain"] = f"com.keplr.vizor.regtest.e2e.{namespace}"
            value["notifications"]["prefix"] = f"vizor_e2e_{namespace}."
            if self.bad_receipt:
                self.bad_receipt(value, mode)
            code = "print(" + repr(json.dumps(value)) + ", flush=True); print('com.keplr.vizor: 12345')"
            return self.real_start([sys.executable, "-u", "-c", code], **options)
        owner = simulator._state.native_owner
        namespace = owner.case.workspace.namespace
        context = {"schema_version": 1, "namespace": namespace, "support_directory": str(owner.path),
            "secure_store_services": NATIVE._services(namespace), "preferences_prefix": f"flutter.vizor_e2e_{namespace}.",
            "native_preferences_suite": f"com.keplr.vizor.regtest.e2e.{namespace}",
            "notification_identifier_prefix": f"vizor_e2e_{namespace}.",
            "os_background_scheduling_enabled": False, "storage_cleanup_completed": False}
        if self.bad_context:
            self.bad_context(context)
        context_file = str(owner.path / "native-context.json")
        code = ("import os,json,time; from pathlib import Path; context=" + repr(context)
                + "; context.setdefault('pid',os.getpid()); time.sleep(" + repr(self.context_delay) + "); temporary=Path(" + repr(context_file + ".atomic")
                + "); temporary.write_text(json.dumps(context)); os.replace(temporary," + repr(context_file)
                + "); time.sleep(60)")
        writer = self.real_start([sys.executable, "-u", "-c", code], cwd=self.root,
            env={}, log_path=self.root / f"app-{udid}-{len(self.sdk_launches)}.log")
        self.addCleanup(RUNTIME.terminate_process, writer)
        self.model.writers[udid] = writer
        # This independently owned SDK console group does not own the fake app.
        return self.real_start([sys.executable, "-u", "-c", "import time; time.sleep(60)"], **options)

    def test_helper_console_accepts_only_one_receipt_and_exact_sdk_launch_line(self):
        for lines in (("{}\n", "com.keplr.vizor: 12345\n"),
                      ("com.keplr.vizor: 12345\n", "{}\n")):
            with self.subTest(lines=lines):
                self.assertEqual(STORAGE._helper_stdout(lines), ("{}",))
        for lines in (("{}\n",), ("{}\n", "diagnostic\n"),
                      ("{}\n", "com.keplr.vizor: 0\n"),
                      ("{}\n", "other.bundle: 12345\n"),
                      ("{}\n", "com.keplr.vizor: 12345 extra\n"),
                      ("{}\n", "com.keplr.vizor: 12345\n", "{}\n"),
                      ("{}\n", "com.keplr.vizor: 12345\n", "diagnostic\n"),
                      ("x" * 16384, "\ncom.keplr.vizor: 12345\n")):
            with self.subTest(lines=lines):
                with self.assertRaises(STORAGE.IosCaseStorageError):
                    STORAGE._helper_stdout(lines)

    def test_preparation_preflights_and_exclusively_allocates_private_support(self):
        owner = self.prepare()
        self.assertEqual(owner.path, self.model.container(self.simulator.udid) / "Library/Application Support/e2e" / self.case.workspace.namespace)
        self.assertEqual(owner.path.stat().st_mode & 0o777, 0o700)
        self.assertEqual((owner.path / STORAGE._MARKER).stat().st_mode & 0o777, 0o600)
        self.assertIs(self.simulator._state.native_owner, owner)
        self.assertTrue(self.case.accepting_launches)
        self.assertFalse((owner.path / "native-context.json").exists())
        owner.retain()
        self.assertTrue(owner.path.exists())
        self.assertIn(self.simulator.udid, self.model.devices)

    def test_sdk_group_writable_data_requires_private_ancestor(self):
        self.home.chmod(0o755)
        library = self.home / "Library"
        library.mkdir(mode=0o755)
        with self.assertRaises(STORAGE.IosCaseStorageError):
            self.prepare()
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))
        self.assertEqual((self.model.device_root(self.simulator.udid) / "data").stat().st_mode & 0o777, 0o775)

    def test_sdk_group_writable_data_allowed_below_private_library_without_chmod(self):
        self.home.chmod(0o755)
        (self.home / "Library").mkdir(mode=0o700)
        owner = self.prepare()
        self.assertEqual((self.model.device_root(self.simulator.udid) / "data").stat().st_mode & 0o777, 0o775)
        owner.close()

    def test_owned_start_stop_restart_and_native_cleanup_delete_only_its_device(self):
        owner = self.prepare()
        original_path = owner.path
        original_ids = owner._ids
        original_marker = owner._marker_bytes
        first = owner.start_app()
        self.assertNotEqual(owner.path, original_path)
        self.assertEqual(owner._ids, original_ids)
        self.assertEqual((owner.path / STORAGE._MARKER).read_bytes(), original_marker)
        self.assertNotEqual(first.pid, first.console.process.pid)
        owner.stop_app(first)
        self.assertTrue(first.console.cleanup_completed)
        second = owner.start_app()
        self.assertEqual(owner._relocations, 1)  # Restart never reinstalls.
        self.assertNotEqual(second.pid, first.pid)
        context_before = (owner.path / "native-context.json").read_bytes()
        cleaned = owner.close()
        self.assertEqual(cleaned.udid, self.simulator.udid)
        self.assertEqual(cleaned.application_identifier, APP_ID)
        self.assertFalse(owner.path.exists())
        self.assertNotIn(self.simulator.udid, self.model.devices)
        self.assertEqual(self.model.devices, self.before)
        self.assertTrue(self.case.workspace.root.exists())
        self.assertEqual(len(list(self.case.workspace.root.glob("ios-storage-relocation-*.json"))), 2)
        self.assertIn(b'"storage_cleanup_completed": false', context_before)
        self.assertTrue(any(call[:3] == ("terminate", self.simulator.udid, "com.keplr.vizor") for call in self.model.calls))
        self.assertEqual(sum(call == ("install", self.simulator.udid, str(self.helper._cohort.path))
                             for call in self.model.calls), 1)

    def test_console_group_completion_is_not_native_app_completion(self):
        owner = self.prepare()
        launch = owner.start_app()
        self.case.stop_process(launch.console)
        self.assertIsNone(self.model.writers[self.simulator.udid].process.poll())
        owner.close()
        self.assertIsNotNone(self.model.writers[self.simulator.udid].process.poll())
        self.assertTrue(any(call[0] == "terminate" for call in self.model.calls))

    def test_failed_scenario_retains_support_context_and_device(self):
        owner = self.prepare()
        launch = owner.start_app()
        context = (owner.path / "native-context.json").read_bytes()
        owner.retain()
        self.assertTrue(launch.console.cleanup_completed)
        self.assertIsNotNone(self.model.writers[self.simulator.udid].process.poll())
        self.assertEqual((owner.path / "native-context.json").read_bytes(), context)
        self.assertEqual(self.model.devices[self.simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))

    def test_failed_preflight_retains_claimed_device_and_case_evidence(self):
        self.bad_receipt = lambda value, mode: value.update(completed=False)
        with self.assertRaises(NATIVE.IosCleanupError):
            self.prepare()
        self.assertIsNotNone(self.simulator._state.native_owner)
        self.assertEqual(self.model.devices[self.simulator.udid]["state"], "Shutdown")
        self.assertTrue(self.case.workspace.root.exists())
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))

    def test_bad_delete_receipt_never_grants_device_deletion_or_retry(self):
        owner = self.prepare()
        owner.start_app()
        self.bad_receipt = lambda value, mode: value.update(completed=False) if mode == "delete" else None
        with self.assertRaises(NATIVE.IosCleanupError):
            owner.close()
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertTrue(owner.path.exists())
        self.assertFalse(owner._native_cleanup_completed)
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner.close()
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))

    def test_wrong_context_pid_is_not_a_global_signal_target(self):
        owner = self.prepare()
        self.bad_context = lambda value: value.update(pid=1)
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner.start_app()
        owner.retain()
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertFalse(any(call[0] in {"terminate", "delete"} for call in self.model.calls))

    def test_replaced_container_observation_prevents_native_cleanup_and_deletion(self):
        owner = self.prepare()
        self.model.container_output = str(self.home)
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner.close()
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))

    def test_sdk_install_copy_is_not_original_support_ownership(self):
        owner = self.prepare()
        original = owner.path
        self.model.replace_on_install = True
        with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "replaced original"):
            owner.start_app()
        owner.retain()
        self.assertTrue(original.exists())
        self.assertEqual(owner._relocations, 0)
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))

    def test_ordinary_sdk_observation_never_adopts_even_identical_renamed_container(self):
        owner = self.prepare()
        old = self.model.container(self.simulator.udid)
        self.model.container_names[self.simulator.udid] = str(uuid.uuid4()).upper()
        old.rename(self.model.container(self.simulator.udid))
        with self.assertRaisesRegex(STORAGE.IosCaseStorageError, "container changed"):
            owner.start_app()
        owner.retain()
        self.assertEqual(owner._relocations, 0)
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))

    def test_same_case_restart_waits_for_atomic_context_from_previous_owned_generation(self):
        owner = self.prepare()
        first = owner.start_app()
        owner.stop_app(first)
        self.context_delay = 0.2
        second = owner.start_app()
        self.assertNotEqual(first.pid, second.pid)
        self.assertEqual(json.loads((owner.path / "native-context.json").read_text())["pid"], second.pid)
        owner.retain()

    def test_changed_support_marker_or_parent_identity_prevents_deletion(self):
        owner = self.prepare()
        (owner.path / STORAGE._MARKER).write_bytes(b"changed")
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner.close()
        self.assertTrue(owner.path.exists())
        self.assertIn(self.simulator.udid, self.model.devices)

    def test_native_ownership_cannot_be_claimed_twice_or_forged_for_deletion(self):
        owner = self.prepare()
        with self.assertRaises(STORAGE.IosCaseStorageError):
            self.prepare()
        with self.assertRaises(STORAGE.IosCaseStorageError):
            owner._delete_after_native_cleanup(deadline=SIMULATOR._deadline(30))
        owner.retain()
        self.assertIn(self.simulator.udid, self.model.devices)

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

    def test_other_owned_case_app_support_and_device_survive_cleanup(self):
        first = self.prepare()
        other_case = self.make_case(18)
        other_simulator = SIMULATOR.acquire_ios_simulator(other_case, runtime_identifier=RUNTIME_ID,
                                                         device_type_identifier=DEVICE_ID)
        self.simulators[other_simulator.udid] = other_simulator
        other = self.prepare(other_simulator)
        other_launch = other.start_app()
        first.start_app()
        first.close()
        self.assertTrue(other.path.exists())
        self.assertIn(other_simulator.udid, self.model.devices)
        self.assertIsNone(other_launch.console.process.poll())
        self.assertIsNone(self.model.writers[other_simulator.udid].process.poll())
        other.retain()

    def test_preexisting_support_namespace_is_not_adopted_or_removed(self):
        path = self.model.container(self.simulator.udid) / "Library/Application Support/e2e" / self.case.workspace.namespace
        path.mkdir(mode=0o700, parents=True)
        sentinel = path / "existing-state"
        sentinel.write_text("preserve")
        with self.assertRaises(STORAGE.IosCaseStorageError):
            self.prepare()
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertIn(self.simulator.udid, self.model.devices)
        self.assertFalse(any(call[0] == "delete" for call in self.model.calls))


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
