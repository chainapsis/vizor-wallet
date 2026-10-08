"""Offline source-pin checks with disposable Git objects, not wallet scenarios."""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import zakura_fixture_source as SOURCE
finally:
    sys.path.pop(0)

PUBLISHED_COMMIT = SOURCE.SOURCE_COMMIT


def fixture_code() -> bytes:
    lines = ["from __future__ import annotations", "from dataclasses import dataclass",
             f"ZAKURA_IMAGE = {SOURCE.ZAKURA_IMAGE!r}",
             f"LIGHTWALLETD_IMAGE = {SOURCE.LIGHTWALLETD_IMAGE!r}",
             "@dataclass", "class RegtestFixture:", "    marker: str = 'verified-blob'"]
    lines.extend(f"    def {method}(self): pass" for method in SOURCE._REQUIRED_METHODS)
    return ("\n".join(lines) + "\n").encode()


class ZakuraFixtureSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "--quiet")
        self.path = self.root / SOURCE.SOURCE_PATH
        self.path.parent.mkdir()
        self.code = fixture_code()
        self.commit = self.commit_code(self.code)
        self.pin(self.commit, self.code)
        self.modules_before = set(sys.modules)
        self.addCleanup(self.clear_modules)

    def clear_modules(self):
        for name in set(sys.modules) - self.modules_before:
            if name.startswith("_vizor_zakura_fixture_"):
                sys.modules.pop(name, None)

    def git(self, *arguments):
        return subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
            "-c", "user.name=E2E Source Test", "-c", "user.email=e2e-source@example.invalid",
            "-C", str(self.root), *arguments], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def commit_code(self, code):
        self.path.write_bytes(code)
        self.git("add", SOURCE.SOURCE_PATH)
        self.git("commit", "--quiet", "-m", "fixture source test")
        return self.git("rev-parse", "HEAD").decode().strip()

    def pin(self, commit, code):
        changes = patch.multiple(SOURCE, SOURCE_COMMIT=commit, SOURCE_SIZE=len(code),
                                 SOURCE_SHA256=hashlib.sha256(code).hexdigest())
        changes.start()
        self.addCleanup(changes.stop)

    def test_loads_verified_blob_with_registered_dataclass_module_and_identity(self):
        loaded = SOURCE.load_zakura_fixture_source(self.root)
        self.assertEqual(loaded.fixture_class().marker, "verified-blob")
        self.assertIs(sys.modules[loaded.fixture_class.__module__].RegtestFixture, loaded.fixture_class)
        self.assertEqual(loaded.identity(), {"repository": SOURCE.SOURCE_REPOSITORY, "commit": self.commit,
            "path": SOURCE.SOURCE_PATH, "sha256": hashlib.sha256(self.code).hexdigest(), "size": len(self.code),
            "publication": "contributor-fork-not-official-release"})

    def test_dirty_checkout_script_is_not_executed_or_rewritten(self):
        dirty = b"raise AssertionError('never execute checkout code')\n"
        self.path.write_bytes(dirty)
        status = self.git("status", "--porcelain")
        loaded = SOURCE.load_zakura_fixture_source(self.root)
        self.assertEqual(loaded.fixture_class().marker, "verified-blob")
        self.assertEqual(self.path.read_bytes(), dirty)
        self.assertEqual(self.git("status", "--porcelain"), status)

    def test_another_head_does_not_retarget_the_pinned_blob(self):
        other = self.commit_code(b"raise AssertionError('different HEAD')\n")
        self.assertNotEqual(other, self.commit)
        self.assertEqual(SOURCE.load_zakura_fixture_source(self.root).commit, self.commit)
        self.assertEqual(self.git("rev-parse", "HEAD").decode().strip(), other)

    def test_git_replace_objects_cannot_retarget_the_pinned_commit(self):
        other = self.commit_code(b"raise AssertionError('replacement commit')\n")
        self.git("replace", self.commit, other)
        self.assertNotEqual(self.git("cat-file", "blob", f"{self.commit}:{SOURCE.SOURCE_PATH}"), self.code)
        self.assertEqual(SOURCE.load_zakura_fixture_source(self.root).fixture_class().marker, "verified-blob")

    def test_same_pin_does_not_reuse_or_replace_previous_owner_module(self):
        first = SOURCE.load_zakura_fixture_source(self.root)
        second = SOURCE.load_zakura_fixture_source(self.root)
        self.assertIsNot(first.fixture_class, second.fixture_class)
        self.assertEqual(first.identity(), second.identity())
        self.assertIs(sys.modules[first.fixture_class.__module__].RegtestFixture, first.fixture_class)

    def test_documented_fetch_keeps_the_cached_commit_reachable_after_gc(self):
        readme = (Path(__file__).parent / "README.md").read_text()
        example = re.search(r"git -C /path/to/zakura fetch https://github\.com/piatoss3612/zakura\.git (\S+)", readme)
        self.assertIsNotNone(example)
        refspec = example.group(1)
        self.assertEqual(refspec, f"{PUBLISHED_COMMIT}:refs/vizor-e2e/zakura-fixture/{PUBLISHED_COMMIT}")
        cache = self.root / "isolated-object-cache"
        cache.mkdir()
        self.git("-C", str(cache), "init", "--quiet")
        # This is a local disposable test remote, not the developer's checkout.
        self.git("-C", str(cache), "fetch", "--quiet", str(self.root), refspec.replace(PUBLISHED_COMMIT, self.commit))
        self.git("-C", str(cache), "reflog", "expire", "--expire=now", "--all")
        self.git("-C", str(cache), "gc", "--prune=now")
        self.assertEqual(SOURCE.load_zakura_fixture_source(cache).fixture_class().marker, "verified-blob")

    def test_size_mismatch_stops_before_blob_capture_or_code_execution(self):
        with patch.object(SOURCE, "_git_bytes", side_effect=[b"commit\n", b"99999999\n"]) as git:
            with self.assertRaisesRegex(SOURCE.RunnerError, "size"):
                SOURCE.load_zakura_fixture_source(self.root)
        self.assertEqual(git.call_count, 2)

    def test_commit_type_must_match_before_blob_access(self):
        with patch.object(SOURCE, "_git_bytes", return_value=b"blob\n") as git:
            with self.assertRaisesRegex(SOURCE.RunnerError, "not a Git commit"):
                SOURCE.load_zakura_fixture_source(self.root)
        git.assert_called_once()

    def test_wrong_hash_or_changed_capture_cannot_execute_python(self):
        for captured in (b"raise AssertionError('unverified code')\n", self.code[:-1]):
            with self.subTest(captured=captured[:20]), patch.object(SOURCE, "_git_bytes",
                side_effect=[b"commit\n", f"{len(self.code)}\n".encode(), captured]):
                with self.assertRaisesRegex(SOURCE.RunnerError, "SHA-256"):
                    SOURCE.load_zakura_fixture_source(self.root)
        with patch.object(SOURCE, "SOURCE_SHA256", "0" * 64):
            with self.assertRaisesRegex(SOURCE.RunnerError, "SHA-256"):
                SOURCE.load_zakura_fixture_source(self.root)

    def test_captured_blob_not_second_path_read_is_executed(self):
        original = SOURCE._git_bytes
        def read(root, *arguments):
            data = original(root, *arguments)
            if arguments[:2] == ("cat-file", "blob"):
                self.path.write_bytes(b"raise AssertionError('file changed after capture')\n")
            return data
        with patch.object(SOURCE, "_git_bytes", side_effect=read):
            self.assertEqual(SOURCE.load_zakura_fixture_source(self.root).fixture_class().marker, "verified-blob")

    def test_failed_import_removes_only_its_own_module(self):
        bad = b"raise RuntimeError('verified but broken fixture')\n"
        self.pin(self.commit_code(bad), bad)
        before = set(sys.modules)
        with self.assertRaisesRegex(SOURCE.RunnerError, "could not import"):
            SOURCE.load_zakura_fixture_source(self.root)
        self.assertEqual({name for name in set(sys.modules) - before if name.startswith("_vizor_zakura_fixture_")}, set())

    def test_missing_api_or_changed_image_is_not_an_accepted_source(self):
        for bad in (self.code.replace(b"def retain", b"def missing_retain"),
                    self.code.replace(SOURCE.ZAKURA_IMAGE.encode(), b"unpinned/node:latest")):
            with self.subTest(bad=bad[-80:]):
                self.pin(self.commit_code(bad), bad)
                with self.assertRaisesRegex(SOURCE.RunnerError, "required API/images"):
                    SOURCE.load_zakura_fixture_source(self.root)

    def test_missing_directory_or_git_commit_is_not_fetched_automatically(self):
        with self.assertRaisesRegex(SOURCE.RunnerError, "existing directory"):
            SOURCE.load_zakura_fixture_source(self.root / "absent")
        with patch.object(SOURCE, "SOURCE_COMMIT", "0" * 40):
            with self.assertRaisesRegex(SOURCE.RunnerError, "fetch its exact commit"):
                SOURCE.load_zakura_fixture_source(self.root)

    def test_git_timeout_or_failure_does_not_disclose_transport_diagnostics(self):
        for error in (OSError("credential secret"), subprocess.TimeoutExpired(["git"], 15)):
            with self.subTest(error=error), patch.object(SOURCE.subprocess, "run", side_effect=error):
                with self.assertRaisesRegex(SOURCE.RunnerError, "could not read") as raised:
                    SOURCE.load_zakura_fixture_source(self.root)
                self.assertNotIn("credential secret", str(raised.exception))
        with patch.object(SOURCE.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"credential secret")):
            with self.assertRaises(SOURCE.RunnerError) as raised:
                SOURCE.load_zakura_fixture_source(self.root)
            self.assertNotIn("credential secret", str(raised.exception))

    def test_git_reads_disable_replacement_and_all_transports_without_new_options(self):
        with patch.object(SOURCE.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"blob", b"")) as run:
            self.assertEqual(SOURCE._git_bytes(self.root, "cat-file", "-t", self.commit), b"blob")
        command = run.call_args.args[0]
        self.assertIn("--no-replace-objects", command)
        self.assertNotIn("--no-lazy-fetch", command)
        self.assertEqual(run.call_args.kwargs["env"]["GIT_ALLOW_PROTOCOL"], "")
        self.assertEqual(run.call_args.kwargs["timeout"], 15)

    def test_partial_cache_does_not_download_missing_promisor_blob(self):
        self.git("config", "uploadpack.allowFilter", "true")
        cache = self.root / "filtered-object-cache.git"
        self.git("clone", "--quiet", "--bare", "--no-local", "--filter=blob:none", str(self.root), str(cache))
        self.git("-C", str(cache), "config", "protocol.file.allow", "always")
        blob = self.git("rev-parse", f"{self.commit}:{SOURCE.SOURCE_PATH}").strip()
        def local_objects():
            return self.git("-C", str(cache), "cat-file", "--batch-all-objects", "--batch-check=%(objectname)").splitlines()
        before = local_objects()
        self.assertNotIn(blob, before)
        with self.assertRaisesRegex(SOURCE.RunnerError, "fetch its exact commit"):
            SOURCE.load_zakura_fixture_source(cache)
        self.assertEqual(local_objects(), before)


if __name__ == "__main__":
    unittest.main()
