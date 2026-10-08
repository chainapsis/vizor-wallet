"""Portable contract tests with a modelled simctl transport, not real devices."""

from __future__ import annotations

import copy
import dataclasses
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
import uuid


sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_ios_simulator as SIMULATOR
    import native_workspace as WORKSPACE
finally:
    sys.path.pop(0)
RUNTIME = SIMULATOR.runtime
RUNTIME_ID = "com.apple.CoreSimulator.SimRuntime.iOS-26-3"
DEVICE_ID = "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"


class SimctlModel:
    def __init__(self):
        self.calls = []
        self.environments = []
        self.devices = {}
        self.serial = 10
        self.create_output = None
        self.failures = {}
        self.keep_deleted = False
        self.boot_state = "Booted"
        self.runtimes = [{
            "identifier": RUNTIME_ID, "platform": "iOS", "isAvailable": True,
            "supportedDeviceTypes": [{"identifier": DEVICE_ID}],
        }]
        self.add_device("user device", "Booted", number=1)
        self.add_device("sibling device", "Shutdown", number=2)

    def add_device(self, name, state="Shutdown", *, number=None):
        if number is None:
            self.serial += 1
            number = self.serial
        udid = str(uuid.UUID(int=number)).upper()
        self.devices[udid] = {
            "udid": udid, "name": name, "state": state,
            "deviceTypeIdentifier": DEVICE_ID, "isAvailable": True,
        }
        return udid

    def run(self, command, *, cwd, env, log_path, timeout, cancel_event, **kwargs):
        assert command[:2] == ["/usr/bin/xcrun", "simctl"]
        arguments = command[2:]
        self.calls.append(tuple(arguments))
        self.environments.append(dict(env))
        if cancel_event.is_set():
            raise RUNTIME.Cancelled()
        operation = arguments[0]
        failure = self.failures.get(operation)
        if isinstance(failure, BaseException):
            raise failure
        if failure:
            return RUNTIME.CommandResult(failure, ("injected failure\n",))
        if arguments[:2] == ["list", "runtimes"]:
            output = json.dumps({"runtimes": self.runtimes}) + "\n"
        elif arguments[:2] == ["list", "devices"]:
            output = json.dumps({"devices": {RUNTIME_ID: list(self.devices.values())}}) + "\n"
        elif operation == "create":
            if self.create_output in self.devices:
                output = self.create_output + "\n"
            else:
                created = self.add_device(arguments[1])
                output = (self.create_output or created) + "\n"
        elif operation == "boot":
            self.devices[arguments[1]]["state"] = self.boot_state
            output = ""
        elif operation == "bootstatus":
            output = "boot ready\n"
        elif operation == "shutdown":
            self.devices[arguments[1]]["state"] = "Shutdown"
            output = ""
        elif operation == "delete":
            if not self.keep_deleted:
                del self.devices[arguments[1]]
            output = ""
        else:
            raise AssertionError(f"unmodelled simctl operation: {arguments}")
        log_path.write_text(output)
        return RUNTIME.CommandResult(0, tuple(output.splitlines(keepends=True)))


class OwnedIosSimulatorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-ios-simulator-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.run_root = self.root / "run"
        self.run_root.mkdir(mode=0o700)
        self.case = self.make_case()
        self.addCleanup(self.case.close)
        self.model = SimctlModel()
        self.before = copy.deepcopy(self.model.devices)
        self.transport = patch.object(RUNTIME, "run_logged_command", side_effect=self.model.run)
        self.transport.start()
        self.addCleanup(self.transport.stop)
        self.platform = patch.object(SIMULATOR, "_HOST_PLATFORM", "darwin")
        self.platform.start()
        self.addCleanup(self.platform.stop)

    def make_case(self, *, platform="ios", case_index=17):
        workspace = WORKSPACE.prepare_native_case_workspace(
            self.run_root, platform=platform, scenario_id=f"flutter.{platform}.contract-probe",
            run_id="a1b2c3d4e5", worker_id=2, case_index=case_index,
            ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=500,
        )
        return SIMULATOR.NativeCaseLifecycle(workspace)

    def acquire(self, **updates):
        options = {"runtime_identifier": RUNTIME_ID, "device_type_identifier": DEVICE_ID, **updates}
        return SIMULATOR.acquire_ios_simulator(self.case, **options)

    def mutations(self):
        return [entry for entry in self.model.calls if entry[0] in ("create", "boot", "shutdown", "delete")]

    def test_new_device_is_created_with_explicit_compatible_identity(self):
        simulator = self.acquire()
        self.assertNotIn(simulator.udid, self.before)
        self.assertEqual(self.mutations(), [("create", simulator.name, DEVICE_ID, RUNTIME_ID)])
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        for name in (SIMULATOR._INTENT, SIMULATOR._OWNER):
            self.assertEqual((self.case.workspace.root / name).stat().st_mode & 0o777, 0o600)
        for file in self.case.workspace.root.glob("simulator-*.log"):
            self.assertEqual(file.stat().st_mode & 0o777, 0o600)
        simulator.close()

    def test_boot_waits_for_readiness_and_targets_only_the_created_uuid(self):
        simulator = self.acquire()
        simulator.boot()
        self.assertIn(("boot", simulator.udid), self.model.calls)
        self.assertIn(("bootstatus", simulator.udid), self.model.calls)
        self.assertNotIn(("bootstatus", simulator.udid, "-b"), self.model.calls)
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Booted")
        simulator.close()
        for udid, device in self.before.items():
            self.assertEqual(self.model.devices[udid], device)

    def test_close_shuts_down_and_proves_absence_without_removing_evidence(self):
        simulator = self.acquire()
        simulator.boot()
        receipt = simulator.close()
        self.assertEqual(receipt.udid, simulator.udid)
        self.assertEqual(receipt.namespace, self.case.workspace.namespace)
        self.assertNotIn(simulator.udid, self.model.devices)
        self.assertEqual(self.model.devices, self.before)
        self.assertFalse(hasattr(receipt, "storage_cleanup_completed"))
        self.assertTrue((self.case.workspace.root / SIMULATOR._OWNER).exists())
        self.assertTrue(self.case.workspace.manifest_path.exists())

    def test_repeated_close_never_acts_on_a_retired_uuid(self):
        simulator = self.acquire()
        receipt = simulator.close()
        before = len(self.model.calls)
        self.assertIs(simulator.close(), receipt)
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.boot()
        self.assertEqual(len(self.model.calls), before)

    def test_already_booted_owned_device_still_requires_bootstatus(self):
        simulator = self.acquire()
        simulator.boot()
        first = len([entry for entry in self.model.calls if entry[0] == "boot"])
        simulator.boot()
        self.assertEqual(len([entry for entry in self.model.calls if entry[0] == "boot"]), first)
        self.assertEqual(len([entry for entry in self.model.calls if entry[0] == "bootstatus"]), 2)
        simulator.close()

    def test_existing_case_name_is_not_adopted(self):
        self.model.add_device(f"Vizor E2E {self.case.workspace.namespace}")
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "cannot be adopted"):
            self.acquire()
        self.assertEqual(self.mutations(), [])

    def test_create_returning_an_existing_uuid_is_never_adopted_or_deleted(self):
        self.model.create_output = next(iter(self.before))
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "pre-existing"):
            self.acquire()
        self.assertEqual(self.model.devices, self.before)
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_case_cannot_allocate_another_device_over_existing_markers(self):
        simulator = self.acquire()
        before = copy.deepcopy(self.model.devices)
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            self.acquire()
        self.assertEqual(self.model.devices, before)
        simulator.close()

    def test_invalid_identifiers_and_budgets_fail_before_simctl(self):
        for options in (
            {"runtime_identifier": "all"}, {"runtime_identifier": "com.apple.CoreSimulator.SimRuntime.watchOS-26-0"},
            {"device_type_identifier": "booted"}, {"device_type_identifier": None},
            {"timeout": 0}, {"timeout": True}, {"timeout": float("nan")},
        ):
            with self.subTest(options=options), self.assertRaises(SIMULATOR.NativeSimulatorError):
                self.acquire(**options)
        self.assertEqual(self.model.calls, [])

    def test_nonmacos_host_fails_before_any_files_or_commands(self):
        with patch.object(SIMULATOR, "_HOST_PLATFORM", "linux"):
            with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "macOS"):
                self.acquire()
        self.assertEqual(self.model.calls, [])
        self.assertFalse((self.case.workspace.root / SIMULATOR._INTENT).exists())

    def test_macos_case_or_closed_owner_is_not_accepted(self):
        macos = self.make_case(platform="macos", case_index=18)
        self.addCleanup(macos.close)
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "iOS case"):
            SIMULATOR.acquire_ios_simulator(macos, runtime_identifier=RUNTIME_ID, device_type_identifier=DEVICE_ID)
        self.case.close()
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "open owned"):
            self.acquire()
        self.assertEqual(self.model.calls, [])

    def test_unavailable_duplicate_or_incompatible_runtime_is_rejected(self):
        good = copy.deepcopy(self.model.runtimes)
        for runtimes in ([], good + good, [{**good[0], "isAvailable": False}], [{**good[0], "supportedDeviceTypes": []}]):
            self.model.runtimes = runtimes
            with self.assertRaises(SIMULATOR.NativeSimulatorError):
                self.acquire()
        self.assertEqual(self.mutations(), [])

    def test_invalid_device_inventory_cannot_authorize_creation(self):
        self.model.devices["broken"] = {"udid": "booted", "name": "broken"}
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "UUID"):
            self.acquire()
        self.assertEqual(self.mutations(), [])

    def test_unproven_create_output_retains_partial_allocation_without_name_based_delete(self):
        self.model.create_output = "booted"
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "partial state retained"):
            self.acquire()
        self.assertTrue((self.case.workspace.root / SIMULATOR._INTENT).exists())
        self.assertFalse((self.case.workspace.root / SIMULATOR._OWNER).exists())
        self.assertEqual(len(self.model.devices), len(self.before) + 1)
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_marker_publication_failure_retains_new_device_and_allocation_intent(self):
        real_publish = SIMULATOR._publish

        def fail_owner(path, payload):
            if path.name == SIMULATOR._OWNER:
                raise OSError("injected owner publication failure")
            return real_publish(path, payload)

        with patch.object(SIMULATOR, "_publish", side_effect=fail_owner):
            with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "owner publication"):
                self.acquire()
        self.assertTrue((self.case.workspace.root / SIMULATOR._INTENT).exists())
        self.assertEqual(len(self.model.devices), len(self.before) + 1)
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_interrupted_create_preserves_interruption_and_does_not_delete_by_name(self):
        self.model.failures["create"] = KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt):
            self.acquire()
        self.assertTrue((self.case.workspace.root / SIMULATOR._INTENT).exists())
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_cancelled_create_preserves_cancellation_classification(self):
        self.model.failures["create"] = RUNTIME.Cancelled()
        with self.assertRaises(RUNTIME.Cancelled) as raised:
            self.acquire()
        self.assertEqual(raised.exception.exit_code, 130)
        self.assertTrue((self.case.workspace.root / SIMULATOR._INTENT).exists())

    def test_marker_tampering_is_sticky_and_blocks_all_device_mutations(self):
        simulator = self.acquire()
        owner = self.case.workspace.root / SIMULATOR._OWNER
        original = owner.read_bytes()
        owner.write_bytes(b"changed")
        before = self.mutations()
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.boot()
        owner.write_bytes(original)
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        self.assertEqual(self.mutations(), before)
        self.assertIn(simulator.udid, self.model.devices)

    def test_allocation_intent_tampering_is_not_repaired_into_cleanup_success(self):
        simulator = self.acquire()
        intent = self.case.workspace.root / SIMULATOR._INTENT
        original = intent.read_bytes()
        intent.write_bytes(b"changed")
        before = self.mutations()
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        intent.write_bytes(original)
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        self.assertEqual(self.mutations(), before)

    def test_same_bytes_replacement_is_not_the_original_owner_marker(self):
        simulator = self.acquire()
        owner = self.case.workspace.root / SIMULATOR._OWNER
        original = owner.read_bytes()
        owner.rename(owner.with_name("held-owner"))
        owner.write_bytes(original)
        owner.chmod(0o600)
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        self.assertIn(simulator.udid, self.model.devices)

    def test_public_or_linked_markers_do_not_authorize_device_changes(self):
        for index, kind in enumerate(("public", "symlink", "hardlink")):
            case = self.make_case(case_index=40 + index)
            self.addCleanup(case.close)
            simulator = SIMULATOR.acquire_ios_simulator(case, runtime_identifier=RUNTIME_ID, device_type_identifier=DEVICE_ID)
            owner = case.workspace.root / SIMULATOR._OWNER
            foreign = self.root / f"foreign-{index}"
            if kind == "public":
                owner.chmod(0o644)
            elif kind == "hardlink":
                os.link(owner, foreign)
            else:
                owner.rename(foreign)
                owner.symlink_to(foreign)
            before = self.mutations()
            with self.assertRaises(SIMULATOR.NativeSimulatorError):
                simulator.close()
            self.assertEqual(self.mutations(), before)

    def test_forged_or_rebound_handle_cannot_mutate_an_existing_device(self):
        simulator = self.acquire()
        forged = dataclasses.replace(simulator, _ownership_token=object())
        rebound = dataclasses.replace(simulator, udid=next(iter(self.before)))
        before = self.mutations()
        for handle in (forged, rebound):
            with self.assertRaises(SIMULATOR.NativeSimulatorError):
                handle.close()
        self.assertEqual(self.mutations(), before)
        self.assertEqual({udid: self.model.devices[udid] for udid in self.before}, self.before)

    def test_renamed_missing_or_retyped_device_cannot_be_deleted(self):
        for index, change in enumerate(("name", "deviceTypeIdentifier", "missing")):
            case = self.make_case(case_index=50 + index)
            self.addCleanup(case.close)
            simulator = SIMULATOR.acquire_ios_simulator(case, runtime_identifier=RUNTIME_ID, device_type_identifier=DEVICE_ID)
            if change == "missing":
                del self.model.devices[simulator.udid]
            else:
                self.model.devices[simulator.udid][change] = "changed"
            before = self.mutations()
            with self.assertRaises(SIMULATOR.NativeSimulatorError):
                simulator.close()
            self.assertEqual(self.mutations(), before)

    def test_any_case_launch_requires_native_cleanup_and_retains_simulator(self):
        simulator = self.acquire()
        simulator.boot()
        self.transport.stop()  # The case phase is a real disposable Python process.
        try:
            managed = self.case.start_process([sys.executable, "-c", "pass"], env=os.environ)
            self.case.wait_process(managed, timeout=3, cancel_event=threading.Event())
        finally:
            self.transport.start()
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "native state cleanup is unimplemented"):
            simulator.close()
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))
        self.assertIsNone(simulator._state.receipt)

    def test_unproven_case_teardown_never_deletes_the_owned_device(self):
        simulator = self.acquire()
        simulator.boot()
        with patch.object(SIMULATOR.NativeCaseLifecycle, "close", side_effect=RUNTIME.RunnerError("unproven group")):
            with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "unproven group"):
                simulator.close()
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_shutdown_failure_is_sticky_and_does_not_delete(self):
        simulator = self.acquire()
        simulator.boot()
        self.model.failures["shutdown"] = 1
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        del self.model.failures["shutdown"]
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_delete_requires_positive_device_absence(self):
        simulator = self.acquire()
        self.model.keep_deleted = True
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "still exists"):
            simulator.close()
        self.assertIsNone(simulator._state.receipt)
        self.model.keep_deleted = False
        before = len([entry for entry in self.model.calls if entry[0] == "delete"])
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.close()
        self.assertEqual(len([entry for entry in self.model.calls if entry[0] == "delete"]), before)

    def test_boot_command_failure_can_teardown_a_verified_empty_device(self):
        simulator = self.acquire()
        self.model.failures["bootstatus"] = 1
        with self.assertRaises(SIMULATOR.NativeSimulatorError):
            simulator.boot()
        simulator.close()
        self.assertNotIn(simulator.udid, self.model.devices)

    def test_helper_exception_cannot_prove_process_cleanup_or_authorize_delete(self):
        simulator = self.acquire()
        self.model.failures["bootstatus"] = RUNTIME.RunnerError("timeout with unproven group", 124)
        with self.assertRaises(RUNTIME.RunnerError) as raised:
            simulator.boot()
        self.assertEqual(raised.exception.exit_code, 124)
        del self.model.failures["bootstatus"]
        before = len(self.model.calls)
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "lifecycle is closed"):
            simulator.boot()
        self.assertEqual(len(self.model.calls), before)
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "simctl process cleanup unproven"):
            simulator.close()
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_cancelled_boot_keeps_classification_and_retains_device(self):
        simulator = self.acquire()
        self.model.failures["bootstatus"] = RUNTIME.Cancelled()
        with self.assertRaises(RUNTIME.Cancelled):
            simulator.boot()
        del self.model.failures["bootstatus"]
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "simctl process cleanup unproven"):
            simulator.close()
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_timed_out_booting_device_is_shut_down_but_not_deleted(self):
        simulator = self.acquire()
        self.model.boot_state = "Booting"
        self.model.failures["bootstatus"] = RUNTIME.RunnerError("boot readiness timed out", 124)
        with self.assertRaises(RUNTIME.RunnerError) as raised:
            simulator.boot()
        self.assertEqual(raised.exception.exit_code, 124)
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Booting")
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "simctl process cleanup unproven"):
            simulator.close()
        self.assertIn(("shutdown", simulator.udid), self.model.calls)
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))
        self.assertEqual({udid: self.model.devices[udid] for udid in self.before}, self.before)

    def test_cancelled_booting_device_is_shut_down_but_not_deleted(self):
        simulator = self.acquire()
        self.model.boot_state = "Booting"
        self.model.failures["bootstatus"] = RUNTIME.Cancelled()
        with self.assertRaises(RUNTIME.Cancelled):
            simulator.boot()
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Booting")
        with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "simctl process cleanup unproven"):
            simulator.close()
        self.assertIn(("shutdown", simulator.udid), self.model.calls)
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))
        self.assertEqual({udid: self.model.devices[udid] for udid in self.before}, self.before)

    def test_zero_exit_bootstatus_requires_positive_booted_inventory(self):
        simulator = self.acquire()

        def still_shutdown(command, **kwargs):
            result = self.model.run(command, **kwargs)
            if command[2] == "bootstatus":
                self.model.devices[simulator.udid]["state"] = "Shutdown"
            return result

        with patch.object(RUNTIME, "run_logged_command", side_effect=still_shutdown):
            with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "readiness was not proven"):
                simulator.boot()
        simulator.close()

    def assert_post_boot_inventory_failure_retains_shutdown_device(self, failure):
        simulator = self.acquire()

        def fail_final_inventory(command, **kwargs):
            result = self.model.run(command, **kwargs)
            if command[2] == "bootstatus":
                self.model.failures["list"] = failure
            return result

        with patch.object(RUNTIME, "run_logged_command", side_effect=fail_final_inventory):
            with self.assertRaises(type(failure) if isinstance(failure, BaseException) else SIMULATOR.NativeSimulatorError) as raised:
                simulator.boot()
        if isinstance(failure, RUNTIME.RunnerError):
            self.assertEqual(raised.exception.exit_code, failure.exit_code)
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Booted")
        self.assertIsNone(simulator._state.ownership_error)
        del self.model.failures["list"]
        for _ in range(2):
            with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "device inventory unavailable"):
                simulator.close()
        self.assertEqual(self.model.calls.count(("shutdown", simulator.udid)), 1)
        self.assertEqual(self.model.devices[simulator.udid]["state"], "Shutdown")
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))
        self.assertIsNone(simulator._state.receipt)
        self.assertEqual({udid: self.model.devices[udid] for udid in self.before}, self.before)

    def test_timed_out_post_boot_inventory_allows_shutdown_without_deletion(self):
        self.assert_post_boot_inventory_failure_retains_shutdown_device(RUNTIME.RunnerError("inventory timed out", 124))

    def test_cancelled_post_boot_inventory_allows_shutdown_without_deletion(self):
        self.assert_post_boot_inventory_failure_retains_shutdown_device(RUNTIME.Cancelled())

    def test_nonzero_post_boot_inventory_allows_shutdown_without_deletion(self):
        self.assert_post_boot_inventory_failure_retains_shutdown_device(1)

    def test_disappearance_during_shutdown_is_not_delete_proof(self):
        simulator = self.acquire()
        simulator.boot()

        def disappear(command, **kwargs):
            result = self.model.run(command, **kwargs)
            if command[2] == "shutdown":
                del self.model.devices[simulator.udid]
            return result

        with patch.object(RUNTIME, "run_logged_command", side_effect=disappear):
            with self.assertRaisesRegex(SIMULATOR.NativeSimulatorError, "disappeared before shutdown proof"):
                simulator.close()
        self.assertIsNone(simulator._state.receipt)
        self.assertFalse(any(entry[0] == "delete" for entry in self.model.calls))

    def test_invalid_close_budget_has_no_process_or_device_side_effects(self):
        simulator = self.acquire()
        before = len(self.model.calls)
        for timeout in (0, -1, True, float("inf")):
            with self.assertRaises(SIMULATOR.NativeSimulatorError):
                simulator.close(timeout=timeout)
        self.assertEqual(len(self.model.calls), before)
        self.assertTrue(self.case.accepting_launches)
        simulator.close()

    def test_boot_child_environment_is_not_inherited_from_the_host(self):
        with patch.dict(os.environ, {"SIMCTL_CHILD_UNRELATED": "not-for-this-device"}):
            simulator = self.acquire()
            simulator.boot()
            simulator.close()
        self.assertTrue(all(not any(key.startswith("SIMCTL_CHILD_") for key in env) for env in self.model.environments))


if __name__ == "__main__":
    unittest.main()
