"""Real bundles, aliases, original groups and locks; SDK/signing are modeled."""
from pathlib import Path
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
        self.tool = self.root/"flutter"
        self.tool.write_text("model Flutter executable")
        self.cancel = threading.Event()

    def command(self, args, **_):
        if "--machine" in args:
            return (json.dumps({"frameworkRevision":"flutter", "engineRevision":"engine", "dartSdkVersion":"3.13"}),)
        if args == ["rustup","toolchain","list"]:
            return ("stable-aarch64-apple-darwin (default)",)
        return ("modeled tool/SDK version",)

    def inputs(self, **options):
        return CACHE.collect_native_cache_inputs(self.root,{self.tool:CACHE._capture(self.tool)},self.tool,
            platform="ios",architecture="arm64",command=self.command,
            environment={"RUSTFLAGS":"private compiler flags"},cancel=self.cancel,**options)

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

    def test_pod_version_and_package_source_changes_are_not_normalized_away(self):
        first = self.inputs()
        self.lock.write_text(self.lock.read_text().replace("Local (1.0)","Local (2.0)"))
        self.assertNotEqual(first,self.inputs())


if __name__ == "__main__":
    unittest.main()
