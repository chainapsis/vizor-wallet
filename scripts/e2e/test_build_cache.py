"""Build cache pruning on a modeled cache directory."""
from __future__ import annotations

import contextlib
import fcntl
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import build_cache as CACHE
finally:
    sys.path.pop(0)

_CLI = importlib.util.spec_from_file_location("prune_build_cache", Path(__file__).resolve().parent / "prune-build-cache.py")
CLI = importlib.util.module_from_spec(_CLI)
_CLI.loader.exec_module(CLI)


class BuildCacheTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="vizor-build-cache-test-")
        self.addCleanup(directory.cleanup)
        self.cache = Path(directory.name) / "build-cache"
        self.kind = self.cache / "funder-v1"
        self.kind.mkdir(parents=True)
        self.keys = [f"{index:064x}" for index in (1, 2, 3)]
        for age, key in enumerate(reversed(self.keys)):
            self.publish(key, mtime=1_700_000_000 - age * 60)
        self.leftover = self.kind / ".pruned-0123456789ab-89abcdef"
        self.leftover.mkdir()
        (self.leftover / "regtest_direct_funder").write_bytes(b"0" * 1024)
        (self.kind / ".pending-staging").mkdir()
        (self.kind / ("f" * 64)).symlink_to(self.kind / self.keys[0])
        self.output = []
        self.addCleanup(self.writable)

    def publish(self, key, *, mtime):
        entry = self.kind / key
        entry.mkdir()
        (entry / "regtest_direct_funder").write_bytes(b"0" * 2**20)
        (entry / "manifest.json").write_text("{}")
        for path in entry.iterdir():
            path.chmod(0o400)
        entry.chmod(0o500)
        (self.kind / (key + ".lock")).touch()
        os.utime(entry, (mtime, mtime))

    def writable(self):
        for directory, _, _ in os.walk(self.cache):
            os.chmod(directory, 0o700)

    def entries(self):
        return sorted(path.name for path in self.kind.iterdir())

    def test_the_two_newest_publications_stay(self):
        actions = {name: action for _, name, _, action in CACHE.plan(self.cache)}
        self.assertEqual(actions, {self.keys[2]: "keep", self.keys[1]: "keep", self.keys[0]: "delete",
                                   self.leftover.name: "delete"})

    def test_a_dry_run_changes_nothing(self):
        before = self.entries()
        self.assertEqual(CACHE.prune(self.cache, out=self.output.append), 0)
        self.assertEqual(self.entries(), before)
        self.assertIn("1 MiB would be removed", self.output[-1])

    def test_apply_removes_old_read_only_publications_and_leftovers(self):
        self.assertEqual(CACHE.prune(self.cache, apply=True, out=self.output.append), 0)
        remaining = self.entries()
        self.assertIn(self.keys[1], remaining)
        self.assertIn(self.keys[2], remaining)
        self.assertNotIn(self.keys[0], remaining)
        self.assertNotIn(self.leftover.name, remaining)
        self.assertIn(".pending-staging", remaining)
        self.assertTrue((self.kind / ("f" * 64)).is_symlink())

    def test_a_publication_a_run_holds_is_skipped(self):
        lock = os.open(self.kind / (self.keys[0] + ".lock"), os.O_RDWR)
        self.addCleanup(os.close, lock)
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        self.assertEqual(CACHE.prune(self.cache, apply=True, out=self.output.append), 0)
        self.assertIn(self.keys[0], self.entries())
        self.assertTrue(any("a run is using it" in line for line in self.output))

    def test_a_missing_cache_has_nothing_to_prune(self):
        self.assertEqual(CACHE.prune(self.cache / "absent", out=self.output.append), 0)
        self.assertIn("nothing to prune", self.output[0])

    def test_keep_must_be_positive(self):
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            CLI.main(["--keep", "0"])


if __name__ == "__main__":
    unittest.main()
