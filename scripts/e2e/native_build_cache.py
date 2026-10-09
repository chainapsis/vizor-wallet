"""Immutable signed cohort/helper pairs; never native storage or loose outputs."""
from __future__ import annotations

import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import uuid
from urllib.parse import unquote, urlparse

from funder_cache import FunderCacheLease, FunderCacheError, _json, _read, _rename_exclusive
from funder_build import _file_record, _MAX_BINARY_BYTES
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
from native_zakura_front import _capture


_TOKEN = object()
_ROLES = ("cohort", "helper")


class NativeBuildCacheError(FunderCacheError):
    """An immutable native build's inputs, bytes or original owner are unproven."""


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


def _package_digest(root, cancel):
    """Dependency source contents, not only lock versions or package-cache paths."""
    ignored = {".git", ".dart_tool", "build", "target", ".regtest-logs", "__pycache__"}
    digest, count, total = hashlib.sha256(), 0, 0
    for directory, children, files in os.walk(root, followlinks=False):
        children[:] = sorted(children)
        if Path(directory) == root:
            children[:] = [name for name in children if name not in ignored]
        for name in sorted((*children, *files)):
            if cancel.is_set():
                from e2e_runtime import Cancelled
                raise Cancelled()
            path = Path(directory)/name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                target = os.readlink(path)
                if Path(target).is_absolute() or not path.resolve(strict=True).is_relative_to(root):
                    raise NativeBuildCacheError("package source link escapes its package")
                value = [relative, "link", target]
            elif stat.S_ISDIR(info.st_mode):
                value = [relative, "directory"]
            else:
                value = [relative, "file", _capture(path)[1], bool(info.st_mode & stat.S_IXUSR)]
                total += info.st_size
            count += 1
            if count > 100_000 or total > 1024*1024*1024:
                raise NativeBuildCacheError("package source exceeds its bound")
            digest.update(_json(value)+b"\n")
    return digest.hexdigest()


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
    rust = {name: {"rustc":list(command(["rustup", "run", name, "rustc", "-vV"], in_source=True)),
                  "cargo":list(command(["rustup", "run", name, "cargo", "-V"], in_source=True))}
            for name in toolchains}
    if not rust:
        raise NativeBuildCacheError("native Rust toolchain inventory is empty")
    cargo_home = Path(environment.get("CARGO_HOME", str(Path.home()/".cargo")))
    configurations = {cargo_home/name for name in ("config", "config.toml")}
    configurations.update(parent/".cargo"/name for parent in (root,*root.parents)
                          for name in ("config", "config.toml"))
    return {"schema":1, "platform":platform, "architecture":architecture, "tex_address":tex_address,
        "source_sha256":{str(path.relative_to(root)) if path.is_relative_to(root) else str(path):record[1]
            for path,record in source.items() if path != configuration},
        "package_config":packages, "pod_lock_sha256":_pod_lock(root/platform/"Podfile.lock"),
        "flutter":flutter, "xcode":list(command(["/usr/bin/xcodebuild", "-version"])),
        "sdk":list(command(["/usr/bin/xcrun", "--sdk", sdk, "--show-sdk-build-version"])),
        "rust_toolchains":rust,
        "cocoapods":list(command(["pod", "--version"], in_source=True)),
        "ruby":list(command(["ruby", "--version"], in_source=True)),
        "signing_identities_sha256":hashlib.sha256("".join(command(
            ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"])).encode()).hexdigest()
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
