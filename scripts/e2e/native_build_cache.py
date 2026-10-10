"""Immutable signed cohort/helper pairs; never native storage or loose outputs."""
from __future__ import annotations

import contextlib
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import sys
import uuid
from urllib.parse import unquote, urlparse

from funder_cache import FunderCacheLease, FunderCacheError, _json, _read, _rename_exclusive
from funder_build import _file_record, _MAX_BINARY_BYTES
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
import toolchain_inputs
from native_zakura_front import _capture


_TOKEN = object()
_ROLES = ("cohort", "helper")
_APPLE_SYSTEM_TOOLS = {name:"/usr/bin/"+name for name in (
    "xcrun", "codesign", "security", "xcodebuild")}
_RUBY_INPUT_QUERY = (
    "require 'rubygems'; require 'rbconfig'; require 'json'; "
    "Gem.activate_bin_path('cocoapods','pod','>= 0.a'); require 'cocoapods'; "
    "roots=[RbConfig::CONFIG.fetch('libdir')]+$LOAD_PATH.select { |p| Dir.exist?(p) }; "
    "Gem.path.each { |p| %w[gems specifications extensions].each { |d| "
    "path=File.join(p,d); roots << path if Dir.exist?(path) } }; "
    "Gem.loaded_specs.each_value { |s| roots << s.full_gem_path unless s.default_gem?; "
    "roots << s.extension_dir if Dir.exist?(s.extension_dir) }; "
    "puts JSON.generate({ruby:RbConfig.ruby,roots:roots.uniq.sort,"
    "shared_library:File.join(RbConfig::CONFIG.fetch('libdir'),RbConfig::CONFIG.fetch('LIBRUBY'))})"
)
_PROFILE_EXPIRY_QUERY = (
    "import datetime,json,plistlib,subprocess,sys\n"
    "result=subprocess.run(['/usr/bin/security','cms','-D','-i',sys.argv[1]],"
    "check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)\n"
    "expiry=plistlib.loads(result.stdout)['ExpirationDate']\n"
    "if not isinstance(expiry,datetime.datetime): raise TypeError('invalid profile expiry')\n"
    "expiry=expiry.replace(tzinfo=datetime.timezone.utc) if expiry.tzinfo is None else expiry\n"
    "print(json.dumps({'expires_at':expiry.astimezone(datetime.timezone.utc).isoformat()}))\n"
)


class NativeBuildCacheError(FunderCacheError):
    """An immutable native build's inputs, bytes or original owner are unproven."""


def _tool_input_record(path, *, executable=False, limit=_MAX_BINARY_BYTES):
    return toolchain_inputs.file_record(path, executable=executable, limit=limit,
                                       error_type=NativeBuildCacheError)


def _original_bundle_file(path):
    # Joined SDK output can contain group-writable assets (Flutter's stock
    # Material Icons font). Never change that output or publish those modes:
    # bind exact bytes/attachment while copying, then seal independent files.
    descriptor = os.open(path, os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        before = os.fstat(descriptor)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid()
            or before.st_mode & 0o002 or before.st_nlink < 1 or before.st_size > _MAX_BINARY_BYTES
            or path.resolve(strict=True) != path):
            raise NativeBuildCacheError("original SDK resource is not a bounded owned regular file")
        digest, count = hashlib.sha256(), 0
        with os.fdopen(os.dup(descriptor),"rb") as reader:
            for chunk in iter(lambda:reader.read(1024*1024),b""):
                count += len(chunk)
                if count > _MAX_BINARY_BYTES:
                    raise NativeBuildCacheError("original SDK resource grew beyond its bound")
                digest.update(chunk)
        identity = tree.identity(before)
        if tree.identity(os.fstat(descriptor)) != identity or tree.identity(path.lstat()) != identity:
            raise NativeBuildCacheError("original SDK resource changed during inspection")
        return identity,digest.hexdigest()
    finally:
        os.close(descriptor)


def _bundle(path, *, immutable=False):
    """Inventory actual bytes and safe internal Framework aliases, never follow links."""
    path = Path(path)
    if not path.is_absolute() or path.resolve(strict=True) != path:
        raise NativeBuildCacheError("native bundle must be canonical")
    result, total = {}, 0
    for directory, children, files in os.walk(path, followlinks=False):
        current = Path(directory)
        details = current.lstat()
        tree.check(details, directory=True, private=immutable)
        directory_id = tree.identity(details)
        if immutable and stat.S_IMODE(details.st_mode) != 0o500:
            raise NativeBuildCacheError("cached bundle directory is writable")
        if len(current.relative_to(path).parts) > 48:
            raise NativeBuildCacheError("native bundle exceeds its depth bound")
        result[current.relative_to(path).as_posix()] = {"kind":"directory"}
        for name in (*children, *files):
            item = current/name
            details = item.lstat()
            relative = item.relative_to(path).as_posix()
            if stat.S_ISLNK(details.st_mode):
                target = os.readlink(item)
                resolved = item.resolve(strict=True)
                if (details.st_uid != os.getuid() or Path(target).is_absolute()
                    or not resolved.is_relative_to(path)):
                    raise NativeBuildCacheError("bundle alias escapes the original bundle")
                result[relative] = {"kind":"link", "target":target}
                if name in children:
                    children.remove(name)
            elif not stat.S_ISDIR(details.st_mode):
                record = (_file_record(item, limit=_MAX_BINARY_BYTES) if immutable
                          else _original_bundle_file(item))
                executable = bool(details.st_mode & stat.S_IXUSR)
                if immutable and stat.S_IMODE(details.st_mode) != (0o500 if executable else 0o400):
                    raise NativeBuildCacheError("cached bundle file is writable")
                result[relative] = {"kind":"file", "sha256":record[1],
                                    "size":details.st_size, "executable":executable}
                total += details.st_size
            if len(result) > 30_000 or total > 2*1024*1024*1024:
                raise NativeBuildCacheError("native bundle exceeds its inventory/byte bound")
        if tree.identity(current.lstat()) != directory_id:
            raise NativeBuildCacheError("native bundle directory changed")
    if not result:
        raise NativeBuildCacheError("native bundle is missing")
    return result


def _copy_bundle(source, destination, *, seal=False):
    before = _bundle(source)
    shutil.copytree(source, destination, symlinks=True, copy_function=shutil.copy2)
    if _bundle(source) != before or _bundle(destination) != before:
        raise NativeBuildCacheError("native bundle changed during copy")
    # Preserve sealed cache entries, not their modes in SDK staging copies.
    # CoreSimulator's copyfile staging cannot populate a copied read-only app
    # directory. Normalize only fresh independent inodes; never the source.
    for directory, children, files in os.walk(destination, topdown=not seal, followlinks=False):
        if not seal:
            Path(directory).chmod(0o700)
        for name in files:
            path = Path(directory)/name
            if not path.is_symlink():
                executable = bool(path.stat().st_mode & stat.S_IXUSR)
                path.chmod((0o500 if executable else 0o400) if seal
                           else (0o700 if executable else 0o600))
        if seal:
            Path(directory).chmod(0o500)
    if _bundle(destination, immutable=seal) != before:
        raise NativeBuildCacheError("native publication differs from original bytes")
    return before


def _package_digest(root, cancel, *, capture=_capture, ignore_generated=True,
                    max_bytes=1024*1024*1024, linked_files=frozenset(), linked_roots=frozenset()):
    return toolchain_inputs.tree_digest(root, cancel, capture=capture,
        ignore_generated=ignore_generated, max_bytes=max_bytes, linked_files=linked_files,
        linked_roots=linked_roots, error_type=NativeBuildCacheError)


def _pod_lock(path):
    # CocoaPods rewrites workspace-local podspec checksums. Bind their actual
    # checked package sources instead; preserve versions and remote checksums.
    _capture(path)
    lines = path.read_text().splitlines()
    local, section, current = set(), None, None
    for line in lines:
        if line and not line.startswith(" "):
            section, current = line, None
        elif section == "EXTERNAL SOURCES:":
            match = re.fullmatch(r"  ([A-Za-z0-9_.+-]+):", line)
            if match:
                current = match[1]
            elif current and line.startswith("    :path:"):
                local.add(current)
    section, normalized = None, []
    for line in lines:
        if line and not line.startswith(" "):
            section = line
        match = re.fullmatch(r"  ([A-Za-z0-9_.+-]+): [a-f0-9]{40}", line)
        normalized.append("  "+match[1]+": checked-local-source"
            if section == "SPEC CHECKSUMS:" and match and match[1] in local else line)
    return hashlib.sha256("\n".join(normalized).encode()).hexdigest()


def _flutter_sdk_inputs(tool, platform, cancel):
    # Both original builders produce debug native cohorts. Bind the actual
    # compiler/runtime, patched platform SDK and selected debug engine, not
    # just the launch script or Flutter's unchanged version metadata.
    if tool.name != "flutter" or tool.parent.name != "bin":
        raise NativeBuildCacheError("Flutter must resolve to the selected SDK's bin/flutter")
    sdk = tool.parent.parent
    files = (
        "bin/cache/flutter_tools.snapshot", "bin/cache/dart-sdk/bin/dart",
        "bin/cache/dart-sdk/bin/dartvm", "bin/cache/dart-sdk/bin/dartaotruntime",
        "bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot",
        "bin/cache/dart-sdk/bin/snapshots/kernel-service.dart.snapshot",
        "bin/cache/dart-sdk/bin/snapshots/dartdev_aot.dart.snapshot",
    )
    trees = ("bin/internal", "bin/cache/dart-sdk/lib",
        "bin/cache/artifacts/engine/common/flutter_patched_sdk",
        "bin/cache/artifacts/engine/"+("ios" if platform == "ios" else "darwin-x64"))
    def artifact_record(path):
        return _tool_input_record(path)
    for name in trees:
        path = sdk/name
        if path.resolve(strict=True) != path or not path.is_dir():
            raise NativeBuildCacheError("native Flutter SDK artifact tree must be canonical")
    return {"root":str(sdk), "files_sha256":{name:_tool_input_record(sdk/name,
                executable=Path(name).name in {"dart", "dartvm", "dartaotruntime"},
                limit=_MAX_BINARY_BYTES)[1] for name in files},
        "trees_sha256":{name:_package_digest(sdk/name, cancel,
            capture=artifact_record, ignore_generated=False) for name in trees}}


def _macos_provisioning_inputs(command, cancel, *, now=None):
    # Xcode selects automatic profiles during the build. Conservatively bind
    # both SDK-supported installed inventories, not a guessed selected UUID.
    now = datetime.now(timezone.utc) if now is None else now
    result = {}
    for name in ("Library/Developer/Xcode/UserData/Provisioning Profiles",
                 "Library/MobileDevice/Provisioning Profiles"):
        directory = Path.home()/name
        if not directory.exists() and not directory.is_symlink():
            result[str(directory)] = None
            continue
        if directory.resolve(strict=True) != directory or not directory.is_dir():
            raise NativeBuildCacheError("installed provisioning directory must be canonical")
        before = tree.identity(directory.lstat())
        paths = sorted(path for path in directory.iterdir()
                       if path.suffix in {".mobileprovision", ".provisionprofile"})
        if len(paths) > 2048:
            raise NativeBuildCacheError("installed provisioning inventory exceeds its bound")
        records = {}
        for path in paths:
            if cancel.is_set():
                from e2e_runtime import Cancelled
                raise Cancelled()
            record = _tool_input_record(path, limit=8*1024*1024)
            # Only expiry reaches original command logs, never profile device
            # lists, certificate payloads or other developer-account metadata.
            payload = json.loads("".join(command([sys.executable, "-c",
                _PROFILE_EXPIRY_QUERY, str(path)])))
            try:
                expiry = datetime.fromisoformat(payload["expires_at"])
                if expiry.tzinfo is None:
                    raise ValueError("profile expiry requires UTC offset")
            except (KeyError, TypeError, ValueError) as error:
                raise NativeBuildCacheError("installed provisioning expiry is invalid") from error
            if _tool_input_record(path, limit=8*1024*1024) != record:
                raise NativeBuildCacheError("installed provisioning profile changed during inspection")
            records[path.name] = {"sha256":record[1], "expires_at":expiry.isoformat(),
                                  "unexpired":now < expiry}
        if tree.identity(directory.lstat()) != before:
            raise NativeBuildCacheError("installed provisioning inventory changed during inspection")
        result[str(directory)] = records
    return result


def _native_apple_inputs(command, platform, cancel):
    def selected(arguments):
        lines = tuple(line.rstrip("\r\n") for line in command(arguments, in_source=True))
        if len(lines) != 1 or not Path(lines[0]).is_absolute():
            raise NativeBuildCacheError("native Apple tool must resolve to one absolute path")
        return Path(lines[0]).resolve(strict=True)

    sdk_name = "iphonesimulator" if platform == "ios" else "macosx"
    programs = {name:selected(["/usr/bin/xcrun", "--sdk", sdk_name, "--find", name])
        for name in ("xcodebuild", "clang", "swiftc", "swift-frontend", "ld",
                     "actool", "ibtool", "dsymutil", "strip")}
    programs.update({"system_"+name:Path(path).resolve(strict=True)
                     for name, path in _APPLE_SYSTEM_TOOLS.items()})
    programs.update({name:selected(["/usr/bin/which", name]) for name in ("pod", "ruby")})
    launcher = _tool_input_record(programs["pod"], executable=True)
    shebang = shlex.split(programs["pod"].read_text().splitlines()[0].removeprefix("#!"))
    if len(shebang) == 2 and shebang == ["/usr/bin/env", "ruby"]:
        interpreter = programs["ruby"]
    elif len(shebang) == 1 and Path(shebang[0]).is_absolute():
        interpreter = Path(shebang[0]).resolve(strict=True)
    else:
        raise NativeBuildCacheError("CocoaPods launcher must identify its Ruby interpreter")
    ruby = json.loads("".join(command([str(interpreter), "-e", _RUBY_INPUT_QUERY], in_source=True)))
    if (not isinstance(ruby, dict) or not isinstance(ruby.get("roots"), list)
        or not ruby["roots"] or len(ruby["roots"]) > 2048
        or not isinstance(ruby.get("ruby"), str) or not Path(ruby["ruby"]).is_absolute()):
        raise NativeBuildCacheError("native Ruby library inventory is invalid")
    programs["pod_ruby"] = Path(ruby["ruby"]).resolve(strict=True)
    library = ruby.get("shared_library")
    if not isinstance(library, str) or not Path(library).is_absolute():
        raise NativeBuildCacheError("native Ruby shared library must be absolute")
    library = Path(library).resolve(strict=True)
    library_record = _tool_input_record(library)
    if programs["pod_ruby"] != interpreter or _tool_input_record(programs["pod"], executable=True) != launcher:
        raise NativeBuildCacheError("CocoaPods interpreter or launcher changed during inspection")
    roots = {selected(["/usr/bin/xcrun", "--sdk", sdk_name, "--show-sdk-path"])}
    developer = programs["xcodebuild"].parent.parent.parent
    candidates = {programs[name].parent.parent/"lib" for name in ("clang", "swift-frontend")}
    candidates.update((developer/"usr/lib", developer.parent/"SharedFrameworks/XCBuild.framework"))
    roots.update(path.resolve(strict=True) for path in candidates if path.exists())
    for name in ruby["roots"]:
        if not isinstance(name, str) or not Path(name).is_absolute():
            raise NativeBuildCacheError("native Ruby source root must be absolute")
        roots.add(Path(name).resolve(strict=True))
    # Hash each real directory once; ancestors already include descendants.
    roots = {path for path in roots if not any(parent in roots for parent in path.parents)}
    for path in roots:
        if not path.is_dir():
            raise NativeBuildCacheError("native SDK/library input is not a directory")
    digests = {}
    for path in set(programs.values()):
        digests[path] = _tool_input_record(path, executable=True)[1]
    def capture(path):
        return _tool_input_record(path)
    return {"executables":{name:{"path":str(path), "sha256":digests[path]}
        for name, path in sorted(programs.items())},
        "shared_libraries":{str(library):library_record[1]},
        "source_trees_sha256":{str(path):_package_digest(path, cancel,
            capture=capture, ignore_generated=False, max_bytes=4*1024*1024*1024,
            linked_files=frozenset({library}), linked_roots=roots)
            for path in sorted(roots)}}


def collect_native_cache_inputs(root, source, tool, *, platform, architecture,
                                command, environment, cancel, tex_address=None):
    configuration = root/".dart_tool/package_config.json"
    raw = json.loads(configuration.read_text())
    if not isinstance(raw, dict) or raw.get("configVersion") != 2 or not isinstance(raw.get("packages"), list):
        raise NativeBuildCacheError("native package configuration is invalid")
    packages = {}
    for package in raw["packages"]:
        uri = urlparse(package["rootUri"])
        if uri.scheme not in {"", "file"} or uri.netloc not in {"", "localhost"} or uri.query or uri.fragment:
            raise NativeBuildCacheError("native package root is not a local file")
        package_root = Path(unquote(uri.path))
        if not package_root.is_absolute():
            package_root = configuration.parent/package_root
        package_root = package_root.resolve(strict=True)
        packages[package["name"]] = {"root":str(package_root), "package_uri":package["packageUri"],
            "language":package["languageVersion"], "sha256":None if package_root == root
            else _package_digest(package_root, cancel)}
    sdk = "iphonesimulator" if platform == "ios" else "macosx"
    flutter = json.loads("".join(command([str(tool), "--version", "--machine"], in_source=True)))
    if (not isinstance(flutter, dict) or any(not isinstance(flutter.get(name), str) or not flutter[name]
        for name in ("frameworkRevision", "engineRevision", "dartSdkVersion"))):
        raise NativeBuildCacheError("Flutter machine identity is incomplete")
    override = environment.get("VIZOR_RUST_TOOLCHAIN")
    if override:
        if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", override):
            raise NativeBuildCacheError("Cargokit override must be an exact Rust version")
        toolchains = (override,)
    elif (root/"rust/cargokit.yaml").exists():
        # Cargokit's published enum permits these three channels. Bind installed
        # candidates rather than parsing its YAML with a second implementation.
        host = {"arm64":"aarch64-apple-darwin", "x86_64":"x86_64-apple-darwin"}[architecture]
        installed = {line.split()[0] for line in command(["rustup","toolchain","list"], in_source=True) if line.strip()}
        toolchains = tuple(name for name in ("stable","beta","nightly") if name+"-"+host in installed)
    else:
        toolchains = ("stable",)  # The actual Cargokit default, not rustup's active toolchain.
    rust = {}
    for name in toolchains:
        records = {}
        for program, flag in (("rustc", "-vV"), ("cargo", "-V")):
            paths = tuple(line.rstrip("\r\n") for line in command(
                ["rustup", "which", "--toolchain", name, program], in_source=True))
            if len(paths) != 1 or not Path(paths[0]).is_absolute():
                raise NativeBuildCacheError("rustup must identify one absolute native Rust executable")
            executable = Path(paths[0]).resolve(strict=True)
            records[program] = list(command([str(executable), flag], in_source=True))
            records[program+"_binary"] = str(executable)
            records[program+"_sha256"] = _tool_input_record(executable, executable=True)[1]
        records["sysroot"] = toolchain_inputs.rust_toolchain_inputs(
            lambda args:command(args, in_source=True), Path(records["rustc_binary"]), cancel)
        rust[name] = records
    if not rust:
        raise NativeBuildCacheError("native Rust toolchain inventory is empty")
    cargo_home = Path(environment.get("CARGO_HOME", str(Path.home()/".cargo")))
    configurations = {cargo_home/name for name in ("config", "config.toml")}
    configurations.update(parent/".cargo"/name for parent in (root,*root.parents)
                          for name in ("config", "config.toml"))
    configurations.update(root/"rust/.cargo"/name for name in ("config", "config.toml"))
    return {"schema":1, "platform":platform, "architecture":architecture, "tex_address":tex_address,
        "source_sha256":{str(path.relative_to(root)) if path.is_relative_to(root) else str(path):record[1]
            for path,record in source.items() if path != configuration},
        "package_config":packages, "pod_lock_sha256":_pod_lock(root/platform/"Podfile.lock"),
        "flutter":flutter, "flutter_sdk":_flutter_sdk_inputs(tool, platform, cancel),
        "apple_toolchain":_native_apple_inputs(command, platform, cancel),
        "collector_sha256":_capture(Path(toolchain_inputs.__file__).resolve(strict=True))[1],
        "configured_tools":toolchain_inputs.configured_tool_inputs(environment, configurations, root/"rust"),
        "xcode":list(command(["/usr/bin/xcodebuild", "-version"])),
        "sdk":list(command(["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-build-version"])),
        "rust_toolchains":rust,
        "cocoapods":list(command(["pod", "--version"], in_source=True)),
        "ruby":list(command(["ruby", "--version"], in_source=True)),
        "signing_identities_sha256":hashlib.sha256("".join(command(
            ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])).encode()).hexdigest()
            if platform == "macos" else None,
        "provisioning_profiles":_macos_provisioning_inputs(command, cancel)
            if platform == "macos" else None,
        "cargo_config_sha256":{str(path):_capture(path)[1] for path in sorted(configurations) if path.exists() or path.is_symlink()},
        "environment_sha256":{name:hashlib.sha256(value.encode()).hexdigest() for name,value in sorted(environment.items())}}


class ProducedNativeCohort:
    """Original joined source-checking builder, not a caller's signing receipt."""
    def __init__(self, case, captured, inputs, token):
        if token is not _TOKEN:
            raise NativeBuildCacheError("only the original native builder may publish")
        self.case, self.captured, self.inputs = case, captured, inputs
        self.verify()

    def verify(self):
        from native_ios_cleanup import CapturedIosCleanupHelper
        from native_mac_cleanup import CapturedMacCleanupHelper
        if (not isinstance(self.case, NativeCaseLifecycle) or self.case.accepting_launches
            or self.case._receipt is None or not self.case._receipt.exit_codes
            or any(self.case._receipt.exit_codes)
            or not isinstance(self.captured, (CapturedIosCleanupHelper, CapturedMacCleanupHelper))):
            raise NativeBuildCacheError("native producer did not positively join successful original builds")
        self.case.workspace.verify_owned()
        self.captured.verify_unchanged()


class NativeCohortCacheLease(FunderCacheLease):
    """Same original per-key lock; lookup/publication is for full signed bundles."""
    def __init__(self, root, inputs, *, timeout, cancel_event):
        super().__init__(root, inputs, _ROLES, timeout=timeout, cancel_event=cancel_event)

    def load(self):
        self._check()
        if not self.entry.exists() and not self.entry.is_symlink():
            return None
        with contextlib.ExitStack() as stack:
            fd = tree.open_directory(stack, self.entry, private=True)
            identity = tree.identity(os.fstat(fd))
            if ((self.entry_id is not None and self.entry_id != identity)
                or stat.S_IMODE(os.fstat(fd).st_mode) != 0o500
                or set(os.listdir(fd)) != {"manifest.json", "cohort.app", "helper.app"}):
                raise NativeBuildCacheError("native cache attachment/inventory changed")
            self.entry_id = identity
        manifest = json.loads(_read(self.entry/"manifest.json", 16*1024*1024))
        if (not isinstance(manifest, dict) or set(manifest) != {"schema", "inputs", "bundles"}
            or type(manifest["schema"]) is not int or manifest["schema"] != 1
            or manifest["inputs"] != self.inputs or set(manifest["bundles"]) != set(_ROLES)):
            raise NativeBuildCacheError("native cache does not bind current build inputs")
        paths = {role:self.entry/(role+".app") for role in _ROLES}
        for role,path in paths.items():
            self._check()
            if _bundle(path, immutable=True) != manifest["bundles"][role]:
                raise NativeBuildCacheError("cached native bundle bytes changed")
        if tree.identity(self.entry.lstat()) != identity:
            raise NativeBuildCacheError("native cache publication was replaced")
        self._check()
        return paths

    def materialize(self, case, paths):
        if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches:
            raise NativeBuildCacheError("native cache hit requires a fresh original publication owner")
        case.workspace.verify_owned()
        if paths != self.load():
            raise NativeBuildCacheError("native cache paths are not the original validated entry")
        destination = case.workspace.root/"native-publication"
        destination.mkdir(mode=0o700)
        for role in _ROLES:
            _copy_bundle(paths[role], destination/(role+".app"))
        self.load()
        case.workspace.verify_owned()
        return {role:destination/(role+".app") for role in _ROLES}

    def publish(self, producer):
        if not isinstance(producer, ProducedNativeCohort) or producer.inputs != self.inputs:
            raise NativeBuildCacheError("only this key's original joined native producer may publish")
        producer.verify()
        self._check()
        if self.entry.exists() or self.entry.is_symlink():
            raise NativeBuildCacheError("native cache publication already exists; never replace")
        staging = self.root/(".pending-"+uuid.uuid4().hex)
        staging.mkdir(mode=0o700)
        paths = {"cohort":producer.captured._cohort.path, "helper":producer.captured._helper.path}
        bundles = {role:_copy_bundle(path, staging/(role+".app"), seal=True) for role,path in paths.items()}
        producer.verify()
        fd = os.open(staging/"manifest.json", os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o400)
        with os.fdopen(fd, "wb") as output:
            output.write(_json({"schema":1, "inputs":self.inputs, "bundles":bundles}))
            output.flush()
            os.fsync(output.fileno())
        staging.chmod(0o500)
        self._check()
        _rename_exclusive(staging, self.entry)
        self.load()
