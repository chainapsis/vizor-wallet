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


def _input_payload(request):
    # iterencode may emit one whole escaped string/integer as a chunk. Bound
    # those atoms before encoding too; visit containers without copying them.
    active = set()
    remaining = _MAX_JSON_BYTES
    def check_atoms(value):
        nonlocal remaining
        remaining -= 1
        if remaining < 0:
            raise FunderExecutionError("signer input exceeds its bound")
        if isinstance(value, str):
            remaining -= 1  # Both quotes; the node check already counted one.
            if remaining < 0:
                raise FunderExecutionError("signer input exceeds its bound")
            for character in value:
                code = ord(character)
                width = (2 if character in '\"\\\b\f\n\r\t' else
                         1 if 0x20 <= code <= 0x7E else
                         6 if code <= 0xFFFF else 12)
                remaining -= width
                if remaining < 0:
                    raise FunderExecutionError("signer input exceeds its bound")
        if isinstance(value, int):
            # Conservative decimal digit upper bound without a huge str(int).
            digits = value.bit_length() * 30103 // 100000 + 1 + (value < 0)
            if digits > _MAX_JSON_BYTES:
                raise FunderExecutionError("signer input exceeds its bound")
        if isinstance(value, (dict, list, tuple)):
            if len(value) > _MAX_JSON_BYTES:
                raise FunderExecutionError("signer input exceeds its bound")
            marker = id(value)
            if marker in active:
                raise ValueError("circular JSON input")
            active.add(marker)
            try:
                children = (child for pair in value.items() for child in pair) if isinstance(value, dict) else value
                for child in children:
                    check_atoms(child)
            finally:
                active.remove(marker)
    try:
        check_atoms(request)
        payload = bytearray()
        encoder = json.JSONEncoder(allow_nan=False, ensure_ascii=True, separators=(",", ":"))
        for chunk in encoder.iterencode(request):
            if len(chunk) > _MAX_JSON_BYTES - len(payload) - 1:
                raise FunderExecutionError("signer input exceeds its bound")
            payload.extend(chunk.encode("ascii"))
    except (TypeError, ValueError, RecursionError) as error:
        raise FunderExecutionError("signer input is not finite JSON") from error
    payload.append(10)
    return bytes(payload)


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
    payload = None if request is None else _input_payload(request)
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
            descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent)
            with os.fdopen(descriptor, "wb") as writer:
                writer.write(payload)
                writer.flush()
                os.fchmod(writer.fileno(), 0o400)
                input_identity = tree.identity(os.fstat(writer.fileno()))
            descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
            stdin = stack.enter_context(os.fdopen(descriptor, "rb"))
            if tree.identity(os.fstat(stdin.fileno())) != input_identity:
                raise FunderExecutionError("original signer input changed before read-only reopen")
        def verify_input():
            if stdin is None:
                return
            if (tree.identity(os.fstat(stdin.fileno())) != input_identity
                or tree.identity(os.stat(name, dir_fd=parent, follow_symlinks=False)) != input_identity):
                raise FunderExecutionError("original signer input attachment changed")
            stdin.seek(0)
            if stdin.read(_MAX_JSON_BYTES + 1) != payload:
                raise FunderExecutionError("original signer input bytes changed")

        def verify_attachments():
            errors = []
            # A changed consumer workspace must not skip sticky producer checks
            # or inspection through the original input's still-open parent FD.
            for check in (case.workspace.verify_owned, artifact.verify_unchanged, verify_input):
                try:
                    check()
                except BaseException as error:
                    errors.append(error)
            if errors:
                detail = "; ".join(f"{type(error).__name__}: {error}" for error in errors)
                raise errors[0] from FunderExecutionError("signer attachment verification failed: " + detail)

        # Keep the original descriptors open on both normal and exceptional
        # execution exits. Attachment failure must not reclassify the primary.
        try:
            result = case.run_command([str(artifact.binary), command], env=os.environ,
                            stdin=stdin, timeout=timeout, cancel_event=cancellation,
                            max_output_bytes=_MAX_JSON_BYTES)
            if result.returncode != 0:
                raise FunderExecutionError("offline signer failed; preserve its owned process log", result.returncode)
        except BaseException as primary:
            try:
                verify_attachments()
            except BaseException as attachment:
                raise primary from attachment
            raise
        verify_attachments()
        output = "".join(result.lines)
        if len(output.encode("utf-8")) > _MAX_JSON_BYTES:
            raise FunderExecutionError("signer output exceeds its bound")
        try:
            value = json.loads(output, object_pairs_hook=_object, parse_constant=_nonfinite,
                               parse_float=_finite_float)
        except (TypeError, ValueError, RecursionError) as error:
            raise FunderExecutionError("signer did not return exactly one JSON object") from error
        if (not isinstance(value, dict) or type(value.get("schema_version")) is not int
            or value["schema_version"] != 1):
            raise FunderExecutionError("signer output schema is invalid")
        if command == "identity" and (set(value) != {"schema_version", "miner_address"}
            or value["miner_address"] != "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX"):
            raise FunderExecutionError("signer identity is not the fixed public regtest miner")
        return value
