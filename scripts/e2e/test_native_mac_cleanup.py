"""Host binding tests: private fake signed artifacts and real owned children.

codesign/native storage are modelled here. These tests cannot establish real
Keychain deletion; the standalone Swift fixture covers that separate boundary.
"""

from __future__ import annotations

import dataclasses
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
try:
    import native_mac_cleanup as CLEANUP
    from native_case_lifecycle import NativeCaseLifecycle
    from native_workspace import prepare_native_case_workspace
finally:
    sys.path.pop(0)


TEAM = "ABCDEFGHIJ"
NS = "vizor_a1b2c3d4e5_w2_17"


def receipt(namespace=NS):
    service = f"com.keplr.vizor.regtest.secure_store.e2e.{namespace}"
    return {
        "schema_version": 1, "platform": "macos", "mode": "delete",
        "namespace": namespace, "expected_team": TEAM, "completed": True,
        "identity": {"bundle_id": "com.keplr.vizor", "team_id": TEAM,
                     "application_identifier": f"{TEAM}.com.keplr.vizor"},
        "keychain": [
            {"service": target, "before_status": 0, "delete_status": 0, "after_status": -25300}
            for target in (service, f"{service}.mnemonic")
        ],
        "preferences": {"prefix": f"flutter.vizor_e2e_{namespace}.", "before_count": 1,
                        "removed_count": 1, "after_count": 0, "synchronized": True},
    }


class MacCleanupReceiptTests(unittest.TestCase):
    def validate(self, value):
        CLEANUP._validate_receipt((json.dumps(value) + "\n",), namespace=NS, team=TEAM)

    def test_complete_deletion_or_already_absent_observations(self):
        self.validate(receipt())
        absent = receipt()
        for item in absent["keychain"]:
            item.update(before_status=-25300, delete_status=-25300)
        absent["preferences"].update(before_count=0, removed_count=0)
        self.validate(absent)

    def test_case_platform_mode_identity_and_completion_must_match(self):
        for field, value in (
            ("schema_version", True), ("schema_version", 2), ("platform", "ios"),
            ("mode", "verify"), ("namespace", NS + "0"), ("expected_team", "ZZZZZZZZZZ"),
            ("completed", False), ("completed", 1),
        ):
            with self.subTest(field=field, value=value):
                modified = receipt()
                modified[field] = value
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.validate(modified)
        for field in ("bundle_id", "team_id", "application_identifier"):
            modified = receipt()
            modified["identity"][field] += ".other"
            with self.assertRaises(CLEANUP.MacCleanupError):
                self.validate(modified)

    def test_keychain_partial_errors_retention_boolean_and_wrong_scope(self):
        for update in (
            {"service": "com.keplr.vizor.mainnet.secure_store"},
            {"before_status": -25308}, {"delete_status": -34018}, {"after_status": 0},
            {"before_status": False}, {"after_status": -25300.0},
        ):
            with self.subTest(update=update):
                modified = receipt()
                modified["keychain"][0].update(update)
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.validate(modified)
        for observations in ([], receipt()["keychain"][:1], receipt()["keychain"] * 2,
                             list(reversed(receipt()["keychain"])), {}):
            modified = receipt()
            modified["keychain"] = observations
            with self.assertRaises(CLEANUP.MacCleanupError):
                self.validate(modified)

    def test_preferences_require_exact_prefix_counts_synchronization_and_absence(self):
        for update in (
            {"prefix": "flutter."}, {"before_count": -1}, {"before_count": True},
            {"removed_count": 0}, {"after_count": 1}, {"after_count": 0.0},
            {"synchronized": False}, {"synchronized": 1},
        ):
            with self.subTest(update=update):
                modified = receipt()
                modified["preferences"].update(update)
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.validate(modified)

    def test_unknown_missing_and_duplicate_fields_cannot_claim_success(self):
        for section in (None, "identity", "preferences"):
            for extra in (False, True):
                modified = receipt()
                selected = modified if section is None else modified[section]
                if extra:
                    selected["error_code"] = None
                else:
                    del selected[next(iter(selected))]
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.validate(modified)
        text = json.dumps(receipt()).replace('"completed": true', '"completed": true, "completed": true')
        with self.assertRaisesRegex(CLEANUP.MacCleanupError, "duplicate"):
            CLEANUP._validate_receipt((text,), namespace=NS, team=TEAM)

    def test_invalid_multiple_and_oversized_output_is_not_a_receipt(self):
        for text in ("", "{}", "null", "[]", "diagnostic\n" + json.dumps(receipt()),
                     json.dumps(receipt()) * 2, " " * 8193, "[" * 2000):
            with self.subTest(text=text[:20]), self.assertRaises(CLEANUP.MacCleanupError):
                CLEANUP._validate_receipt((text,), namespace=NS, team=TEAM)


class MacCleanupHostTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-mac-cleanup-host-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.run_root = self.root / "run"
        self.run_root.mkdir(mode=0o700)
        self.cases = []
        self.addCleanup(self.close_cases)
        self.case = self.make_case()
        self.helper_app = self.make_app("Cleanup", background=True)
        self.cohort_app = self.make_app("Cohort", background=False)
        self.signing_fail = False
        self.team_overrides = {}
        self.certificate_overrides = {}
        self.entitlement_updates = {}
        self.addCleanup(patch.stopall)
        patch.object(CLEANUP.sys, "platform", "darwin").start()
        patch.object(CLEANUP, "_codesign", side_effect=self.codesign).start()

    def make_case(self, *, platform="macos", index=17):
        workspace = prepare_native_case_workspace(
            self.run_root, platform=platform, scenario_id=f"flutter.{platform}.contract-probe",
            run_id="a1b2c3d4e5", worker_id=2, case_index=index,
            ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=500,
        )
        case = NativeCaseLifecycle(workspace)
        self.cases.append(case)
        return case

    def close_cases(self):
        for case in self.cases:
            try:
                case.close()
            except CLEANUP.runtime.RunnerError:
                self.assertIsNone(case._receipt)
            for managed in case._processes:
                self.assertIsNotNone(managed.process.poll())
                self.assertFalse(managed.pump_thread.is_alive())

    def make_app(self, name, *, background):
        app = self.root / f"{name}.app"
        executable_name = "vizor-native-cleanup" if background else name
        (app / "Contents/MacOS").mkdir(parents=True, mode=0o700)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.keplr.vizor", "CFBundleExecutable": executable_name,
            "LSBackgroundOnly": background,
        }))
        (app / "Contents/embedded.provisionprofile").write_bytes(b"public-profile-model")
        executable = app / "Contents/MacOS" / executable_name
        executable.write_text(f"#!{sys.executable}\nimport json\nprint(json.dumps({receipt()!r}))\n")
        executable.chmod(0o700)
        return app

    def codesign(self, *arguments):
        if self.signing_fail:
            raise CLEANUP.MacCleanupError("model signing inspection failed")
        app = Path(arguments[-1])
        team = self.team_overrides.get(app, TEAM)
        stdout = stderr = b""
        if "--verbose=4" in arguments:
            stderr = f"Identifier=com.keplr.vizor\nTeamIdentifier={team}\n".encode()
        elif "--entitlements" in arguments:
            entitlements = {
                "com.apple.security.app-sandbox": True,
                "com.apple.developer.team-identifier": team,
                "com.apple.application-identifier": f"{team}.com.keplr.vizor",
            }
            entitlements.update(self.entitlement_updates.get(app, {}))
            stdout = plistlib.dumps(entitlements)
        else:
            for argument in arguments:
                if argument.startswith("--extract-certificates="):
                    prefix = argument.split("=", 1)[1]
                    Path(prefix + "0").write_bytes(self.certificate_overrides.get(app, b"public-leaf-model"))
        return subprocess.CompletedProcess(arguments, 0, stdout, stderr)

    def capture(self):
        return CLEANUP.capture_mac_cleanup_helper(self.helper_app, cohort_app=self.cohort_app)

    def clean(self, *, case=None, helper=None, timeout=3, cancel_event=None):
        return CLEANUP.clean_mac_case(
            case or self.case, helper or self.capture(), timeout=timeout,
            cancel_event=cancel_event or threading.Event(),
        )

    def rewrite_helper(self, source):
        (self.helper_app / "Contents/MacOS/vizor-native-cleanup").write_text(f"#!{sys.executable}\n{source}\n")

    def test_capture_reads_actual_matching_signing_and_does_not_launch(self):
        with patch.object(CLEANUP.runtime, "start_logged_process") as started:
            helper = self.capture()
            helper.verify_unchanged()
            self.assertEqual(helper.team, TEAM)
            started.assert_not_called()

    def test_wrong_team_certificate_profile_and_signature_are_refused(self):
        for kind in ("team", "certificate", "profile", "signature"):
            with self.subTest(kind=kind):
                if kind == "team":
                    self.team_overrides[self.helper_app] = "ZZZZZZZZZZ"
                elif kind == "certificate":
                    self.certificate_overrides[self.helper_app] = b"different-leaf"
                elif kind == "profile":
                    (self.helper_app / "Contents/embedded.provisionprofile").write_bytes(b"different-profile")
                else:
                    self.signing_fail = True
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.capture()
                self.team_overrides.clear()
                self.certificate_overrides.clear()
                self.signing_fail = False
                (self.helper_app / "Contents/embedded.provisionprofile").write_bytes(b"public-profile-model")

    def test_bad_entitlements_or_extra_helper_permissions_are_refused(self):
        for update in (
            {"com.apple.security.app-sandbox": False},
            {"com.apple.application-identifier": "wrong"},
            {"keychain-access-groups": [f"{TEAM}.com.keplr.vizor", "other"]},
            {"com.apple.security.cs.disable-library-validation": True},
            {"com.apple.security.network.client": True},
        ):
            with self.subTest(update=update):
                self.entitlement_updates[self.helper_app] = update
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.capture()

    def test_same_app_or_foreground_helper_is_refused(self):
        with self.assertRaises(CLEANUP.MacCleanupError):
            CLEANUP.capture_mac_cleanup_helper(self.cohort_app, cohort_app=self.cohort_app)
        info = self.helper_app / "Contents/Info.plist"
        values = plistlib.loads(info.read_bytes())
        values["LSBackgroundOnly"] = False
        info.write_bytes(plistlib.dumps(values))
        with self.assertRaises(CLEANUP.MacCleanupError):
            self.capture()

    def test_signed_smoke_or_wallet_executable_is_not_a_cleanup_cli(self):
        info = self.helper_app / "Contents/Info.plist"
        values = plistlib.loads(info.read_bytes())
        values["CFBundleExecutable"] = "Smoke"
        (self.helper_app / "Contents/MacOS/vizor-native-cleanup").rename(
            self.helper_app / "Contents/MacOS/Smoke",
        )
        info.write_bytes(plistlib.dumps(values))
        with self.assertRaisesRegex(CLEANUP.MacCleanupError, "vizor-native-cleanup"):
            self.capture()

    def test_terminal_command_can_follow_a_completed_close_without_new_phase_launches(self):
        self.case.close()
        self.assertFalse(self.case.accepting_launches)
        observed = self.clean()
        self.assertEqual(observed.process_cleanup.exit_codes, (0,))
        self.assertFalse(self.case.accepting_launches)

    def test_invalid_terminal_budget_does_not_consume_the_one_attempt(self):
        for budget in (True, 0, -1, float("nan"), float("inf")):
            with self.subTest(budget=budget), self.assertRaises(CLEANUP.runtime.RunnerError):
                self.clean(timeout=budget)
        self.assertTrue(self.case.accepting_launches)
        self.clean()

    def test_symlink_hardlink_and_writable_artifacts_are_refused(self):
        file = self.helper_app / "Contents/embedded.provisionprofile"
        for kind in ("symlink", "hardlink", "writable"):
            with self.subTest(kind=kind):
                other = self.root / f"{kind}-public-file"
                file.rename(other)
                if kind == "symlink":
                    file.symlink_to(other)
                elif kind == "hardlink":
                    os.link(other, file)
                else:
                    file.write_bytes(other.read_bytes())
                    file.chmod(0o666)
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.capture()
                file.unlink()
                other.rename(file)

    def test_changed_helper_or_cohort_is_refused_before_spawn(self):
        for file in (
            self.helper_app / "Contents/MacOS/vizor-native-cleanup",
            self.cohort_app / "Contents/MacOS/Cohort",
            self.helper_app / "Contents/embedded.provisionprofile",
        ):
            helper = self.capture()
            original = file.read_bytes()
            file.write_bytes(original + b"changed")
            with patch.object(CLEANUP.runtime, "start_logged_process") as started:
                with self.assertRaises(CLEANUP.MacCleanupError):
                    self.clean(helper=helper)
                started.assert_not_called()
            file.write_bytes(original)

    def test_forged_handle_is_refused_before_storage_launch(self):
        helper = dataclasses.replace(self.capture(), _capture_token=object())
        with patch.object(CLEANUP.runtime, "start_logged_process") as started:
            with self.assertRaises(CLEANUP.MacCleanupError):
                self.clean(helper=helper)
            started.assert_not_called()

    def test_ios_case_and_changed_workspace_are_refused_before_spawn(self):
        ios = self.make_case(platform="ios", index=18)
        with patch.object(CLEANUP.runtime, "start_logged_process") as started:
            with self.assertRaises(CLEANUP.MacCleanupError):
                self.clean(case=ios)
            self.case.workspace.marker_path.write_text("{}")
            with self.assertRaises(RuntimeError):
                self.clean()
            started.assert_not_called()

    def test_live_writer_is_stopped_before_terminal_launch_without_reopening(self):
        writer = self.case.start_process(
            [sys.executable, "-B", "-c", "import time; print('ready',flush=True); time.sleep(30)"],
            env=os.environ,
        )
        deadline = time.monotonic() + 3
        while "ready" not in writer.log_path.read_text() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertIn("ready", writer.log_path.read_text())
        start = self.case._start_process
        def after_stop(*args, **kwargs):
            self.assertTrue(writer.cleanup_completed)
            self.assertIsNotNone(writer.process.poll())
            self.assertFalse(self.case.accepting_launches)
            return start(*args, **kwargs)
        with patch.object(self.case, "_start_process", side_effect=after_stop):
            observed = self.clean()
        self.assertEqual(observed.namespace, NS)
        self.assertEqual(len(observed.process_cleanup.exit_codes), 2)
        self.assertTrue(self.case.workspace.marker_path.exists())
        self.assertTrue(writer.log_path.exists())
        with self.assertRaisesRegex(CLEANUP.runtime.RunnerError, "sealed"):
            self.case.start_process([sys.executable, "-c", "pass"], env={})
        with self.assertRaisesRegex(CLEANUP.runtime.RunnerError, "already attempted"):
            self.clean()

    def test_helper_does_not_inherit_loader_or_user_domain_overrides(self):
        start = CLEANUP.runtime.start_logged_process
        with patch.dict(os.environ, {"DYLD_INSERT_LIBRARIES": "other", "CFFIXED_USER_HOME": "other"}):
            with patch.object(CLEANUP.runtime, "start_logged_process", wraps=start) as started:
                self.clean()
        environment = started.call_args.kwargs["env"]
        self.assertEqual(set(environment), {"PATH", "LANG", "VIZOR_E2E_NAMESPACE", "VIZOR_E2E_CASE_MANIFEST"})
        self.assertEqual(environment["VIZOR_E2E_NAMESPACE"], NS)

    def test_receipt_must_come_from_owned_completed_launch_not_an_external_file(self):
        (self.case.workspace.root / "native-context.json").write_text(json.dumps(receipt()))
        self.rewrite_helper("print('{}')")
        with self.assertRaises(CLEANUP.MacCleanupError):
            self.clean()
        self.assertTrue((self.case.workspace.root / "native-context.json").exists())
        self.assertTrue((self.case.workspace.root / "process-0000.log").exists())

    def test_nonzero_timeout_cancel_and_bad_output_never_become_native_success(self):
        for kind, source in (
            ("nonzero", f"import json; print(json.dumps({receipt()!r})); raise SystemExit(7)"),
            ("timeout", "import time; print('partial',flush=True); time.sleep(30)"),
            ("cancel", "import time; time.sleep(30)"),
            ("wrong-scope", f"import json; print(json.dumps({receipt(NS + '0')!r}))"),
        ):
            with self.subTest(kind=kind):
                case = self.make_case(index=20 + len(self.cases))
                self.rewrite_helper(source)
                cancelled = threading.Event()
                if kind == "cancel":
                    cancelled.set()
                with self.assertRaises(CLEANUP.runtime.RunnerError):
                    self.clean(case=case, timeout=0.04 if kind == "timeout" else 3, cancel_event=cancelled)
                self.assertFalse(case.accepting_launches)
                self.assertTrue((case.workspace.root / "process-0000.log").exists())
                with self.assertRaises(CLEANUP.runtime.RunnerError):
                    self.clean(case=case)

    def test_unproven_writer_cleanup_forbids_terminal_spawn(self):
        self.case._cleanup_failed(CLEANUP.runtime.RunnerError("writer output unproven"))
        with patch.object(CLEANUP.runtime, "start_logged_process") as started:
            with self.assertRaisesRegex(CLEANUP.runtime.RunnerError, "unproven"):
                self.clean()
            started.assert_not_called()

    def test_artifact_changed_during_helper_execution_forbids_success(self):
        cohort_executable = self.cohort_app / "Contents/MacOS/Cohort"
        self.rewrite_helper(
            f"import json; from pathlib import Path; Path({str(cohort_executable)!r}).write_text('changed'); "
            f"print(json.dumps({receipt()!r}))"
        )
        with self.assertRaisesRegex(CLEANUP.MacCleanupError, "changed"):
            self.clean()
        self.assertFalse(self.case.accepting_launches)
        self.assertTrue((self.case.workspace.root / "process-0000.log").exists())


if __name__ == "__main__":
    unittest.main()
