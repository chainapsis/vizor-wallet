#!/usr/bin/env python3
"""Loopback gateway for signed logical voting E2E endpoints."""

from __future__ import annotations

import argparse
import base64
import hashlib
from datetime import datetime, timezone
import http.client
import json
import mimetypes
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


CONFIG_HOST = "config.vizor-vote.invalid"
PIR_HOST = "pir.vizor-vote.invalid"
VOTE_HOST = "vote.vizor-vote.invalid"
SLOW_VOTE_HOST = "slow.vizor-vote.invalid"
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}
MAX_REQUEST_BODY = 128 * 1024 * 1024


def read_request_body(stream, headers) -> bytes | None:
    content_length = headers.get("Content-Length")
    if content_length is not None:
        length = int(content_length)
        if length < 0 or length > MAX_REQUEST_BODY:
            raise ValueError("request body is too large")
        return stream.read(length) if length else None
    if headers.get("Transfer-Encoding", "").lower() != "chunked":
        return None

    body = bytearray()
    while True:
        size_line = stream.readline()
        if not size_line:
            raise ValueError("unexpected EOF in chunked request body")
        try:
            size = int(size_line.split(b";", 1)[0].strip(), 16)
        except ValueError as error:
            raise ValueError("invalid chunk size") from error
        if size < 0 or len(body) + size > MAX_REQUEST_BODY:
            raise ValueError("request body is too large")
        if size == 0:
            while True:
                trailer = stream.readline()
                if trailer in {b"\r\n", b"\n"}:
                    return bytes(body)
                if not trailer:
                    raise ValueError("unexpected EOF in chunked trailers")
        chunk = stream.read(size)
        if len(chunk) != size or stream.read(2) != b"\r\n":
            raise ValueError("truncated chunked request body")
        body.extend(chunk)


def discovery_revision(static_bytes: bytes, config: dict, listing: dict) -> str:
    """Minimal discovery.ts contract, with the local static config checksum.

    Only local fixture data is supported; no lambda infrastructure or deployed
    configuration is needed. Counters, roots and proposal bodies are excluded.
    """
    rounds = []
    for item in listing.get("rounds", []):
        raw = item["vote_round_id"]
        round_id = raw.lower() if len(raw) == 64 else base64.b64decode(raw, validate=True).hex()
        if len(round_id) != 64:
            raise ValueError("invalid round ID")
        rounds.append({"id": round_id, "status": str(item["status"]),
                       "end": str(item["vote_end_time"]), "title": item.get("title", "")})
    value = {"staticChecksum": hashlib.sha256(static_bytes).hexdigest(),
             "config": config, "rounds": sorted(rounds, key=lambda item: item["id"])}
    canonical = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(canonical.encode()).hexdigest()


class GatewayHandler(BaseHTTPRequestHandler):
    config_dir: Path
    pir_target: tuple[str, int]
    vote_target: tuple[str, int]
    rpc_target: tuple[str, int] | None = None
    participation_requests = 0
    discovery_requests = 0
    discovery_successes = 0
    config_requests = 0
    round_list_requests = 0
    discovery_transition = False
    publication_lock = threading.Lock()
    config_release = threading.Event()
    config_blocked = False
    config_waiting = 0
    simulator: str | None = None
    screenshot_dir: Path | None = None
    enable_zcash_mining = False
    slow_helper_delay: float
    metrics_lock = threading.Lock()
    slow_share_inflight = 0
    slow_share_max_inflight = 0
    slow_share_requests = 0
    share_inflight = 0
    share_max_inflight = 0
    share_requests = 0

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch()

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch()

    def log_message(self, fmt: str, *args: object) -> None:
        # ABCI URLs contain governance identifiers; retain only aggregate counts.
        if urlsplit(self.path).path in {"/commit", "/validators", "/abci_query"}:
            return
        print(f"[voting-gateway] {self.address_string()} {fmt % args}", flush=True)

    def _dispatch(self) -> None:
        parsed = urlsplit(self.path)
        if self.command == "GET" and parsed.path == "/v1/voting/discovery/prod":
            self._discovery()
            return
        if self.command == "POST" and parsed.path == "/publish-discovery" and self.discovery_transition:
            body = json.loads(read_request_body(self.rfile, self.headers) or b"{}")
            stage = body.get("stage")
            if stage not in {"same-round", "new-round"}:
                self._json(400, {"error": "unknown publication stage"})
                return
            # Prepared, verified fixtures only: never accept paths or config JSON.
            with self.publication_lock:
                target = self.config_dir / "dynamic-voting-config.json"
                pending = self.config_dir / "dynamic.pending"
                pending.write_bytes((self.config_dir / (stage + ".json")).read_bytes())
                pending.replace(target)
            if body.get("holdConfig") is True:
                type(self).config_release.clear()
                type(self).config_blocked = True
            self._json(200, {"ok": True})
            return
        if self.command == "POST" and parsed.path == "/release-discovery-config" and self.discovery_transition:
            read_request_body(self.rfile, self.headers)
            type(self).config_blocked = False
            type(self).config_release.set()
            self._json(200, {"ok": True})
            return
        if self.command == "POST" and parsed.path == "/mine-for-home-sync" and self.enable_zcash_mining:
            read_request_body(self.rfile, self.headers)
            scripts = Path(__file__).resolve().parents[1] / "ironwood-regtest"
            subprocess.run([str(scripts / "mine.sh"), "20"], check=True, timeout=90, capture_output=True)
            height = subprocess.check_output([str(scripts / "rpc.sh"), "getblockcount"], timeout=30)
            self._json(200, {"height": int(height)})
            return
        if self.command == "GET" and parsed.path in {"/commit", "/validators", "/abci_query"} and self.rpc_target is not None:
            with self.metrics_lock:
                type(self).participation_requests += 1
            self._proxy(self.rpc_target, self.path)
            return
        if self.command == "POST" and parsed.path == "/screenshot" and self.simulator and self.screenshot_dir:
            body = json.loads(read_request_body(self.rfile, self.headers) or b"{}")
            name = body.get("name")
            if name not in {"before-vote", "completed-home", "restored-home", "restored-detail", "home-during-resync", "home-after-resync"}:
                self._json(400, {"error": "unknown screenshot"})
                return
            self.screenshot_dir.mkdir(parents=True, exist_ok=True)
            subprocess.run(["xcrun", "simctl", "io", self.simulator, "screenshot", str(self.screenshot_dir / (name + ".png"))], check=True, timeout=30)
            self._json(200, {"ok": True})
            return
        if parsed.path == "/health":
            self._json(200, {"status": "ok"})
            return
        if parsed.path == "/metrics":
            with self.metrics_lock:
                self._json(200, {
                    "config_waiting": type(self).config_waiting,
                    "discovery_successes": type(self).discovery_successes,
                    "discovery_requests": type(self).discovery_requests,
                    "config_requests": type(self).config_requests,
                    "round_list_requests": type(self).round_list_requests,
                    "participation_requests": type(self).participation_requests,
                    "share_requests": type(self).share_requests,
                    "share_max_inflight": type(self).share_max_inflight,
                    "slow_share_requests": type(self).slow_share_requests,
                    "slow_share_max_inflight": type(self).slow_share_max_inflight,
                })
            return

        segments = [segment for segment in parsed.path.split("/") if segment]
        if not segments:
            self._json(404, {"error": "missing logical host"})
            return
        logical_host = segments[0]
        upstream_path = "/" + "/".join(segments[1:])
        if parsed.query:
            upstream_path += "?" + parsed.query

        if logical_host == CONFIG_HOST:
            self._serve_config(segments[1:])
        elif logical_host == PIR_HOST:
            self._proxy(self.pir_target, upstream_path)
        elif logical_host == VOTE_HOST:
            self._vote(upstream_path, delayed=False)
        elif logical_host == SLOW_VOTE_HOST:
            self._vote(upstream_path, delayed=True)
        else:
            self._json(404, {"error": f"unknown logical host: {logical_host}"})

    def _vote(self, upstream_path: str, *, delayed: bool) -> None:
        if self.command == "GET" and upstream_path == "/shielded-vote/v1/rounds":
            with self.metrics_lock:
                type(self).round_list_requests += 1
        if self.command != "POST" or upstream_path != "/shielded-vote/v1/shares":
            self._proxy(self.vote_target, upstream_path)
            return
        handler = type(self)
        with self.metrics_lock:
            handler.share_requests += 1
            handler.share_inflight += 1
            handler.share_max_inflight = max(
                handler.share_max_inflight, handler.share_inflight
            )
            if delayed:
                handler.slow_share_requests += 1
                handler.slow_share_inflight += 1
                handler.slow_share_max_inflight = max(
                    handler.slow_share_max_inflight,
                    handler.slow_share_inflight,
                )
        try:
            if delayed:
                time.sleep(self.slow_helper_delay)
            self._proxy(self.vote_target, upstream_path)
        finally:
            with self.metrics_lock:
                handler.share_inflight -= 1
                if delayed:
                    handler.slow_share_inflight -= 1

    def _serve_config(self, segments: list[str]) -> None:
        if self.command != "GET" or len(segments) != 1:
            self._json(404, {"error": "unknown config object"})
            return
        if segments[0] not in {"static-voting-config.json", "dynamic-voting-config.json"}:
            self._json(404, {"error": "unknown config object"})
            return
        with self.metrics_lock:
            type(self).config_requests += 1
        if self.config_blocked and segments[0] == "dynamic-voting-config.json":
            with self.metrics_lock:
                type(self).config_waiting += 1
            try:
                if not self.config_release.wait(timeout=8):
                    self._json(503, {"error": "test publication gate timed out"})
                    return
            finally:
                with self.metrics_lock:
                    type(self).config_waiting -= 1
        candidate = self.config_dir / segments[0]
        if not candidate.is_file() or candidate.parent != self.config_dir:
            self._json(404, {"error": "unknown config object"})
            return
        body = candidate.read_bytes()
        content_type = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _discovery(self) -> None:
        with self.metrics_lock:
            type(self).discovery_requests += 1
        connection = http.client.HTTPConnection(*self.vote_target, timeout=10)
        try:
            connection.request("GET", "/shielded-vote/v1/rounds")
            response = connection.getresponse()
            if response.status != 200:
                raise ValueError("round list unavailable")
            listing = json.loads(response.read())
            with self.publication_lock:
                revision = discovery_revision(
                    (self.config_dir / "static-voting-config.json").read_bytes(),
                    json.loads((self.config_dir / "dynamic-voting-config.json").read_bytes()),
                    listing,
                )
            with self.metrics_lock:
                type(self).discovery_successes += 1
            self._json(200, {"schemaVersion": 1, "scope": "prod", "revision": revision,
                             "checkedAt": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")},
                       headers={"Cache-Control": "public, max-age=0, s-maxage=30, must-revalidate"})
        except (OSError, ValueError, KeyError, http.client.HTTPException):
            self._json(503, {"error": "Voting discovery temporarily unavailable"},
                       headers={"Cache-Control": "no-store", "Retry-After": "60"})
        finally:
            connection.close()

    def _proxy(self, target: tuple[str, int], path: str) -> None:
        try:
            body = read_request_body(self.rfile, self.headers)
        except (TypeError, ValueError) as error:
            self._json(400, {"error": f"invalid request body: {error}"})
            return
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP | {"host", "content-length"}
        }
        connection = http.client.HTTPConnection(*target, timeout=30)
        try:
            connection.request(self.command, path, body=body, headers=headers)
            response = connection.getresponse()
            response_body = response.read()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in HOP_BY_HOP | {"content-length"}:
                    self.send_header(key, value)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            self.wfile.write(response_body)
        except (OSError, http.client.HTTPException) as error:
            self._json(502, {"error": f"upstream unavailable: {error}"})
        finally:
            connection.close()

    def _json(self, status: int, value: object, *, headers: dict[str, str] | None = None) -> None:
        body = json.dumps(value, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def parse_target(raw: str) -> tuple[str, int]:
    parsed = urlsplit(raw)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost"}:
        raise argparse.ArgumentTypeError("target must be a loopback HTTP origin")
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        raise argparse.ArgumentTypeError("target must not contain a path, query, or fragment")
    return parsed.hostname, parsed.port or 80


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--config-dir", type=Path, required=True)
    parser.add_argument("--pir-target", type=parse_target, required=True)
    parser.add_argument("--vote-target", type=parse_target, required=True)
    parser.add_argument("--simulator")
    parser.add_argument("--discovery-transition", action="store_true")
    parser.add_argument("--enable-zcash-mining", action="store_true")
    parser.add_argument("--screenshot-dir", type=Path)
    parser.add_argument("--rpc-target", type=parse_target)
    parser.add_argument("--slow-helper-delay", type=float, default=0.0)
    args = parser.parse_args()

    config_dir = args.config_dir.resolve(strict=True)
    if not config_dir.is_dir():
        raise SystemExit(f"config directory is not a directory: {config_dir}")

    handler = type(
        "ConfiguredGatewayHandler",
        (GatewayHandler,),
        {
            "config_dir": config_dir,
            "pir_target": args.pir_target,
            "vote_target": args.vote_target,
            "rpc_target": args.rpc_target,
            "simulator": args.simulator,
            "discovery_transition": args.discovery_transition,
            "enable_zcash_mining": args.enable_zcash_mining,
            "screenshot_dir": args.screenshot_dir,
            "slow_helper_delay": max(0.0, args.slow_helper_delay),
        },
    )
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[voting-gateway] listening on http://{args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
