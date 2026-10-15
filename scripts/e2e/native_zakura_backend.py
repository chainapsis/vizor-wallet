"""Own one case's Zakura regtest chain and the directory that holds its evidence.

The chain's ports are internal, not the native manifest's front ports. This
module provides no faucet, signer, control server, shim or scenario PASS.
"""
from __future__ import annotations

import contextlib
import copy
import json
import math
import os
from pathlib import Path
import re
import secrets
import uuid

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
from zakura_regtest import ZakuraRegtest


_TOKEN = object()


class NativeZakuraError(runtime.RunnerError):
    """A backend operation/teardown is unproven; retain case state."""


class OwnedNativeZakuraBackend:
    """One cooperative owner, registered before starting any Docker resource."""
    def __init__(self, case, root, directory_fd, directory_id, token):
        if token is not _TOKEN:
            raise NativeZakuraError("use prepare_native_zakura_backend")
        self._case, self.root = case, root
        self._directory_fd, self._directory_id = directory_fd, directory_id
        self._regtest = None
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
        """All chain writes stay anchored to the originally opened evidence dir."""
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
        if (self._finished or self._ready is not None or self._regtest is None
            or not self._case.accepting_launches):
            raise NativeZakuraError("backend start is unavailable or already attempted")
        self.verify_owned()
        try:
            observed = self._regtest.start()
            self._ready = copy.deepcopy(observed)
            return copy.deepcopy(observed)
        except BaseException:
            self._finished = True
            self._failure = "backend startup failed"
            # A failed start removes what it created. Do not call retain on an
            # already removed chain or turn its original failure into PASS.
            self._resources_finalized = self._regtest.closed is True
            raise

    def _running(self):
        if self._finished or self._ready is None or not self._case.accepting_launches:
            raise NativeZakuraError("backend execution is sealed or not ready")
        self.verify_owned()

    def rpc(self, method, params=None, *, deadline=None):
        self._running()
        return self._regtest.rpc(method, params, deadline=deadline)

    def grpc(self, method, payload=None, *, deadline=None):
        self._running()
        return self._regtest.grpc(method, payload, deadline=deadline)

    def grpc_stream(self, method, payload=None, *, deadline=None):
        self._running()
        return self._regtest.grpc_stream(method, payload, deadline=deadline)

    def mine(self, count):
        self._running()
        return self._regtest.mine(count)

    def wait_synced(self, *, deadline=None):
        self._running()
        return self._regtest.wait_synced(deadline=deadline)

    def replace_tip_holding(self, required_txids, *, deadline=None):
        self._running()
        return self._regtest.replace_tip_holding(required_txids, deadline=deadline)

    def replace_fork_holding(self, required_txids, *, fork_height, deadline=None):
        self._running()
        return self._regtest.replace_fork_holding(required_txids,
            fork_height=fork_height, deadline=deadline)

    def release_held_transactions(self, txids, *, deadline=None):
        self._running()
        return self._regtest.release_held_transactions(txids, deadline=deadline)

    def hold_pending_transactions(self, txids, *, expiry_height, deadline=None):
        self._running()
        return self._regtest.hold_pending_transactions(txids,
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
            proof = self._regtest.close()
            # This flag comes from the original chain object, never caller JSON.
            if (self._regtest.closed is not True or proof.get("complete") is not True
                or proof.get("run_id") != self._regtest.run_id or proof.get("errors") != []):
                raise NativeZakuraError("owned Docker/port cleanup was not proved")
            self._resources_finalized = True
            self.verify_owned()
            self._release_directory()
            self._closed = True
            return copy.deepcopy(proof)
        except BaseException:
            self._failure = "backend finalization unproven"
            raise

    def retained_resources(self):
        """Docker identity this original owner left in place; it grants no deletion."""
        if self._regtest is None or self._resources_finalized:
            return None
        retention = self._retention or {}
        return {"regtest_run_id": self._regtest.run_id, "stopped": retention.get("complete") is True,
                "identity": copy.deepcopy(retention.get("identity"))}

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
            if self._resources_finalized or self._regtest is None:
                proof = {"complete": True, "mode": "resources-already-finalized"}
            else:
                # Even after path drift, the chain can stop its original Docker
                # IDs; its writer refuses writes to replacement directories.
                proof = self._regtest.retain()
            if (proof.get("complete") is not True or (not self._resources_finalized and self._regtest is not None
                and (self._regtest.retained is not True or proof.get("run_id") != self._regtest.run_id
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
        raise NativeZakuraError("Ironwood must activate at height 1 or 500")
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
        owner = OwnedNativeZakuraBackend(case, root, descriptor, identity, _TOKEN)
        owner.verify_owned()
        labels = {"com.keplr.vizor.e2e.namespace": case.workspace.namespace}
        suites = [part for part in case.workspace.root.parts if re.fullmatch(r"native-suite-[0-9a-f]{10}", part)]
        if len(suites) == 1:
            labels["com.keplr.vizor.e2e.suite-run"] = suites[0].removeprefix("native-suite-")

        run_id = uuid.uuid4()
        # The chain needs at most three containers. Avoid consuming Docker's
        # much larger default subnets while retaining failed-case networks.
        subnet_bytes = run_id.bytes
        network_subnet = f"10.{subnet_bytes[0]}.{subnet_bytes[1]}.{subnet_bytes[2] & 0xf0}/28"
        # Every Docker resource is created and ownership-checked with these labels.
        owner._regtest = regtest = ZakuraRegtest(root, grpcurl, proto_dir, run_id=run_id,
            miner_address=miner_address, activation_height=activation, network_subnet=network_subnet,
            labels=labels, write_text=owner._write_text, timeout=timeout)
        # Before Docker starts, so a network or volume left by a killed runner still maps here.
        owner._write_text("regtest-identity.json", json.dumps({"schema_version": 1, "run_id": regtest.run_id,
            "names": {"network": regtest.network_name, "node": regtest.node_name, "donor": regtest.donor_name,
                      "lightwalletd": regtest.lwd_name, "lightwalletd_volume": regtest.lwd_volume},
            "network_subnet": network_subnet, "labels": regtest.labels}, sort_keys=True) + "\n")
        return owner
    except BaseException:
        if owner is not None:
            owner._release_directory()
        elif descriptor is not None:
            os.close(descriptor)
        raise
