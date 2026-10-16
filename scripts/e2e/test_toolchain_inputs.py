"""Build-environment key policy; collectors still read the complete environment."""
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import toolchain_inputs as INPUTS


class BuildEnvironmentTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="build-environment-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.first, self.second = self.root/"first", self.root/"second"
        self.first.mkdir()
        self.second.mkdir()
        self.environment = {"PATH":os.pathsep.join((str(self.first), str(self.second))),
                            "HOME":str(self.root), "LANG":"en_US.UTF-8", "RUSTFLAGS":"--cfg model"}

    def hashed(self, **changes):
        return INPUTS.build_environment_inputs({**self.environment, **changes})[0]

    def test_shell_session_and_credential_names_are_reported_but_not_hashed(self):
        noise = {"PWD":"/model/elsewhere", "OLDPWD":"/model/before", "SHLVL":"9", "_":"/usr/bin/env",
                 "TERM_SESSION_ID":"w9t9p9:model", "TERM_PROGRAM":"model", "LC_TERMINAL":"model",
                 "TMPDIR":"/model/tmp", "SSH_AUTH_SOCK":"/model/agent", "CARGO_REGISTRY_TOKEN":"model",
                 "CARGO_REGISTRY_SECRET_KEY":"model", "CARGO_REGISTRIES_MODEL_CREDENTIAL_PROVIDER":"model",
                 "GOAUTH":"netrc", "RUSTUP_NETRC":"model", "SWIFTPM_REGISTRY_PASSWORD":"model",
                 "BUNDLE_LOGIN":"model", "GEM_HOST_API_KEY":"model", "CMAKE_PRIVATE_KEY":"model",
                 "TARGET_PKG_CONFIG_PASSWORD":"model", "MODEL_TOKEN_STATIC":"model"}
        hashed, report = INPUTS.build_environment_inputs({**self.environment, **noise})
        self.assertEqual(hashed, self.hashed())
        self.assertEqual(report, {"hashed_names":sorted(self.environment), "excluded_names":sorted(noise),
                                  "requested_extra_names":[]})

    def test_build_selectors_and_flags_change_their_digest(self):
        for name in ("CC", "CC_aarch64-apple-darwin", "TARGET_AR", "CFLAGS", "TARGET_CXXFLAGS", "LDFLAGS",
                     "CARGO_PROFILE_DEV_OPT_LEVEL", "RUSTFLAGS", "RUSTUP_TOOLCHAIN", "BUILD_TAGS", "GOFLAGS",
                     "CGO_CFLAGS", "FLUTTER_XCODE_OTHER_SWIFT_FLAGS", "PUB_HOSTED_URL", "LOCAL_ENGINE",
                     "MACOSX_DEPLOYMENT_TARGET", "SDKROOT", "DEVELOPER_DIR", "LANG", "LC_ALL", "HOME",
                     "PKG_CONFIG_PATH", "CMAKE_TOOLCHAIN_FILE", "AWS_LC_SYS_NO_ASM", "GEM_HOME",
                     "COCOAPODS_DISABLE_STATS", "SWIFT_EXEC", "DYLD_LIBRARY_PATH", "VIZOR_RUST_TOOLCHAIN",
                     "VIZOR_E2E_CACHE_ENV",
                     # pkg-config's prefixed, target-suffixed and per-library forms; ICU4X baked data.
                     "HOST_PKG_CONFIG", "HOST_PKG_CONFIG_PATH", "TARGET_PKG_CONFIG_PATH",
                     "PKG_CONFIG_PATH_aarch64-apple-darwin", "PKG_CONFIG_PATH_aarch64_apple_darwin",
                     "LIBLZMA_STATIC", "LIBLZMA_DYNAMIC", "LIBLZMA_NO_PKG_CONFIG", "LZMA_API_STATIC",
                     "ICU4X_DATA_DIR"):
            with self.subTest(name=name):
                self.assertNotEqual(self.hashed(**{name:"FIRST"}), self.hashed(**{name:"SECOND"}))

    def test_requested_names_are_added_even_when_they_look_like_credentials(self):
        environment = {**self.environment, "OTHER_SWIFT_FLAGS":"-DMODEL", "MODEL_TOKEN":"model"}
        hashed = INPUTS.build_environment_inputs(environment)[0]
        self.assertFalse({"OTHER_SWIFT_FLAGS", "MODEL_TOKEN"} & set(hashed))
        hashed, report = INPUTS.build_environment_inputs({**environment,
            "VIZOR_E2E_CACHE_ENV":" OTHER_SWIFT_FLAGS,\tMODEL_TOKEN  UNSET_MODEL "})
        self.assertEqual(hashed["MODEL_TOKEN"], hashlib.sha256(b"model").hexdigest())
        self.assertLessEqual({"OTHER_SWIFT_FLAGS", "VIZOR_E2E_CACHE_ENV"}, set(hashed))
        self.assertNotIn("UNSET_MODEL", hashed)
        self.assertEqual(report["requested_extra_names"], ["MODEL_TOKEN", "OTHER_SWIFT_FLAGS", "UNSET_MODEL"])

    def test_requested_names_must_be_exact_names(self):
        for value in ("1MODEL", "-MODEL", ".MODEL", "MODEL_*", "MODEL=VALUE", "MODEL;OTHER"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(INPUTS.ToolInputError, "VIZOR_E2E_CACHE_ENV"):
                    INPUTS.build_environment_inputs({"VIZOR_E2E_CACHE_ENV":value})
        self.assertEqual(INPUTS.requested_environment_names({"VIZOR_E2E_CACHE_ENV":" A,B\n_C ,A,, "}),
                         ("A", "B", "_C"))
        self.assertEqual(INPUTS.requested_environment_names({}), ())
        # Target-suffixed names keep their '-' and '.', and listing them hashes them.
        names = ("CXXSTDLIB_aarch64-apple-darwin", "MODEL.NAME")
        hashed, report = INPUTS.build_environment_inputs({"VIZOR_E2E_CACHE_ENV":" ".join(names),
                                                          **{name:"model" for name in names}})
        self.assertLessEqual(set(names), set(hashed))
        self.assertEqual(report["requested_extra_names"], sorted(names))

    def test_producer_owned_names_stay_excluded_even_when_requested(self):
        hashed, report = INPUTS.build_environment_inputs({**self.environment,
            "CARGO_TARGET_DIR":"/model/case/target", "CARGO_BUILD_JOBS":"8",
            "VIZOR_E2E_CACHE_ENV":"CARGO_TARGET_DIR"}, excluded={"CARGO_TARGET_DIR", "CARGO_BUILD_JOBS"})
        self.assertFalse({"CARGO_TARGET_DIR", "CARGO_BUILD_JOBS"} & set(hashed))
        self.assertEqual(report["excluded_names"], ["CARGO_BUILD_JOBS", "CARGO_TARGET_DIR"])

    def test_path_binds_existing_canonical_directories_in_lookup_order(self):
        alias = self.root/"alias"
        alias.symlink_to(self.first, target_is_directory=True)
        (self.root/"file").write_text("not a directory")
        first, second, missing = str(self.first), str(self.second), str(self.root/"missing")
        original = self.hashed()["PATH"]
        for entries in ((first, missing, second, first), (str(alias), second, second),
                        (first, str(self.root/"file"), second)):
            with self.subTest(path=entries):
                self.assertEqual(self.hashed(PATH=os.pathsep.join(entries))["PATH"], original)
        self.assertNotEqual(self.hashed(PATH=os.pathsep.join((second, first)))["PATH"], original)
        self.assertNotEqual(self.hashed(PATH=first)["PATH"], original)

    def test_report_never_contains_values_or_digests(self):
        environment = {**self.environment, "OLDPWD":"/model/private-directory", "MODEL_TOKEN":"model-secret"}
        hashed, report = INPUTS.build_environment_inputs(environment)
        text = json.dumps(report)
        for value in (*environment.values(), *hashed.values()):
            self.assertNotIn(value, text)

    def test_every_variable_the_collectors_read_directly_is_hashed(self):
        read = set()
        for module in ("toolchain_inputs", "funder_build"):
            source = ast.parse(Path(__file__).with_name(module+".py").read_text())
            read.update(node.args[0].value for node in ast.walk(source)
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "get"
                and isinstance(node.func.value, ast.Name) and node.func.value.id in {"environment", "build_env"}
                and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str))
        self.assertLessEqual({"PATH", "CARGO_HOME", "RUSTC"}, read)
        # One name of each configured-tool selector form; each must really select a program.
        selectors = {"RUSTC", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "RUSTDOC", "CARGO_BUILD_RUSTC",
            "CARGO_BUILD_RUSTC_WRAPPER", "CARGO_BUILD_RUSTC_WORKSPACE_WRAPPER",
            "CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS",
            "CARGO_BUILD_RUSTFLAGS", "CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS", "PKG_CONFIG", "GOCACHEPROG"}
        selectors.update(prefix+tool+suffix for prefix in ("", "HOST_", "TARGET_")
            for tool in ("CC", "CXX", "FC", "AR", "LD", "AS", "RANLIB")
            for suffix in ("", "_aarch64_apple_darwin", "_aarch64-apple-ios-sim"))
        tool = self.root/"selected-tool"
        tool.write_text("modeled tool")
        tool.chmod(0o700)
        for name in sorted(selectors):
            value = ("-C\x1flinker="+str(tool) if name == "CARGO_ENCODED_RUSTFLAGS" else
                     "-C linker="+str(tool) if name.endswith("RUSTFLAGS") else str(tool))
            with self.subTest(selector=name):
                self.assertIn(str(tool), INPUTS.configured_tool_inputs({name:value}, (), self.root)[
                    "executables_sha256"])
        # Path.home() reads HOME; Go reports effective settings of the same names.
        names = read | selectors | {"HOME", "GOROOT", "GOTOOLDIR", "GOENV", "GOMODCACHE"}
        hashed = INPUTS.build_environment_inputs({name:"model" for name in names})[0]
        self.assertEqual(sorted(names - set(hashed)), [])


if __name__ == "__main__":
    unittest.main()
