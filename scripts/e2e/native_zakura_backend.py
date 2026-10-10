"""Compose the pinned raw Zakura fixture with one case's original ownership.

The raw fixture ports are internal, not the native manifest's front ports. This
module provides no faucet, signer, control server, shim or scenario PASS.
"""
from __future__ import annotations

import contextlib
import copy
import json
import math
import os
from pathlib import Path
import secrets
import uuid

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
from zakura_fixture_source import load_zakura_fixture_source


_TOKEN = object()


class NativeZakuraError(runtime.RunnerError):
    """A backend operation/teardown is unproven; retain case state."""


class OwnedNativeZakuraBackend:
    """One cooperative owner, registered before starting any Docker resource."""
    def __init__(self, case, source, root, directory_fd, directory_id, token):
        if token is not _TOKEN:
            raise NativeZakuraError("use prepare_native_zakura_backend")
        self._case, self._source, self.root = case, source, root
        self._directory_fd, self._directory_id = directory_fd, directory_id
        self._fixture = None
        self._finished = self._closed = self._resources_finalized = False
        self._failure = None
        self._ready = None
        self._front = None
        self._control = None
        self._retention = None
        self._retention_attempted = False

    @property
    def closed(self):
        """Only successful internal cleanup, not an externally supplied receipt."""
        return self._closed

    def verify_owned(self):
        self._case.workspace.verify_owned()
        if (self.root != self._case.workspace.root / "zakura-backend"
            or self._directory_fd is None):
            raise NativeZakuraError("backend evidence attachment is unavailable")
        with contextlib.ExitStack() as stack:
            current = tree.open_directory(stack, self.root, private=True)
            if (tree.identity(os.fstat(current)) != self._directory_id
                or tree.identity(os.fstat(self._directory_fd)) != self._directory_id):
                raise NativeZakuraError("backend evidence directory identity changed")

    def _write_text(self, name, text):
        """All helper writes stay anchored to the originally opened evidence dir."""
        if not isinstance(name, str) or Path(name).name != name or name in {"", ".", ".."}:
            raise NativeZakuraError("backend artifact name escaped its directory")
        self.verify_owned()
        temporary = f".{name}.{secrets.token_hex(8)}.tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self._directory_fd)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write(text)
                output.flush()
                os.fsync(output.fileno())
            self.verify_owned()
            os.replace(temporary, name, src_dir_fd=self._directory_fd, dst_dir_fd=self._directory_fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self._directory_fd)
            except FileNotFoundError:
                pass

    def _release_directory(self):
        descriptor, self._directory_fd = self._directory_fd, None
        if descriptor is not None:
            os.close(descriptor)

    def start(self):
        if (self._finished or self._ready is not None or self._fixture is None
            or not self._case.accepting_launches):
            raise NativeZakuraError("backend start is unavailable or already attempted")
        self.verify_owned()
        try:
            observed = self._fixture.start()
            self._ready = copy.deepcopy(observed)
            return copy.deepcopy(observed)
        except BaseException:
            self._finished = True
            self._failure = "backend startup failed"
            # The pinned helper rolls back partial startup. Do not call retain
            # on an already closed fixture or turn its original failure into PASS.
            self._resources_finalized = self._fixture._closed is True
            raise

    def _running(self):
        if self._finished or self._ready is None or not self._case.accepting_launches:
            raise NativeZakuraError("backend execution is sealed or not ready")
        self.verify_owned()

    def rpc(self, method, params=None, *, deadline=None):
        self._running()
        return self._fixture.rpc(method, params, deadline=deadline)

    def grpc(self, method, payload=None, *, deadline=None):
        self._running()
        return self._fixture.grpc(method, payload, deadline=deadline)

    def grpc_stream(self, method, payload=None, *, deadline=None):
        self._running()
        return self._fixture.grpc_stream(method, payload, deadline=deadline)

    def mine(self, count):
        self._running()
        return self._fixture.mine(count)

    def wait_synced(self, *, deadline=None):
        self._running()
        return self._fixture.wait_synced(deadline=deadline)

    def replace_tip_holding(self, required_txids, *, deadline=None):
        self._running()
        return self._fixture.replace_tip_holding(required_txids, deadline=deadline)

    def replace_fork_holding(self, required_txids, *, fork_height, deadline=None):
        self._running()
        return self._fixture.replace_fork_holding(required_txids,
            fork_height=fork_height, deadline=deadline)

    def release_held_transactions(self, txids, *, deadline=None):
        self._running()
        return self._fixture.release_held_transactions(txids, deadline=deadline)

    def hold_pending_transactions(self, txids, *, expiry_height, deadline=None):
        self._running()
        return self._fixture.hold_pending_transactions(txids,
            expiry_height=expiry_height, deadline=deadline)

    def close(self):
        """Caller must stop SDK-native apps and seal/join original case writers."""
        if self._control is not None and not self._control.closed:
            raise NativeZakuraError("original control listener must close before backend deletion")
        if self._finished or self._case.accepting_launches or self._case._receipt is None:
            raise NativeZakuraError("backend finalization requires sealed original writers")
        self._finished = True
        try:
            self.verify_owned()
            proof = self._fixture.close()
            # This flag comes from the original captured helper, never caller JSON.
            if (self._fixture._closed is not True or proof.get("complete") is not True
                or proof.get("run_id") != self._fixture.run_id or proof.get("errors") != []):
                raise NativeZakuraError("owned Docker/port cleanup was not proved")
            self._resources_finalized = True
            self.verify_owned()
            self._release_directory()
            self._closed = True
            return copy.deepcopy(proof)
        except BaseException:
            self._failure = "backend finalization unproven"
            raise

    def retain(self):
        """Stop original Docker writers without permitting later deletion/retry."""
        if self._control is not None and not self._control.closed:
            raise NativeZakuraError("original control listener must close before backend retention")
        if self._case.accepting_launches:
            raise NativeZakuraError("backend retention requires sealed original writers")
        self._finished = True
        if self._retention is not None:
            if self._retention.get("complete") is not True:
                raise NativeZakuraError("original backend retention was incomplete")
            return copy.deepcopy(self._retention)
        if self._retention_attempted:
            raise NativeZakuraError("original backend retention did not finish")
        self._retention_attempted = True
        try:
            if self._resources_finalized or self._fixture is None:
                proof = {"complete": True, "mode": "resources-already-finalized"}
            else:
                # Even after path drift, the captured helper can stop its original
                # Docker IDs; its adapter refuses writes to replacement directories.
                proof = self._fixture.retain()
            if (proof.get("complete") is not True or (not self._resources_finalized and self._fixture is not None
                and (self._fixture._retained is not True or proof.get("run_id") != self._fixture.run_id
                     or proof.get("errors") != []))):
                raise NativeZakuraError("owned Docker writer stop was not proved")
            self._retention = copy.deepcopy(proof)
            return copy.deepcopy(proof)
        finally:
            self._release_directory()


def prepare_native_zakura_backend(case: NativeCaseLifecycle, *,
                                 grpcurl: Path, proto_dir: Path, miner_address: str,
                                 timeout: float = 60.0):
    """Construct only; caller registers this original handle before start()."""
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches:
        raise NativeZakuraError("expected an original accepting case process owner")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise NativeZakuraError("timeout must be positive and finite")
    case.workspace.verify_owned()
    manifest = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    activation = manifest["regtest_ironwood_activation_height"]
    if activation not in {1, 500}:
        raise NativeZakuraError("direct backend requires the fixed height1 or activation500 profile")
    source = load_zakura_fixture_source()
    root = case.workspace.root / "zakura-backend"
    descriptor = None
    owner = None
    try:
        with contextlib.ExitStack() as stack:
            parent_fd = tree.open_directory(stack, case.workspace.root, private=True)
            os.mkdir("zakura-backend", 0o700, dir_fd=parent_fd)
            descriptor = os.open("zakura-backend", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
            identity = tree.identity(os.fstat(descriptor))
            tree.check(os.fstat(descriptor), directory=True, private=True)
        owner = OwnedNativeZakuraBackend(case, source, root, descriptor, identity, _TOKEN)
        owner.verify_owned()

        class AnchoredFixture(source.fixture_class):
            def _write_text(self, name, text):
                owner._write_text(name, text)

        fixture_run_id = uuid.uuid4()
        # The fixture needs at most three containers. Avoid consuming Docker's
        # much larger default subnets while retaining failed-case networks.
        subnet_bytes = fixture_run_id.bytes
        network_subnet = f"10.{subnet_bytes[0]}.{subnet_bytes[1]}.{subnet_bytes[2] & 0xf0}/28"
        owner._fixture = AnchoredFixture(root, grpcurl, proto_dir, timeout=timeout,
            run_id=fixture_run_id, miner_address=miner_address, network_subnet=network_subnet,
            profile="zakura-direct-height1" if activation == 1 else "zakura-direct-activation500")
        owner._write_text("source-identity.json", json.dumps(source.identity(), sort_keys=True) + "\n")
        return owner
    except BaseException:
        if owner is not None:
            owner._release_directory()
        elif descriptor is not None:
            os.close(descriptor)
        raise
