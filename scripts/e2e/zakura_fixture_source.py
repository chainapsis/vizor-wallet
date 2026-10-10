"""Load the vendored Zakura regtest fixture only after verifying its pinned bytes."""

from __future__ import annotations

import dataclasses
import hashlib
from pathlib import Path
import sys
import types
import uuid

from e2e_runtime import RunnerError


# The helper was first published in a contributor fork and is vendored here
# byte-for-byte. Editing the vendored file requires a reviewed update of this pin.
ORIGIN_REPOSITORY = "https://github.com/piatoss3612/zakura"
ORIGIN_COMMIT = "5ecafcfdb43cf42f34c8046f09c6d874b567daa4"
ORIGIN_PATH = "scripts/regtest_fixture.py"
VENDORED_PATH = "scripts/e2e/zakura_fixture/regtest_fixture.py"
SOURCE_PATH = Path(__file__).resolve().parent / "zakura_fixture" / "regtest_fixture.py"
SOURCE_SHA256 = "a37f5913fbd3322a4d9afbc4a1bc27c86409835c7eb5295afe6af4ed440c8fc1"
SOURCE_SIZE = 98120
ZAKURA_IMAGE = "zakuracore/zakura@sha256:bf53c178e9549217fce7cfaa21efc85c478129ba6dc5307d55640514affeb0ac"
LIGHTWALLETD_IMAGE = "ghcr.io/zcashlabs/thus-spoke-zakura-lightwalletd@sha256:ac78a456daee0bb98ceced333f5b8a2526b18b436ef90dc6033eef1686a92270"
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
                "vendored_path": VENDORED_PATH, "sha256": self.sha256, "size": self.size,
                "publication": "vendored-from-contributor-fork"}


def load_zakura_fixture_source() -> ZakuraFixtureSource:
    """Verify and execute the same captured bytes of the vendored helper.

    The file is read once, and only the bytes that match the pinned size and
    SHA-256 execute. This never starts Docker or instantiates the fixture.
    """
    try:
        captured = SOURCE_PATH.read_bytes()
    except OSError as error:
        raise RunnerError("vendored Zakura fixture is unavailable") from error
    if len(captured) != SOURCE_SIZE or hashlib.sha256(captured).hexdigest() != SOURCE_SHA256:
        raise RunnerError("vendored Zakura fixture SHA-256 does not match its pin")

    # Dataclasses resolve postponed annotations through the defining module.
    # A unique module prevents one load from replacing an earlier owner's module
    # or accepting a caller-populated sys.modules cache entry.
    name = f"_vizor_zakura_fixture_{ORIGIN_COMMIT}_{uuid.uuid4().hex}"
    module = types.ModuleType(name)
    module.__file__ = str(SOURCE_PATH)
    sys.modules[name] = module
    try:
        exec(compile(captured, str(SOURCE_PATH), "exec", dont_inherit=True), module.__dict__)
        fixture_class = getattr(module, "RegtestFixture", None)
        if (not isinstance(fixture_class, type) or fixture_class.__module__ != name
            or any(not callable(getattr(fixture_class, method, None)) for method in _REQUIRED_METHODS)
            or getattr(module, "ZAKURA_IMAGE", None) != ZAKURA_IMAGE
            or getattr(module, "LIGHTWALLETD_IMAGE", None) != LIGHTWALLETD_IMAGE):
            raise RunnerError("vendored Zakura fixture does not expose the required API/images")
    except BaseException as error:
        sys.modules.pop(name, None)
        if isinstance(error, RunnerError) or not isinstance(error, Exception):
            raise
        raise RunnerError("could not import the verified Zakura fixture bytes") from error
    return ZakuraFixtureSource(fixture_class, ORIGIN_REPOSITORY, ORIGIN_COMMIT,
                              ORIGIN_PATH, SOURCE_SHA256, len(captured))
