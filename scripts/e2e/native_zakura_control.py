"""Pump bounded loopback controls on the original case execution owner.

No HTTP thread may mutate the cooperative case. The native executor pumps this
server while observing its original app child, including across same-case restarts.
"""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
import http.client
import json
import math
import threading
import time

import e2e_runtime as runtime
from funder_build import ProducedRegtestFunder
from native_case_lifecycle import NativeCaseLifecycle
from native_zakura_backend import OwnedNativeZakuraBackend
from native_zakura_front import OwnedNativeZakuraFront
from zakura_funding import fund_zakura


_TOKEN = object()
_MAX_HEADERS = 16 * 1024
_MAX_BODY = 64 * 1024
_MAX_RESPONSE = 2 * 1024 * 1024


class NativeZakuraControlError(runtime.RunnerError):
    """Original control execution or listener closure is unproven."""


class _BadRequest(ValueError):
    pass


def _remaining(deadline, cancel):
    if cancel.is_set():
        raise runtime.Cancelled()
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise NativeZakuraControlError("control deadline expired", 124)
    return remaining


class _RequestReader:
    """Bound cumulative headers/body reads by one receive deadline, not per byte."""
    def __init__(self, stream, connection, deadline):
        self._stream, self._connection, self._deadline = stream, connection, deadline
        self._buffer = bytearray()
        self._headers = 0

    def _receive(self, count):
        remaining = self._deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("control receive deadline expired")
        self._connection.settimeout(remaining)
        return self._stream.read1(count)

    def readline(self, size=-1):
        limit = min(_MAX_HEADERS - self._headers + 1, size if size >= 0 else _MAX_HEADERS + 1)
        while True:
            newline = self._buffer.find(b"\n")
            if newline >= 0 or len(self._buffer) >= limit:
                count = min(newline + 1 if newline >= 0 else len(self._buffer), limit)
                value = bytes(self._buffer[:count])
                del self._buffer[:count]
                self._headers += count
                if self._headers > _MAX_HEADERS:
                    raise http.client.HTTPException("control headers exceed their byte bound")
                return value
            chunk = self._receive(min(4096, limit - len(self._buffer)))
            if not chunk:
                value = bytes(self._buffer)
                self._buffer.clear()
                self._headers += len(value)
                return value
            self._buffer.extend(chunk)

    def read(self, count):
        if not 0 <= count <= _MAX_BODY:
            raise ValueError("control body exceeds its byte bound")
        while len(self._buffer) < count:
            chunk = self._receive(min(4096, count - len(self._buffer)))
            if not chunk:
                raise ValueError("control body ended before Content-Length")
            self._buffer.extend(chunk)
        value = bytes(self._buffer[:count])
        del self._buffer[:count]
        return value

    def close(self):
        self._stream.close()


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise _BadRequest("control JSON repeats an object field")
        result[key] = value
    return result


def _nonfinite(_value):
    raise _BadRequest("control JSON requires integer values")


def _integer(value, label, minimum, maximum):
    if type(value) is not int or not minimum <= value <= maximum:
        raise _BadRequest(label + " must be a bounded integer")
    return value


class OwnedNativeZakuraControl:
    def __init__(self, case, backend, front, artifact, port, activation, token):
        if token is not _TOKEN:
            raise NativeZakuraControlError("use prepare_native_zakura_control")
        self._case, self._backend, self._front = case, backend, front
        self._artifact, self._port, self._activation = artifact, port, activation
        self._owner = threading.get_ident()
        self._server = None
        self._closed = self._serving = False
        self._failure = None
        self._requests = 0

    @property
    def closed(self):
        return self._closed

    @property
    def url(self):
        return f"http://127.0.0.1:{self._port}"

    def _require_owner(self):
        if threading.get_ident() != self._owner or self._serving:
            raise NativeZakuraControlError("control requires its original non-reentrant execution owner")

    def _bind(self):
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def setup(self):
                super().setup()
                self.rfile = _RequestReader(self.rfile, self.connection,
                    min(owner._deadline, time.monotonic() + 2.0))

            def log_message(self, *_args):
                pass

            def handle_one_request(self):
                self.requestline, self.request_version, self.command = "", "HTTP/1.0", ""
                try:
                    super().handle_one_request()
                except http.client.HTTPException:
                    self.send_error(431, "Control headers exceed their bound")

            def do_GET(self):
                self.dispatch("GET")

            def do_POST(self):
                self.dispatch("POST")

            def dispatch(self, method):
                self.close_connection = True
                status = 200
                try:
                    if self.headers.get("Transfer-Encoding") is not None:
                        raise _BadRequest("chunked controls are unsupported")
                    lengths = self.headers.get_all("Content-Length", [])
                    if len(lengths) > 1 or (lengths and not lengths[0].isascii()):
                        raise _BadRequest("control Content-Length is ambiguous")
                    text = lengths[0] if lengths else "0"
                    if not text.isdecimal() or len(text) > 6:
                        raise _BadRequest("control Content-Length is invalid")
                    length = _integer(int(text), "Content-Length", 0, _MAX_BODY)
                    if method == "GET" and length:
                        raise _BadRequest("GET control cannot have a body")
                    try:
                        payload = json.loads(self.rfile.read(length) or b"{}",
                            object_pairs_hook=_object, parse_constant=_nonfinite, parse_float=_nonfinite)
                    except (ValueError, RecursionError, TimeoutError) as error:
                        raise _BadRequest("control body is incomplete or invalid integer JSON") from error
                    if not isinstance(payload, dict):
                        raise _BadRequest("control payload must be an object")
                    _remaining(owner._deadline, owner._cancel)
                    result = owner._dispatch(method, self.path, payload)
                    _remaining(owner._deadline, owner._cancel)
                except _BadRequest as error:
                    status, result = 400, {"error": str(error)}
                except Exception as error:
                    owner._failure = error
                    status, result = 500, {"error": "original control operation failed; retain case evidence"}
                body = json.dumps(result, allow_nan=False).encode("utf-8")
                if len(body) > _MAX_RESPONSE:
                    raise NativeZakuraControlError("control response exceeds its byte bound")
                try:
                    self.connection.settimeout(min(2.0, max(0.001, owner._deadline - time.monotonic())))
                    self.send_response(status)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError, TimeoutError):
                    pass  # Original mutation/evidence is not undone by a vanished client.
                owner._requests += 1

        class Server(HTTPServer):
            def handle_error(self, _request, _address):
                # socketserver would otherwise print and swallow an owner failure.
                raise

        self._server = Server(("127.0.0.1", self._port), Handler, bind_and_activate=False)
        self._server.server_bind()
        self._server.server_activate()

    def _dispatch(self, method, path, payload):
        if method == "GET" and payload == {}:
            if path == "/health":
                return {"ok": True}
            if path == "/status":
                parity = self._backend.wait_synced(deadline=self._deadline)
                height = parity["height"]
                if type(height) is not int or not 1 <= height <= 0xFFFFFFFF:
                    raise NativeZakuraControlError("original parity height is invalid")
                return {"zcashdHeight": height, "lightwalletdHeight": height,
                    "ironwoodActivationHeight": self._activation,
                    "ironwoodActive": height >= self._activation,
                    "consensusBranchId": parity["consensus_branch_id"]}
            if path == "/mempool":
                txids = self._backend.rpc("getrawmempool", deadline=self._deadline)
                if not isinstance(txids, list) or any(not isinstance(txid, str) for txid in txids):
                    raise NativeZakuraControlError("original mempool response is invalid")
                return {"size": len(txids), "txids": txids}
        if method == "POST" and path == "/mine" and set(payload) == {"blocks"}:
            count = _integer(payload["blocks"], "blocks", 1, 1000)
            return self._backend.mine(count)
        if method == "POST" and path == "/fund-confirmed" and set(payload) == {
                "address", "amount_zatoshi", "source_height", "recipient_pool", "confirmations"}:
            if self._artifact is None:
                raise _BadRequest("confirmed funding requires an original signer producer")
            address, pool = payload["address"], payload["recipient_pool"]
            if not isinstance(address, str) or not 1 <= len(address) <= 4096:
                raise _BadRequest("funding address is invalid")
            if not isinstance(pool, str) or pool not in {"ironwood", "orchard", "transparent"}:
                raise _BadRequest("funding pool is invalid")
            amount = _integer(payload["amount_zatoshi"], "zatoshis", 1, 2_100_000_000_000_000)
            source = _integer(payload["source_height"], "source height", 1, 0xFFFFFFFF)
            confirmations = _integer(payload["confirmations"], "confirmations", 1, 1000)
            return fund_zakura(self._case, self._backend, self._artifact,
                recipient_address=address, amount_zatoshi=amount, source_height=source,
                recipient_pool=pool, confirmations=confirmations,
                timeout=_remaining(self._deadline, self._cancel), cancel_event=self._cancel)
        raise _BadRequest("unsupported control path or exact payload")

    def pump(self, *, deadline, cancel_event, timeout=0.05):
        """Handle at most one request on the original owner; no background mutation."""
        self._require_owner()
        if self._closed or self._server is None or self._failure is not None:
            raise NativeZakuraControlError("control listener is unavailable or failed") from self._failure
        if (isinstance(deadline, bool) or not isinstance(deadline, (int, float))
            or not math.isfinite(deadline) or isinstance(timeout, bool)
            or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or not 0 <= timeout <= 0.05):
            raise NativeZakuraControlError("control pump deadline/poll interval is invalid")
        self._front.assert_running()
        remaining = _remaining(deadline, cancel_event)
        self._deadline, self._cancel = deadline, cancel_event
        self._server.timeout = min(timeout, remaining)
        before = self._requests
        self._serving = True
        try:
            self._server.handle_request()
            if self._failure is not None:
                raise self._failure
            self._front.assert_running()
            _remaining(deadline, cancel_event)
        except BaseException as error:
            self._failure = error
            raise
        finally:
            self._serving = False
        return self._requests != before

    def drive(self, process, *, timeout, cancel_event):
        """Observe/join one original app while pumping controls; caller owns retention."""
        self._require_owner()
        self._case._require_member(process)
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
            raise NativeZakuraControlError("control drive timeout must be positive and finite")
        deadline = time.monotonic() + timeout
        while process.process.poll() is None:
            self.pump(deadline=deadline, cancel_event=cancel_event)
        return self._case.wait_process(process, timeout=_remaining(deadline, cancel_event), cancel_event=cancel_event)

    def close(self):
        """Synchronous original-owner closure means no accepted handler survives it."""
        self._require_owner()
        if self._server is not None:
            self._server.server_close()
            if self._server.socket.fileno() != -1:
                raise NativeZakuraControlError("original control listener closure is unproven")
        self._closed = True


def prepare_native_zakura_control(case, backend, front, *, artifact=None):
    if (not isinstance(case, NativeCaseLifecycle) or not isinstance(backend, OwnedNativeZakuraBackend)
        or backend._case is not case or not isinstance(front, OwnedNativeZakuraFront)
        or front._case is not case or front._backend is not backend or backend._front is not front
        or backend._control is not None or not case.accepting_launches
        or (artifact is not None and not isinstance(artifact, ProducedRegtestFunder))):
        raise NativeZakuraControlError("expected unused original case/backend/front/signer handles")
    front.assert_running()
    manifest = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    owner = OwnedNativeZakuraControl(case, backend, front, artifact, manifest["zcashd_rpc_port"],
        manifest["regtest_ironwood_activation_height"], _TOKEN)
    backend._control = owner  # Register before binding even a partial listener.
    try:
        owner._bind()
    except BaseException as primary:
        try:
            owner.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
    return owner
