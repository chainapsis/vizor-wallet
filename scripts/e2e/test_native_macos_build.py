"""Real private source files; modeled SDK commands/signatures/native artifacts."""
from pathlib import Path
import os
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e2e_runtime as runtime
import native_macos_build as BUILD
from native_case_lifecycle import NativeCaseLifecycle
from native_workspace import prepare_native_case_workspace


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="native-build-model-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        self.source = self.root/"source"
        self.source.mkdir(mode=0o700)
        for name in ("macos/Runner.xcodeproj/project.pbxproj", "lib/app.dart",
                     "test/support/legacy_payment_link.dart", ".dart_tool/package_config.json", "bin/flutter"):
            path = self.source/name
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text("model source")
            path.chmod(0o700)
        self.project = self.source/"macos/Runner.xcodeproj/project.pbxproj"
        self.commands = []
        self.case = NativeCaseLifecycle(prepare_native_case_workspace(self.root,platform="macos",
            scenario_id="flutter.macos.native-build",run_id="abcdef0123",
            worker_id=0,case_index=0,ports={"rpc":28232,"lwd":29067,"proxy":29068},activation_height=1))
        self.mode = "same-project-bytes"
        self.native_arguments = None
        self.installed_targets = {"aarch64-apple-darwin", "x86_64-apple-darwin"}

    def command(self, arguments, **kwargs):
        self.commands.append(arguments)
        actual = arguments[4:] if arguments[0] == sys.executable else arguments
        if actual[:3] == ["rustup", "toolchain", "list"]:
            return runtime.CommandResult(0,("stable\n",))
        if actual[:3] == ["rustup", "target", "list"]:
            return runtime.CommandResult(0,tuple(name+"\n" for name in sorted(self.installed_targets)))
        if actual[:3] == ["rustup", "target", "add"]:
            self.installed_targets.add(actual[-1])
        if "ls-files" in arguments:
            requested = arguments[arguments.index("--")+1:]
            files = ("lib/app.dart", "macos/Runner.xcodeproj/project.pbxproj", "test/support/legacy_payment_link.dart")
            return runtime.CommandResult(0,("\0".join(name for name in files if name.split("/")[0] in requested)+"\0",))
        if "--target" in arguments:
            self.native_arguments = arguments
            # Reproduce the SDK's same-content metadata rewrite.
            timestamp = self.project.stat().st_mtime_ns + 1_000_000
            os.utime(self.project,ns=(timestamp,timestamp))
            if self.mode == "changed-project-bytes":
                self.project.write_text("changed project")
            elif self.mode == "changed-wallet-source":
                (self.source/"lib/app.dart").write_text("changed wallet")
            elif self.mode == "changed-test-support":
                (self.source/"test/support/legacy_payment_link.dart").write_text("changed imported test support")
            if "--config-only" in arguments:
                (self.source/"macos/Pods").mkdir(exist_ok=True)
            else:
                app = self.source/"build/macos/Build/Products/Debug/Vizor.app/Contents"
                app.mkdir(parents=True)
                (app/"embedded.provisionprofile").write_text("modeled profile")
        elif "--display" in arguments:
            return runtime.CommandResult(0,("Authority=modeled identity",))
        elif "swift" in arguments:
            target = Path(arguments[arguments.index("--scratch-path")+1])/"debug"
            target.mkdir(parents=True)
            (target/"vizor-native-cleanup").write_text("modeled executable")
        return runtime.CommandResult(0,())

    def build(self, **options):
        captured = SimpleNamespace(team="MODEL",verify_unchanged=lambda:None)
        with patch.object(self.case,"run_command",side_effect=self.command), \
             patch.object(BUILD,"_inspect_signed_app",return_value=SimpleNamespace(team="MODEL")), \
             patch.object(BUILD,"capture_mac_cleanup_helper",return_value=captured):
            return BUILD.build_native_macos_cohort(self.case,source_root=self.source,
                                                  flutter=self.source/"bin/flutter", **options)

    def test_pods_are_prepared_without_app_compilation_before_cache_lookup(self):
        def inputs(*args, **kwargs):
            self.assertTrue((self.source/"macos/Pods").is_dir())
            self.assertTrue(any("--config-only" in args for args in self.commands))
            self.assertFalse(any("add" in args for args in self.commands))
            self.assertFalse(any("install" in args for args in self.commands))
            self.assertFalse(any("swift" in args for args in self.commands))
            raise RuntimeError("cache lookup boundary")
        with patch.object(BUILD.cache, "collect_native_cache_inputs", side_effect=inputs):
            with self.assertRaisesRegex(RuntimeError, "cache lookup boundary"):
                self.build(cache_root=self.root/"cache")

    def test_imported_test_support_is_in_cache_input_inventory(self):
        def inputs(root, source, *args, **kwargs):
            self.assertIn(self.source/"test/support/legacy_payment_link.dart", source)
            raise RuntimeError("cache lookup boundary")
        with patch.object(BUILD.cache,"collect_native_cache_inputs",side_effect=inputs):
            with self.assertRaisesRegex(RuntimeError,"cache lookup boundary"):
                self.build(cache_root=self.root/"cache")

    def test_preparation_test_support_changes_are_rejected_before_cache_lookup(self):
        self.mode = "changed-test-support"
        with patch.object(BUILD.cache,"collect_native_cache_inputs") as inputs:
            with self.assertRaisesRegex(BUILD.NativeMacosBuildError,"legacy_payment_link.dart"):
                self.build(cache_root=self.root/"cache")
            inputs.assert_not_called()

    def test_preparation_source_changes_are_rejected_before_cache_lookup(self):
        self.mode = "changed-wallet-source"
        with patch.object(BUILD.cache, "collect_native_cache_inputs") as inputs:
            with self.assertRaisesRegex(BUILD.NativeMacosBuildError, "lib/app.dart"):
                self.build(cache_root=self.root/"cache")
            inputs.assert_not_called()

    def test_sdk_project_metadata_rewrite_preserves_identical_input_bytes(self):
        _,proof = self.build()
        self.assertEqual(proof["app_build_count"],1)
        self.assertFalse(proof["wallet_or_catalog_pass"])

    def test_sdk_project_content_change_is_still_rejected(self):
        self.mode = "changed-project-bytes"
        with self.assertRaisesRegex(BUILD.NativeMacosBuildError,"project.pbxproj"):
            self.build()

    def test_cohort_build_keeps_the_existing_regtest_gift_creation_gate(self):
        self.build()
        for flag in ("--dart-define=ZCASH_DEFAULT_NETWORK=regtest",
                     "--dart-define=VIZOR_E2E_MACOS_COHORT=true",
                     "--dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true"):
            self.assertEqual(self.native_arguments.count(flag), 1)

    def test_wallet_source_content_change_is_still_rejected(self):
        self.mode = "changed-wallet-source"
        with self.assertRaisesRegex(BUILD.NativeMacosBuildError,"lib/app.dart"):
            self.build()


if __name__ == "__main__":
    unittest.main()
