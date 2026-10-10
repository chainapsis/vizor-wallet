"""Own native worker mutable storage while retaining every case's evidence.

No source cloning/build/executor is implemented here. Case/native/port cleanup
is executed through originally constructed handles, never external booleans or
JSON. One cooperative owner; no concurrent calls or untracked resource writers.
"""
from __future__ import annotations

import contextlib
import dataclasses
import json
import os
from pathlib import Path
import secrets
import threading

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_ios_case_storage as ios_storage
import native_ios_cohort as ios_cohort
import native_ios_simulator as ios_simulator
import native_mac_case_storage as mac_storage
import native_mac_cleanup as mac_native
from native_rust_case_storage import RustCaseStorage
import native_owned_tree as tree
import native_zakura_backend as zakura
import native_zakura_front as zakura_front
from zakura_genesis import create_zakura_genesis_proof
from native_zakura_control import prepare_native_zakura_control
from native_ports import lease_native_ports
import native_workspace as workspace_api


_TOKEN = object()
_MARKER = "worker-owner.json"


class NativeWorkerError(runtime.RunnerError):
    """Worker ownership/cleanup unproven; stop assignment and retain evidence."""


@dataclasses.dataclass(frozen=True)
class WorkerWorkspaceCleanup:
    """Observed mutable workspace removal, not scenario PASS or report authority."""
    run_id: str
    worker_id: int
    workspace: str
    evidence: str
    namespaces: tuple[str, ...]


class NativeWorkerCase:
    """Allocated by an owned worker; finalize only through close()/retain()."""
    def __init__(self, worker, case, lease, mutable_directory, token):
        if token is not _TOKEN:
            raise NativeWorkerError("use the worker case allocation API")
        self.worker = worker
        self.case = case
        self.lease = lease
        self.mutable_directory = mutable_directory
        self._mutable_id = None
        self.storage = None
        self.simulator = None
        self._backend = None
        self._front = None
        self._control = None
        self._backend_finalized = False
        self._finished = False
        self._completed = False
        self._native_finalized = False
        self._failure = None

    def verify_owned(self):
        self.worker.verify_owned()
        self.case.workspace.verify_owned()
        if self.mutable_directory != self.worker.workspace / self.case.workspace.namespace:
            raise NativeWorkerError("case mutable path is not its original worker namespace")
        with contextlib.ExitStack() as stack:
            _, workspace_fd = self.worker._open(stack)
            mutable_fd = tree.open_directory(stack, self.case.workspace.namespace, dir_fd=workspace_fd, private=True)
            if tree.identity(os.fstat(mutable_fd)) != self._mutable_id:
                raise NativeWorkerError("case mutable directory identity changed")

    def prepare_zakura_backend(self, *, grpcurl, proto_dir, miner_address, timeout=60.0):
        """Register the pinned original fixture before any Docker start attempt."""
        ios_simulator._deadline(timeout)
        if self._finished or self._backend is not None or self.storage is None:
            raise NativeWorkerError("backend allocation is unavailable or already attempted")
        self.verify_owned()
        try:
            self._backend = zakura.prepare_native_zakura_backend(self.case,
                grpcurl=grpcurl, proto_dir=proto_dir,
                miner_address=miner_address, timeout=timeout)
            return self._backend.start()
        except BaseException as primary:
            self._failure = "backend preparation failed; retain worker"
            try:
                self.retain(timeout=timeout)
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    @property
    def backend(self):
        """Original registered raw backend; no external backend/cleanup adoption."""
        return self._backend

    def prepare_zakura_front(self, *, dart, source_root, timeout=30.0, cancel_event=None):
        """Own the front through this case; locks survive the socket handoff."""
        ios_simulator._deadline(timeout)
        if self._finished or self._front is not None or self._backend is None:
            raise NativeWorkerError("front allocation is unavailable or already attempted")
        self.verify_owned()
        try:
            genesis = create_zakura_genesis_proof(self.case, self._backend,
                timeout=timeout, cancel_event=cancel_event)
            self._front = zakura_front.prepare_native_zakura_front(self.case, self._backend, genesis,
                dart=dart, source_root=source_root, timeout=timeout)
            self.lease.release_sockets()
            return self._front.start(cancel_event=cancel_event)
        except BaseException as primary:
            self._failure = "front preparation failed; retain worker"
            try:
                self.retain(timeout=timeout)
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    def prepare_zakura_control(self, *, artifact=None, timeout=30.0):
        """Bind a synchronous control pump; the executor must drive it on this owner."""
        ios_simulator._deadline(timeout)
        if self._finished or self._control is not None or self._front is None:
            raise NativeWorkerError("control allocation is unavailable or already attempted")
        self.verify_owned()
        try:
            self._control = prepare_native_zakura_control(self.case, self._backend, self._front,
                artifact=artifact)
            return self._control
        except BaseException as primary:
            self._failure = "control preparation failed; retain worker"
            try:
                self.retain(timeout=timeout)
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    def close(self, *, timeout=60.0, cancel_event=None):
        """Successful scenario teardown; do not supply external cleanup proof."""
        ios_simulator._deadline(timeout)
        if self._finished or self.storage is None:
            raise NativeWorkerError("case storage lifecycle is unavailable or finished")
        self._finished = True
        cancellation = cancel_event if cancel_event is not None else threading.Event()
        try:
            if self._control is not None:
                self._control.close()
            self.verify_owned()
            if self._backend is not None:
                if isinstance(self.storage, ios_storage.OwnedIosCaseStorage) and self.storage._active is not None:
                    self.storage.stop_app(self.storage._active, timeout=timeout)
                self.case.close()
                if self._control is not None:
                    self._control.release_clipboard_after_writers()
                self._backend.close()
                self._backend_finalized = True
            observation = self.storage.close(timeout=timeout, cancel_event=cancellation)
            self._native_finalized = True
            self.case.close()
            self.lease.close()
            self.verify_owned()
            self._completed = True
            return observation
        except BaseException as primary:
            self._failure = "case/native/port finalization unproven"
            self.worker._failure = self._failure
            try:
                self.retain(timeout=timeout)
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    def retain(self, *, timeout=60.0):
        """Stop owned writers/device; retain native/mutable/evidence state."""
        ios_simulator._deadline(timeout)
        self._finished = True
        self.worker._failure = "failed case retained; stop worker assignment"
        errors = []
        control = self._control or (self._backend._control if self._backend is not None else None)
        if control is not None:
            try:
                control.close()
            except BaseException as error:
                errors.append(error)
        if self.storage is not None and not self._native_finalized:
            try:
                if isinstance(self.storage, ios_storage.OwnedIosCaseStorage):
                    self.storage.retain(timeout=timeout)
                else:
                    self.storage.retain()
            except BaseException as error:
                errors.append(error)
        elif self.storage is None and self.simulator is not None:
            # Failed iOS preparation may already have claimed its native owner.
            # Never use the old pre-app deletion route for a failed case.
            claimed = self.simulator._state.native_owner
            if claimed is not None:
                try:
                    claimed.retain(timeout=timeout)
                except BaseException as error:
                    errors.append(error)
        try:
            self.case.close()
            if self._control is not None:
                self._control.release_clipboard_after_writers()
        except BaseException as error:
            errors.append(error)
        if self._backend is not None and not self._backend_finalized:
            try:
                self._backend.retain()
            except BaseException as error:
                errors.append(error)
        # Keep cooperative port locks when any writer/device stop is unproven.
        if not errors:
            try:
                self.lease.close()
            except BaseException as error:
                errors.append(error)
        if errors:
            self._failure = "failed-case writer/device/port stop unproven"
            raise errors[0]


class NativeWorkerLifecycle:
    """One private worker root; cases and build data are never adopted."""
    def __init__(self, artifacts_root, run_id, worker_id, token):
        if token is not _TOKEN:
            raise NativeWorkerError("use prepare_native_worker_lifecycle")
        self.artifacts_root = artifacts_root
        self.run_id, self.worker_id = run_id, worker_id
        self.root = artifacts_root / "native-workers" / f"{run_id}-w{worker_id}"
        self.workspace = self.root / "workspace"
        self.evidence = self.root / "evidence"
        self._token = token
        self._ids = self._marker_bytes = self._marker_id = None
        self._finished = False
        self._failure = None
        self._cases = []

    def _open(self, stack):
        if self._token is not _TOKEN or workspace_api._canonical_root(self.artifacts_root) != self.artifacts_root:
            raise NativeWorkerError("worker artifact root changed")
        if (self.root != self.artifacts_root / "native-workers" / f"{self.run_id}-w{self.worker_id}"
            or self.workspace != self.root / "workspace" or self.evidence != self.root / "evidence"):
            raise NativeWorkerError("worker paths no longer match the original layout")
        descriptors = [tree.open_directory(stack, self.artifacts_root, private=True)]
        descriptors.append(tree.open_directory(stack, "native-workers", dir_fd=descriptors[-1], private=True))
        descriptors.append(tree.open_directory(stack, self.root.name, dir_fd=descriptors[-1], private=True))
        root_fd = descriptors[-1]
        descriptors.append(tree.open_directory(stack, "evidence", dir_fd=root_fd, private=True))
        descriptors.append(tree.open_directory(stack, "workspace", dir_fd=root_fd, private=True))
        identities = tuple(tree.identity(os.fstat(fd)) for fd in descriptors)
        marker, marker_id = workspace_api._read_private_file(root_fd, _MARKER, len(self._marker_bytes) + 1)
        if identities != self._ids or marker != self._marker_bytes or marker_id != self._marker_id:
            raise NativeWorkerError("worker original directory/marker identity changed")
        return root_fd, descriptors[-1]

    def verify_owned(self):
        try:
            with contextlib.ExitStack() as stack:
                self._open(stack)
        except BaseException as error:
            self._failure = "worker ownership unproven"
            if not isinstance(error, Exception) or isinstance(error, runtime.Cancelled):
                raise
            raise NativeWorkerError(self._failure) from error

    def prepare_case(self, *, platform, scenario_id, case_index, activation_height,
                     helper=None, runtime_identifier=None, device_type_identifier=None,
                     timeout=120.0, cancel_event=None):
        """Allocate and claim native state before returning a usable case.

        Mutable backend/build data belongs below mutable_directory; process
        logs, manifests and app context belong to the retained evidence tree.
        Native writers use storage.start_app(); control/backend writers use case.
        """
        ios_simulator._deadline(timeout)
        if self._finished or self._failure is not None:
            raise NativeWorkerError("worker is sealed or failed; no new case assignment")
        if platform not in {"ios", "macos", "rust"}:
            raise NativeWorkerError("worker supports Rust, macOS and iOS Simulator only")
        expected = ios_cohort.CapturedIosCohort if platform == "ios" else mac_native.CapturedMacCleanupHelper
        if platform == "rust" and any(value is not None for value in (helper, runtime_identifier, device_type_identifier)):
            raise NativeWorkerError("Rust cases do not use native helpers or Simulator selection")
        if platform != "rust" and not isinstance(helper, expected):
            raise NativeWorkerError("platform requires its actual captured helper/cohort")
        if platform == "ios" and (runtime_identifier is None or device_type_identifier is None):
            raise NativeWorkerError("iOS runtime and device type selection must be explicit")
        self.verify_owned()
        cancellation = cancel_event if cancel_event is not None else threading.Event()
        lease = None
        session = None
        try:
            lease = lease_native_ports(self.worker_id, self.run_id)
            workspace = workspace_api.prepare_native_case_workspace(self.evidence,
                platform=platform, scenario_id=scenario_id, run_id=self.run_id,
                worker_id=self.worker_id, case_index=case_index, ports=lease.ports,
                activation_height=activation_height)
            case = NativeCaseLifecycle(workspace)
            mutable = self.workspace / workspace.namespace
            # Register resource handles before any native operation can launch.
            session = NativeWorkerCase(self, case, lease, mutable, _TOKEN)
            self._cases.append(session)
            with contextlib.ExitStack() as stack:
                _, workspace_fd = self._open(stack)
                os.mkdir(workspace.namespace, 0o700, dir_fd=workspace_fd)
                mutable_fd = tree.open_directory(stack, workspace.namespace, dir_fd=workspace_fd, private=True)
                session._mutable_id = tree.identity(os.fstat(mutable_fd))
            if platform == "ios":
                session.simulator = ios_simulator.acquire_ios_simulator(case,
                    runtime_identifier=runtime_identifier, device_type_identifier=device_type_identifier,
                    timeout=timeout, cancel_event=cancellation)
                session.storage = ios_storage.prepare_ios_case_storage(session.simulator, helper,
                    timeout=timeout, cancel_event=cancellation)
            elif platform == "macos":
                session.storage = mac_storage.prepare_mac_case_storage(case, helper,
                    timeout=timeout, cancel_event=cancellation)
            else:
                session.storage = RustCaseStorage(case)
            session.verify_owned()
            return session
        except BaseException as primary:
            self._failure = "case allocation/native preparation failed; retain worker"
            try:
                if session is not None:
                    session.retain(timeout=timeout)
                elif lease is not None:
                    lease.close()
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    def retain(self, *, timeout=60.0):
        """Stop assignments/writers; retain workspace, case state and evidence."""
        ios_simulator._deadline(timeout)
        self._finished = True
        self._failure = self._failure or "worker retained after failed scenario"
        errors = []
        for case in self._cases:
            if not case._completed:
                try:
                    case.retain(timeout=timeout)
                except BaseException as error:
                    errors.append(error)
        if errors:
            raise errors[0]

    def close(self):
        """Remove only mutable workspace after internally completed case teardown.

        All cases must already have finalized through their original session.
        No automatic success inference from an empty directory or external log.
        Evidence and worker marker remain; partial removals stay failed.
        """
        if self._finished or self._failure is not None:
            raise NativeWorkerError("worker is finished/failed; workspace retained")
        self._finished = True
        try:
            self.verify_owned()
            if any(not case._completed for case in self._cases):
                raise NativeWorkerError("owned case/native/port teardown is incomplete")
            for case in self._cases:
                case.case.close()
                case.verify_owned()
                if case.lease.sockets or case.lease.lock_descriptors or case.lease._cleanup_error:
                    raise NativeWorkerError("owned case port handles remain")
            with contextlib.ExitStack() as stack:
                root_fd, workspace_fd = self._open(stack)
                entries = tree.scan(workspace_fd, allow_links=True)
                tree.remove_entries(workspace_fd, entries, self.verify_owned)
                self.verify_owned()
                os.rmdir("workspace", dir_fd=root_fd)
                try:
                    os.stat("workspace", dir_fd=root_fd, follow_symlinks=False)
                except FileNotFoundError:
                    return WorkerWorkspaceCleanup(self.run_id, self.worker_id, str(self.workspace),
                        str(self.evidence), tuple(case.case.workspace.namespace for case in self._cases))
                raise NativeWorkerError("worker workspace removal absence is unproven")
        except BaseException as primary:
            self._failure = "worker finalization unproven; retain remaining workspace/evidence"
            try:
                self.retain()
            except BaseException as cleanup:
                raise primary from cleanup
            raise


def prepare_native_worker_lifecycle(artifacts_root: Path, *, run_id: str, worker_id: int):
    """Exclusively allocate a private worker; leave partial allocations retained."""
    artifacts_root = workspace_api._canonical_root(artifacts_root)
    if not isinstance(run_id, str) or not workspace_api._RUN_ID_RE.fullmatch(run_id):
        raise NativeWorkerError("run_id must be ten lowercase hexadecimal characters")
    workspace_api._bounded_integer(worker_id, "worker_id", 1_000_000)
    owner = NativeWorkerLifecycle(artifacts_root, run_id, worker_id, _TOKEN)
    owner._marker_bytes = (json.dumps({"schema_version": 1, "run_id": run_id,
        "worker_id": worker_id, "workspace": str(owner.workspace), "evidence": str(owner.evidence),
        "owner_nonce": secrets.token_hex(8)}, sort_keys=True, separators=(",", ":")) + "\n").encode("ascii")
    try:
        with contextlib.ExitStack() as stack:
            artifacts_fd = tree.open_directory(stack, artifacts_root, private=True)
            try:
                os.mkdir("native-workers", 0o700, dir_fd=artifacts_fd)
            except FileExistsError:
                pass
            workers_fd = tree.open_directory(stack, "native-workers", dir_fd=artifacts_fd, private=True)
            os.mkdir(owner.root.name, 0o700, dir_fd=workers_fd)
            root_fd = tree.open_directory(stack, owner.root.name, dir_fd=workers_fd, private=True)
            os.mkdir("evidence", 0o700, dir_fd=root_fd)
            os.mkdir("workspace", 0o700, dir_fd=root_fd)
            evidence_fd = tree.open_directory(stack, "evidence", dir_fd=root_fd, private=True)
            workspace_fd = tree.open_directory(stack, "workspace", dir_fd=root_fd, private=True)
            owner._ids = tuple(tree.identity(os.fstat(fd)) for fd in
                (artifacts_fd, workers_fd, root_fd, evidence_fd, workspace_fd))
            owner._marker_id = workspace_api._write_new_file(root_fd, _MARKER, owner._marker_bytes)
        owner.verify_owned()
        return owner
    except BaseException:
        owner._failure = "worker allocation unproven; partial state retained"
        raise
