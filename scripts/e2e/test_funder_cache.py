"""Real publications, original groups and locks; compiler output is modeled."""
import json
import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import funder_cache as CACHE
import test_funder_build as FIXTURES


class FunderCacheTests(unittest.TestCase):
    def setUp(self):
        self.model = FIXTURES.FunderBuildTests()
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.cache = self.model.root / "cache"

    def build(self, **options):
        return self.model.build(cache_root=self.cache, **options)

    def entry(self, artifact):
        return self.cache / artifact.identity()["cache_key"]

    def test_warm_build_has_fresh_original_owner_without_another_compiler(self):
        cold, warm = self.build(), self.build()
        self.assertEqual(self.model.compile_calls, 1)
        self.assertFalse(cold.identity()["cache_hit"])
        self.assertTrue(warm.identity()["cache_hit"])
        self.assertEqual(warm.identity()["cargo_build_count"], 0)
        self.assertNotEqual(cold.identity()["producer_namespace"], warm.identity()["producer_namespace"])
        self.assertNotEqual(cold.binary, warm.binary)
        self.assertEqual(cold.identity()["binary_sha256"], warm.identity()["binary_sha256"])
        self.assertTrue(all(not case.accepting_launches and case._receipt is not None
                            for case in self.model.cases))
        cold.verify_unchanged()
        warm.verify_unchanged()

    def test_miss_checks_inputs_around_its_build_and_hit_once_after_sealing(self):
        inputs = FIXTURES.BUILD.toolchain_inputs
        observed = []
        for _ in range(2):
            collected, rechecked = [], []
            def collect(*args, original=inputs.rust_toolchain_inputs, **kwargs):
                collected.append(self.model.compile_calls)
                return original(*args, **kwargs)
            def recheck(*args, original=inputs.rust_inputs_unchanged, **kwargs):
                rechecked.append(self.model.compile_calls)
                return original(*args, **kwargs)
            with patch.object(inputs, "rust_toolchain_inputs", side_effect=collect), \
                 patch.object(inputs, "rust_inputs_unchanged", side_effect=recheck):
                self.build()
            observed.append((collected, rechecked))
        # Compiler runs seen by each check. A miss collects for its key, before
        # and after its build, then rechecks after sealing; a hit collects only
        # for its key and rechecks once after sealing.
        self.assertEqual(observed, [([0, 0, 1], [1]), ([1], [1])])

    def test_hit_rejects_inputs_changed_before_its_single_check(self):
        self.build()
        copy = FIXTURES.BUILD._copy_cargo_executable
        def changed(*args):
            (self.model.cargo_dependency/"lib.rs").write_text("patched while publishing")
            return copy(*args)
        with patch.object(FIXTURES.BUILD, "_copy_cargo_executable", side_effect=changed), \
             self.assertRaisesRegex(FIXTURES.BUILD.FunderBuildError, "Cargo dependency sources changed"):
            self.build()
        self.assertEqual(self.model.compile_calls, 1)

    def test_unrelated_commit_and_build_job_count_do_not_invalidate_rust(self):
        first = self.build(jobs=1)
        (self.model.source / "README.md").write_text("unrelated runner/documentation change")
        self.model.git("add", "README.md")
        self.model.git("commit", "-qm", "unrelated source")
        self.model.commit = self.model.git("rev-parse", "HEAD").strip()
        second = self.build(jobs=8)
        self.assertEqual(self.model.compile_calls, 1)
        self.assertEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        self.assertNotEqual(first.identity()["source_commit"], second.identity()["source_commit"])
        self.assertEqual(second.identity()["jobs"], 8)

    def test_shell_last_command_is_neither_a_build_input_nor_a_cache_miss(self):
        with patch.dict(os.environ, {"_": "python3"}):
            first = self.build()
        with patch.dict(os.environ, {"_": "/usr/bin/time"}):
            second = self.build()
        self.assertEqual(self.model.compile_calls, 1)
        self.assertEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        self.assertNotIn("_", self.model.last_build_env)
        self.assertNotIn("_", second.identity()["cache_inputs"]["environment_sha256"])

    def test_shell_session_credential_and_path_noise_reuse_the_signer(self):
        first = self.build()
        entries = os.environ.get("PATH", "").split(os.pathsep)
        with patch.dict(os.environ, {"PWD":"/model/elsewhere", "OLDPWD":"/model/before", "SHLVL":"9",
                                     "TERM_SESSION_ID":"w9t9p9:model", "MODEL_ACCESS_TOKEN":"model-secret",
                                     "PATH":os.pathsep.join((*entries, str(self.model.root/"missing"), entries[0]))}):
            second = self.build()
        self.assertEqual(self.model.compile_calls, 1)
        self.assertTrue(second.identity()["cache_hit"])
        self.assertEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        hashed = second.identity()["cache_inputs"]["environment_sha256"]
        for name in ("OLDPWD", "MODEL_ACCESS_TOKEN", "CARGO_TARGET_DIR", "CARGO_BUILD_JOBS"):
            self.assertNotIn(name, hashed)
        self.assertIn("RUSTC", hashed)

    def test_build_variables_and_requested_names_invalidate_the_signer(self):
        keys = {}
        for label, changes in (("original", {}), ("unlisted", {"OTHER_SWIFT_FLAGS":"-DMODEL"}),
                               ("cflags", {"CFLAGS":"-DMODEL"}), ("rustflags", {"RUSTFLAGS":"--cfg model"}),
                               ("requested", {"VIZOR_E2E_CACHE_ENV":"OTHER_SWIFT_FLAGS"}),
                               ("requested-value", {"VIZOR_E2E_CACHE_ENV":"OTHER_SWIFT_FLAGS",
                                                    "OTHER_SWIFT_FLAGS":"-DMODEL"})):
            with patch.dict(os.environ, changes):
                keys[label] = self.build().identity()["cache_key"]
        self.assertEqual(keys["original"], keys["unlisted"])
        self.assertEqual(len(set(keys.values())), 5)
        self.assertEqual(self.model.compile_calls, 5)

    def test_locked_rust_source_change_invalidates_the_cache(self):
        first = self.build()
        (self.model.source / "rust/Cargo.lock").write_text("# changed locked inputs\n")
        self.model.git("add", "rust/Cargo.lock")
        self.model.git("commit", "-qm", "new locked source")
        self.model.commit = self.model.git("rev-parse", "HEAD").strip()
        second = self.build()
        self.assertEqual(self.model.compile_calls, 2)
        self.assertNotEqual(first.identity()["cache_key"], second.identity()["cache_key"])

    def test_compiler_identity_bytes_and_build_environment_invalidate(self):
        keys = [self.build().identity()["cache_key"]]
        self.model.rustc_identity = "rustc newer\nhost: aarch64-apple-darwin"
        keys.append(self.build().identity()["cache_key"])
        self.model.compiler.write_text("new compiler bytes\n")
        keys.append(self.build().identity()["cache_key"])
        with patch.dict(os.environ, {"CARGO_PROFILE_DEV_OPT_LEVEL": "1"}):
            keys.append(self.build().identity()["cache_key"])
        self.assertEqual(self.model.compile_calls, 4)
        self.assertEqual(len(set(keys)), 4)

    def test_cargo_configuration_contents_invalidate_without_exposing_values(self):
        cargo_home = self.model.root / "cargo-home"
        cargo_home.mkdir(mode=0o700)
        configuration = cargo_home / "config.toml"
        configuration.write_text('[build]\nrustflags=["--cfg", "first"]\n')
        with patch.dict(os.environ, {"CARGO_HOME": str(cargo_home)}):
            first = self.build()
            configuration.write_text('[build]\nrustflags=["--cfg", "second"]\n')
            second = self.build()
        self.assertEqual(self.model.compile_calls, 2)
        self.assertNotEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        self.assertNotIn('"second"', json.dumps(second.identity()["cache_inputs"]))

    def test_forwarded_linker_prefix_bytes_invalidate_with_unchanged_environment(self):
        linker = self.model.root/"forwarded-tools/ld"
        linker.parent.mkdir()
        linker.write_text("original forwarded linker")
        linker.chmod(0o700)
        with patch.dict(os.environ,{"RUSTFLAGS":"-C link-arg=-B"+str(linker.parent)}):
            first = self.build().identity()
            linker.write_text("patched forwarded linker")
            second = self.build().identity()
        self.assertEqual(first["cache_inputs"]["environment_sha256"],second["cache_inputs"]["environment_sha256"])
        self.assertNotEqual(first["cache_key"],second["cache_key"])
        self.assertEqual(self.model.compile_calls,2)

    def test_cargo_dependency_bytes_invalidate_without_lock_config_or_environment_changes(self):
        first = self.build()
        (self.model.cargo_dependency/"lib.rs").write_text("patched Cargo dependency")
        second = self.build()
        for field in ("configuration_sha256", "environment_sha256", "rust_blobs"):
            self.assertEqual(first.identity()["cache_inputs"][field], second.identity()["cache_inputs"][field])
        self.assertNotEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        self.assertEqual(self.model.compile_calls, 2)

    def test_target_rustflags_linker_bytes_invalidate_with_unchanged_environment(self):
        linker = self.model.root/"target-linker"
        linker.write_text("original target linker")
        linker.chmod(0o700)
        with patch.dict(os.environ, {"CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS":"-C linker="+str(linker)}):
            first = self.build()
            linker.write_text("patched target linker")
            second = self.build()
        self.assertEqual(first.identity()["cache_inputs"]["environment_sha256"],
                         second.identity()["cache_inputs"]["environment_sha256"])
        self.assertNotEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        self.assertEqual(self.model.compile_calls, 2)

    def test_cargo_executable_bytes_invalidate_even_when_version_is_unchanged(self):
        first = self.build()
        self.model.cargo.write_text("different Cargo executable, same reported version\n")
        second = self.build()
        self.assertEqual(self.model.compile_calls, 2)
        self.assertNotEqual(first.identity()["cache_key"], second.identity()["cache_key"])
        self.assertEqual(self.model.selected_cargo, str(self.model.cargo))

    def test_rustup_cargo_proxy_binds_and_launches_the_actual_executable(self):
        self.model.rustup = self.model.root / "rustup"
        self.model.rustup.write_text("modeled rustup\n")
        self.model.rustup.chmod(0o700)
        self.model.cargo_entry = self.model.root / "cargo"
        self.model.cargo_entry.symlink_to(self.model.rustup)
        first = self.build()
        self.model.cargo.write_text("updated actual Cargo bytes\n")
        second = self.build()
        self.assertEqual(self.model.selected_cargo, str(self.model.cargo))
        self.assertEqual(self.model.compile_calls, 2)
        self.assertNotEqual(first.identity()["cache_key"], second.identity()["cache_key"])

    def test_selected_test_and_address_tools_are_reused_without_adopting_others(self):
        self.model.add_test_sources()
        self.model.add_address_source()
        cold = self.build(test_targets=("regtest_send", "regtest_receive_sync"), wallet_addresses=True)
        warm = self.build(test_targets=("regtest_receive_sync", "regtest_send"), wallet_addresses=True)
        self.assertEqual(self.model.compile_calls, 1)
        self.assertEqual(cold.identity()["cache_key"], warm.identity()["cache_key"])
        self.assertEqual(warm.test_binary("regtest_send").read_text(), "modeled-test-output")
        self.assertEqual(warm.wallet_addresses_binary().read_text(), "modeled-address-output")
        smaller = self.build(test_targets=("regtest_send",))
        self.assertEqual(self.model.compile_calls, 2)
        self.assertFalse(smaller.identity()["cache_hit"])

    def test_mutating_one_run_copy_never_mutates_the_cache_or_sibling(self):
        first, second = self.build(), self.build()
        first.binary.chmod(0o700)
        first.binary.write_text("changed original run copy")
        with self.assertRaises(FIXTURES.BUILD.FunderBuildError):
            first.verify_unchanged()
        second.verify_unchanged()
        third = self.build()
        self.assertEqual(self.model.compile_calls, 1)
        self.assertEqual(third.binary.read_text(), "modeled-compiler-output")

    def test_corrupt_bytes_fail_without_rebuilding_or_overwriting_the_entry(self):
        artifact = self.build()
        executable = self.entry(artifact) / "regtest_direct_funder"
        executable.chmod(0o700)
        executable.write_text("corrupt cached output")
        executable.chmod(0o500)
        with self.assertRaisesRegex(CACHE.FunderCacheError, "bytes changed"):
            self.build()
        self.assertEqual(self.model.compile_calls, 1)
        self.assertEqual(executable.read_text(), "corrupt cached output")
        artifact.verify_unchanged()

    def test_wrong_manifest_or_partial_inventory_never_becomes_a_hit(self):
        artifact = self.build()
        manifest = self.entry(artifact) / "manifest.json"
        manifest.chmod(0o600)
        manifest.write_text('{"schema":1,"inputs":{},"files":{}}')
        manifest.chmod(0o400)
        with self.assertRaisesRegex(CACHE.FunderCacheError, "current build inputs"):
            self.build()
        self.assertEqual(self.model.compile_calls, 1)

    def test_failed_original_compile_cannot_publish_a_cache_entry(self):
        self.model.compiler_exit = 1
        with self.assertRaises(FIXTURES.BUILD.FunderBuildError):
            self.build()
        self.assertFalse(any(path.is_dir() for path in self.cache.iterdir()))
        self.model.compiler_exit = 0
        self.assertFalse(self.build().identity()["cache_hit"])
        self.assertEqual(self.model.compile_calls, 2)

    def test_writable_entry_and_symlink_root_are_rejected(self):
        artifact = self.build()
        self.entry(artifact).chmod(0o700)
        with self.assertRaisesRegex(CACHE.FunderCacheError, "immutable"):
            self.build()
        alias = self.model.root / "alias"
        alias.symlink_to(self.cache, target_is_directory=True)
        with self.assertRaisesRegex(CACHE.FunderCacheError, "canonical"):
            self.model.build(cache_root=alias)
        self.assertEqual(self.model.compile_calls, 1)

    def test_lock_wait_is_bounded_and_original_publication_is_not_overwritten(self):
        cancel = threading.Event()
        inputs = {"schema": 1, "model": "lock"}
        with CACHE.FunderCacheLease(self.cache, inputs, ("model_binary",), timeout=2, cancel_event=cancel):
            with self.assertRaisesRegex(CACHE.FunderCacheError, "deadline"):
                with CACHE.FunderCacheLease(self.cache, inputs, ("model_binary",), timeout=0.05,
                                           cancel_event=cancel):
                    self.fail("a second original lease acquired an already held key")
        source, destination = self.model.root / "staging", self.model.root / "published"
        source.mkdir(mode=0o700)
        destination.mkdir(mode=0o700)
        with self.assertRaises(OSError):
            CACHE._rename_exclusive(source, destination)
        self.assertTrue(source.is_dir())
        self.assertTrue(destination.is_dir())


if __name__ == "__main__":
    unittest.main()
