"""Original private files; model Xcode/Flutter transport and signed captures."""
from pathlib import Path
import os
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e2e_runtime as runtime
import native_ios_build as BUILD
from native_case_lifecycle import NativeCaseLifecycle
from native_workspace import prepare_native_case_workspace


class BuildTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="ios-build-model-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.source = self.root/"source"
        self.source.mkdir(mode=0o700)
        for name in ("lib/app.dart", "ios/Runner.xcodeproj/project.pbxproj",
                     ".dart_tool/package_config.json", "bin/flutter"):
            path = self.source/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("model source")
            path.chmod(0o700)
        self.case = NativeCaseLifecycle(prepare_native_case_workspace(self.root,
            platform="ios", scenario_id="flutter.ios.native-build", run_id="abcdef0123",
            worker_id=0, case_index=0, ports={"rpc":28232,"lwd":29067,"proxy":29068}, activation_height=1))
        self.commands = []
        self.change_source = False
        self.installed_targets = {"aarch64-apple-ios-sim"}
        self.installed_toolchains = {"stable"}

    def command(self, arguments, **kwargs):
        self.commands.append(arguments)
        actual = arguments[4:] if arguments[0] == sys.executable else arguments
        if actual[:3] == ["rustup", "toolchain", "list"]:
            return runtime.CommandResult(0,tuple(name+"\n" for name in sorted(self.installed_toolchains)))
        if actual[:3] == ["rustup", "toolchain", "install"]:
            self.installed_toolchains.add(actual[-1])
        if actual[:3] == ["rustup", "target", "list"]:
            if actual[-1] not in self.installed_toolchains:
                return runtime.CommandResult(1,("selected toolchain is not installed\n",))
            return runtime.CommandResult(0,tuple(name+"\n" for name in sorted(self.installed_targets)))
        if actual[:3] == ["rustup", "target", "add"]:
            self.installed_targets.add(actual[-1])
        if "ls-files" in arguments:
            return runtime.CommandResult(0,("lib/app.dart\0ios/Runner.xcodeproj/project.pbxproj\0",))
        if "--config-only" in arguments:
            (self.source/"ios/Pods").mkdir(exist_ok=True)
            project = self.source/"ios/Runner.xcodeproj/project.pbxproj"
            stamp = project.stat().st_mtime_ns + 1_000_000
            os.utime(project, ns=(stamp,stamp))
            if self.change_source:
                (self.source/"lib/app.dart").write_text("changed")
        return runtime.CommandResult(0,())

    def build(self, **options):
        captured = SimpleNamespace(architecture="arm64",team="MODEL",verify_unchanged=lambda:None)
        with patch.object(self.case,"run_command",side_effect=self.command), \
             patch.object(BUILD.platform,"machine",return_value="arm64"), \
             patch.object(BUILD,"_inspect_app",return_value=SimpleNamespace(application_identifier="MODELTEAM1.com.keplr.vizor")), \
             patch.object(BUILD,"capture_ios_cleanup_helper",return_value=captured):
            return BUILD.build_native_ios_cohort(self.case, source_root=self.source, flutter=self.source/"bin/flutter", **options)

    def test_pods_are_prepared_without_app_compilation_before_cache_lookup(self):
        def inputs(*args, **kwargs):
            self.assertTrue((self.source/"ios/Pods").is_dir())
            self.assertTrue(any("--config-only" in args for args in self.commands))
            self.assertFalse(any("add" in args for args in self.commands))
            self.assertFalse(any("install" in args for args in self.commands))
            self.assertFalse(any("xcodebuild" in args for args in self.commands))
            raise RuntimeError("cache lookup boundary")
        with patch.object(BUILD.cache, "collect_native_cache_inputs", side_effect=inputs):
            with self.assertRaisesRegex(RuntimeError, "cache lookup boundary"):
                self.build(cache_root=self.root/"cache")

    def test_missing_simulator_rust_target_is_prepared_before_input_snapshot(self):
        self.installed_targets.clear()
        def inputs(*args, **kwargs):
            self.assertIn("aarch64-apple-ios-sim", self.installed_targets)
            additions = [args[4:] for args in self.commands if "add" in args]
            self.assertEqual(additions, [["rustup", "target", "add", "--toolchain", "stable", "aarch64-apple-ios-sim"]])
            self.assertFalse(any("xcodebuild" in args for args in self.commands))
            raise RuntimeError("prepared cache lookup boundary")
        with patch.object(BUILD.cache,"collect_native_cache_inputs",side_effect=inputs):
            with self.assertRaisesRegex(RuntimeError,"prepared cache lookup boundary"):
                self.build(cache_root=self.root/"cache")

    def test_missing_stable_toolchain_is_installed_before_target_query(self):
        self._assert_missing_toolchain_preparation("")

    def test_missing_exact_override_toolchain_is_installed_before_target_query(self):
        self._assert_missing_toolchain_preparation("1.96.0")

    def _assert_missing_toolchain_preparation(self, override):
        self.installed_targets.clear()
        self.installed_toolchains.clear()
        name = override or "stable"
        def inputs(*args, **kwargs):
            self.assertIn(name,self.installed_toolchains)
            self.assertIn("aarch64-apple-ios-sim",self.installed_targets)
            operations = [args[4:] for args in self.commands if "rustup" in args]
            install = operations.index(["rustup","toolchain","install",name])
            target_query = operations.index(["rustup","target","list","--installed","--toolchain",name])
            self.assertLess(install,target_query)
            self.assertFalse(any("xcodebuild" in args for args in self.commands))
            raise RuntimeError("prepared cache lookup boundary")
        with patch.dict(os.environ,{"VIZOR_RUST_TOOLCHAIN":override}), patch.object(
                BUILD.cache,"collect_native_cache_inputs",side_effect=inputs):
            with self.assertRaisesRegex(RuntimeError,"prepared cache lookup boundary"):
                self.build(cache_root=self.root/"cache")

    def test_preparation_source_changes_are_rejected_before_cache_lookup(self):
        self.change_source = True
        with patch.object(BUILD.cache, "collect_native_cache_inputs") as inputs:
            with self.assertRaisesRegex(BUILD.NativeIosBuildError, "lib/app.dart"):
                self.build(cache_root=self.root/"cache")
            inputs.assert_not_called()

    def test_one_mobile_regtest_cohort_and_original_helper_build(self):
        _, proof = self.build()
        self.assertEqual(proof["ios_app_build_count"], 1)
        self.assertEqual(proof["ios_helper_build_count"], 1)
        self.assertFalse(proof["wallet_or_catalog_pass"])
        configure = next(args for args in self.commands if "--config-only" in args)
        for flag in ("--simulator", "--debug", "--dart-define=VIZOR_FORM_FACTOR=mobile",
                     "--dart-define=VIZOR_E2E_IOS_COHORT=true", "--dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true"):
            self.assertEqual(configure.count(flag), 1)
        app = next(args for args in self.commands if "Runner" in args)
        self.assertIn("ENABLE_DEBUG_DYLIB=NO", app)
        self.assertIn(str(self.case.workspace.root/"ios-build"), app)
        helper = next(args for args in self.commands if "VizorIosCleanup" in args)
        self.assertIn("DEVELOPMENT_TEAM=MODELTEAM1", helper)

    def test_changed_wallet_input_does_not_publish_a_pair(self):
        self.change_source = True
        with self.assertRaisesRegex(BUILD.NativeIosBuildError,"lib/app.dart"):
            self.build()


if __name__ == "__main__":
    unittest.main()
