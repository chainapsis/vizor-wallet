"""Run an original published offline signer in a separately owning case.

Returned JSON is signing-tool output, never chain inclusion or scenario PASS.
"""
from __future__ import annotations

import contextlib
import json
import math
import os
import threading

import e2e_runtime as runtime
from funder_build import ProducedRegtestFunder
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree


_COMMANDS = {"identity", "build", "build-orchard", "build-transparent", "build-batch"}
_MAX_JSON_BYTES = 2 * 1024 * 1024


class FunderExecutionError(runtime.RunnerError):
    """Original execution, output or source attachment is unproven."""


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise FunderExecutionError("signer JSON repeats an object field")
        result[key] = value
    return result


def _nonfinite(value):
    raise FunderExecutionError("signer JSON contains a non-finite number")


def _finite_float(value):
    number = float(value)
    if not math.isfinite(number):
        raise FunderExecutionError("signer JSON number overflows its finite range")
    return number


def run_offline_funder(case: NativeCaseLifecycle, artifact: ProducedRegtestFunder,
                       command: str, request=None, *, timeout: float = 60.0,
                       cancel_event=None):
    """Own input, process group and complete output; do not broadcast or mine.

    Every attempt retains its input/process evidence. The caller still owns
    final case shutdown and backend/native cleanup after any execution failure.
    """
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches:
        raise FunderExecutionError("expected an accepting original consumer case")
    if not isinstance(artifact, ProducedRegtestFunder):
        raise FunderExecutionError("expected the original published producer handle")
    if not isinstance(command, str) or command not in _COMMANDS:
        raise FunderExecutionError("unsupported offline signer command")
    if (command == "identity" and request is not None) or (command != "identity" and not isinstance(request, dict)):
        raise FunderExecutionError("identity accepts no input; build commands require one object")
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
        raise FunderExecutionError("signer timeout must be positive and finite")
    payload = None
    if request is not None:
        try:
            payload = (json.dumps(request, allow_nan=False, ensure_ascii=True, separators=(",", ":")) + "\n").encode("ascii")
        except (TypeError, ValueError) as error:
            raise FunderExecutionError("signer input is not finite JSON") from error
        if len(payload) > _MAX_JSON_BYTES:
            raise FunderExecutionError("signer input exceeds its bound")
    cancellation = cancel_event if cancel_event is not None else threading.Event()
    if cancellation.is_set():
        raise runtime.Cancelled()
    case.workspace.verify_owned()
    artifact.verify_unchanged()
    with contextlib.ExitStack() as stack:
        parent = tree.open_directory(stack, case.workspace.root, private=True)
        stdin = None
        name = f"funder-input-{case.launched_process_count:04d}.json"
        input_identity = None
        if payload is not None:
            descriptor = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
            stdin = stack.enter_context(os.fdopen(descriptor, "w+b"))
            stdin.write(payload)
            stdin.flush()
            stdin.seek(0)
            os.fchmod(stdin.fileno(), 0o400)
            input_identity = tree.identity(os.fstat(stdin.fileno()))
        # The file descriptor stays open through positive process/output join.
        result = case.run_command([str(artifact.binary), command], env=os.environ,
                        stdin=stdin, timeout=timeout, cancel_event=cancellation)
        case.workspace.verify_owned()
        artifact.verify_unchanged()
        if stdin is not None:
            if (tree.identity(os.fstat(stdin.fileno())) != input_identity
                or tree.identity(os.stat(name, dir_fd=parent, follow_symlinks=False)) != input_identity):
                raise FunderExecutionError("original signer input attachment changed")
            stdin.seek(0)
            if stdin.read(_MAX_JSON_BYTES + 1) != payload:
                raise FunderExecutionError("original signer input bytes changed")
        if result.returncode != 0:
            raise FunderExecutionError("offline signer failed; preserve its owned process log", result.returncode)
        output = "".join(result.lines)
        if len(output.encode("utf-8")) > _MAX_JSON_BYTES:
            raise FunderExecutionError("signer output exceeds its bound")
        try:
            value = json.loads(output, object_pairs_hook=_object, parse_constant=_nonfinite,
                               parse_float=_finite_float)
        except (TypeError, ValueError) as error:
            raise FunderExecutionError("signer did not return exactly one JSON object") from error
        if (not isinstance(value, dict) or type(value.get("schema_version")) is not int
            or value["schema_version"] != 1):
            raise FunderExecutionError("signer output schema is invalid")
        if command == "identity" and (set(value) != {"schema_version", "miner_address"}
            or value["miner_address"] != "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX"):
            raise FunderExecutionError("signer identity is not the fixed public regtest miner")
        return value
