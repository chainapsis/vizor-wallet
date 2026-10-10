"""Real bundles, aliases, original groups and locks; SDK/signing are modeled."""
from pathlib import Path
from datetime import datetime, timezone
import json
import os
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_build_cache as CACHE
import native_ios_cleanup as NATIVE
from native_case_lifecycle import NativeCaseLifecycle
from native_workspace import prepare_native_case_workspace


class CacheTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="native-build-cache-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.inputs = {"schema":1, "platform":"ios", "model":"source/toolchain"}
        self.cancel = threading.Event()
        self.cases = []
        self.addCleanup(lambda:[case.close() for case in self.cases])
        self.apps = {}
        for role, executable in (("cohort","Runner"), ("helper","vizor-ios-cleanup")):
            app = self.root/(role+".app")
            app.mkdir(mode=0o700)
            (app/executable).write_bytes(b"modeled signed Mach-O")
            (app/executable).chmod(0o700)
            (app/"Info.plist").write_text("modeled info")
            framework = app/"Frameworks/Foo.framework/Versions/A"
            framework.mkdir(parents=True)
            (framework/"Foo").write_bytes(b"modeled framework bytes")
            (framework/"Foo").chmod(0o700)
            (framework.parent/"Current").symlink_to("A", target_is_directory=True)
            (framework.parent.parent/"Foo").symlink_to("Versions/Current/Foo")
            self.apps[role] = NATIVE._SimulatorApp(app, app/executable,
                "MODELTEAM1.com.keplr.vizor", "arm64", (), ())
        self.captured = NATIVE.CapturedIosCleanupHelper(self.apps["helper"],self.apps["cohort"],NATIVE._CAPTURE_TOKEN)
        observation = patch.object(NATIVE,"_inspect_app",side_effect=lambda path,helper:
            self.apps["helper" if helper else "cohort"])
        observation.start()
        self.addCleanup(observation.stop)

    def case(self, *, close=True, code=0):
        case = NativeCaseLifecycle(prepare_native_case_workspace(self.root,platform="ios",
            scenario_id="flutter.ios.native-build",run_id="abcdef0123",worker_id=0,
            case_index=len(self.cases),ports={"rpc":28232,"lwd":29067,"proxy":29068},activation_height=1))
        self.cases.append(case)
        case.run_command([sys.executable,"-B","-c",f"raise SystemExit({code})"],
            env=os.environ.copy(),timeout=2,cancel_event=self.cancel)
        if close:
            case.close()
        return case

    def lease(self, **kwargs):
        return CACHE.NativeCohortCacheLease(self.root/"cache", self.inputs,
            timeout=2,cancel_event=self.cancel,**kwargs)

    def publish(self, lease):
        lease.publish(CACHE.ProducedNativeCohort(self.case(),self.captured,self.inputs,CACHE._TOKEN))

    def test_original_publication_warm_lookup_and_private_copy_preserve_framework_aliases(self):
        with self.lease() as lease:
            self.assertIsNone(lease.load())
            self.publish(lease)
            paths = lease.load()
            owner = self.case(close=False)
            copies = lease.materialize(owner,paths)
            self.assertNotEqual(copies,paths)
            for role in self.apps:
                self.assertEqual(CACHE._bundle(copies[role]),CACHE._bundle(paths[role],immutable=True))
                self.assertNotEqual((copies[role]/self.apps[role].executable.name).stat().st_ino,
                                    (paths[role]/self.apps[role].executable.name).stat().st_ino)
                self.assertEqual(os.readlink(copies[role]/"Frameworks/Foo.framework/Foo"),"Versions/Current/Foo")
            owner.close()
        with self.lease() as lease:
            self.assertEqual(lease.load(),paths)

    def test_joined_sdk_group_writable_resource_is_copied_and_sealed_not_changed(self):
        resource = self.apps["cohort"].path/"MaterialIcons-Regular.otf"
        resource.write_bytes(b"modeled SDK font")
        resource.chmod(0o664)
        with self.lease() as lease:
            self.publish(lease)
            cached = lease.load()["cohort"]/resource.name
            self.assertEqual(cached.read_bytes(),resource.read_bytes())
            self.assertEqual(cached.stat().st_mode & 0o777,0o400)
            self.assertEqual(cached.stat().st_nlink,1)
            self.assertNotEqual(cached.stat().st_ino,resource.stat().st_ino)
            self.assertEqual(resource.stat().st_mode & 0o777,0o664)

    def test_fresh_publications_allow_sdk_staging_without_unsealing_cache(self):
        with self.lease() as lease:
            self.publish(lease)
            paths = lease.load()
            copies = lease.materialize(self.case(close=False),paths)
            for role,app in self.apps.items():
                self.assertEqual(copies[role].stat().st_mode & 0o777,0o700)
                self.assertEqual((copies[role]/app.executable.name).stat().st_mode & 0o777,0o700)
                self.assertEqual((copies[role]/"Info.plist").stat().st_mode & 0o777,0o600)
                self.assertEqual((copies[role]/"Frameworks/Foo.framework/Versions/A").stat().st_mode & 0o777,0o700)
                self.assertEqual(paths[role].stat().st_mode & 0o777,0o500)
                self.assertEqual((paths[role]/app.executable.name).stat().st_mode & 0o777,0o500)
                self.assertEqual((paths[role]/"Info.plist").stat().st_mode & 0o777,0o400)
                self.assertEqual(CACHE._bundle(copies[role]),CACHE._bundle(paths[role],immutable=True))
            (copies["helper"]/"sdk-staging-model").write_text("independent SDK copy")
            self.assertEqual(lease.load(),paths)

    def test_one_run_copy_cannot_mutate_cached_or_sibling_bytes(self):
        with self.lease() as lease:
            self.publish(lease)
            first = lease.materialize(self.case(close=False),lease.load())
            second = lease.materialize(self.case(close=False),lease.load())
            executable = first["cohort"]/"Runner"
            executable.chmod(0o700)
            executable.write_bytes(b"changed private run")
            self.assertEqual((second["cohort"]/"Runner").read_bytes(),b"modeled signed Mach-O")
            self.assertEqual((lease.load()["cohort"]/"Runner").read_bytes(),b"modeled signed Mach-O")

    def test_entire_bundle_resource_corruption_fails_without_replacement(self):
        with self.lease() as lease:
            self.publish(lease)
            resource = lease.load()["cohort"]/"Frameworks/Foo.framework/Versions/A/Foo"
            resource.chmod(0o700)
            resource.write_bytes(b"changed framework, unchanged top-level executable")
            resource.chmod(0o500)
            with self.assertRaisesRegex(CACHE.NativeBuildCacheError,"bytes changed"):
                lease.load()
            self.assertEqual(resource.read_bytes(),b"changed framework, unchanged top-level executable")

    def test_unjoined_failed_or_external_producer_cannot_publish(self):
        with self.lease() as lease:
            for owner in (self.case(close=False),self.case(code=7)):
                with self.assertRaisesRegex(CACHE.NativeBuildCacheError,"positively join"):
                    CACHE.ProducedNativeCohort(owner,self.captured,self.inputs,CACHE._TOKEN)
            with self.assertRaisesRegex(CACHE.NativeBuildCacheError,"original joined"):
                lease.publish({"completed":True,"apps":self.apps})
            self.assertIsNone(lease.load())

    def test_external_absolute_or_escaping_framework_alias_is_rejected(self):
        outside = self.root/"outside"
        outside.write_text("developer data")
        app = self.apps["cohort"].path
        for target in (str(outside),"../outside"):
            alias = app/"bad-link"
            alias.symlink_to(target)
            try:
                with self.assertRaisesRegex(CACHE.NativeBuildCacheError,"escapes"):
                    CACHE._bundle(app)
            finally:
                alias.unlink()
        self.assertEqual(outside.read_text(),"developer data")

    def test_writable_or_partial_entry_is_not_a_cache_hit(self):
        with self.lease() as lease:
            self.publish(lease)
            lease.entry.chmod(0o700)
            with self.assertRaisesRegex(CACHE.NativeBuildCacheError,"attachment/inventory"):
                lease.load()
            lease.entry.chmod(0o500)
            folder = lease.load()["helper"]/"Frameworks"
            folder.chmod(0o700)
            with self.assertRaisesRegex(CACHE.NativeBuildCacheError,"writable"):
                lease.load()


class InputTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="native-cache-inputs-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.package = self.root/"dependency"
        self.package.mkdir(mode=0o700)
        (self.package/"source.dart").write_text("initial dependency")
        (self.root/".dart_tool").mkdir()
        self.configuration = self.root/".dart_tool/package_config.json"
        self.configuration.write_text(json.dumps({"configVersion":2,"packages":[{
            "name":"dependency","rootUri":self.package.as_uri(),"packageUri":"lib/","languageVersion":"3.11"}]}))
        (self.root/"ios").mkdir()
        self.lock = self.root/"ios/Podfile.lock"
        self.lock.write_text("PODS:\n  - Local (1.0)\nEXTERNAL SOURCES:\n  Local:\n    :path: source\n"
            "SPEC CHECKSUMS:\n  Local: "+"a"*40+"\n  Remote: "+"b"*40+"\nCOCOAPODS: 1.16.2\n")
        (self.root/"macos").mkdir()
        (self.root/"macos/Podfile.lock").write_text(self.lock.read_text())
        toolchain = self.root/"toolchain"
        toolchain.mkdir()
        self.rust_sysroot = self.root/"rust-sysroot"
        self.rust_libraries = (self.rust_sysroot/"lib/libLLVM.dylib",
                               self.rust_sysroot/"lib/rustlib/host/lib/libstd.rlib")
        for path in self.rust_libraries:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original Rust compiler/runtime library")
        self.rust_tools = {name:toolchain/name for name in ("rustc", "cargo")}
        for name, path in self.rust_tools.items():
            path.write_text("original "+name+" executable")
            path.chmod(0o700)
        self.sdk = self.root/"flutter-sdk"
        self.tool = self.sdk/"bin/flutter"
        self.tool.parent.mkdir(parents=True)
        self.tool.write_text("model Flutter executable")
        self.sdk_files = (
            "bin/cache/flutter_tools.snapshot", "bin/cache/dart-sdk/bin/dart",
            "bin/cache/dart-sdk/bin/dartvm", "bin/cache/dart-sdk/bin/dartaotruntime",
            "bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot",
            "bin/cache/dart-sdk/bin/snapshots/kernel-service.dart.snapshot",
            "bin/cache/dart-sdk/bin/snapshots/dartdev_aot.dart.snapshot",
        )
        for name in self.sdk_files:
            path = self.sdk/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original compiler "+name)
            if path.name in {"dart", "dartvm", "dartaotruntime"}:
                path.chmod(0o700)
        self.sdk_trees = (
            "packages/flutter_tools", "bin/internal", "bin/cache/dart-sdk/lib",
            "bin/cache/artifacts/engine/common/flutter_patched_sdk",
            "bin/cache/artifacts/engine/ios", "bin/cache/artifacts/engine/darwin-x64",
        )
        for name in self.sdk_trees:
            path = self.sdk/name/"artifact"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original SDK artifact "+name)
        self.home = self.root/"developer-home"
        self.home.mkdir()
        home = patch.object(CACHE.Path, "home", return_value=self.home)
        home.start()
        self.addCleanup(home.stop)
        self.profile_payload = {"ExpirationDate":datetime(2099, 1, 1),
                                "privateDeviceData":"must not appear in cache inputs"}
        self.apple = self.root/"Xcode.app/Contents/Developer"
        self.apple_tools = {name:self.apple/"usr/bin"/name for name in (
            "xcodebuild", "clang", "swiftc", "swift-frontend", "ld", "actool", "ibtool", "dsymutil", "strip")}
        self.host_tools = {name:self.root/"host/bin"/name for name in ("xcrun", "codesign", "security", "ruby", "pod")}
        for name, path in {**self.apple_tools, **self.host_tools}.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original "+name+" executable")
            path.chmod(0o700)
        self.host_tools["pod"].write_text("#!"+str(self.host_tools["ruby"])+"\noriginal pod launcher")
        self.apple_trees = (self.apple/"usr/lib", self.apple.parent/"SharedFrameworks/XCBuild.framework",
            self.root/"native-sdk-ios", self.root/"native-sdk-macos",
            self.root/"ruby-libraries", self.root/"ruby-gems")
        for path in self.apple_trees:
            path.mkdir(parents=True)
            (path/"artifact").write_text("original native compiler/library input")
        system = patch.object(CACHE, "_APPLE_SYSTEM_TOOLS", {
            name:self.host_tools[name] for name in ("xcrun", "codesign", "security")})
        system.start()
        self.addCleanup(system.stop)
        self.cancel = threading.Event()

    def command(self, args, **_):
        if "--machine" in args:
            return (json.dumps({"frameworkRevision":"flutter", "engineRevision":"engine", "dartSdkVersion":"3.13"}),)
        if args == ["rustup","toolchain","list"]:
            return ("stable-aarch64-apple-darwin (default)",)
        if len(args) == 5 and args[:3] == ["rustup", "which", "--toolchain"]:
            return (str(self.rust_tools[args[-1]]),)
        if args == [str(self.rust_tools["rustc"]), "--print", "sysroot"]:
            return (str(self.rust_sysroot)+"\n",)
        if args[:2] == [sys.executable, "-c"] and "'cms'" in args[2]:
            expiry = self.profile_payload["ExpirationDate"]
            return (json.dumps({"expires_at":expiry.replace(tzinfo=timezone.utc).isoformat()}),)
        if args[0] == "/usr/bin/which":
            return (str(self.host_tools[args[-1]])+"\n",)
        if args[0] == "/usr/bin/xcrun" and "--find" in args:
            return (str(self.apple_tools[args[-1]])+"\n",)
        if args[0] == "/usr/bin/xcrun" and "--show-sdk-path" in args:
            return (str(self.root/("native-sdk-ios" if "iphonesimulator" in args else "native-sdk-macos"))+"\n",)
        if args[0] == str(self.host_tools["ruby"]) and "-e" in args:
            return (json.dumps({"ruby":str(self.host_tools["ruby"]),
                                "shared_library":str(self.host_tools["ruby"]),
                                "roots":[str(path) for path in self.apple_trees[-2:]]}),)
        return ("modeled tool/SDK version",)

    def inputs(self, *, platform="ios", environment=None, **options):
        return CACHE.collect_native_cache_inputs(self.root,{self.tool:CACHE._capture(self.tool)},self.tool,
            platform=platform,architecture="arm64",command=self.command,
            environment={"RUSTFLAGS":"private compiler flags"} if environment is None else environment,
            cancel=self.cancel,**options)

    def test_configured_environment_tool_bytes_invalidate_without_setting_changes(self):
        wrapper = self.root/"custom-wrapper"
        wrapper.write_text("original custom build tool")
        wrapper.chmod(0o700)
        variables = ("RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "CC", "CC_aarch64_apple_ios",
                     "CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS",
                     "CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS", "CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS")
        for platform in ("ios", "macos"):
            for name in variables:
                with self.subTest(platform=platform, variable=name):
                    wrapper.write_text("original "+platform+name)
                    value = ("-C\x1flinker="+str(wrapper) if name == "CARGO_ENCODED_RUSTFLAGS" else
                             "-C linker="+str(wrapper) if name.endswith("RUSTFLAGS") else str(wrapper))
                    environment = {name:value}
                    first = self.inputs(platform=platform, environment=environment)
                    wrapper.write_text("changed custom tool bytes")
                    second = self.inputs(platform=platform, environment=environment)
                    self.assertEqual(first["environment_sha256"], second["environment_sha256"])
                    self.assertNotEqual(first, second)

    def test_cargo_configured_tool_and_included_file_bytes_invalidate(self):
        directory = self.root/"rust/.cargo"
        directory.mkdir(parents=True)
        tool = self.root/"rust/custom linker"
        tool.write_text("original configured linker")
        tool.chmod(0o700)
        extra = directory/"extra.toml"
        extra.write_text("[target.'cfg(target_os = \"ios\")']\nlinker = \"./custom linker\"\n")
        config = directory/"config.toml"
        config.write_text('include = ["extra.toml"]\n[build]\nrustc-wrapper = "./custom linker"\n')
        first = self.inputs()
        tool.write_text("changed configured linker")
        second = self.inputs()
        self.assertEqual(first["cargo_config_sha256"], second["cargo_config_sha256"])
        self.assertNotEqual(first, second)
        first = second
        extra.write_text(extra.read_text()+"\n# included configuration update\n")
        second = self.inputs()
        self.assertEqual(first["cargo_config_sha256"], second["cargo_config_sha256"])
        self.assertNotEqual(first, second)

    def test_configured_cargo_path_resolves_bare_tool_without_changing_settings(self):
        directory = self.root/"rust/.cargo"
        directory.mkdir(parents=True)
        tool = self.root/"rust/tools/custom-linker"
        tool.parent.mkdir()
        tool.write_text("original PATH-selected custom linker")
        tool.chmod(0o700)
        (directory/"config.toml").write_text(
            '[env]\nPATH = { value = "./tools", relative = true, force = true }\n'
            '[target.aarch64-apple-ios-sim]\nlinker = "custom-linker"\n')
        environment = {"PATH":str(self.root/"empty-path")}
        first = self.inputs(environment=environment)
        tool.write_text("patched PATH-selected linker")
        second = self.inputs(environment=environment)
        self.assertEqual(first["cargo_config_sha256"], second["cargo_config_sha256"])
        self.assertEqual(first["environment_sha256"], second["environment_sha256"])
        self.assertNotEqual(first, second)
        self.assertIn(str(tool), first["configured_tools"]["executables_sha256"])

    def test_native_rust_executable_bytes_invalidate_with_unchanged_versions(self):
        for platform in ("ios", "macos"):
            for name, executable in self.rust_tools.items():
                with self.subTest(platform=platform, tool=name):
                    first = self.inputs(platform=platform)
                    executable.write_text(platform+" patched "+name+" executable")
                    second = self.inputs(platform=platform)
                    for tool in ("rustc", "cargo"):
                        self.assertEqual(first["rust_toolchains"]["stable"][tool],
                                         second["rust_toolchains"]["stable"][tool])
                    self.assertNotEqual(first, second)

    def test_rust_sysroot_changes_invalidate_without_compiler_or_version_changes(self):
        for platform in ("ios", "macos"):
            for path in self.rust_libraries:
                with self.subTest(platform=platform, input=path):
                    first = self.inputs(platform=platform)
                    path.write_text("patched "+platform+" Rust sysroot library")
                    second = self.inputs(platform=platform)
                    self.assertEqual(first["rust_toolchains"]["stable"]["rustc_sha256"],
                                     second["rust_toolchains"]["stable"]["rustc_sha256"])
                    self.assertEqual(first["rust_toolchains"]["stable"]["rustc"],
                                     second["rust_toolchains"]["stable"]["rustc"])
                    self.assertNotEqual(first, second)

    def test_installed_pod_sources_invalidate_without_lock_or_package_changes(self):
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform):
                path = self.root/platform/"Pods/LocalPod/Sources/native.m"
                path.parent.mkdir(parents=True)
                path.write_text("original installed Pod source")
                first = self.inputs(platform=platform)
                path.write_text("patched installed Pod source")
                second = self.inputs(platform=platform)
                self.assertEqual(first["pod_lock_sha256"], second["pod_lock_sha256"])
                self.assertEqual(first["package_config"], second["package_config"])
                self.assertNotEqual(first, second)

    def test_native_flutter_helper_sources_invalidate_without_snapshot_or_version_changes(self):
        names = ("bin/xcode_backend.sh", "bin/xcode_backend.dart", "bin/macos_assemble.sh",
                 "bin/podhelper.rb", "lib/src/build_system/build_system.dart")
        for name in names:
            path = self.sdk/"packages/flutter_tools"/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original native Flutter build source")
        for platform in ("ios", "macos"):
            for name in names:
                with self.subTest(platform=platform, input=name):
                    path = self.sdk/"packages/flutter_tools"/name
                    first = self.inputs(platform=platform)
                    path.write_text("patched "+platform+" native Flutter build source")
                    second = self.inputs(platform=platform)
                    self.assertEqual(first["flutter"], second["flutter"])
                    self.assertEqual(first["flutter_sdk"]["files_sha256"],
                                     second["flutter_sdk"]["files_sha256"])
                    self.assertNotEqual(first, second)

    def test_installed_provisioning_profile_bytes_invalidate_with_same_certificate(self):
        for directory in ("Library/Developer/Xcode/UserData/Provisioning Profiles",
                          "Library/MobileDevice/Provisioning Profiles"):
            with self.subTest(directory=directory):
                profile = self.home/directory/"automatic.mobileprovision"
                profile.parent.mkdir(parents=True)
                profile.write_bytes(b"original profile")
                first = self.inputs(platform="macos")
                profile.write_bytes(b"renewed profile, unchanged signing certificate")
                second = self.inputs(platform="macos")
                self.assertEqual(first["signing_identities_sha256"], second["signing_identities_sha256"])
                self.assertNotEqual(first, second)
                self.assertNotIn("must not appear", json.dumps(second))

    def test_apple_compilers_sdk_and_ruby_pod_sources_invalidate_with_same_versions(self):
        for platform in ("ios", "macos"):
            sdk = self.apple_trees[2 if platform == "ios" else 3]
            artifacts = (*self.apple_tools.values(), *self.host_tools.values(),
                         *(path/"artifact" for path in (self.apple_trees[0], self.apple_trees[1],
                                                        sdk, *self.apple_trees[-2:])))
            for path in artifacts:
                with self.subTest(platform=platform, artifact=path.name):
                    first = self.inputs(platform=platform)
                    if path == self.host_tools["pod"]:
                        path.write_text(path.read_text()+"\npatched pod launcher")
                    else:
                        path.write_text("patched "+platform+" native input")
                    second = self.inputs(platform=platform)
                    for field in ("xcode", "sdk", "cocoapods", "ruby"):
                        self.assertEqual(first[field], second[field])
                    self.assertNotEqual(first, second)

    def test_installed_tool_hardlinks_do_not_relax_output_artifact_ownership(self):
        tool = self.host_tools["ruby"]
        os.link(tool, tool.with_name("ruby-alias"))
        self.assertEqual(CACHE._tool_input_record(tool)[1],
                         CACHE.hashlib.sha256(tool.read_bytes()).hexdigest())
        with self.assertRaises(CACHE.tree.OwnedTreeError):
            CACHE._file_record(tool)

    def test_tool_aliases_require_explicit_separately_hashed_inputs(self):
        libraries, site = self.apple_trees[-2:]
        library = self.host_tools["ruby"]
        (libraries/"shared-library").symlink_to(os.path.relpath(library, libraries))
        (libraries/"site-ruby").symlink_to(os.path.relpath(site, libraries))
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "link escapes"):
            CACHE._package_digest(libraries, self.cancel)
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "link escapes"):
            CACHE._package_digest(libraries, self.cancel, linked_files=frozenset({library}))
        before = self.inputs()
        library.write_text("patched Ruby shared library")
        self.assertNotEqual(before, self.inputs())
        before = self.inputs()
        (site/"artifact").write_text("patched site Ruby source")
        self.assertNotEqual(before, self.inputs())
        (libraries/"unbound-source").symlink_to(os.path.relpath(self.tool, libraries))
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "link escapes"):
            self.inputs()

    def test_package_digest_retains_default_byte_bound(self):
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "exceeds its bound"):
            CACHE._package_digest(self.apple_trees[-1], self.cancel, max_bytes=1)

    def test_writable_tool_or_parent_and_alias_input_are_rejected(self):
        tool = self.host_tools["ruby"]
        tool.chmod(0o777)
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "protected bounded file"):
            CACHE._tool_input_record(tool)
        tool.chmod(0o700)
        tool.parent.chmod(0o777)
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "parent is not protected"):
            CACHE._tool_input_record(tool)
        tool.parent.chmod(0o700)
        alias = tool.with_name("ruby-alias")
        alias.symlink_to(tool)
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "must be canonical"):
            CACHE._tool_input_record(alias)

    def test_profile_expiration_invalidates_without_byte_or_certificate_changes(self):
        profile = self.home/"Library/Developer/Xcode/UserData/Provisioning Profiles/test.mobileprovision"
        profile.parent.mkdir(parents=True)
        profile.write_bytes(b"unchanged installed profile")
        original = CACHE._macos_provisioning_inputs
        before, after = datetime(2098, 12, 31, tzinfo=timezone.utc), datetime(2099, 1, 1, tzinfo=timezone.utc)
        with patch.object(CACHE, "_macos_provisioning_inputs",
                side_effect=lambda command, cancel:original(command, cancel, now=before)):
            first = self.inputs(platform="macos")
        with patch.object(CACHE, "_macos_provisioning_inputs",
                side_effect=lambda command, cancel:original(command, cancel, now=after)):
            second = self.inputs(platform="macos")
        self.assertNotEqual(first, second)
        self.assertEqual(first["signing_identities_sha256"], second["signing_identities_sha256"])
        self.assertEqual(profile.read_bytes(), b"unchanged installed profile")

    def test_ios_collection_does_not_decode_host_provisioning_profiles(self):
        with patch.object(CACHE, "_macos_provisioning_inputs") as inspect:
            self.assertIsNone(self.inputs()["provisioning_profiles"])
        inspect.assert_not_called()

    def test_profile_change_during_expiry_query_and_invalid_expiry_are_rejected(self):
        profile = self.home/"Library/Developer/Xcode/UserData/Provisioning Profiles/test.mobileprovision"
        profile.parent.mkdir(parents=True)
        profile.write_bytes(b"original installed profile")
        original = self.command

        def command(args, **options):
            result = original(args, **options)
            if args[:2] == [sys.executable, "-c"] and "'cms'" in args[2]:
                profile.write_bytes(b"changed during original query")
            return result

        with patch.object(self, "command", side_effect=command):
            with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "profile changed"):
                self.inputs(platform="macos")
        for expiry in (None, "not-a-date", "2099-01-01T00:00:00"):
            with self.subTest(expiry=expiry):
                with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "expiry is invalid"):
                    CACHE._macos_provisioning_inputs(
                        lambda *_args, **_options:(json.dumps({"expires_at":expiry}),), self.cancel)

    def test_native_rust_resolution_rejects_missing_relative_and_multiple_paths(self):
        original = self.command
        for paths in ((), ("relative/rustc",), (str(self.rust_tools["rustc"]),)*2):
            with self.subTest(paths=paths):
                def command(args, **options):
                    if args[:2] == ["rustup", "which"]:
                        return paths
                    return original(args, **options)
                with patch.object(self, "command", side_effect=command):
                    with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "one absolute"):
                        self.inputs()

    def test_native_rust_resolution_accepts_original_process_line_endings(self):
        first = self.inputs()
        original = self.command

        for ending in ("\n", "\r\n"):
            with self.subTest(ending=ending):
                def command(args, **options):
                    result = original(args, **options)
                    if args[:2] == ["rustup", "which"]:
                        return tuple(line+ending for line in result)
                    return result

                with patch.object(self, "command", side_effect=command):
                    self.assertEqual(first, self.inputs())

    def test_flutter_compiler_and_selected_engine_bytes_invalidate_with_same_versions(self):
        for platform in ("ios", "macos"):
            engine = "ios" if platform == "ios" else "darwin-x64"
            artifacts = (*self.sdk_files,
                "bin/internal/artifact", "bin/cache/dart-sdk/lib/artifact",
                "bin/cache/artifacts/engine/common/flutter_patched_sdk/artifact",
                "bin/cache/artifacts/engine/"+engine+"/artifact")
            for name in artifacts:
                with self.subTest(platform=platform, artifact=name):
                    first = self.inputs(platform=platform)
                    (self.sdk/name).write_text(platform+" patched "+name)
                    second = self.inputs(platform=platform)
                    self.assertEqual(first["flutter"], second["flutter"])
                    self.assertNotEqual(first, second)

    def test_unselected_platform_engine_does_not_invalidate(self):
        for platform, other in (("ios", "darwin-x64"), ("macos", "ios")):
            with self.subTest(platform=platform):
                first = self.inputs(platform=platform)
                (self.sdk/"bin/cache/artifacts/engine"/other/"artifact").write_text("other engine patched")
                self.assertEqual(first, self.inputs(platform=platform))

    def test_sdk_artifact_tree_does_not_ignore_generated_directory_names(self):
        for name in ("build", "target", ".git", ".dart_tool", ".regtest-logs", "__pycache__"):
            with self.subTest(directory=name):
                first = self.inputs()
                artifact = self.sdk/"bin/internal"/name/"artifact"
                artifact.parent.mkdir()
                artifact.write_text("SDK input even under a generated-looking name")
                self.assertNotEqual(first, self.inputs())

    def test_sdk_artifact_tree_rejects_an_alias(self):
        artifact = self.sdk/"bin/internal"
        original = self.sdk/"bin/original-internal"
        artifact.rename(original)
        artifact.symlink_to(original, target_is_directory=True)
        with self.assertRaisesRegex(CACHE.NativeBuildCacheError, "must be canonical"):
            self.inputs()

    def test_dependency_contents_platform_flags_and_tool_identity_invalidate(self):
        first = self.inputs()
        (self.package/"source.dart").write_text("modified dependency")
        second = self.inputs()
        self.assertNotEqual(first,second)
        self.assertNotEqual(second,self.inputs(tex_address="different fixture"))
        self.assertNotIn("private compiler flags",json.dumps(second))

    def test_generated_package_metadata_and_local_pod_checksum_do_not_invalidate(self):
        first = self.inputs()
        config = json.loads(self.configuration.read_text())
        config["generated"] = "new pub-get timestamp"
        self.configuration.write_text(json.dumps(config))
        self.lock.write_text(self.lock.read_text().replace("a"*40,"c"*40))
        self.assertEqual(first,self.inputs())
        self.lock.write_text(self.lock.read_text().replace("b"*40,"d"*40))
        self.assertNotEqual(first,self.inputs())

    def test_nested_generated_directory_names_are_source_inputs(self):
        for name in ("build", "target", ".git", ".dart_tool", ".regtest-logs", "__pycache__"):
            with self.subTest(directory=name):
                source = self.package/"lib/src"/name/"code.dart"
                source.parent.mkdir(parents=True)
                source.write_text("original compiled source")
                first = self.inputs()["package_config"]["dependency"]["sha256"]
                source.write_text("changed compiled source")
                self.assertNotEqual(first,self.inputs()["package_config"]["dependency"]["sha256"])

    def test_generated_directories_at_package_root_do_not_invalidate(self):
        first = self.inputs()
        for name in ("build", "target", ".git", ".dart_tool", ".regtest-logs", "__pycache__"):
            with self.subTest(directory=name):
                output = self.package/name/"generated.dart"
                output.parent.mkdir()
                output.write_text("generated output")
                self.assertEqual(first,self.inputs())
                output.write_text("changed generated output")
                self.assertEqual(first,self.inputs())

    def test_pod_version_and_package_source_changes_are_not_normalized_away(self):
        first = self.inputs()
        self.lock.write_text(self.lock.read_text().replace("Local (1.0)","Local (2.0)"))
        self.assertNotEqual(first,self.inputs())


if __name__ == "__main__":
    unittest.main()
