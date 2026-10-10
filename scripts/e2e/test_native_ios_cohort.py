"""Portable Simulator cohort capture models; no app, signature or device I/O."""

from __future__ import annotations

import dataclasses
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
    import native_ios_cohort as COHORT
finally:
    sys.path.pop(0)


def executable(*, cpu=0x0100000C, platform=7):
    """A thin Mach-O header: one empty __TEXT segment and one build version."""
    data = bytearray(128)
    struct.pack_into("<8I", data, 0, 0xFEEDFACF, cpu, 0, 2, 2, 96, 0, 0)
    struct.pack_into("<2I", data, 32, 0x19, 72)
    data[40:56] = b"__TEXT".ljust(16, b"\0")
    struct.pack_into("<6I", data, 104, 0x32, 24, platform, 0, 0, 0)
    return bytes(data)


class SimulatorCohortTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-ios-capture-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cohort = self.make_app("Runner.app")
        self.calls = []
        self.on_verify = None
        self.signature_code = 0
        for target, name, value in ((COHORT, "_HOST_PLATFORM", "darwin"),
                                    (COHORT.subprocess, "run", self.codesign)):
            context = patch.object(target, name, value)
            context.start()
            self.addCleanup(context.stop)

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

    def codesign(self, command, **kwargs):
        self.assertEqual(command, ["/usr/bin/codesign", "--verify", "--strict", "--deep", str(self.cohort)])
        self.assertEqual(kwargs, {"capture_output": True, "timeout": 15, "check": False})
        self.calls.append(command)
        if self.on_verify:
            self.on_verify(Path(command[-1]))
        return subprocess.CompletedProcess(command, self.signature_code, b"", b"")

    def capture(self):
        return COHORT.capture_ios_cohort(self.cohort)

    def rewrite_info(self, path, **updates):
        file = path / "Info.plist"
        value = plistlib.loads(file.read_bytes())
        file.write_bytes(plistlib.dumps({**value, **updates}))

    def test_capture_runs_one_signature_check_and_needs_no_build_marker(self):
        # Only standard bundle keys; no E2E build-profile marker is stamped.
        self.assertEqual(set(plistlib.loads((self.cohort / "Info.plist").read_bytes())),
                         {"CFBundleIdentifier", "CFBundleExecutable", "CFBundleSupportedPlatforms"})
        captured = self.capture()
        self.assertEqual(captured.path, self.cohort)
        self.assertEqual(captured.architecture, "arm64")
        self.assertEqual(len(self.calls), 1)
        captured.verify_unchanged()
        captured.verify_unchanged()
        self.assertEqual(len(self.calls), 1)  # Continuity checks never rerun codesign.
        for name in ("team", "application_identifier", "storage_cleanup_completed"):
            self.assertFalse(hasattr(captured, name))

    def test_x86_64_cohort_reports_its_architecture(self):
        (self.cohort / "Runner").write_bytes(executable(cpu=0x01000007))
        self.assertEqual(self.capture().architecture, "x86_64")

    def test_device_platform_and_non_mach_o_executables_are_refused(self):
        for data in (executable(platform=2), executable(platform=1), b"not a Mach-O"):
            with self.subTest(data=data[:32]):
                (self.cohort / "Runner").write_bytes(data)
                with self.assertRaises(COHORT.IosCohortError):
                    self.capture()
        self.assertEqual(self.calls, [])

    def test_only_the_actual_runner_simulator_bundle_is_a_cohort(self):
        for updates in ({"CFBundleIdentifier": "com.keplr.vizor.other"},
                        {"CFBundleSupportedPlatforms": ["iPhoneOS"]},
                        {"CFBundleExecutable": "vizor-ios-cleanup"},
                        {"CFBundleExecutable": None}):
            with self.subTest(updates=updates):
                original = (self.cohort / "Info.plist").read_bytes()
                value = {**plistlib.loads(original), **updates}
                (self.cohort / "Info.plist").write_bytes(plistlib.dumps(
                    {key: item for key, item in value.items() if item is not None}))
                with self.assertRaisesRegex(COHORT.IosCohortError, "bundle identity mismatch"):
                    self.capture()
                (self.cohort / "Info.plist").write_bytes(original)
        self.assertEqual(self.calls, [])
        self.capture()

    def test_failed_or_unavailable_signature_verification_is_refused(self):
        self.signature_code = 1
        with self.assertRaisesRegex(COHORT.IosCohortError, "signature verification failed"):
            self.capture()
        self.signature_code = 0
        for error in (subprocess.TimeoutExpired(["/usr/bin/codesign"], 15), OSError("codesign unavailable")):
            with self.subTest(error=type(error).__name__), \
                 patch.object(COHORT.subprocess, "run", side_effect=error):
                with self.assertRaisesRegex(COHORT.IosCohortError, "cannot verify"):
                    self.capture()

    def test_files_cannot_change_during_signature_verification(self):
        self.on_verify = lambda app: self.rewrite_info(app, unrelated="changed")
        with self.assertRaisesRegex(COHORT.IosCohortError, "changed during capture"):
            self.capture()

    def test_parsed_info_must_be_the_same_snapshot_as_captured_info(self):
        reader = COHORT._regular_bytes
        changed = False

        def read(path, limit):
            nonlocal changed
            result = reader(path, limit)
            if path == self.cohort / "Info.plist" and not changed:
                changed = True
                self.rewrite_info(self.cohort, CFBundleExecutable="Changed")
            return result

        with patch.object(COHORT, "_regular_bytes", side_effect=read):
            with self.assertRaisesRegex(COHORT.IosCohortError, "changed during capture"):
                self.capture()

    def test_directory_permissions_cannot_change_during_signature_verification(self):
        self.on_verify = lambda app: app.chmod(0o777)
        with self.assertRaises(COHORT.IosCohortError):
            self.capture()

    def test_original_inode_and_digest_are_both_required(self):
        captured = self.capture()
        file = self.cohort / "Info.plist"
        contents = file.read_bytes()
        replacement = self.cohort / "replacement.plist"
        replacement.write_bytes(contents)
        replacement.replace(file)
        with self.assertRaisesRegex(COHORT.IosCohortError, "identity changed"):
            captured.verify_unchanged()
        captured = self.capture()
        self.rewrite_info(self.cohort, unrelated="new value")
        with self.assertRaisesRegex(COHORT.IosCohortError, "identity changed"):
            captured.verify_unchanged()
        captured = self.capture()
        (self.cohort / "Runner").write_bytes(executable(cpu=0x01000007))
        with self.assertRaisesRegex(COHORT.IosCohortError, "identity changed"):
            captured.verify_unchanged()
        self.assertEqual(len(self.calls), 3)  # One per capture, none per verification.

    def test_symlink_hardlink_and_group_writable_files_are_refused(self):
        file = self.cohort / "Info.plist"
        file.chmod(0o666)
        with self.assertRaises(COHORT.IosCohortError):
            self.capture()
        file.chmod(0o600)
        os.link(file, self.root / "info-hardlink")
        with self.assertRaises(COHORT.IosCohortError):
            self.capture()
        (self.root / "info-hardlink").unlink()
        alias = self.root / "Alias.app"
        alias.symlink_to(self.cohort, target_is_directory=True)
        with self.assertRaises(COHORT.IosCohortError):
            COHORT.capture_ios_cohort(alias)
        with self.assertRaises(COHORT.IosCohortError):
            COHORT.capture_ios_cohort(Path("Runner.app"))
        self.assertEqual(self.calls, [])

    def test_foreign_capture_token_and_unsupported_host_are_refused(self):
        captured = self.capture()
        with self.assertRaises(COHORT.IosCohortError):
            dataclasses.replace(captured, _capture_token=object()).verify_unchanged()
        with patch.object(COHORT, "_HOST_PLATFORM", "linux"):
            with self.assertRaises(COHORT.IosCohortError):
                self.capture()

    def test_malformed_header_and_load_commands_are_refused(self):
        self.assertEqual(COHORT._simulator_architecture(executable()), "arm64")
        for size in (0, 1, 31, 32, 100, 127):
            with self.subTest(size=size), self.assertRaises(COHORT.IosCohortError):
                COHORT._simulator_architecture(executable()[:size])
        # Magic, CPU, file type, command count/size, segment length, build
        # version command/length and its platform.
        for offset in (0, 4, 12, 16, 20, 36, 104, 108, 112):
            value = bytearray(executable())
            struct.pack_into("<I", value, offset, 0xFFFFFFFF)
            with self.subTest(offset=offset), self.assertRaises(COHORT.IosCohortError):
                COHORT._simulator_architecture(bytes(value))
        value = bytearray(executable())
        struct.pack_into("<I", value, 16, 1)  # Fewer commands than their declared size.
        with self.assertRaises(COHORT.IosCohortError):
            COHORT._simulator_architecture(bytes(value))

    def test_duplicate_platform_commands_are_refused(self):
        value = bytearray(executable())
        struct.pack_into("<2I", value, 32, 0x32, 72)  # A second, larger build version.
        struct.pack_into("<I", value, 40, 7)
        with self.assertRaisesRegex(COHORT.IosCohortError, "ambiguous"):
            COHORT._simulator_architecture(bytes(value))


if __name__ == "__main__":
    unittest.main()
