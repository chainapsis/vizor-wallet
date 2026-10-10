"""Offline checks for the vendored Zakura fixture pin, not wallet scenarios."""

from __future__ import annotations

import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import zakura_fixture_source as SOURCE
    from e2e_runtime import RunnerError
finally:
    sys.path.pop(0)


def fixture_code(marker: str = "verified-bytes") -> bytes:
    lines = ["from __future__ import annotations", "from dataclasses import dataclass",
             f"ZAKURA_IMAGE = {SOURCE.ZAKURA_IMAGE!r}",
             f"LIGHTWALLETD_IMAGE = {SOURCE.LIGHTWALLETD_IMAGE!r}",
             "@dataclass", "class RegtestFixture:", f"    marker: str = {marker!r}"]
    lines.extend(f"    def {method}(self): pass" for method in SOURCE._REQUIRED_METHODS)
    return ("\n".join(lines) + "\n").encode()


class ZakuraFixtureSourceTests(unittest.TestCase):
    def setUp(self):
        self.modules_before = set(sys.modules)
        self.addCleanup(self.clear_modules)

    def clear_modules(self):
        for name in self.new_fixture_modules():
            sys.modules.pop(name, None)

    def new_fixture_modules(self):
        return {name for name in set(sys.modules) - self.modules_before
                if name.startswith("_vizor_zakura_fixture_")}

    def pin(self, code: bytes) -> Path:
        """Point the loader at a temporary helper pinned to exactly these bytes."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "regtest_fixture.py"
        path.write_bytes(code)
        changes = patch.multiple(SOURCE, SOURCE_PATH=path, SOURCE_SIZE=len(code),
                                 SOURCE_SHA256=hashlib.sha256(code).hexdigest())
        changes.start()
        self.addCleanup(changes.stop)
        return path

    def test_vendored_helper_matches_its_pin(self):
        captured = SOURCE.SOURCE_PATH.read_bytes()
        self.assertEqual(len(captured), SOURCE.SOURCE_SIZE)
        self.assertEqual(hashlib.sha256(captured).hexdigest(), SOURCE.SOURCE_SHA256)
        self.assertEqual(SOURCE.SOURCE_PATH.relative_to(Path(__file__).resolve().parents[2]).as_posix(),
                         SOURCE.VENDORED_PATH)

    def test_loads_the_actual_vendored_helper(self):
        loaded = SOURCE.load_zakura_fixture_source()
        for method in SOURCE._REQUIRED_METHODS:
            self.assertTrue(callable(getattr(loaded.fixture_class, method)))
        self.assertEqual(loaded.identity(), {
            "repository": SOURCE.ORIGIN_REPOSITORY, "commit": SOURCE.ORIGIN_COMMIT,
            "path": SOURCE.ORIGIN_PATH, "vendored_path": SOURCE.VENDORED_PATH,
            "sha256": SOURCE.SOURCE_SHA256, "size": SOURCE.SOURCE_SIZE,
            "publication": "vendored-from-contributor-fork"})

    def test_each_load_executes_in_its_own_module(self):
        self.pin(fixture_code())
        first = SOURCE.load_zakura_fixture_source().fixture_class
        second = SOURCE.load_zakura_fixture_source().fixture_class
        self.assertIsNot(first, second)
        self.assertNotEqual(first.__module__, second.__module__)
        self.assertIs(sys.modules[first.__module__].RegtestFixture, first)
        self.assertEqual(first().marker, "verified-bytes")

    def test_changed_bytes_are_rejected_before_execution(self):
        path = self.pin(fixture_code())
        path.write_bytes(fixture_code("changed") + b"raise SystemExit('must not run')\n")
        with self.assertRaisesRegex(RunnerError, "SHA-256"):
            SOURCE.load_zakura_fixture_source()
        self.assertEqual(self.new_fixture_modules(), set())

    def test_missing_helper_is_rejected(self):
        self.pin(fixture_code()).unlink()
        with self.assertRaisesRegex(RunnerError, "unavailable"):
            SOURCE.load_zakura_fixture_source()

    def test_missing_api_or_images_are_rejected_and_released(self):
        for code in (fixture_code().replace(b"    def close(self): pass\n", b""),
                     fixture_code().replace(SOURCE.ZAKURA_IMAGE.encode(), b"zakuracore/zakura:latest"),
                     fixture_code().replace(b"class RegtestFixture", b"class OtherFixture")):
            with self.subTest(code=hashlib.sha256(code).hexdigest()[:12]):
                self.pin(code)
                with self.assertRaisesRegex(RunnerError, "required API/images"):
                    SOURCE.load_zakura_fixture_source()
                self.assertEqual(self.new_fixture_modules(), set())

    def test_import_failure_is_wrapped_and_released(self):
        self.pin(b"raise ValueError('broken fixture')\n")
        with self.assertRaisesRegex(RunnerError, "could not import"):
            SOURCE.load_zakura_fixture_source()
        self.assertEqual(self.new_fixture_modules(), set())

    def test_interrupts_are_not_wrapped(self):
        self.pin(b"raise KeyboardInterrupt\n")
        with self.assertRaises(KeyboardInterrupt):
            SOURCE.load_zakura_fixture_source()
        self.assertEqual(self.new_fixture_modules(), set())


if __name__ == "__main__":
    unittest.main()
