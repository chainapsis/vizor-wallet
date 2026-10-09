"""One original producer for the pinned voting services and round-creation tool."""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import threading
import time
import uuid

import e2e_runtime as runtime
from funder_build import _file_record, _copy_cargo_executable
from funder_cache import FunderCacheLease, _json, _rename_exclusive
from native_case_lifecycle import NativeCaseLifecycle
from native_zakura_front import _capture


VOTE_SDK_REV = "36f5d828fc5be42d9a80baa38d1145c5541b229e"
PIR_REV = "20356d14f61a825ef28726f38270c37d604cc268"
_TOKEN = object()
_LIMIT = 512 * 1024 * 1024
_CACHE_NAMES = {name: name.replace("-", "_") for name in
                ("svoted", "voting-config", "pir-export", "nf-server", "create-round")}


class VotingBuildError(runtime.RunnerError):
    """Original source/build publication is not proved; retain its evidence."""


def _snapshot(archive, destination):
    """Extract bounded regular pinned inputs, never links or traversal members."""
    destination.mkdir(mode=0o700)
    records, seen, total = {}, set(), 0
    with tarfile.open(archive, mode="r:") as source:
        for member in source:
            name = member.name.rstrip("/")
            path = PurePosixPath(name)
            if (not name or path.is_absolute() or path.as_posix() != name
                or any(part in {".", ".."} for part in path.parts)
                or name in seen or len(seen) >= 30000):
                raise VotingBuildError("unsafe or duplicate pinned voting archive member")
            seen.add(name)
            output = destination.joinpath(*path.parts)
            if member.isdir():
                output.mkdir(mode=0o700, parents=True, exist_ok=True)
                continue
            total += member.size
            if not member.isfile() or member.size > _LIMIT or total > _LIMIT:
                raise VotingBuildError("voting source archive is nonregular or exceeds its bound")
            output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o700 if member.mode & 0o111 else 0o600)
            with os.fdopen(descriptor, "wb") as writer, source.extractfile(member) as reader:
                copied = 0
                for chunk in iter(lambda: reader.read(1024 * 1024), b""):
                    copied += len(chunk)
                    writer.write(chunk)
                if copied != member.size:
                    raise VotingBuildError("pinned archive member changed size")
            records[output] = _file_record(output)
    return records


class VotingCacheLease(FunderCacheLease):
    """Reuse the original immutable-executable lease, not an external receipt."""
    def __init__(self, root, inputs, *, timeout, cancel_event):
        super().__init__(root, inputs, _CACHE_NAMES.values(),
                         timeout=timeout, cancel_event=cancel_event)

    def publish(self, artifact):
        if (not isinstance(artifact, ProducedVotingArtifacts)
            or artifact._cache_inputs != self.inputs):
            raise VotingBuildError("only this key's original joined voting producer may publish")
        artifact.verify_unchanged()
        self._check()
        if self.entry.exists() or self.entry.is_symlink():
            raise VotingBuildError("voting cache publication already exists; never overwrite")
        staging = self.root / (".pending-" + uuid.uuid4().hex)
        staging.mkdir(mode=0o700)
        files = {}
        for name, cache_name in _CACHE_NAMES.items():
            self._check()
            record = _copy_cargo_executable(artifact.binaries[name], staging / cache_name)
            files[cache_name] = {"sha256": record[1], "size": (staging / cache_name).stat().st_size}
        artifact.verify_unchanged()
        descriptor = os.open(staging / "manifest.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
        with os.fdopen(descriptor, "wb") as output:
            output.write(_json({"schema": 1, "inputs": self.inputs, "files": files}))
            output.flush()
            os.fsync(output.fileno())
        staging.chmod(0o500)
        self._check()
        _rename_exclusive(staging, self.entry)
        self.load()


class ProducedVotingArtifacts:
    """Originally built/joined artifacts, never reconstructed from a JSON receipt."""
    def __init__(self, case, root, binaries, records, sdk, token, *, cache_inputs):
        if token is not _TOKEN:
            raise VotingBuildError("use build_voting_artifacts")
        self._case, self._root, self._records = case, root, records
        self.sdk, self.binaries = sdk, binaries
        self._cache_inputs = json.loads(_json(cache_inputs))
        self._failed = False

    def verify_unchanged(self):
        if self._failed:
            raise VotingBuildError("voting publication previously failed verification")
        try:
            self._case.workspace.verify_owned()
            if (self._case.accepting_launches or self._case._receipt is None
                or not self._case._receipt.exit_codes or any(self._case._receipt.exit_codes)
                or self._root != self._case.workspace.root / "voting-build"):
                raise VotingBuildError("original voting build writers were not joined")
            if (self.sdk != self._root / "vote-sdk" or set(self.binaries) != set(_CACHE_NAMES)
                or any(path != self._root / "bin" / name for name, path in self.binaries.items())):
                raise VotingBuildError("original voting publication inventory changed")
            for path, record in self._records.items():
                if _file_record(path, limit=_LIMIT) != record:
                    raise VotingBuildError("original voting artifact or runtime source changed")
        except BaseException:
            self._failed = True
            raise


def build_voting_artifacts(case, *, sdk_cache, pir_cache, cache_root, jobs=4, timeout=2400,
                          cancel_event=None):
    """Reuse immutable binaries; prepare original pinned runtime sources each time."""
    if (not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches
        or case.launched_process_count):
        raise VotingBuildError("voting build requires a fresh original producer case")
    if (type(jobs) is not int or not 1 <= jobs <= 8 or isinstance(timeout, bool)
        or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0):
        raise VotingBuildError("invalid voting build budget")
    caches = (Path(sdk_cache).resolve(strict=True), Path(pir_cache).resolve(strict=True))
    cancel = cancel_event if cancel_event is not None else threading.Event()
    deadline = time.monotonic() + timeout
    case.workspace.verify_owned()
    root = case.workspace.root / "voting-build"
    root.mkdir(mode=0o700)
    target = root / "target"
    target.mkdir(mode=0o700)
    environment = {key: value for key, value in os.environ.items()
                   if not key.startswith("GIT_") and key not in {"CARGO_TARGET_DIR", "GOFLAGS", "_"}}
    environment.update(CARGO_TARGET_DIR=str(target), CARGO_BUILD_JOBS=str(jobs),
                       CGO_LDFLAGS="-L" + str(target / "release"),
                       GOFLAGS="-mod=readonly -buildvcs=false", GOMAXPROCS=str(jobs))

    def command(arguments, *, cwd=None, git=False, rust_context=None):
        case.workspace.verify_owned()
        if cancel.is_set():
            raise runtime.Cancelled()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise VotingBuildError("original voting build deadline expired", 124)
        if cwd is not None:
            arguments = [sys.executable, "-c",
                "import os,sys; os.chdir(sys.argv[1]); os.execvp(sys.argv[2],sys.argv[2:])",
                str(cwd), *arguments]
        env = {**environment, **({"GIT_ALLOW_PROTOCOL": ""} if git else {})}
        if rust_context is not None:
            # Absolute Cargo bypasses rustup's exported toolchain selection.
            # Its rustc proxy must not switch compiler in dependency directories.
            env["RUSTC"] = str(tools[rust_context]["rustc"])
        result = case.run_command(arguments, env=env, timeout=remaining,
            cancel_event=cancel, max_output_bytes=16*1024*1024)
        if result.returncode:
            raise VotingBuildError("original voting build phase failed; retain process log", result.returncode)
        return result.lines

    lease = None
    try:
        inputs, archives, sources = {}, {}, []
        for name, revision, cache in zip(("vote-sdk", "vote-nullifier-pir"),
                                        (VOTE_SDK_REV, PIR_REV), caches):
            git = ["git", "--no-replace-objects", "-C", str(cache)]
            if "".join(command([*git, "cat-file", "-t", revision], git=True)).strip() != "commit":
                raise VotingBuildError("voting pin is not a cached immutable commit")
            archive = root / (name + ".tar")
            command([*git, "archive", "--format=tar", "--output="+str(archive), revision], git=True)
            archives[archive] = _file_record(archive, limit=_LIMIT)
            source = root / name
            inputs.update(_snapshot(archive, source))
            sources.append(source)
        sdk, pir = sources
        tool_records, tools, versions = {}, {}, {}
        for context, cwd in (("outer", None), ("sdk", sdk)):
            tools[context], versions[context] = {}, {}
            for name, flag in (("cargo", "-V"), ("rustc", "-vV"), ("go", "version"), ("make", "--version")):
                selected = (environment.get("RUSTC") or name) if name == "rustc" else name
                entry = shutil.which(selected, path=environment.get("PATH"))
                if entry is None:
                    raise VotingBuildError("selected voting build tool is unavailable: " + name)
                tool = Path(entry).resolve(strict=True)
                if sys.platform == "darwin" and tool == Path("/usr/bin/make"):
                    paths = [line.strip() for line in
                             command(["/usr/bin/xcrun", "--find", "make"], cwd=cwd)]
                    if len(paths) != 1 or not Path(paths[0]).is_absolute():
                        raise VotingBuildError("Xcode did not identify one absolute Make implementation")
                    tool = Path(paths[0]).resolve(strict=True)
                if tool.name == "rustup" and name in {"rustc", "cargo"}:
                    paths = [line.strip() for line in command([str(tool), "which", name], cwd=cwd)]
                    if len(paths) != 1 or not Path(paths[0]).is_absolute():
                        raise VotingBuildError("rustup did not identify one absolute voting tool")
                    tool = Path(paths[0]).resolve(strict=True)
                if not os.access(tool, os.X_OK):
                    raise VotingBuildError("selected voting build tool is not executable")
                tool_records[tool] = (_capture(tool) if tool.stat().st_uid == 0 else _file_record(tool))
                tools[context][name] = tool
                versions[context][name] = command([str(tool), flag], cwd=cwd)
        configuration_paths = {Path(environment.get("CARGO_HOME", str(Path.home() / ".cargo"))) / name
                               for name in ("config", "config.toml")}
        configuration_paths.update(parent / ".cargo" / name for parent in root.parents
                                   for name in ("config", "config.toml"))
        go_configuration = [line.strip() for line in
                            command([str(tools["sdk"]["go"]), "env", "GOENV"], cwd=sdk)]
        if len(go_configuration) != 1:
            raise VotingBuildError("Go did not identify its build configuration")
        if go_configuration[0] != "off":
            if not Path(go_configuration[0]).is_absolute():
                raise VotingBuildError("Go configuration path is not absolute")
            configuration_paths.add(Path(go_configuration[0]))
        def configuration_hashes():
            return {str(path): _capture(path)[1] for path in sorted(configuration_paths)
                    if path.exists() or path.is_symlink()}
        producer = Path(__file__).resolve(strict=True)
        tool_records[producer] = _file_record(producer)
        cache_inputs = {"schema": 1, "sdk_revision": VOTE_SDK_REV, "pir_revision": PIR_REV,
            "archives_sha256": {path.name: record[1] for path, record in archives.items()},
            "tool_versions": versions,
            "tools": {context: {name: {"path": str(path), "sha256": tool_records[path][1]}
                       for name, path in items.items()} for context, items in tools.items()},
            "producer_sha256": tool_records[producer][1], "platform": sys.platform,
            "configuration_sha256": configuration_hashes(),
            "environment_sha256": {name: hashlib.sha256(value.encode()).hexdigest()
                for name, value in sorted(environment.items())
                if name not in {"CARGO_TARGET_DIR", "CARGO_BUILD_JOBS", "CGO_LDFLAGS", "GOMAXPROCS"}}}
        def verify_inputs():
            if configuration_hashes() != cache_inputs["configuration_sha256"]:
                raise VotingBuildError("voting build configuration changed during publication")
            for path, record in tool_records.items():
                current = _capture(path) if path.stat().st_uid == 0 else _file_record(path)
                if current != record:
                    raise VotingBuildError("voting build tool or producer changed during publication")
        lease = VotingCacheLease(cache_root, cache_inputs,
            timeout=max(0.001, deadline-time.monotonic()), cancel_event=cancel)
        lease.__enter__()
        verify_inputs()
        cached = lease.load()
        if cached is None:
            print("Building pinned vote-sdk services once", file=sys.stderr, flush=True)
            command([str(tools["outer"]["make"]), "-C", str(sdk), "PATH="+environment.get("PATH", ""),
                 "COMMIT="+VOTE_SDK_REV, "VERSION=v1.6.0",
                 "CIRCUITS_CARGO_FLAGS=--locked --no-default-features --features zakura",
                 "build-ffi", "build-voting-config"])
            print("Building pinned PIR services once", file=sys.stderr, flush=True)
            command([str(tools["outer"]["cargo"]), "build", "--release", "--locked", "--manifest-path", str(pir/"Cargo.toml"),
                 "-p", "pir-export", "--features", "cli", "-p", "nf-server", "--features", "serve"], rust_context="outer")
            print("Building pinned round creation test once", file=sys.stderr, flush=True)
            lines = command([str(tools["outer"]["cargo"]), "test", "--release", "--locked", "--no-run", "--message-format=json",
                         "--manifest-path", str(sdk/"e2e-tests/Cargo.toml"),
                         "--test", "create_round_for_zashi"], rust_context="outer")
            rounds = []
            for line in lines:
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if (isinstance(item, dict) and item.get("reason") == "compiler-artifact"
                and item.get("executable")
                and item.get("target", {}).get("name") == "create_round_for_zashi"):
                    binary = Path(item["executable"])
                    if (not binary.is_absolute() or binary.resolve(strict=True) != binary
                    or not binary.is_relative_to(target/"release")
                    or item["target"].get("kind") != ["test"]
                    or item["target"].get("src_path") != str(sdk/"e2e-tests/tests/create_round_for_zashi.rs")
                    or item.get("profile", {}).get("test") is not True):
                        raise VotingBuildError("round creation output is not this original Cargo test")
                    rounds.append(binary)
            if len(rounds) != 1:
                raise VotingBuildError("original Cargo did not publish one round creation executable")
            outputs = {"svoted": sdk/"svoted", "voting-config": sdk/"voting-config",
                       "pir-export": target/"release/pir-export", "nf-server": target/"release/nf-server",
                       "create-round": rounds[0]}
        else:
            outputs = {name: cached[cache_name] for name, cache_name in _CACHE_NAMES.items()}
        verify_inputs()
        for path, record in inputs.items():
            if _file_record(path) != record:
                raise VotingBuildError("pinned voting source changed during build")
        publication = root / "bin"
        publication.mkdir(mode=0o700)
        binaries, records = {}, dict(archives)
        for name, output in outputs.items():
            destination = publication / name
            _copy_cargo_executable(output, destination)
            binaries[name] = destination
            records[destination] = _file_record(destination, executable=True, limit=_LIMIT)
        for path, record in inputs.items():
            if path.is_relative_to(sdk/"scripts"):
                records[path] = record
        receipt = case.close()
        proof = {"schema_version":1,"sdk_revision":VOTE_SDK_REV,"pir_revision":PIR_REV,
                 "build_count":int(cached is None),"tool_versions":versions,"exit_codes":receipt.exit_codes,
                 "cache_hit":cached is not None,"cache_key":lease.key,"cache_inputs":cache_inputs,
                 "persistent_cache_attestation":True,"wallet_or_catalog_pass":False,
                 "binary_sha256":{name:records[path][1] for name,path in binaries.items()}}
        with (root/"build-proof.json").open("x") as output:
            json.dump(proof, output, indent=2)
        verify_inputs()
        artifact = ProducedVotingArtifacts(case, root, binaries, records, sdk, _TOKEN, cache_inputs=cache_inputs)
        artifact.verify_unchanged()
        if cached is None:
            lease.publish(artifact)
        else:
            lease.load()
        return artifact, proof
    except BaseException as primary:
        try:
            case.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
    finally:
        if lease is not None:
            lease.__exit__()
