"""One original producer for the pinned voting services and round-creation tool."""
from __future__ import annotations

import json
import math
import os
from pathlib import Path, PurePosixPath
import sys
import tarfile
import threading
import time

import e2e_runtime as runtime
from funder_build import _file_record, _copy_cargo_executable
from native_case_lifecycle import NativeCaseLifecycle


VOTE_SDK_REV = "36f5d828fc5be42d9a80baa38d1145c5541b229e"
PIR_REV = "20356d14f61a825ef28726f38270c37d604cc268"
_TOKEN = object()
_LIMIT = 512 * 1024 * 1024


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


class ProducedVotingArtifacts:
    """Originally built/joined artifacts, never reconstructed from a JSON receipt."""
    def __init__(self, case, root, binaries, records, sdk, token):
        if token is not _TOKEN:
            raise VotingBuildError("use build_voting_artifacts")
        self._case, self._root, self._records = case, root, records
        self.sdk, self.binaries = sdk, binaries
        self._failed = False

    def verify_unchanged(self):
        if self._failed:
            raise VotingBuildError("voting publication previously failed verification")
        try:
            self._case.workspace.verify_owned()
            if (self._case.accepting_launches or self._case._receipt is None
                or self._root != self._case.workspace.root / "voting-build"):
                raise VotingBuildError("original voting build writers were not joined")
            for path, record in self._records.items():
                if _file_record(path, limit=_LIMIT) != record:
                    raise VotingBuildError("original voting artifact or runtime source changed")
        except BaseException:
            self._failed = True
            raise


def build_voting_artifacts(case, *, sdk_cache, pir_cache, jobs=4, timeout=2400,
                          cancel_event=None):
    """Compile once from exact Git archives; caches provide source, never binaries."""
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
                   if not key.startswith("GIT_") and key not in {"CARGO_TARGET_DIR", "GOFLAGS"}}
    environment.update(CARGO_TARGET_DIR=str(target), CARGO_BUILD_JOBS=str(jobs),
                       CGO_LDFLAGS="-L" + str(target / "release"),
                       GOFLAGS="-mod=readonly -buildvcs=false", GOMAXPROCS=str(jobs))

    def command(arguments, *, cwd=None, git=False):
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
        result = case.run_command(arguments, env=env, timeout=remaining,
            cancel_event=cancel, max_output_bytes=16*1024*1024)
        if result.returncode:
            raise VotingBuildError("original voting build phase failed; retain process log", result.returncode)
        return result.lines

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
        versions = {tool: command([tool, flag]) for tool, flag in
                    (("cargo", "-V"), ("rustc", "-vV"), ("go", "version"))}
        print("Building pinned vote-sdk services once", file=sys.stderr, flush=True)
        command(["make", "-C", str(sdk), "COMMIT="+VOTE_SDK_REV, "VERSION=v1.6.0",
                 "CIRCUITS_CARGO_FLAGS=--locked --no-default-features --features zakura",
                 "build-ffi", "build-voting-config"])
        print("Building pinned PIR services once", file=sys.stderr, flush=True)
        command(["cargo", "build", "--release", "--locked", "--manifest-path", str(pir/"Cargo.toml"),
                 "-p", "pir-export", "--features", "cli", "-p", "nf-server", "--features", "serve"])
        print("Building pinned round creation test once", file=sys.stderr, flush=True)
        lines = command(["cargo", "test", "--release", "--locked", "--no-run", "--message-format=json",
                         "--manifest-path", str(sdk/"e2e-tests/Cargo.toml"),
                         "--test", "create_round_for_zashi"])
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
        for path, record in inputs.items():
            if _file_record(path) != record:
                raise VotingBuildError("pinned voting source changed during build")
        publication = root / "bin"
        publication.mkdir(mode=0o700)
        binaries, records = {}, dict(archives)
        outputs = {"svoted": sdk/"svoted", "voting-config": sdk/"voting-config",
                   "pir-export": target/"release/pir-export", "nf-server": target/"release/nf-server",
                   "create-round": rounds[0]}
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
                 "build_count":1,"tool_versions":versions,"exit_codes":receipt.exit_codes,
                 "persistent_cache_attestation":False,"wallet_or_catalog_pass":False,
                 "binary_sha256":{name:records[path][1] for name,path in binaries.items()}}
        with (root/"build-proof.json").open("x") as output:
            json.dump(proof, output, indent=2)
        artifact = ProducedVotingArtifacts(case, root, binaries, records, sdk, _TOKEN)
        artifact.verify_unchanged()
        return artifact, proof
    except BaseException as primary:
        try:
            case.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
