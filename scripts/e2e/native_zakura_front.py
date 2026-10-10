"""Own a verified LWD front through the original case, not external receipts.

The caller owns leased manifest ports and final backend/native teardown. Source
continuity during launch is checked, not hermetic build/cache provenance.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import stat
import threading
import time
from urllib.parse import urljoin, urlparse, unquote

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
from native_zakura_backend import OwnedNativeZakuraBackend
from zakura_genesis import OwnedZakuraGenesisProof


_TOKEN = object()
_OUTPUT_BYTES = 2 * 1024 * 1024
_SOURCE_FILES = (
    "scripts/e2e/zakura_lwd_shim.dart",
    "integration_test/support/verified_zakura_genesis.dart",
    "integration_test/support/zakura_lightwalletd_shim.dart",
    "integration_test/support/regtest_lightwalletd_proxy.dart",
    "lib/src/generated/service.pb.dart", "lib/src/generated/service.pbgrpc.dart",
    "lib/src/generated/service.pbenum.dart", "lib/src/generated/compact_formats.pb.dart",
    "lib/src/generated/compact_formats.pbenum.dart", "pubspec.lock",
    ".dart_tool/package_config.json",
)


class NativeZakuraFrontError(runtime.RunnerError):
    """Front startup, original child or exact RPC adaptation is unproven."""


def _capture(path, *, chunks=None):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        details = os.fstat(descriptor)
        if (not stat.S_ISREG(details.st_mode) or details.st_uid not in {0, os.getuid()}
            or details.st_mode & 0o022 or details.st_nlink != 1 or details.st_size > 32 * 1024 * 1024):
            raise NativeZakuraFrontError("front source/tool must be an owned bounded regular file")
        digest = hashlib.sha256()
        total = 0
        with os.fdopen(descriptor, "rb", closefd=False) as source:
            for chunk in iter(lambda: source.read(min(64 * 1024, details.st_size - total + 1)), b""):
                total += len(chunk)
                if total > details.st_size:
                    raise NativeZakuraFrontError("front source/tool grew during capture")
                digest.update(chunk)
                if chunks is not None:
                    chunks.append(chunk)
        identity = tree.identity(details)
        if (tree.identity(os.fstat(descriptor)) != identity
            or tree.identity(path.lstat()) != identity):
            raise NativeZakuraFrontError("front source/tool changed during capture")
        return identity, digest.hexdigest()
    finally:
        os.close(descriptor)


class OwnedNativeZakuraFront:
    def __init__(self, case, backend, genesis, dart, source_root, port, snapshot, timeout, token):
        if token is not _TOKEN:
            raise NativeZakuraFrontError("use prepare_native_zakura_front")
        self._case, self._backend, self._genesis = case, backend, genesis
        self._dart, self._source_root, self._port = dart, source_root, port
        self._snapshot, self._timeout = snapshot, timeout
        self._attempted = self._finished = False
        self._process = self._ready = None
        self._lines = []
        self._available = None
        self._availability_sequence = 0

    @property
    def process(self):
        """Original case-registered child, never a caller-supplied PID."""
        return self._process

    def assert_running(self):
        """A caller must monitor this during execution; startup is not wallet PASS."""
        self._backend._running()
        if self._finished or self._process is None:
            raise NativeZakuraFrontError("front is unavailable or finished")
        self._case._require_member(self._process)
        if self._process.process.poll() is not None:
            raise NativeZakuraFrontError("owned front exited; retain its process log")
        capture = self._process._capture
        if capture.output_limit_error is not None:
            raise capture.output_limit_error
        if capture.errors:
            raise NativeZakuraFrontError("owned front output capture failed")

    def _query(self, method, payload, deadline, cancel):
        fixture = self._backend._fixture
        remaining = deadline - time.monotonic()
        result = self._case.run_command([str(fixture.grpcurl), "-plaintext",
            "-max-time", f"{min(remaining, 2.0):.3f}", "-import-path", str(fixture.proto_dir),
            "-proto", fixture.service_proto.name, "-d", json.dumps(payload),
            f"127.0.0.1:{self._port}", "cash.z.wallet.sdk.rpc.CompactTxStreamer/" + method],
            env=os.environ.copy(), timeout=remaining, cancel_event=cancel, max_output_bytes=_OUTPUT_BYTES)
        output = "".join(result.lines)
        if result.returncode != 0:
            if "connection refused" in output.lower():
                return None  # Only the expected pre-listen transport failure is retryable.
            raise NativeZakuraFrontError("front RPC failed; retain its original process log", result.returncode)
        try:
            value = json.loads(output)
        except (ValueError, RecursionError) as error:
            raise NativeZakuraFrontError("front RPC returned invalid JSON") from error
        if not isinstance(value, dict):
            raise NativeZakuraFrontError("front RPC returned a non-object")
        return value

    def set_available(self, available, *, timeout=10.0, cancel_event=None):
        """Inject an outage in this original front, never stop a shared service."""
        if type(available) is not bool:
            raise NativeZakuraFrontError("front availability must be boolean")
        runtime._positive_timeout(timeout)
        cancel = cancel_event if cancel_event is not None else threading.Event()
        deadline = time.monotonic() + timeout
        self.assert_running()
        if self._ready is None or self._available is None:
            raise NativeZakuraFrontError("front readiness is unproven")
        if cancel.is_set():
            raise runtime.Cancelled()
        if available != self._available:
            floor = len(self._lines)
            self._case._require_member(self._process)
            runtime._signal_group(self._process,
                signal.SIGUSR2 if available else signal.SIGUSR1, deadline=deadline)
            while True:
                self.assert_running()
                if cancel.is_set():
                    raise runtime.Cancelled()
                if time.monotonic() >= deadline:
                    raise NativeZakuraFrontError("front availability acknowledgement timed out", 124)
                for line in self._lines[floor:]:
                    floor += 1
                    try:
                        value = json.loads(line)
                    except ValueError:
                        continue  # Other bounded, original daemon diagnostics.
                    if not isinstance(value, dict) or value.get("event") != "zakura-lwd-shim-availability":
                        continue
                    if (set(value) != {"event", "fixture_run_id", "pid", "available", "sequence"}
                        or value["fixture_run_id"] != self._ready["fixture_run_id"]
                        or type(value["pid"]) is not int or value["pid"] != self._process.process.pid
                        or type(value["available"]) is not bool or value["available"] != available
                        or type(value["sequence"]) is not int
                        or value["sequence"] != self._availability_sequence + 1):
                        raise NativeZakuraFrontError("front availability acknowledgement differs from its original owner")
                    self._available = available
                    self._availability_sequence = value["sequence"]
                    return {"available": available, "sequence": self._availability_sequence,
                        "fixture_run_id": self._ready["fixture_run_id"]}
                cancel.wait(min(0.01, max(0, deadline - time.monotonic())))
        return {"available": available, "sequence": self._availability_sequence,
            "fixture_run_id": self._ready["fixture_run_id"]}

    def start(self, *, cancel_event=None):
        if self._attempted or self._finished:
            raise NativeZakuraFrontError("front startup was already attempted or finished")
        self._attempted = True
        cancel = cancel_event if cancel_event is not None else threading.Event()
        deadline = time.monotonic() + self._timeout
        floor = self._case.launched_process_count

        def check():
            if cancel.is_set():
                raise runtime.Cancelled()
            if time.monotonic() >= deadline:
                raise NativeZakuraFrontError("front readiness deadline expired", 124)
            self._backend._running()
            if self._process is not None:
                self.assert_running()

        def raw(method, payload):
            check()
            value = self._backend.grpc(method, payload, deadline=deadline)
            check()
            return value

        def front(method, payload):
            check()
            value = self._query(method, payload, deadline, cancel)
            check()
            return value

        try:
            check()
            handoff = self._genesis.handoff()
            state = self._genesis.tree_state()
            if {path: _capture(path) for path in self._snapshot} != self._snapshot:
                raise NativeZakuraFrontError("front launch source/tool changed")
            check()
            self._process = self._case.start_process([str(self._dart),
                "--packages=" + str(self._source_root / ".dart_tool/package_config.json"),
                str(self._source_root / "scripts/e2e/zakura_lwd_shim.dart"),
                "--listen-port", str(self._port), "--upstream-port", str(handoff["upstream_port"]),
                "--genesis-proof", handoff["path"], "--genesis-proof-sha256", handoff["sha256"],
                "--fixture-run-id", handoff["fixture_run_id"]],
                env=os.environ.copy(), max_output_bytes=_OUTPUT_BYTES, raw_lines=self._lines)
            # Initial lightwalletd catch-up legitimately changes LightdInfo's
            # height. Establish parity before capturing the stable comparison;
            # the exact post-parity adaptation checks below remain unchanged.
            parity = self._backend.wait_synced(deadline=deadline)
            check()
            height = parity.get("height")
            if type(height) is not int or not 1 <= height <= 0xFFFFFFFF:
                raise NativeZakuraFrontError("raw backend parity height is invalid")
            while True:
                normalized = front("GetLightdInfo", {})
                if normalized is not None:
                    break
                cancel.wait(min(0.05, max(0, deadline - time.monotonic())))
            before = raw("GetLightdInfo", {})
            if (before.get("chainName") not in {"test", "regtest"}
                or normalized != dict(before, chainName="regtest")):
                raise NativeZakuraFrontError("front changed more than the known LightdInfo chainName")
            genesis = front("GetTreeState", {"height": "0"})
            if genesis is None or dict(genesis, height=str(genesis.get("height", "0"))) != state:
                raise NativeZakuraFrontError("front genesis differs from original node-verified evidence")
            payload = {"height": str(height)}
            raw_tree = raw("GetTreeState", payload)
            if front("GetTreeState", payload) != raw_tree or raw("GetTreeState", payload) != raw_tree:
                raise NativeZakuraFrontError("front changed the nonzero TreeState")
            latest = raw("GetLatestBlock", {})
            if front("GetLatestBlock", {}) != latest or raw("GetLatestBlock", {}) != latest:
                raise NativeZakuraFrontError("front changed LatestBlock")
            if raw("GetLightdInfo", {}) != before:
                raise NativeZakuraFrontError("raw backend changed during front readiness")
            self._genesis.handoff()
            if {path: _capture(path) for path in self._snapshot} != self._snapshot:
                raise NativeZakuraFrontError("front launch source/tool changed")
            check()
            self._ready = {"fixture_run_id": handoff["fixture_run_id"],
                "lightwalletd_url": f"http://127.0.0.1:{self._port}", "raw_port": handoff["upstream_port"],
                "genesis_sha256": handoff["sha256"], "parity_height": height,
                "lightd_info_only_chainName_changed": True, "nonzero_tree_and_latest_unchanged": True,
                "wallet_or_catalog_pass": False}
            self._available = True
            return copy.deepcopy(self._ready)
        except BaseException as primary:
            self._finished = True
            errors = []
            # Includes a launch interrupted before assignment, but never existing
            # case children. The original case owner is cooperatively single-threaded.
            for process in reversed(self._case._processes[floor:]):
                try:
                    self._case.stop_process(process)
                except BaseException as error:
                    errors.append(error)
            if errors:
                raise primary from NativeZakuraFrontError("front startup process stop was unproven")
            raise

    def stop(self):
        """Stop only this original daemon; final case/backend/ports remain caller-owned."""
        self._finished = True
        if self._process is not None:
            self._case.stop_process(self._process)


def prepare_native_zakura_front(case, backend, genesis, *, dart, source_root, timeout=30.0):
    """Construct/register once, before any front process; caller hands off its sockets."""
    if (not isinstance(case, NativeCaseLifecycle) or not isinstance(backend, OwnedNativeZakuraBackend)
        or backend._case is not case or not isinstance(genesis, OwnedZakuraGenesisProof)
        or genesis._backend is not backend or not case.accepting_launches or backend._front is not None):
        raise NativeZakuraFrontError("expected unused original accepting case/backend/genesis ownership")
    if (isinstance(timeout, bool) or not isinstance(timeout, (int, float))
        or not math.isfinite(timeout) or timeout <= 0):
        raise NativeZakuraFrontError("front timeout must be positive and finite")
    backend._running()
    handoff = genesis.handoff()
    root = Path(source_root)
    if not root.is_absolute() or root.resolve(strict=True) != root or not root.is_dir():
        raise NativeZakuraFrontError("front source root must be an existing canonical directory")
    executable = Path(dart).resolve(strict=True)
    if not os.access(executable, os.X_OK):
        raise NativeZakuraFrontError("Dart tool must be executable")
    paths = [root / name for name in _SOURCE_FILES] + [executable]
    config_path = root / ".dart_tool/package_config.json"
    chunks = []
    snapshot = {path: _capture(path, chunks=chunks if path == config_path else None) for path in paths}
    try:
        config = json.loads(b"".join(chunks))
    except (ValueError, RecursionError) as error:
        raise NativeZakuraFrontError("front package binding is invalid JSON") from error
    if not isinstance(config, dict) or not isinstance(config.get("packages"), list):
        raise NativeZakuraFrontError("front package binding is malformed")
    packages = [entry for entry in config["packages"]
                if isinstance(entry, dict) and entry.get("name") == "zcash_wallet"]
    if len(packages) != 1:
        raise NativeZakuraFrontError("front package binding is not unique")
    if not isinstance(packages[0].get("rootUri"), str):
        raise NativeZakuraFrontError("front package root URI is invalid")
    uri = urlparse(urljoin(config_path.as_uri(), packages[0]["rootUri"]))
    if uri.scheme != "file" or uri.netloc or Path(unquote(uri.path)).resolve(strict=True) != root:
        raise NativeZakuraFrontError("front package binding escaped the source root")
    manifest = json.loads(case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
    port = manifest["lightwalletd_port"]
    if port == handoff["upstream_port"]:
        raise NativeZakuraFrontError("manifest front port must differ from the original raw port")
    owner = OwnedNativeZakuraFront(case, backend, genesis, executable, root, port, snapshot, timeout, _TOKEN)
    backend._front = owner
    return owner
