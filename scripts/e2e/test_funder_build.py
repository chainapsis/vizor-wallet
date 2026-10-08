"""Real tiny Git/frozen files/owned children; modeled Rust compiler only."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import funder_build as BUILD
    import native_workspace as WORKSPACE
finally:
    sys.path.pop(0)


class FunderBuildTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-funder-build-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.source = self.root / "source-cache"
        self.source.mkdir(mode=0o700)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        for name, value in (("rust/Cargo.toml", '[package]\nname="model"\nversion="0.0.0"\n'),
                            ("rust/Cargo.lock", "# model lock\n"),
                            ("rust/examples/regtest_direct_funder.rs", "fn main() {}\n")):
            path = self.source / name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            path.write_text(value)
        self.git("add", "rust")
        self.git("commit", "-qm", "model source")
        self.commit = self.git("rev-parse", "HEAD").strip()
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir(mode=0o700)
        self.cases = []
        self.addCleanup(self.close_cases)
        self.completed = True
        self.candidate_mode = "original"
        self.mutate_source = False
        self.compiler_exit = 0
        self.compile_calls = 0
        self.rustc_identity = "rustc modeled\nhost: aarch64-apple-darwin"

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.source), *args], check=True,
                              capture_output=True, text=True).stdout

    def case(self):
        workspace = WORKSPACE.prepare_native_case_workspace(self.artifacts, platform="macos",
            scenario_id="flutter.macos.funder-build-probe", run_id="a1b2c3d4e5", worker_id=0,
            case_index=len(self.cases), ports={"rpc": 28232, "lwd": 29067, "proxy": 29068},
            activation_height=500)
        owner = BUILD.NativeCaseLifecycle(workspace)
        self.cases.append(owner)
        return owner

    def close_cases(self):
        for case in self.cases:
            case.close()

    def build(self, case=None, **updates):
        case = case or self.case()
        original = case.run_command
        def command(arguments, **options):
            if arguments[:2] == ["rustc", "-vV"]:
                return original([sys.executable, "-B", "-c", f"print({self.rustc_identity!r})"], **options)
            if arguments[:2] == ["cargo", "-V"]:
                return original([sys.executable, "-B", "-c", "print('cargo modeled')"], **options)
            if arguments[:2] != ["cargo", "build"]:
                return original(arguments, **options)
            self.compile_calls += 1
            self.assertIn("--offline", arguments)
            self.assertIn("--locked", arguments)
            self.assertEqual(arguments[arguments.index("--target") + 1], "aarch64-apple-darwin")
            target = Path(options["env"]["CARGO_TARGET_DIR"])
            binary = target / "debug/examples/regtest_direct_funder"
            if self.candidate_mode == "outside":
                binary = self.root / "outside-binary"
            manifest = Path(arguments[arguments.index("--manifest-path") + 1])
            source_file = manifest.parent / "examples/regtest_direct_funder.rs"
            message = {"reason": "compiler-artifact", "executable": str(binary),
                "target": {"name": "regtest_direct_funder", "kind": ["example"], "src_path": str(source_file)},
                "profile": {"test": self.candidate_mode == "test-harness"}}
            if self.candidate_mode == "wrong-source":
                message["target"]["src_path"] = str(self.source / "rust/examples/regtest_direct_funder.rs")
            script = ("from pathlib import Path; import json,sys; "
                f"p=Path({str(binary)!r}); p.parent.mkdir(mode=0o700,parents=True,exist_ok=True); "
                "p.write_text('modeled-compiler-output'); p.chmod(0o700); ")
            if self.mutate_source:
                script += f"s=Path({str(source_file)!r}); s.chmod(0o600); s.write_text('changed'); "
            finished = {"reason": "build-finished", "success": self.completed}
            script += ("print('Compiling modeled transport', file=sys.stderr); "
                f"print(json.dumps({message!r})); "
                f"print(json.dumps({finished!r})); "
                f"raise SystemExit({self.compiler_exit})")
            return original([sys.executable, "-B", "-c", script], **options)
        with patch.object(case, "run_command", side_effect=command):
            return BUILD.build_regtest_funder(case, source_root=self.source, source_commit=self.commit,
                                            timeout=5, **updates)

    def test_original_git_bytes_not_dirty_checkout_and_published_only_after_join(self):
        (self.source / "rust/examples/regtest_direct_funder.rs").write_text("dirty-checkout")
        case = self.case()
        artifact = self.build(case)
        frozen = case.workspace.root / "funder-build/source/rust/examples/regtest_direct_funder.rs"
        self.assertEqual(frozen.read_text(), "fn main() {}\n")
        self.assertEqual(frozen.stat().st_mode & 0o777, 0o400)
        self.assertFalse(case.accepting_launches)
        self.assertIsNotNone(case._receipt)
        self.assertTrue(all(process.cleanup_completed for process in case._processes))
        self.assertEqual(artifact.binary.stat().st_mode & 0o777, 0o500)
        self.assertEqual(self.compile_calls, 1)
        self.assertEqual(artifact.identity()["source_commit"], self.commit)
        self.assertEqual(artifact.identity()["host_target"], "aarch64-apple-darwin")
        evidence = artifact.identity()
        evidence["rust_blobs"].clear()
        self.assertEqual(len(artifact.identity()["rust_blobs"]), 3)

    def test_invalid_timeout_jobs_commit_or_nonfresh_case_never_launches_compiler(self):
        for update in ({"jobs": True}, {"jobs": 0}, {"jobs": 9}):
            with self.subTest(update=update), self.assertRaises(BUILD.FunderBuildError):
                self.build(**update)
        for timeout in (False, 0, float("nan")):
            with self.assertRaises(BUILD.FunderBuildError):
                BUILD.build_regtest_funder(self.case(), source_root=self.source,
                    source_commit=self.commit, timeout=timeout)
        with self.assertRaises(BUILD.FunderBuildError):
            BUILD.build_regtest_funder(self.case(), source_root=self.source, source_commit="HEAD")
        case = self.case()
        case.run_command([sys.executable, "-c", "pass"], env=os.environ, timeout=3, cancel_event=threading.Event())
        with self.assertRaises(BUILD.FunderBuildError):
            self.build(case)
        self.assertEqual(self.compile_calls, 0)

    def test_unproven_cargo_finish_wrong_target_or_test_harness_never_publishes(self):
        for mode in ("outside", "wrong-source", "test-harness"):
            self.candidate_mode = mode
            case = self.case()
            with self.subTest(mode=mode), self.assertRaises((BUILD.FunderBuildError, ValueError)):
                self.build(case)
            self.assertFalse(case.accepting_launches)
            self.assertTrue((case.workspace.root / "funder-build/target").exists())
        self.candidate_mode = "original"
        self.completed = False
        with self.assertRaises(BUILD.FunderBuildError):
            self.build()

    def test_nonzero_compile_and_changed_input_remain_failures_with_evidence(self):
        for kind in ("exit", "changed-source"):
            self.compiler_exit = 23 if kind == "exit" else 0
            self.mutate_source = kind == "changed-source"
            case = self.case()
            with self.subTest(kind=kind), self.assertRaises(BUILD.FunderBuildError):
                self.build(case)
            self.assertFalse(case.accepting_launches)
            self.assertTrue((case.workspace.root / "funder-build/source.tar").exists())

    def test_published_binary_change_is_sticky_even_if_bytes_are_restored(self):
        artifact = self.build()
        original = artifact.binary.read_bytes()
        artifact.binary.chmod(0o700)
        artifact.binary.write_text("changed")
        with self.assertRaises(BUILD.FunderBuildError):
            artifact.verify_unchanged()
        artifact.binary.write_bytes(original)
        artifact.binary.chmod(0o500)
        with self.assertRaises(BUILD.FunderBuildError):
            artifact.identity()

    def test_cancellation_seals_original_owner_without_any_git_or_cargo_launch(self):
        cancellation = threading.Event()
        cancellation.set()
        case = self.case()
        with self.assertRaises(BUILD.runtime.Cancelled):
            self.build(case, cancel_event=cancellation)
        self.assertFalse(case.accepting_launches)
        self.assertEqual(case.launched_process_count, 0)
        self.assertEqual(self.compile_calls, 0)

    def test_replaced_source_parent_is_not_adopted_even_with_original_files_moved(self):
        artifact = self.build()
        parent = artifact._root / "source/rust/examples"
        moved = parent.with_name("original-examples")
        parent.rename(moved)
        parent.mkdir(mode=0o700)
        (moved / "regtest_direct_funder.rs").rename(parent / "regtest_direct_funder.rs")
        moved.rmdir()
        with self.assertRaisesRegex(BUILD.FunderBuildError, "directories changed"):
            artifact.verify_unchanged()

    def test_replaced_executable_parent_is_not_adopted_even_with_original_binary_moved(self):
        artifact = self.build()
        parent = artifact.binary.parent
        moved = parent.with_name("original-executables")
        parent.rename(moved)
        parent.mkdir(mode=0o700)
        (moved / artifact.binary.name).rename(artifact.binary)
        with self.assertRaisesRegex(BUILD.FunderBuildError, "parent changed"):
            artifact.verify_unchanged()

    def test_git_export_ignore_cannot_silently_drop_a_frozen_input(self):
        (self.source / ".gitattributes").write_text("rust/Cargo.lock export-ignore\n")
        self.git("add", ".gitattributes")
        self.git("commit", "-qm", "export filter model")
        self.commit = self.git("rev-parse", "HEAD").strip()
        with self.assertRaisesRegex(BUILD.FunderBuildError, "omitted"):
            self.build()
        self.assertEqual(self.compile_calls, 0)

    def test_missing_duplicate_or_invalid_host_target_never_launches_compiler(self):
        for output in ("rustc modeled", "host: aarch64-apple-darwin\nhost: aarch64-apple-darwin",
                       "host: ../outside"):
            self.rustc_identity = output
            with self.subTest(output=output), self.assertRaisesRegex(BUILD.FunderBuildError, "host target"):
                self.build()
        self.assertEqual(self.compile_calls, 0)

    def test_every_nested_snapshot_parent_is_private(self):
        path = self.source / "rust/src/nested/deep/module.rs"
        path.parent.mkdir(mode=0o700, parents=True)
        path.write_text("// nested Git source\n")
        self.git("add", "rust")
        self.git("commit", "-qm", "nested source")
        self.commit = self.git("rev-parse", "HEAD").strip()
        artifact = self.build()
        frozen = artifact._root / "source"
        for directory, _, _ in os.walk(frozen):
            self.assertEqual(Path(directory).stat().st_mode & 0o777, 0o700)
        self.assertEqual((frozen / "rust/src/nested/deep/module.rs").read_text(), "// nested Git source\n")
        self.assertEqual(len(artifact.identity()["rust_blobs"]), 4)

    def test_git_export_substitution_cannot_change_frozen_blob_bytes(self):
        (self.source / ".gitattributes").write_text("rust/examples/regtest_direct_funder.rs export-subst\n")
        (self.source / "rust/examples/regtest_direct_funder.rs").write_text("// $Format:%H$\n")
        self.git("add", ".gitattributes", "rust")
        self.git("commit", "-qm", "export substitution model")
        self.commit = self.git("rev-parse", "HEAD").strip()
        with self.assertRaisesRegex(BUILD.FunderBuildError, "exact Git blob"):
            self.build()
        self.assertEqual(self.compile_calls, 0)

    def test_tracked_rust_symlink_is_rejected_before_compiler_launch(self):
        (self.source / "rust/linked-input").symlink_to("../../outside")
        self.git("add", "rust")
        self.git("commit", "-qm", "linked source model")
        self.commit = self.git("rev-parse", "HEAD").strip()
        with self.assertRaisesRegex(BUILD.FunderBuildError, "regular Git blob"):
            self.build()
        self.assertEqual(self.compile_calls, 0)


if __name__ == "__main__":
    unittest.main()
