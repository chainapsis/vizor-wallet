"""Load one published Zakura fixture blob, not mutable checkout Python code."""

from __future__ import annotations

import dataclasses
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import types
import uuid

from e2e_runtime import RunnerError


SOURCE_REPOSITORY = "https://github.com/piatoss3612/zakura"
SOURCE_COMMIT = "5ecafcfdb43cf42f34c8046f09c6d874b567daa4"
SOURCE_PATH = "scripts/regtest_fixture.py"
SOURCE_SHA256 = "a37f5913fbd3322a4d9afbc4a1bc27c86409835c7eb5295afe6af4ed440c8fc1"
SOURCE_SIZE = 98120
ZAKURA_IMAGE = "zakuracore/zakura@sha256:bf53c178e9549217fce7cfaa21efc85c478129ba6dc5307d55640514affeb0ac"
LIGHTWALLETD_IMAGE = "ghcr.io/zcashlabs/thus-spoke-zakura-lightwalletd@sha256:ac78a456daee0bb98ceced333f5b8a2526b18b436ef90dc6033eef1686a92270"
_GIT_TIMEOUT = 15
_REQUIRED_METHODS = ("start", "rpc", "grpc", "grpc_stream", "mine", "wait_synced", "close", "retain")


@dataclasses.dataclass(frozen=True)
class ZakuraFixtureSource:
    """Verified code identity; neither live resource ownership nor scenario PASS."""

    fixture_class: type
    repository: str
    commit: str
    path: str
    sha256: str
    size: int

    def identity(self) -> dict[str, str | int]:
        return {"repository": self.repository, "commit": self.commit, "path": self.path,
                "sha256": self.sha256, "size": self.size,
                "publication": "contributor-fork-not-official-release"}


def _git_bytes(root: Path, *arguments: str) -> bytes:
    try:
        completed = subprocess.run(
            ["git", "--no-replace-objects", "-C", str(root), *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, timeout=_GIT_TIMEOUT,
            # Empty protocol allow-list overrides repository protocol settings,
            # denying every transport, including promisor-remote downloads.
            env={**os.environ, "GIT_ALLOW_PROTOCOL": ""},
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RunnerError("could not read the pinned Zakura Git object") from error
    if completed.returncode != 0:
        # Do not disclose arbitrary Git diagnostics/credentials as sanitized evidence.
        raise RunnerError("pinned Zakura Git object is unavailable; fetch its exact commit first")
    return completed.stdout


def load_zakura_fixture_source(tooling_root: Path) -> ZakuraFixtureSource:
    """Verify and execute the same captured bytes from the fixed commit's blob.

    Git replacement objects are disabled. This never reads the checkout script,
    fetches dependencies, starts Docker or instantiates the fixture. A Git object
    cache may be dirty or have another HEAD: only the fixed blob is executable.
    """
    try:
        root = Path(tooling_root).expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RunnerError("Zakura tooling root must be an existing directory") from error
    if not root.is_dir():
        raise RunnerError("Zakura tooling root must be an existing directory")
    if _git_bytes(root, "cat-file", "-t", SOURCE_COMMIT) != b"commit\n":
        raise RunnerError("pinned Zakura source identity is not a Git commit")
    spec = f"{SOURCE_COMMIT}:{SOURCE_PATH}"
    if _git_bytes(root, "cat-file", "-s", spec) != f"{SOURCE_SIZE}\n".encode("ascii"):
        raise RunnerError("pinned Zakura source blob size changed")
    captured = _git_bytes(root, "cat-file", "blob", spec)
    if len(captured) != SOURCE_SIZE or hashlib.sha256(captured).hexdigest() != SOURCE_SHA256:
        raise RunnerError("pinned Zakura source SHA-256 does not match")

    # Dataclasses resolve postponed annotations through the defining module.
    # A unique module prevents loading this pin from replacing an earlier owner's
    # module or accepting a caller-populated sys.modules cache entry.
    name = f"_vizor_zakura_fixture_{SOURCE_COMMIT}_{uuid.uuid4().hex}"
    module = types.ModuleType(name)
    origin = f"{SOURCE_REPOSITORY}/blob/{SOURCE_COMMIT}/{SOURCE_PATH}"
    module.__file__ = origin
    sys.modules[name] = module
    try:
        exec(compile(captured, origin, "exec", dont_inherit=True), module.__dict__)
        fixture_class = getattr(module, "RegtestFixture", None)
        if (not isinstance(fixture_class, type) or fixture_class.__module__ != name
            or any(not callable(getattr(fixture_class, method, None)) for method in _REQUIRED_METHODS)
            or getattr(module, "ZAKURA_IMAGE", None) != ZAKURA_IMAGE
            or getattr(module, "LIGHTWALLETD_IMAGE", None) != LIGHTWALLETD_IMAGE):
            raise RunnerError("pinned Zakura fixture does not expose the required API/images")
    except BaseException as error:
        sys.modules.pop(name, None)
        if isinstance(error, RunnerError) or not isinstance(error, Exception):
            raise
        raise RunnerError("could not import the verified Zakura fixture bytes") from error
    return ZakuraFixtureSource(fixture_class, SOURCE_REPOSITORY, SOURCE_COMMIT,
                              SOURCE_PATH, SOURCE_SHA256, len(captured))
