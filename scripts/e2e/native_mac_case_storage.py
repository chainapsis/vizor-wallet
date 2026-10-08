"""Fresh macOS support allocation and case-owned cleanup; never adopt old state.

The SDK probe declares a location, not ownership. This owner exclusively creates
that location before app launches, retains original identities, and composes
native cleanup internally before removing its own tree. Failed cases should use
retain(), which stops writers without removing native or filesystem state.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
import contextlib
import dataclasses
import json
import os
from pathlib import Path
import pwd
import secrets
import threading

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_mac_cleanup as native
import native_owned_tree as owned_tree


_TOKEN = object()
_MARKER = "mac-storage-owner.json"
_ENV = {"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"}


class MacCaseStorageError(runtime.RunnerError):
    """Ownership/removal is unproven; retain state and original failure evidence."""


@dataclasses.dataclass(frozen=True)
class MacCaseStorageCleanup:
    namespace: str
    support_directory: str
    native_observation: native.CaseMacCleanupObservation


def _home() -> Path:
    # Do not derive cleanup targets from caller HOME/CFFIXED_USER_HOME overrides.
    return Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(strict=True)


def _identity(details: os.stat_result) -> tuple[int, ...]:
    return owned_tree.identity(details)


def _check(details: os.stat_result, *, directory: bool, private: bool = False) -> None:
    try:
        owned_tree.check(details, directory=directory, private=private)
    except owned_tree.OwnedTreeError as error:
        raise MacCaseStorageError(str(error)) from error


def _open_directory(stack: contextlib.ExitStack, path, *, dir_fd=None, private=False) -> int:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dir_fd)
    stack.callback(os.close, descriptor)
    _check(os.fstat(descriptor), directory=True, private=private)
    return descriptor


def _open_chain(stack: contextlib.ExitStack, home: Path, target: Path, *, create: bool):
    if home.resolve(strict=True) != home or not home.is_absolute():
        raise MacCaseStorageError("support home is not canonical")
    relative = target.relative_to(home)
    parent = _open_directory(stack, home)
    identities = [_identity(os.fstat(parent))]
    parent_of_target = None
    for index, part in enumerate(relative.parts):
        # Never synthesize a container/Data/Library root. The SDK/OS must own it.
        if create and index >= len(relative.parts) - 3:
            try:
                os.mkdir(part, 0o700, dir_fd=parent)
            except FileExistsError:
                if index == len(relative.parts) - 1:
                    raise MacCaseStorageError("pre-existing support case is never adopted")
        if index == len(relative.parts) - 1:
            parent_of_target = parent
        parent = _open_directory(stack, part, dir_fd=parent, private=index == len(relative.parts) - 1)
        identities.append(_identity(os.fstat(parent)))
    return parent, parent_of_target, tuple(identities)


def _read_file(directory_fd: int, name: str, limit: int):
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(name, flags, dir_fd=directory_fd), "rb") as stream:
        details = os.fstat(stream.fileno())
        _check(details, directory=False)
        return stream.read(limit), _identity(details)


def _scan(directory_fd: int):
    try:
        return owned_tree.scan(directory_fd, marker=_MARKER)
    except owned_tree.OwnedTreeError as error:
        raise MacCaseStorageError(str(error)) from error


def _remove_entries(directory_fd, entries, verify_attachment):
    try:
        owned_tree.remove_entries(directory_fd, entries, verify_attachment)
    except owned_tree.OwnedTreeError as error:
        raise MacCaseStorageError(str(error)) from error


class MacCaseStorage:
    """Use prepare_mac_case_storage(); one cooperative owner, no concurrent calls.

    Native wallet writers must use start_app(). Ordinary backend/control phases
    can use the same case owner but must not write untracked native storage.
    This owner never removes the case workspace or rewrites its context/result.
    """

    def __init__(self, case, helper, home, path, ids, marker_bytes, marker_identity, token):
        self.case = case
        self.helper = helper
        self.path = path
        self._home = home
        self._ids = ids
        self._marker_bytes = marker_bytes
        self._marker_identity = marker_identity
        self._token = token
        self._writers: list[runtime.ManagedProcess] = []
        self._finished = False
        self._failure: str | None = None

    def verify_owned(self) -> None:
        if self._token is not _TOKEN or self._failure is not None:
            raise MacCaseStorageError("support ownership is unproven")
        try:
            self.case.workspace.verify_owned()
            with contextlib.ExitStack() as stack:
                support_fd, _, ids = _open_chain(stack, self._home, self.path, create=False)
                data, identity = _read_file(support_fd, _MARKER, len(self._marker_bytes) + 1)
                if ids != self._ids or data != self._marker_bytes or identity != self._marker_identity:
                    raise MacCaseStorageError("support ownership metadata changed")
        except (OSError, ValueError, RuntimeError) as error:
            self._failure = "support ownership unproven"
            raise MacCaseStorageError(self._failure) from error

    def start_app(self, arguments: Sequence[str] = (), *, env: Mapping[str, str]) -> runtime.ManagedProcess:
        if self._finished:
            raise MacCaseStorageError("support lifecycle is finished")
        if isinstance(arguments, (str, bytes)):
            raise MacCaseStorageError("app arguments must be a sequence")
        self.verify_owned()
        self.helper.verify_unchanged()
        managed = self.case.start_process([str(self.helper.cohort_executable), *arguments], env=env)
        self._writers.append(managed)
        return managed

    def _verify_context(self) -> None:
        context = Path(self.case.workspace.context_path)
        if not self._writers:
            if context.exists() or context.is_symlink():
                raise MacCaseStorageError("unexpected app context without an owned app launch")
            return
        with contextlib.ExitStack() as stack:
            case_fd = _open_directory(stack, self.case.workspace.root, private=True)
            data, _ = _read_file(case_fd, "native-context.json", 8193)
        if len(data) > 8192:
            raise MacCaseStorageError("app context exceeds validation limit")
        value = native._require_fields(json.loads(data, object_pairs_hook=native._unique_object), {
            "schema_version", "namespace", "pid", "support_directory", "secure_store_services",
            "preferences_prefix", "os_background_scheduling_enabled", "storage_cleanup_completed",
        })
        service = f"com.keplr.vizor.regtest.secure_store.e2e.{self.case.workspace.namespace}"
        if (
            type(value["schema_version"]) is not int or value["schema_version"] != 1
            or value["namespace"] != self.case.workspace.namespace
            or type(value["pid"]) is not int or value["pid"] != self._writers[-1].process.pid
            or value["support_directory"] != str(self.path)
            or value["secure_store_services"] != [service, service + ".mnemonic"]
            or value["preferences_prefix"] != f"flutter.vizor_e2e_{self.case.workspace.namespace}."
            or value["os_background_scheduling_enabled"] is not False
            or value["storage_cleanup_completed"] is not False
        ):
            raise MacCaseStorageError("app context does not match the owned app/support scope")

    def retain(self) -> None:
        """Stop writers on a failed scenario; preserve secrets, support and evidence."""
        self._finished = True
        self.case.close()

    def close(self, *, timeout: float, cancel_event: threading.Event) -> MacCaseStorageCleanup:
        """Finish successful scenarios; prove native absence before anchored removal.

        Not a scenario PASS. The runner must use retain() for failed scenarios.
        Any failed/partial finalization is sticky, never retry/adopt to claim success.
        """
        if self._finished:
            raise MacCaseStorageError("support lifecycle is finished")
        self._finished = True
        try:
            self.case.close()  # Always stop writers before filesystem/context checks.
            self.verify_owned()
            self._verify_context()
            with contextlib.ExitStack() as stack:
                support_fd, parent_fd, ids = _open_chain(stack, self._home, self.path, create=False)
                if ids != self._ids:
                    raise MacCaseStorageError("support identity changed before cleanup")
                tree = _scan(support_fd)  # Reject unsafe children before native mutation.
                observed = native.clean_mac_case(self.case, self.helper, timeout=timeout, cancel_event=cancel_event)
                self.verify_owned()
                if _scan(support_fd) != tree:
                    raise MacCaseStorageError("support tree changed during native cleanup")
                def verify_attachment():
                    self.case.workspace.verify_owned()
                    # Reopen the entire original chain; a moved/replaced parent is not adopted.
                    with contextlib.ExitStack() as check:
                        _, _, current_ids = _open_chain(check, self._home, self.path, create=False)
                    if current_ids != self._ids:
                        raise MacCaseStorageError("support attachment changed during removal")
                _remove_entries(support_fd, tree, verify_attachment)
                verify_attachment()
                os.rmdir(self.path.name, dir_fd=parent_fd)
                try:
                    os.stat(self.path.name, dir_fd=parent_fd, follow_symlinks=False)
                except FileNotFoundError:
                    return MacCaseStorageCleanup(self.case.workspace.namespace, str(self.path), observed)
                raise MacCaseStorageError("support removal absence is unproven")
        except BaseException as error:
            self._failure = "support finalization unproven; retain remaining state/evidence"
            # No state removal follows a failed observation. Case close already
            # attempted all writers; preserve cancellation/interrupt classification.
            if not isinstance(error, Exception) or isinstance(error, runtime.Cancelled):
                raise
            raise MacCaseStorageError(self._failure, getattr(error, "exit_code", 1)) from error


def prepare_mac_case_storage(
    case: NativeCaseLifecycle, helper: native.CapturedMacCleanupHelper, *,
    timeout: float, cancel_event: threading.Event,
) -> MacCaseStorage:
    """Read the signed SDK location, then exclusively allocate before any writers.

    A partial allocation is retained, never adopted by retry. The helper/cohort
    builder must compile the trusted isolated profile; signing is not provenance.
    """
    if not isinstance(case, NativeCaseLifecycle) or not isinstance(helper, native.CapturedMacCleanupHelper):
        raise MacCaseStorageError("support allocation requires an owned case/captured helper")
    case.workspace.verify_owned()
    manifest = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    if not manifest["scenario_id"].startswith("flutter.macos.") or not case.accepting_launches or case.launched_process_count:
        raise MacCaseStorageError("support allocation requires a fresh unlaunched macOS case")
    helper.verify_unchanged()
    result = case.run_command(
        [str(helper.executable), "--support-location", "--namespace", case.workspace.namespace, "--team", helper.team],
        env=_ENV, timeout=timeout, cancel_event=cancel_event,
    )
    if result.returncode != 0:
        raise MacCaseStorageError("native support location probe failed", result.returncode)
    helper.verify_unchanged()
    try:
        data = "".join(result.lines)
        if len(data.encode("utf-8")) > 8192:
            raise MacCaseStorageError("support location probe exceeds its limit")
        value = native._require_fields(json.loads(data, object_pairs_hook=native._unique_object), {
            "schema_version", "platform", "mode", "namespace", "expected_team", "identity",
            "support_directory", "completed",
        })
        home = _home()
        path = home / "Library/Containers/com.keplr.vizor/Data/Library/Application Support/com.keplr.vizor/e2e" / case.workspace.namespace
        if (
            type(value["schema_version"]) is not int or value["schema_version"] != 1
            or value["platform"] != "macos" or value["mode"] != "support_location"
            or value["namespace"] != case.workspace.namespace or value["expected_team"] != helper.team
            or value["completed"] is not True or value["support_directory"] != str(path)
            or value["identity"] != {"bundle_id": "com.keplr.vizor", "team_id": helper.team,
                                     "application_identifier": f"{helper.team}.com.keplr.vizor"}
        ):
            raise MacCaseStorageError("support probe does not match actual sandbox/case identity")
        marker = (json.dumps({"schema_version": 1, "namespace": case.workspace.namespace,
                             "workspace": str(case.workspace.root), "owner_nonce": secrets.token_hex(16)},
                            sort_keys=True) + "\n").encode("ascii")
        with contextlib.ExitStack() as stack:
            support_fd, _, ids = _open_chain(stack, home, path, create=True)
            with os.fdopen(os.open(_MARKER, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                   0o600, dir_fd=support_fd), "wb") as stream:
                stream.write(marker)
                stream.flush()
                identity = _identity(os.fstat(stream.fileno()))
        owner = MacCaseStorage(case, helper, home, path, ids, marker, identity, _TOKEN)
        owner.verify_owned()
        # Exclusive support allocation protects cooperative namespace ownership,
        # but a previous failed run can have left secrets without this folder.
        # Verify absence read-only; never erase/adopt that pre-existing state.
        helper.verify_unchanged()
        preflight = case.run_command(
            [str(helper.executable), "--verify", "--namespace", case.workspace.namespace, "--team", helper.team],
            env=_ENV, timeout=timeout, cancel_event=cancel_event,
        )
        if preflight.returncode != 0:
            raise MacCaseStorageError("pre-existing native state or absence unproven", preflight.returncode)
        helper.verify_unchanged()
        native._validate_receipt(preflight.lines, namespace=case.workspace.namespace, team=helper.team, mode="verify")
        owner.verify_owned()
        return owner
    except runtime.Cancelled:
        raise
    except (OSError, ValueError, TypeError, RuntimeError, RecursionError) as error:
        raise MacCaseStorageError(
            "support allocation unproven; retain partial state/evidence", getattr(error, "exit_code", 1),
        ) from error
