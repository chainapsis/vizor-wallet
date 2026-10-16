"""Real files, descriptors and stat changes; only the 2 s racy window is shortened."""
import contextlib
import hashlib
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import content_memo as MEMO
import funder_build
import native_owned_tree as tree
import native_zakura_front
import toolchain_inputs

# Every whole-file capture that consults the memo, with the error its own checks raise.
CAPTURES = {
    "file_record": (toolchain_inputs.file_record, toolchain_inputs.ToolInputError),
    "_capture": (native_zakura_front._capture, native_zakura_front.NativeZakuraFrontError),
    "_file_record": (funder_build._file_record, funder_build.FunderBuildError),
}


class ContentMemoTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="content-memo-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.path = self.root/"input"
        self.path.write_bytes(b"original")

    @contextlib.contextmanager
    def scope(self):
        """A run scope that may store files written moments ago."""
        with patch.object(MEMO, "_RACY_NS", 0), MEMO.run_scope():
            yield

    def read(self, capture):
        """One capture's digest and how many times it opened the file's bytes."""
        with patch.object(os, "fdopen", wraps=os.fdopen) as opened:
            digest = capture(self.path)[1]
        return digest, opened.call_count

    def test_memo_is_off_outside_a_run_scope(self):
        with patch.object(MEMO, "_RACY_NS", 0):
            for name, (capture, _) in CAPTURES.items():
                with self.subTest(name):
                    self.assertEqual([self.read(capture)[1] for _ in range(2)], [1, 1])
        self.assertIsNone(MEMO._table)

    def test_unchanged_file_is_read_once_per_scope(self):
        digest = hashlib.sha256(b"original").hexdigest()
        for name, (capture, _) in CAPTURES.items():
            with self.subTest(name), self.scope():
                self.assertEqual([self.read(capture) for _ in range(2)], [(digest, 1), (digest, 0)])

    def test_captures_share_one_digest_per_file(self):
        with self.scope():
            self.assertEqual([self.read(capture)[1] for capture, _ in CAPTURES.values()], [1, 0, 0])

    def test_a_stored_digest_does_not_bypass_acceptance_checks(self):
        with self.scope():
            self.read(toolchain_inputs.file_record)  # Stores this file's digest.
            for capture, options, error in (
                    (toolchain_inputs.file_record, {"limit":4}, toolchain_inputs.ToolInputError),
                    (toolchain_inputs.file_record, {"executable":True}, toolchain_inputs.ToolInputError),
                    (funder_build._file_record, {"limit":4}, funder_build.FunderBuildError),
                    (funder_build._file_record, {"executable":True}, funder_build.FunderBuildError)):
                with self.subTest(capture=capture.__name__, **options), self.assertRaises(error):
                    capture(self.path, **options)
            self.assertEqual(len(MEMO._table), 1)  # Rejected before reading, so nothing new is stored.

    def test_hits_still_check_identity_after_the_skipped_read(self):
        lookup = MEMO.lookup
        def rewritten(details):
            self.path.write_bytes(b"changed!")  # In place, after the capture's pre-read fstat.
            return lookup(details)
        for name, (capture, error) in CAPTURES.items():
            with self.subTest(name), self.scope():
                self.read(capture)
                with patch.object(MEMO, "lookup", side_effect=rewritten), self.assertRaisesRegex(error, "changed"):
                    capture(self.path)

    def test_rewrites_restored_mtimes_and_same_stat_replacements_are_rehashed(self):
        def overwrite():
            self.path.write_bytes(b"changed!")
        def restore_mtime():
            details = self.path.stat()
            self.path.write_bytes(b"changed!")
            os.utime(self.path, ns=(details.st_atime_ns, details.st_mtime_ns))
            self.assertEqual(tree.identity(self.path.stat()), tree.identity(details))  # Only ctime moved.
        def rename_over():
            details = self.path.stat()
            other = self.root/"other"
            other.write_bytes(b"changed!")
            os.utime(other, ns=(details.st_atime_ns, details.st_mtime_ns))
            os.rename(other, self.path)
        changed = hashlib.sha256(b"changed!").hexdigest()
        for change in (overwrite, restore_mtime, rename_over):
            for name, (capture, _) in CAPTURES.items():
                with self.subTest(change=change.__name__, capture=name), self.scope():
                    self.path.write_bytes(b"original")
                    self.assertEqual(self.read(capture)[1], 1)
                    change()
                    self.assertEqual(self.read(capture), (changed, 1))

    def test_files_changed_within_the_racy_window_are_never_stored(self):
        for name, (capture, _) in CAPTURES.items():
            with self.subTest(name), MEMO.run_scope():
                self.path.write_bytes(b"original")
                self.assertEqual([self.read(capture)[1] for _ in range(2)], [1, 1])
                self.assertEqual(MEMO._table, {})
                details = self.path.stat()
                changed = max(details.st_mtime_ns, details.st_ctime_ns)
                for offset, entries in ((MEMO._RACY_NS - 1, 0), (MEMO._RACY_NS, 1)):
                    with patch.object(time, "time_ns", return_value=changed + offset):
                        capture(self.path)
                    self.assertEqual(len(MEMO._table), entries)

    def test_digest_is_not_stored_when_ctime_moves_during_the_read(self):
        fdopen = os.fdopen
        def touched(*args, **kwargs):
            details = self.path.stat()
            os.utime(self.path, ns=(details.st_atime_ns, details.st_mtime_ns))  # Identity stays; ctime moves.
            return fdopen(*args, **kwargs)
        for name, (capture, _) in CAPTURES.items():
            with self.subTest(name), self.scope():
                with patch.object(os, "fdopen", side_effect=touched):
                    capture(self.path)
                self.assertEqual(MEMO._table, {})

    def test_front_package_capture_with_chunks_neither_reuses_nor_stores(self):
        chunks = []
        def parsed(path):
            chunks.clear()
            return native_zakura_front._capture(path, chunks=chunks)
        with self.scope():
            self.assertEqual(self.read(parsed)[1], 1)
            self.assertEqual(MEMO._table, {})
            self.read(native_zakura_front._capture)
            self.assertEqual((self.read(parsed)[1], b"".join(chunks)), (1, b"original"))

    def test_full_table_is_cleared_rather_than_grown(self):
        other = self.root/"other"
        other.write_bytes(b"other")
        with self.scope(), patch.object(MEMO, "_MAX_ENTRIES", 1):
            self.read(toolchain_inputs.file_record)
            toolchain_inputs.file_record(other)
            self.assertEqual(len(MEMO._table), 1)
            self.assertEqual(self.read(toolchain_inputs.file_record)[1], 1)

    def test_nested_scope_is_an_error_and_every_scope_ends_with_its_block(self):
        with MEMO.run_scope():
            table = MEMO._table
            with self.assertRaisesRegex(RuntimeError, "already active"):
                with MEMO.run_scope():
                    self.fail("a nested scope was entered")
            self.assertIs(MEMO._table, table)
        self.assertIsNone(MEMO._table)
        with self.assertRaisesRegex(KeyError, "model failure"):
            with MEMO.run_scope():
                raise KeyError("model failure")
        self.assertIsNone(MEMO._table)


if __name__ == "__main__":
    unittest.main()
