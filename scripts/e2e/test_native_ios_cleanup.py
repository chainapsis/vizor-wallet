"""Portable Simulator capture/receipt models; no native storage or device I/O."""

from __future__ import annotations

import dataclasses
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_ios_cleanup as NATIVE
finally:
    sys.path.pop(0)

TEAM = "A1B2C3D4E5"
APP_ID = TEAM + ".com.keplr.vizor"
NAMESPACE = "vizor_a1b2c3d4e5_w2_17"
UDID = "ED3345B2-2A4F-4A41-A35B-2C09EBA034F6"
NONCE = "1234567890abcdef"


def executable(rights=None, *, cpu=0x0100000C, platform=7):
    payload = plistlib.dumps({"application-identifier": APP_ID} if rights is None else rights)
    data = bytearray(208 + len(payload))
    struct.pack_into("<8I", data, 0, 0xFEEDFACF, cpu, 0, 2, 2, 176, 0, 0)
    struct.pack_into("<2I", data, 32, 0x19, 152)
    data[40:56] = b"__TEXT".ljust(16, b"\0")
    struct.pack_into("<I", data, 96, 1)
    data[104:120] = b"__entitlements".ljust(16, b"\0")
    data[120:136] = b"__TEXT".ljust(16, b"\0")
    struct.pack_into("<Q", data, 144, len(payload))
    struct.pack_into("<I", data, 152, 208)
    struct.pack_into("<6I", data, 184, 0x32, 24, platform, 0, 0, 0)
    data[208:] = payload
    return bytes(data)


def receipt(mode="delete"):
    items = [{"service": service, "before_status": 0 if mode == "delete" else -25300,
              "after_status": -25300, **({"delete_status": 0} if mode == "delete" else {})}
             for service in NATIVE._services(NAMESPACE)]
    count = 2 if mode == "delete" else 0
    return {
        "schema_version": 1, "platform": "ios", "mode": mode, "namespace": NAMESPACE,
        "simulator_udid": UDID, "owner_nonce": NONCE, "expected_team": TEAM,
        "keychain_scope": "application_accessible", "completed": True,
        "identity": {"bundle_id": "com.keplr.vizor", "simulator_udid": UDID,
                     "cleanup_build_marker": True, "application_identifier": APP_ID},
        "keychain": items,
        "preferences": [
            {"domain": "com.keplr.vizor", "prefix": f"flutter.vizor_e2e_{NAMESPACE}.",
             "before_count": count, "removed_count": count, "after_count": 0, "synchronized": True},
            {"domain": f"com.keplr.vizor.regtest.e2e.{NAMESPACE}", "before_count": count,
             "removed_count": count, "after_count": 0, "synchronized": True},
        ],
        "notifications": {"prefix": f"vizor_e2e_{NAMESPACE}.", "pending_before_count": count,
            "delivered_before_count": count, "pending_removed_count": count,
            "delivered_removed_count": count, "pending_after_count": 0, "delivered_after_count": 0},
    }


def validate(value, mode="delete", **scope):
    options = {"namespace": NAMESPACE, "udid": UDID, "owner_nonce": NONCE,
               "application_identifier": APP_ID, "mode": mode, **scope}
    NATIVE._validate_receipt((json.dumps(value),), **options)


class SimulatorArtifactTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-ios-capture-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.helper = self.make_app("Helper.app", helper=True)
        self.cohort = self.make_app("Runner.app", helper=False)
        self.metadata = {"Identifier": "com.keplr.vizor", "Signature": "adhoc", "TeamIdentifier": "not set"}
        self.signed_rights = None
        self.calls = []
        self.on_verify = None
        self.signature_code = 0
        for target, name, value in ((NATIVE, "_HOST_PLATFORM", "darwin"),
                                    (NATIVE.subprocess, "run", self.codesign)):
            context = patch.object(target, name, value)
            context.start()
            self.addCleanup(context.stop)

    def make_app(self, name, *, helper, rights=None, cpu=0x0100000C, platform=7):
        path = self.root / name
        path.mkdir(mode=0o700)
        (path / "_CodeSignature").mkdir(mode=0o700)
        executable_name = "vizor-ios-cleanup" if helper else "Runner"
        info = {"CFBundleIdentifier": "com.keplr.vizor", "CFBundleExecutable": executable_name,
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
                "VizorE2eIosCleanup" if helper else "VizorE2eIosCohort": True}
        (path / "Info.plist").write_bytes(plistlib.dumps(info))
        (path / executable_name).write_bytes(executable(rights, cpu=cpu, platform=platform))
        (path / executable_name).chmod(0o700)
        (path / "_CodeSignature/CodeResources").write_bytes(plistlib.dumps({}))
        return path

    def codesign(self, command, **kwargs):
        self.assertEqual(command[0], "/usr/bin/codesign")
        self.assertEqual(kwargs, {"capture_output": True, "timeout": 15, "check": False})
        self.calls.append(command)
        if "--verify" in command:
            if self.on_verify:
                self.on_verify(Path(command[-1]))
            return subprocess.CompletedProcess(command, self.signature_code, b"", b"")
        if "--entitlements" in command:
            data = b"" if self.signed_rights is None else plistlib.dumps(self.signed_rights)
            return subprocess.CompletedProcess(command, 0, data, b"")
        text = "\n".join(f"{key}={value}" for key, value in self.metadata.items())
        return subprocess.CompletedProcess(command, 0, b"", text.encode())

    def capture(self):
        return NATIVE.capture_ios_cleanup_helper(self.helper, cohort_app=self.cohort)

    def rewrite_info(self, path, **updates):
        file = path / "Info.plist"
        value = plistlib.loads(file.read_bytes())
        file.write_bytes(plistlib.dumps({**value, **updates}))

    def test_capture_uses_embedded_rights_despite_empty_ad_hoc_dictionary(self):
        captured = self.capture()
        self.assertEqual(captured.team, TEAM)
        self.assertEqual(captured.application_identifier, APP_ID)
        self.assertEqual(captured.architecture, "arm64")
        captured.verify_unchanged()
        self.assertFalse(hasattr(captured, "storage_cleanup_completed"))
        self.assertTrue(all(command[1] in {"--verify", "--display"} for command in self.calls))
        self.signed_rights = {}
        captured.verify_unchanged()

    def test_x86_64_capture_requires_matching_cohort_architecture(self):
        for path, name in ((self.helper, "vizor-ios-cleanup"), (self.cohort, "Runner")):
            (path / name).write_bytes(executable(cpu=0x01000007))
        self.assertEqual(self.capture().architecture, "x86_64")
        (self.cohort / "Runner").write_bytes(executable())
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()

    def test_cohort_can_have_widget_groups_but_helper_cannot(self):
        rights = {"application-identifier": APP_ID, "com.apple.security.application-groups": ["group.com.keplr.vizor"]}
        (self.cohort / "Runner").write_bytes(executable(rights))
        self.capture()
        (self.helper / "vizor-ios-cleanup").write_bytes(executable(rights))
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()

    def test_wrong_team_or_shared_keychain_group_is_refused(self):
        for rights in ({"application-identifier": "Z9Y8X7W6V5.com.keplr.vizor"},
                       {"application-identifier": APP_ID, "keychain-access-groups": [APP_ID, "shared"]}):
            with self.subTest(rights=rights):
                (self.cohort / "Runner").write_bytes(executable(rights))
                with self.assertRaises(NATIVE.IosCleanupError):
                    self.capture()

    def test_device_platform_and_missing_embedded_rights_are_refused(self):
        for data in (executable(platform=2), executable(platform=1), executable({}), b"not a Mach-O"):
            with self.subTest(data=data[:32]):
                (self.helper / "vizor-ios-cleanup").write_bytes(data)
                with self.assertRaises(NATIVE.IosCleanupError):
                    self.capture()

    def test_false_or_nonboolean_build_markers_are_not_cohorts(self):
        for value in (False, 1, "true"):
            with self.subTest(value=value):
                self.rewrite_info(self.cohort, VizorE2eIosCohort=value)
                with self.assertRaises(NATIVE.IosCleanupError):
                    self.capture()
        self.rewrite_info(self.cohort, VizorE2eIosCohort=True)
        self.rewrite_info(self.helper, VizorE2eIosCleanup=1)
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()

    def test_wrong_helper_executable_role_cannot_be_renamed_into_capture(self):
        self.rewrite_info(self.helper, CFBundleExecutable="vizor-ios-cleanup-smoke")
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()

    def test_invalid_or_non_ad_hoc_signature_is_refused(self):
        self.signature_code = 1
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()
        self.signature_code = 0
        self.metadata["Signature"] = "development"
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()

    def test_signed_and_embedded_rights_must_not_disagree(self):
        self.signed_rights = {"application-identifier": "Z9Y8X7W6V5.com.keplr.vizor"}
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()
        self.signed_rights = {"application-identifier": APP_ID}
        self.capture()

    def test_files_cannot_change_during_signature_inspection(self):
        self.on_verify = lambda app: self.rewrite_info(app, unrelated="changed")
        with self.assertRaisesRegex(NATIVE.IosCleanupError, "changed during capture"):
            self.capture()

    def test_parsed_info_must_be_the_same_snapshot_as_captured_info(self):
        reader = NATIVE._regular_bytes
        changed = False

        def read(path, limit):
            nonlocal changed
            result = reader(path, limit)
            if path == self.helper / "Info.plist" and not changed:
                changed = True
                self.rewrite_info(self.helper, VizorE2eIosCleanup=False)
            return result

        with patch.object(NATIVE, "_regular_bytes", side_effect=read):
            with self.assertRaisesRegex(NATIVE.IosCleanupError, "changed during capture"):
                self.capture()

    def test_directory_permissions_cannot_change_during_capture(self):
        self.on_verify = lambda app: app.chmod(0o777)
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()

    def test_original_inode_and_digest_are_both_required(self):
        captured = self.capture()
        file = self.helper / "Info.plist"
        contents = file.read_bytes()
        replacement = self.helper / "replacement.plist"
        replacement.write_bytes(contents)
        replacement.replace(file)
        with self.assertRaisesRegex(NATIVE.IosCleanupError, "identity changed"):
            captured.verify_unchanged()
        captured = self.capture()
        self.rewrite_info(self.helper, unrelated="new value")
        with self.assertRaisesRegex(NATIVE.IosCleanupError, "identity changed"):
            captured.verify_unchanged()

    def test_symlink_hardlink_and_group_writable_files_are_refused(self):
        file = self.helper / "Info.plist"
        file.chmod(0o666)
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()
        file.chmod(0o600)
        os.link(file, self.root / "info-hardlink")
        with self.assertRaises(NATIVE.IosCleanupError):
            self.capture()
        alias = self.root / "Alias.app"
        alias.symlink_to(self.helper, target_is_directory=True)
        with self.assertRaises(NATIVE.IosCleanupError):
            NATIVE.capture_ios_cleanup_helper(alias, cohort_app=self.cohort)

    def test_foreign_capture_token_and_unsupported_host_are_refused(self):
        captured = self.capture()
        with self.assertRaises(NATIVE.IosCleanupError):
            dataclasses.replace(captured, _capture_token=object()).verify_unchanged()
        with patch.object(NATIVE, "_HOST_PLATFORM", "linux"):
            with self.assertRaises(NATIVE.IosCleanupError):
                self.capture()

    def test_malformed_header_command_section_and_plist_are_not_empty_rights(self):
        for size in (0, 1, 31, 32, 100, 207, 208):
            with self.subTest(size=size), self.assertRaises(NATIVE.IosCleanupError):
                NATIVE._simulator_rights(executable()[:size])
        for offset in (0, 4, 12, 16, 20, 36, 96, 144, 152, 192):
            value = bytearray(executable())
            struct.pack_into("<I", value, offset, 0xFFFFFFFF)
            with self.subTest(offset=offset), self.assertRaises(NATIVE.IosCleanupError):
                NATIVE._simulator_rights(bytes(value))
        value = bytearray(executable())
        value[208:] = b"x" * (len(value) - 208)
        with self.assertRaises(NATIVE.IosCleanupError):
            NATIVE._simulator_rights(bytes(value))
        value = bytearray(executable())
        malformed = b'<?xml version="1.0"?><plist><dict></plist>'
        value[208:] = malformed
        struct.pack_into("<Q", value, 144, len(malformed))
        with self.assertRaises(NATIVE.IosCleanupError):
            NATIVE._simulator_rights(bytes(value))

    def test_duplicate_entitlement_sections_are_refused(self):
        original = executable()
        value = bytearray(original[:184] + original[104:184] + original[184:])
        struct.pack_into("<I", value, 20, 256)
        struct.pack_into("<I", value, 36, 232)
        struct.pack_into("<I", value, 96, 2)
        for offset in (152, 232):
            struct.pack_into("<I", value, offset, 288)
        with self.assertRaises(NATIVE.IosCleanupError):
            NATIVE._simulator_rights(bytes(value))


class SimulatorReceiptTests(unittest.TestCase):
    def test_complete_delete_and_read_only_verify_receipts_are_accepted(self):
        validate(receipt())
        validate(receipt("verify"), mode="verify")

    def test_another_case_device_nonce_team_or_mode_is_not_this_launch(self):
        for key, value in (("namespace", NAMESPACE + "1"), ("simulator_udid", "00000000-0000-0000-0000-000000000001"),
                           ("owner_nonce", "abcdef1234567890"), ("expected_team", "Z9Y8X7W6V5"),
                           ("mode", "verify"), ("platform", "macos"), ("keychain_scope", "shared")):
            data = receipt()
            data[key] = value
            with self.subTest(key=key), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_expected_scope_must_itself_be_canonical(self):
        for scope in ({"namespace": "vizor_a1b2c3d4e5_w02_17"}, {"namespace": "vizor_a1b2c3d4e5_w2_1000001"},
                      {"udid": UDID.lower()}, {"udid": "booted"}, {"owner_nonce": NONCE.upper()},
                      {"application_identifier": "com.keplr.vizor"}, {"mode": "reset"}):
            with self.subTest(scope=scope), self.assertRaises(NATIVE.IosCleanupError):
                validate(receipt(), **scope)

    def test_scope_completion_schema_and_marker_types_are_strict(self):
        for key, value in (("schema_version", True), ("completed", 1), ("completed", False)):
            data = receipt()
            data[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)
        data = receipt()
        data["identity"]["cleanup_build_marker"] = 1
        with self.assertRaises(NATIVE.IosCleanupError):
            validate(data)

    def test_identity_cannot_claim_another_application_or_device(self):
        for key, value in (("application_identifier", "Z9Y8X7W6V5.com.keplr.vizor"),
                           ("bundle_id", "other.app"), ("simulator_udid", "booted")):
            data = receipt()
            data["identity"][key] = value
            with self.subTest(key=key), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_missing_reordered_or_sibling_keychain_services_are_refused(self):
        values = [receipt(), receipt(), receipt()]
        values[0]["keychain"].pop()
        values[1]["keychain"].reverse()
        values[2]["keychain"][1]["service"] += "-sibling"
        for data in values:
            with self.subTest(data=data["keychain"]), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_native_errors_bool_statuses_and_retained_items_are_not_absence(self):
        for key, status in (("before_status", -34018), ("before_status", -25308), ("delete_status", -50),
                            ("delete_status", False), ("after_status", 0), ("after_status", -34018)):
            data = receipt()
            data["keychain"][4][key] = status
            with self.subTest(key=key, status=status), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_preference_domain_prefix_counts_and_synchronization_are_exact(self):
        for index, key, value in ((0, "prefix", "flutter."), (1, "domain", "production"), (1, "prefix", None),
                                 (0, "after_count", 1), (1, "removed_count", 1), (0, "before_count", -1),
                                 (1, "synchronized", 1), (0, "after_count", False)):
            data = receipt()
            data["preferences"][index][key] = value
            with self.subTest(index=index, key=key), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_notification_counts_require_complete_positive_absence(self):
        for key, value in (("prefix", "production"), ("pending_after_count", 1), ("delivered_after_count", False),
                           ("pending_removed_count", 0), ("delivered_before_count", -1)):
            data = receipt()
            data["notifications"][key] = value
            with self.subTest(key=key), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_verify_cannot_report_retained_state_as_absent(self):
        for location in ("keychain", "preferences", "notifications"):
            data = receipt("verify")
            if location == "keychain":
                data[location][0]["before_status"] = 0
            elif location == "preferences":
                data[location][0]["before_count"] = 1
                data[location][0]["removed_count"] = 1
            else:
                data[location]["pending_before_count"] = 1
                data[location]["pending_removed_count"] = 1
            with self.subTest(location=location), self.assertRaises(NATIVE.IosCleanupError):
                validate(data, mode="verify")

    def test_extra_error_secret_or_ownership_fields_are_refused(self):
        for key, value in (("error_code", None), ("secret_value", "not-a-real-secret"),
                           ("storage_cleanup_completed", True), ("pid", 1234)):
            data = receipt()
            data[key] = value
            with self.subTest(key=key), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)
        for section in ("keychain", "preferences"):
            data = receipt()
            data[section][0]["unexpected"] = True
            with self.subTest(section=section), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)

    def test_duplicate_fields_malformed_trailing_and_oversized_output_are_refused(self):
        raw = json.dumps(receipt())
        values = [raw.replace('"namespace":', '"namespace":"duplicate","namespace":', 1),
                  raw.replace('"before_status":', '"before_status":0,"before_status":', 1),
                  raw + raw, raw + "\nSDK failure", "", "{", " " * 16_385 + raw]
        for text in values:
            with self.subTest(text=text[:32]), self.assertRaises(NATIVE.IosCleanupError):
                NATIVE._validate_receipt((text,), namespace=NAMESPACE, udid=UDID,
                    owner_nonce=NONCE, application_identifier=APP_ID, mode="delete")

    def test_receipt_arrays_and_required_observations_cannot_be_missing(self):
        for key in ("identity", "keychain", "preferences", "notifications"):
            data = receipt()
            data[key] = None
            with self.subTest(key=key), self.assertRaises(NATIVE.IosCleanupError):
                validate(data)
        data = receipt()
        data["preferences"].pop()
        with self.assertRaises(NATIVE.IosCleanupError):
            validate(data)


if __name__ == "__main__":
    unittest.main()
