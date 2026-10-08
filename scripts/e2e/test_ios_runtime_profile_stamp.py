#!/usr/bin/env python3

import base64
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional


SCRIPT = Path(__file__).with_name("stamp-ios-runtime-profile.swift")
PLIST_KEY = "VizorE2eIosCohort"


def encode_defines(*definitions: str) -> str:
    return ",".join(
        base64.b64encode(value.encode("utf-8")).decode("ascii")
        for value in definitions
    )


class IosRuntimeProfileStampTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._build_dir = tempfile.TemporaryDirectory(
            prefix="vizor-ios-runtime-profile-stamp-"
        )
        cls.binary = Path(cls._build_dir.name) / "stamp-ios-runtime-profile"
        subprocess.run(
            [
                "/usr/bin/xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                str(SCRIPT),
                "-o",
                str(cls.binary),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls._build_dir.cleanup()

    def setUp(self) -> None:
        self._temp_dir = tempfile.TemporaryDirectory(
            prefix="vizor-ios-runtime-profile-plist-"
        )
        self.plist_path = Path(self._temp_dir.name) / "Info.plist"

    def tearDown(self) -> None:
        self._temp_dir.cleanup()

    def write_plist(self, value: dict, fmt: plistlib.PlistFormat) -> None:
        with self.plist_path.open("wb") as stream:
            plistlib.dump(value, stream, fmt=fmt, sort_keys=False)

    def read_plist(self) -> dict:
        with self.plist_path.open("rb") as stream:
            return plistlib.load(stream)

    def run_stamp(
        self, dart_defines: Optional[str], *, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.pop("DART_DEFINES", None)
        if dart_defines is not None:
            environment["DART_DEFINES"] = dart_defines
        return subprocess.run(
            [str(self.binary), str(self.plist_path)],
            env=environment,
            check=check,
            capture_output=True,
            text=True,
        )

    def test_missing_defines_stamps_false(self) -> None:
        self.write_plist({"CFBundleIdentifier": "com.keplr.vizor"}, plistlib.FMT_XML)

        self.run_stamp(None)

        self.assertIs(self.read_plist()[PLIST_KEY], False)

    def test_true_and_false_values_are_derived_from_dart_defines(self) -> None:
        for value, expected in (("true", True), ("false", False)):
            with self.subTest(value=value):
                self.write_plist({}, plistlib.FMT_XML)
                self.run_stamp(encode_defines(f"VIZOR_E2E_IOS_COHORT={value}"))
                self.assertIs(self.read_plist()[PLIST_KEY], expected)

    def test_repeated_build_clears_a_stale_true_marker(self) -> None:
        self.write_plist({}, plistlib.FMT_XML)
        self.run_stamp(encode_defines("VIZOR_E2E_IOS_COHORT=true"))
        self.assertIs(self.read_plist()[PLIST_KEY], True)

        self.run_stamp(encode_defines("VIZOR_E2E_IOS_COHORT=false"))

        self.assertIs(self.read_plist()[PLIST_KEY], False)

    def test_preserves_xml_and_binary_formats_and_unrelated_values(self) -> None:
        original = {
            "CFBundleIdentifier": "com.keplr.vizor",
            "UnicodeValue": "지갑 🔐",
            "Nested": {"Enabled": True, "Count": 7},
        }
        for fmt, prefix in ((plistlib.FMT_XML, b"<?xml"), (plistlib.FMT_BINARY, b"bplist00")):
            with self.subTest(format=fmt):
                self.write_plist(original, fmt)
                self.run_stamp(
                    encode_defines(
                        "UNRELATED=안녕🙂",
                        "VIZOR_E2E_IOS_COHORT=true",
                    )
                )
                self.assertTrue(self.plist_path.read_bytes().startswith(prefix))
                self.assertEqual(
                    self.read_plist(), {**original, PLIST_KEY: True}
                )

    def assert_failure_is_atomic(self, dart_defines: str) -> None:
        self.write_plist(
            {"CFBundleIdentifier": "com.keplr.vizor", PLIST_KEY: True},
            plistlib.FMT_BINARY,
        )
        before = self.plist_path.read_bytes()

        result = self.run_stamp(dart_defines, check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.plist_path.read_bytes(), before)

    def test_malformed_base64_fails_before_modifying_plist(self) -> None:
        self.assert_failure_is_atomic("not%base64")

    def test_malformed_cohort_value_fails_before_modifying_plist(self) -> None:
        self.assert_failure_is_atomic(
            encode_defines("VIZOR_E2E_IOS_COHORT=yes")
        )
        self.assert_failure_is_atomic(encode_defines("VIZOR_E2E_IOS_COHORT"))

    def test_duplicate_cohort_definitions_are_rejected_atomically(self) -> None:
        self.assert_failure_is_atomic(
            encode_defines(
                "VIZOR_E2E_IOS_COHORT=true",
                "VIZOR_E2E_IOS_COHORT=false",
            )
        )
        self.assert_failure_is_atomic(
            encode_defines(
                "VIZOR_E2E_IOS_COHORT=true",
                "VIZOR_E2E_IOS_COHORT=true",
            )
        )


if __name__ == "__main__":
    unittest.main()
