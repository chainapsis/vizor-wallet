"""Real private trees; build-output removal models, no build or wallet runs."""
import contextlib
import os
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_owned_tree as TREE


class OwnedTreeTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="owned-tree-model-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.outside = self.root / "outside"
        self.outside.mkdir()
        (self.outside / "shared").write_text("preserve")

    def tree(self, name="tree"):
        path = self.root / name
        path.mkdir(mode=0o700)
        return path

    def producer(self, name="vizor_a1b2c3d4e5_w0_1"):
        builds = self.root / "run" / "builds"
        for path in (builds.parent, builds, builds / "e2e", builds / "e2e" / name):
            path.mkdir(mode=0o700, exist_ok=True)
        case = builds / "e2e" / name
        for marker in ("process-0000.log", "process-0001.log", "workspace-owner.json", "case-manifest.json"):
            (case / marker).write_text(marker)
        debug = case / "funder-build" / "target" / "debug"
        (debug / "deps").mkdir(parents=True)
        (debug / "deps" / "regtest_direct_funder-0a1b").write_bytes(b"f" * 4096)
        (debug / "examples").mkdir()
        os.link(debug / "deps" / "regtest_direct_funder-0a1b", debug / "examples" / "regtest_direct_funder")
        (case / "funder-build" / "source.tar").write_bytes(b"s" * 1024)
        (case / "voting-build" / "target" / "release").mkdir(parents=True)
        (case / "voting-build" / "target" / "release" / "nf-server").write_bytes(b"n" * 512)
        (case / "voting-build" / "build-proof.json").write_text("{}")
        fonts = case / "native-publication" / "cohort.app" / "Fonts"
        fonts.mkdir(parents=True)
        (fonts / "MaterialIcons.otf").write_bytes(b"m" * 256)
        (fonts / "MaterialIcons.otf").chmod(0o664)
        (fonts / "external").symlink_to(self.outside / "shared")
        return builds, case

    def test_default_mode_keeps_refusing_hard_links_and_group_writable_files(self):
        for name, prepare in (("hard", lambda path: os.link(self.outside / "shared", path / "link")),
                              ("writable", lambda path: ((path / "font").write_text("x"),
                                                         (path / "font").chmod(0o664)))):
            with self.subTest(name), contextlib.ExitStack() as stack:
                path = self.tree(name)
                prepare(path)
                with self.assertRaises(TREE.OwnedTreeError):
                    TREE.scan(TREE.open_directory(stack, path), allow_links=True)

    def test_build_output_unlinks_hard_links_and_writable_sdk_files_without_following(self):
        path = self.tree()
        (path / "deps").mkdir()
        (path / "deps" / "tool-0a1b").write_bytes(b"t" * 100)
        os.link(path / "deps" / "tool-0a1b", path / "tool")
        os.link(self.outside / "shared", path / "external-hard-link")
        (path / "font").write_bytes(b"f" * 10)
        (path / "font").chmod(0o664)
        (path / "link").symlink_to(self.outside, target_is_directory=True)
        with contextlib.ExitStack() as stack:
            descriptor = TREE.open_directory(stack, path)
            entries = TREE.scan(descriptor, allow_links=True, build_output=True)
            removed = []
            TREE.remove_output(descriptor, entries, lambda: None, removed=removed)
        self.assertEqual(os.listdir(path), [])
        self.assertEqual([name for name, _ in removed], ["deps", "external-hard-link", "font", "link", "tool"])
        # One hard-linked inode counts once; the external link counts its own name.
        self.assertEqual(TREE.output_bytes(entry for _, entry in removed), 100 + 8 + 10)
        self.assertEqual((self.outside / "shared").read_text(), "preserve")
        self.assertEqual((self.outside / "shared").stat().st_nlink, 1)

    def test_build_output_refuses_special_files_and_a_shared_root(self):
        for name, prepare in (("fifo", lambda path: os.mkfifo(path / "pipe")),
                              ("shared-root", lambda path: path.chmod(0o755))):
            with self.subTest(name), contextlib.ExitStack() as stack:
                path = self.tree(name)
                prepare(path)
                with self.assertRaises(TREE.OwnedTreeError):
                    TREE.scan(TREE.open_directory(stack, path), allow_links=True, build_output=True)

    def test_build_output_removes_writable_package_entries_below_a_private_root(self):
        path = self.tree()
        package = path / "SourcePackages" / "checkouts" / "hw-transport-ios-ble" / ".swiftpm"
        (package / "xcode").mkdir(parents=True)
        for directory in (package, package / "xcode"):
            directory.chmod(0o777)  # as Xcode leaves them
        (package / "xcode" / "settings").write_text("x")
        (package / "xcode" / "settings").chmod(0o666)
        with contextlib.ExitStack() as stack:
            descriptor = TREE.open_directory(stack, path, private=True)
            entries = TREE.scan(descriptor, allow_links=True, build_output=True)
            TREE.remove_output(descriptor, entries, lambda: None)
        self.assertEqual(os.listdir(path), [])
        default = self.tree("default")
        (default / "shared").mkdir()
        (default / "shared").chmod(0o777)
        with contextlib.ExitStack() as stack, self.assertRaises(TREE.OwnedTreeError):
            TREE.scan(TREE.open_directory(stack, default), allow_links=True)

    def test_producer_sweep_keeps_logs_markers_and_their_parents(self):
        builds, case = self.producer()
        record = TREE.prune_build_outputs(builds)
        self.assertEqual(record["errors"], [])
        prefix = "e2e/" + case.name + "/"
        self.assertEqual(record["removed"], [prefix + "funder-build", prefix + "native-publication",
                                             prefix + "voting-build/target"])
        self.assertEqual(record["bytes"], 4096 + 1024 + 256 + 512)
        self.assertEqual(sorted(item.relative_to(case).as_posix() for item in case.rglob("*")), [
            "case-manifest.json", "process-0000.log", "process-0001.log", "voting-build",
            "voting-build/build-proof.json", "workspace-owner.json"])
        self.assertEqual((self.outside / "shared").read_text(), "preserve")
        self.assertEqual(TREE.prune_build_outputs(builds), {"removed": [], "bytes": 0, "errors": []})

    def test_producer_sweep_removes_xcode_package_directories(self):
        builds, case = self.producer()
        package = case / "ios-build" / "SourcePackages" / "checkouts" / "pkg" / ".swiftpm"
        (package / "xcode").mkdir(parents=True)
        for directory in (package, package / "xcode"):
            directory.chmod(0o777)
        record = TREE.prune_build_outputs(builds)
        self.assertEqual(record["errors"], [])
        self.assertIn("e2e/" + case.name + "/ios-build", record["removed"])
        self.assertFalse((case / "ios-build").exists())

    def voting_case(self):
        case = self.tree("vizor_a1b2c3d4e5_w0_7")
        voting = case / "voting"
        (voting / "pir-data" / "tier1").mkdir(parents=True)
        (voting / "pir-data" / "tier1" / "rows.bin").write_bytes(b"p" * 4096)
        (voting / "pir-data" / "nullifiers.bin").write_bytes(b"n" * 1024)
        (voting / "vote-home" / "data").mkdir(parents=True)
        (voting / "vote-home" / "data" / "state.db").write_bytes(b"s" * 2048)
        (voting / "logs").mkdir()
        (voting / "logs" / "vote-server.log").write_text("log")
        (voting / "ready.json").write_text("{}")
        return case

    def test_voting_prune_keeps_the_case_evidence(self):
        case = self.voting_case()
        record = TREE.prune_voting_data(case)
        self.assertEqual(record, {"removed": ["voting/pir-data", "voting/vote-home"],
                                  "bytes": 4096 + 1024 + 2048, "errors": []})
        self.assertEqual(sorted(path.name for path in (case / "voting").iterdir()), ["logs", "ready.json"])
        self.assertTrue((case / "voting" / "logs" / "vote-server.log").exists())

    def test_voting_prune_without_voting_data_removes_nothing(self):
        case = self.tree("vizor_a1b2c3d4e5_w0_8")
        (case / "process-0000.log").write_text("log")
        self.assertEqual(TREE.prune_voting_data(case), {"removed": [], "bytes": 0, "errors": []})
        self.assertTrue((case / "process-0000.log").exists())

    def test_voting_prune_records_an_unowned_entry_and_keeps_it(self):
        case = self.voting_case()
        os.link(case / "voting" / "ready.json", case / "voting" / "pir-data" / "linked")
        record = TREE.prune_voting_data(case)
        self.assertEqual(record["removed"], ["voting/vote-home"])
        self.assertEqual(len(record["errors"]), 1)
        self.assertTrue((case / "voting" / "pir-data" / "nullifiers.bin").exists())

    def test_symlinked_roots_are_refused_without_touching_targets(self):
        builds, case = self.producer()
        (case.parent / "vizor_a1b2c3d4e5_w0_2").symlink_to(self.outside, target_is_directory=True)
        record = TREE.prune_build_outputs(builds)
        self.assertEqual(len(record["errors"]), 1)
        self.assertTrue(record["errors"][0].startswith("vizor_a1b2c3d4e5_w0_2: "))
        self.assertEqual((self.outside / "shared").read_text(), "preserve")
        self.assertFalse((case / "funder-build").exists())
        replaced = builds.with_name("original-builds")
        builds.rename(replaced)
        builds.symlink_to(replaced, target_is_directory=True)
        (replaced / "e2e" / case.name / "kept-by-link").mkdir()
        record = TREE.prune_build_outputs(builds)
        self.assertEqual((record["removed"], record["bytes"], len(record["errors"])), ([], 0, 1))
        self.assertTrue((replaced / "e2e" / case.name / "kept-by-link").exists())

    def test_identity_change_aborts_removal_and_keeps_the_replacement(self):
        path = self.tree()
        for name in ("a", "b", "c"):
            (path / name).write_text(name)
        replaced = []
        def replace_sibling():
            if not replaced:
                (path / "b").unlink()
                (path / "b").write_text("replacement")
                replaced.append(True)
        removed = []
        with contextlib.ExitStack() as stack:
            descriptor = TREE.open_directory(stack, path)
            entries = TREE.scan(descriptor, build_output=True)
            with self.assertRaisesRegex(TREE.OwnedTreeError, "changed before removal"):
                TREE.remove_output(descriptor, entries, replace_sibling, removed=removed)
        self.assertEqual([name for name, _ in removed], ["a"])
        self.assertEqual((path / "b").read_text(), "replacement")
        self.assertEqual((path / "c").read_text(), "c")

    def test_replaced_builds_root_or_cancellation_removes_nothing(self):
        builds, case = self.producer()
        with contextlib.ExitStack() as stack:
            other = TREE.identity(os.fstat(TREE.open_directory(stack, self.outside)))
        record = TREE.prune_build_outputs(builds, expected=other)
        self.assertEqual((record["removed"], len(record["errors"])), ([], 1))
        cancel = threading.Event()
        cancel.set()
        record = TREE.prune_build_outputs(builds, cancel=cancel)
        self.assertEqual((record["removed"], len(record["errors"])), ([], 1))
        self.assertIn("cancelled", record["errors"][0])
        self.assertTrue((case / "funder-build" / "source.tar").exists())

    def test_a_directory_on_another_filesystem_stops_the_scan_before_any_removal(self):
        builds, case = self.producer()
        mounted = case / "funder-build"  # Stands in for a volume mounted inside the tree.
        (mounted / "sentinel").write_text("another volume")
        before = sorted(path.relative_to(case).as_posix() for path in case.rglob("*"))
        target = mounted.stat()
        def across_mount(real):
            def observe(*args, **kwargs):
                details = real(*args, **kwargs)
                if (details.st_dev, details.st_ino) != (target.st_dev, target.st_ino):
                    return details
                # stat and fstat of a mount point both show the mounted root, on its own device.
                return os.stat_result((*details[:2], details.st_dev + 1, *details[3:]))
            return observe
        with patch.object(TREE.os, "stat", side_effect=across_mount(os.stat)), \
             patch.object(TREE.os, "fstat", side_effect=across_mount(os.fstat)):
            with contextlib.ExitStack() as stack:
                with self.assertRaisesRegex(TREE.OwnedTreeError, "crosses a filesystem boundary"):
                    TREE.scan(TREE.open_directory(stack, case), allow_links=True, build_output=True)
                TREE.open_directory(stack, mounted)  # A caller's own anchor may be on any filesystem.
            record = TREE.prune_build_outputs(builds)
        self.assertEqual((record["removed"], record["bytes"]), ([], 0))
        self.assertEqual(record["errors"], [case.name + ": tree directory crosses a filesystem boundary"])
        self.assertEqual(sorted(path.relative_to(case).as_posix() for path in case.rglob("*")), before)
        self.assertEqual((mounted / "sentinel").read_text(), "another volume")


if __name__ == "__main__":
    unittest.main()
