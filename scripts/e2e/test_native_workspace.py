"""Host-only case ownership checks; no app, native storage or backend is launched."""

from __future__ import annotations

import dataclasses
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_workspace", SCRIPT_DIR / "native_workspace.py")
assert SPEC is not None and SPEC.loader is not None
WORKSPACE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = WORKSPACE
SPEC.loader.exec_module(WORKSPACE)


class NativeWorkspaceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-case-workspace-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.run_root = self.root / "run"
        self.run_root.mkdir(mode=0o700)
        self.arguments = {
            "platform": "macos", "scenario_id": "flutter.macos.contract-probe",
            "run_id": "a1b2c3d4e5", "worker_id": 2, "case_index": 17,
            "ports": {"rpc": 28232, "lwd": 29067, "proxy": 29068},
            "activation_height": 500,
        }

    def make(self, *, run_root=None, **updates):
        return WORKSPACE.prepare_native_case_workspace(
            self.run_root if run_root is None else run_root, **{**self.arguments, **updates},
        )

    def test_macos_environment_matches_exact_native_schema(self):
        workspace = self.make()
        environment = workspace.launch_environment()
        expected_namespace = "vizor_a1b2c3d4e5_w2_17"
        self.assertEqual(workspace.root, self.run_root / "e2e" / expected_namespace)
        self.assertEqual(set(environment), {"VIZOR_E2E_NAMESPACE", "VIZOR_E2E_CASE_MANIFEST"})
        self.assertEqual(environment["VIZOR_E2E_NAMESPACE"], expected_namespace)
        encoded = environment["VIZOR_E2E_CASE_MANIFEST"]
        self.assertLessEqual(len(encoded.encode("ascii")), 2048)
        self.assertEqual(json.loads(encoded), {
            "schema_version": 1, "scenario_id": "flutter.macos.contract-probe",
            "run_id": "a1b2c3d4e5", "worker_id": 2, "case_index": 17,
            "namespace": expected_namespace,
            "context_path": str(workspace.root / "native-context.json"),
            "lightwalletd_port": 29067, "primary_proxy_port": 29068,
            "zcashd_rpc_port": 28232, "regtest_ironwood_activation_height": 500,
        })
        self.assertEqual(workspace.manifest_path.read_bytes(), encoded.encode("ascii"))
        self.assertFalse((workspace.root / "native-context.json").exists())
        for directory in (self.run_root / "e2e", workspace.root):
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        for file in (workspace.marker_path, workspace.manifest_path):
            self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)
        workspace.verify_owned()

    def test_ios_uses_app_support_context_without_inventing_a_host_receipt(self):
        workspace = self.make(platform="ios", scenario_id="flutter.ios.contract-probe")
        manifest = json.loads(workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
        self.assertEqual(workspace.context_path, "app-support")
        self.assertEqual(manifest["context_path"], "app-support")
        self.assertEqual(manifest["scenario_id"], "flutter.ios.contract-probe")
        self.assertFalse((workspace.root / "native-context.json").exists())

    def test_restart_reuses_identity_and_retains_mutable_state(self):
        workspace = self.make()
        first = workspace.launch_environment()
        state = workspace.root / "fixture-state.json"
        state.write_text('{"height":501}')
        (workspace.root / "native-context.json").write_text('{"storage_cleanup_completed":false}')
        self.assertEqual(workspace.launch_environment(), first)
        self.assertEqual(state.read_text(), '{"height":501}')
        self.assertTrue(workspace.marker_path.exists())

    def test_ports_are_snapshotted_not_shared_with_the_caller(self):
        workspace = self.make()
        self.arguments["ports"]["rpc"] = 12345
        manifest = json.loads(workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
        self.assertEqual(manifest["zcashd_rpc_port"], 28232)

    def test_distinct_run_worker_and_case_own_distinct_directories(self):
        workspaces = [
            self.make(), self.make(case_index=18), self.make(worker_id=3),
            self.make(run_id="1234567890"),
        ]
        self.assertEqual(len({item.namespace for item in workspaces}), 4)
        for index, item in enumerate(workspaces):
            (item.root / "state").write_text(str(index))
        for index, item in enumerate(workspaces):
            item.verify_owned()
            self.assertEqual((item.root / "state").read_text(), str(index))

    def test_duplicate_case_never_adopts_or_rewrites_existing_metadata(self):
        workspace = self.make()
        before = {path: path.read_bytes() for path in (workspace.marker_path, workspace.manifest_path)}
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()
        for path, data in before.items():
            self.assertEqual(path.read_bytes(), data)
        workspace.verify_owned()

    def test_invalid_identity_is_rejected_before_creating_directories(self):
        for update in (
            {"run_id": "A1B2C3D4E5"}, {"run_id": "../outside"}, {"run_id": None},
            {"worker_id": True}, {"worker_id": -1}, {"worker_id": 1_000_001},
            {"case_index": False}, {"case_index": -1}, {"case_index": 1.0},
            {"case_index": 1_000_001}, {"activation_height": False},
            {"activation_height": 0}, {"activation_height": 4_294_967_296},
            {"platform": "linux"}, {"scenario_id": "flutter.ios.contract-probe"},
            {"scenario_id": "flutter.macos.bad--id"}, {"scenario_id": "flutter.macos.a/../b"},
        ):
            with self.subTest(update=update), self.assertRaises(WORKSPACE.NativeWorkspaceError):
                self.make(**update)
            self.assertEqual(list(self.run_root.iterdir()), [])

    def test_invalid_ports_are_rejected_before_creating_directories(self):
        for ports in (
            None, [], {"rpc": 1, "lwd": 2}, {"rpc": 1, "lwd": 2, "proxy": 3, "extra": 4},
            {"rpc": True, "lwd": 2, "proxy": 3}, {"rpc": 0, "lwd": 2, "proxy": 3},
            {"rpc": 65536, "lwd": 2, "proxy": 3}, {"rpc": 1.0, "lwd": 2, "proxy": 3},
            {"rpc": 1, "lwd": 1, "proxy": 3},
        ):
            with self.subTest(ports=ports), self.assertRaises(WORKSPACE.NativeWorkspaceError):
                self.make(ports=ports)
            self.assertEqual(list(self.run_root.iterdir()), [])

    def test_native_integer_boundaries_and_activation_are_explicit(self):
        workspace = self.make(
            worker_id=1_000_000, case_index=1_000_000,
            ports={"rpc": 1, "lwd": 65534, "proxy": 65535}, activation_height=4_294_967_295,
        )
        manifest = json.loads(workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
        self.assertEqual(manifest["regtest_ironwood_activation_height"], 4_294_967_295)
        self.assertLessEqual(len(workspace.namespace.encode("ascii")), 64)

    def test_oversized_manifest_fails_before_filesystem_mutation(self):
        with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "2048-byte"):
            self.make(scenario_id="flutter.macos." + "a" * 2048)
        self.assertEqual(list(self.run_root.iterdir()), [])

    def test_unicode_and_space_paths_still_publish_ascii_json(self):
        private = self.root / "한글 space"
        private.mkdir(mode=0o700)
        workspace = self.make(run_root=private)
        encoded = workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"]
        encoded.encode("ascii")
        self.assertEqual(json.loads(encoded)["context_path"], str(workspace.root / "native-context.json"))

    def test_noncanonical_missing_and_public_run_roots_are_rejected(self):
        alias = self.root / "alias"
        alias.symlink_to(self.run_root, target_is_directory=True)
        for path in (Path("relative"), self.root / "missing", alias):
            with self.subTest(path=path), self.assertRaises(WORKSPACE.NativeWorkspaceError):
                self.make(run_root=path)
        self.run_root.chmod(0o755)
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()
        self.assertEqual(list(self.run_root.iterdir()), [])

    def test_shared_parent_symlink_does_not_touch_its_target(self):
        foreign = self.root / "foreign"
        foreign.mkdir(mode=0o700)
        sentinel = foreign / "keep"
        sentinel.write_text("unrelated")
        (self.run_root / "e2e").symlink_to(foreign, target_is_directory=True)
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()
        self.assertEqual(list(foreign.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_text(), "unrelated")

    def test_nonprivate_shared_parent_is_rejected(self):
        parent = self.run_root / "e2e"
        parent.mkdir(mode=0o755)
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()
        self.assertEqual(list(parent.iterdir()), [])

    def test_preexisting_case_symlink_is_never_adopted(self):
        parent = self.run_root / "e2e"
        parent.mkdir(mode=0o700)
        foreign = self.root / "foreign"
        foreign.mkdir(mode=0o700)
        (parent / "vizor_a1b2c3d4e5_w2_17").symlink_to(foreign, target_is_directory=True)
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()
        self.assertEqual(list(foreign.iterdir()), [])

    def test_metadata_changes_are_sticky_even_after_contents_are_restored(self):
        for index, name in enumerate(("workspace-owner.json", "case-manifest.json")):
            workspace = self.make(case_index=index)
            path = workspace.root / name
            original = path.read_bytes()
            path.write_bytes(original + b" ")
            with self.assertRaises(WORKSPACE.NativeWorkspaceError):
                workspace.launch_environment()
            path.write_bytes(original)
            with self.assertRaises(WORKSPACE.NativeWorkspaceError):
                workspace.verify_owned()
            self.assertTrue(workspace.root.exists())

    def test_same_content_replacement_is_not_original_metadata(self):
        workspace = self.make()
        original = workspace.marker_path.read_bytes()
        workspace.marker_path.rename(workspace.root / "held-marker")
        workspace.marker_path.write_bytes(original)
        workspace.marker_path.chmod(0o600)
        with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "metadata changed"):
            workspace.verify_owned()

    def test_metadata_symlinks_hardlinks_and_public_files_are_rejected(self):
        for index, kind in enumerate(("symlink", "hardlink", "public")):
            workspace = self.make(case_index=index)
            original = workspace.marker_path.read_bytes()
            foreign = self.root / f"foreign-{index}"
            if kind == "symlink":
                foreign.write_bytes(original)
                workspace.marker_path.unlink()
                workspace.marker_path.symlink_to(foreign)
            elif kind == "hardlink":
                os.link(workspace.marker_path, foreign)
            else:
                workspace.marker_path.chmod(0o644)
            with self.subTest(kind=kind), self.assertRaises(WORKSPACE.NativeWorkspaceError):
                workspace.verify_owned()
            self.assertTrue(workspace.root.exists())
            if foreign.exists():
                self.assertEqual(foreign.read_bytes(), original)

    def test_case_directory_replacement_cannot_reuse_an_old_handle(self):
        workspace = self.make()
        held = workspace.root.with_name("held-case")
        workspace.root.rename(held)
        shutil.copytree(held, workspace.root)
        with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "directory identity changed"):
            workspace.verify_owned()
        self.assertTrue((held / "workspace-owner.json").exists())

    def test_parent_directory_identity_is_checked_even_when_case_inode_is_preserved(self):
        workspace = self.make()
        parent = self.run_root / "e2e"
        held = self.run_root / "held-parent"
        parent.rename(held)
        parent.mkdir(mode=0o700)
        (held / workspace.namespace).rename(workspace.root)
        with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "directory identity changed"):
            workspace.verify_owned()

    def test_replaced_run_root_cannot_reuse_an_old_handle(self):
        workspace = self.make()
        held = self.root / "held-run"
        self.run_root.rename(held)
        shutil.copytree(held, self.run_root)
        with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "directory identity changed"):
            workspace.verify_owned()

    def test_forged_handle_is_rejected_without_filesystem_access(self):
        workspace = self.make()
        forged = dataclasses.replace(workspace, _ownership_token=object())
        with patch.object(WORKSPACE.os, "open") as opened:
            with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "expected a handle"):
                forged.launch_environment()
            opened.assert_not_called()
        workspace.verify_owned()

    def test_partial_publication_retains_evidence_and_closes_descriptors(self):
        real_open = os.open
        real_write = WORKSPACE._write_new_file
        descriptors = []

        def capture_open(*args, **kwargs):
            descriptor = real_open(*args, **kwargs)
            descriptors.append(descriptor)
            return descriptor

        def fail_manifest(directory_fd, name, data):
            if name == "case-manifest.json":
                raise OSError("injected manifest write failure")
            return real_write(directory_fd, name, data)

        with patch.object(WORKSPACE.os, "open", side_effect=capture_open), patch.object(
            WORKSPACE, "_write_new_file", side_effect=fail_manifest,
        ):
            with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "state retained"):
                self.make()
        for descriptor in descriptors:
            with self.assertRaises(OSError):
                os.fstat(descriptor)
        case_root = self.run_root / "e2e" / "vizor_a1b2c3d4e5_w2_17"
        marker = case_root / "workspace-owner.json"
        original = marker.read_bytes()
        self.assertFalse((case_root / "case-manifest.json").exists())
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()
        self.assertEqual(marker.read_bytes(), original)

    def test_interrupted_allocation_retains_partial_directory(self):
        with patch.object(WORKSPACE, "_write_new_file", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.make()
        self.assertTrue((self.run_root / "e2e" / "vizor_a1b2c3d4e5_w2_17").is_dir())
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()

    def test_descriptor_close_failure_does_not_publish_a_successful_handle(self):
        real_close = os.close
        closed = []

        def fail_first_close(descriptor):
            real_close(descriptor)
            closed.append(descriptor)
            if len(closed) == 1:
                raise OSError("injected directory close failure")

        with patch.object(WORKSPACE.os, "close", side_effect=fail_first_close):
            with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "close failure"):
                self.make()
        self.assertEqual(len(closed), 3)
        for descriptor in closed:
            with self.assertRaises(OSError):
                os.fstat(descriptor)
        case_root = self.run_root / "e2e" / "vizor_a1b2c3d4e5_w2_17"
        self.assertTrue((case_root / "case-manifest.json").exists())
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            self.make()

    def test_unreadable_metadata_stays_failed_after_permissions_recover(self):
        workspace = self.make()
        with patch.object(WORKSPACE, "_read_private_file", side_effect=PermissionError("injected denial")):
            with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "injected denial"):
                workspace.verify_owned()
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            workspace.launch_environment()
        self.assertTrue(workspace.marker_path.exists())

    def test_missing_metadata_is_not_ownership_proof(self):
        workspace = self.make()
        workspace.manifest_path.unlink()
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            workspace.verify_owned()
        self.assertTrue(workspace.marker_path.exists())

    def test_directory_permission_changes_are_checked_before_relaunch(self):
        workspace = self.make()
        workspace.root.chmod(0o755)
        with self.assertRaises(WORKSPACE.NativeWorkspaceError):
            workspace.launch_environment()

    def test_nonposix_host_fails_before_filesystem_mutation(self):
        with patch.object(WORKSPACE.os, "name", "nt"):
            with self.assertRaisesRegex(WORKSPACE.NativeWorkspaceError, "POSIX"):
                self.make()
        self.assertEqual(list(self.run_root.iterdir()), [])

    def test_concurrent_processes_cannot_both_reserve_the_same_case(self):
        source = (
            "import json,sys; from pathlib import Path; import native_workspace as w\n"
            "try: w.prepare_native_case_workspace(Path(sys.argv[1]),**json.loads(sys.argv[2]))\n"
            "except w.NativeWorkspaceError: sys.exit(3)\n"
        )
        children = []
        try:
            for _ in range(2):
                children.append(subprocess.Popen(
                    [sys.executable, "-B", "-c", source, str(self.run_root), json.dumps(self.arguments)],
                    cwd=self.root, env={**os.environ, "PYTHONPATH": str(SCRIPT_DIR)},
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True,
                ))
            for child in children:
                _stdout, stderr = child.communicate(timeout=5)
                self.assertIn(child.returncode, (0, 3), stderr.decode())
            self.assertEqual(sorted(child.returncode for child in children), [0, 3])
            case = self.run_root / "e2e" / "vizor_a1b2c3d4e5_w2_17"
            self.assertEqual(set(path.name for path in case.iterdir()), {
                "workspace-owner.json", "case-manifest.json",
            })
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                child.communicate(timeout=5)

    def test_replaced_fifo_is_rejected_without_blocking(self):
        source = (
            "import json,os,sys; from pathlib import Path; import native_workspace as w\n"
            "case=w.prepare_native_case_workspace(Path(sys.argv[1]),**json.loads(sys.argv[2]))\n"
            "case.marker_path.unlink(); os.mkfifo(case.marker_path,0o600)\n"
            "try: case.verify_owned()\n"
            "except w.NativeWorkspaceError: sys.exit(0)\n"
            "sys.exit(1)\n"
        )
        completed = subprocess.run(
            [sys.executable, "-B", "-c", source, str(self.run_root), json.dumps(self.arguments)],
            cwd=self.root, env={**os.environ, "PYTHONPATH": str(SCRIPT_DIR)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, start_new_session=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr.decode())


if __name__ == "__main__":
    unittest.main()
