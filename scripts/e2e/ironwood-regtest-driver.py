#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import threading
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, List, Optional


def run_command(
    repo_root: Path,
    args: List[str],
    timeout: int,
    env: Optional[Dict[str, str]] = None,
) -> str:
    command_env = os.environ.copy()
    if env is not None:
        command_env.update(env)

    result = subprocess.run(
        args,
        cwd=repo_root,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
        env=command_env,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{' '.join(args)} failed with {result.returncode}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
    return result.stdout.strip()


class DriverHandler(BaseHTTPRequestHandler):
    repo_root: Path
    activation_height: str
    gift_funder_db: Optional[str] = None
    gift_funder_binary: Optional[str] = None
    lightwalletd_url: Optional[str] = None
    wallet_snapshot: Optional[Dict[str, str]] = None
    wallet_snapshot_lock = threading.Lock()
    # ThreadingHTTPServer handles requests concurrently, but zcashd and
    # lightwalletd mutations must be observed as one atomic operation. Without
    # this lock, a second /mine request can advance the chain while the first
    # mine.sh is waiting for its exact lightwalletd tip hash.
    chain_operation_lock = threading.Lock()

    @classmethod
    def ironwood_env(cls) -> Dict[str, str]:
        return {"IRONWOOD_ACTIVATION_HEIGHT": cls.activation_height}

    @classmethod
    def compose_file(cls) -> str:
        return os.environ.get("IRONWOOD_COMPOSE_FILE", "docker-compose.zcash-ironwood-regtest.yml")

    def do_GET(self) -> None:
        try:
            if self.path == "/health":
                self.respond(200, {"ok": True})
                return
            if self.path == "/status":
                output = run_command(
                    self.repo_root,
                    ["scripts/ironwood-regtest/status.sh"],
                    timeout=240,
                    env=self.ironwood_env(),
                )
                self.respond(200, json.loads(output))
                return
            if self.path == "/mempool":
                output = run_command(
                    self.repo_root,
                    ["scripts/ironwood-regtest/rpc.sh", "getrawmempool"],
                    timeout=60,
                    env=self.ironwood_env(),
                )
                txids = json.loads(output)
                self.respond(200, {"size": len(txids), "txids": txids})
                return
            if self.path == "/wallet-snapshot":
                with self.wallet_snapshot_lock:
                    snapshot = type(self).wallet_snapshot
                if snapshot is None:
                    self.respond(404, {"error": "wallet snapshot not found"})
                    return
                self.respond(200, {"files": snapshot})
                return
            self.respond(404, {"error": "not found"})
        except Exception as exc:
            self.respond(500, {"error": str(exc)})

    def do_POST(self) -> None:
        try:
            payload = self.read_json()
            if self.path == "/fund-confirmed":
                if not (self.gift_funder_db and self.gift_funder_binary and self.lightwalletd_url):
                    raise ValueError("Gift funding is not configured")
                amount = Decimal(str(payload["amount"])) * 100_000_000
                confirmations = payload["confirmations"]
                if not amount.is_finite() or amount <= 0 or amount != amount.to_integral_value():
                    raise ValueError("Gift amount must be positive with at most 8 decimal places")
                if type(confirmations) is not int or confirmations < 1:
                    raise ValueError("confirmations must be a positive integer")
                with self.chain_operation_lock:
                    output = run_command(
                        self.repo_root,
                        [self.gift_funder_binary, "fund", self.gift_funder_db,
                         self.activation_height, self.lightwalletd_url,
                         str(payload["address"]), str(int(amount))],
                        timeout=600,
                    )
                    txids = json.loads(output)["txids"]
                    if not isinstance(txids, str) or not txids:
                        raise ValueError("Gift funder returned no transaction IDs")
                    run_command(
                        self.repo_root,
                        ["scripts/ironwood-regtest/mine.sh", str(confirmations)],
                        timeout=300,
                        env=self.ironwood_env(),
                    )
                self.respond(200, {"txid": txids})
                return
            if self.path == "/activate":
                with self.chain_operation_lock:
                    output = run_command(
                        self.repo_root,
                        ["scripts/ironwood-regtest/activate-ironwood.sh"],
                        timeout=300,
                        env=self.ironwood_env(),
                    )
                self.respond(200, {"ok": True, "output": output})
                return

            if self.path == "/mine":
                blocks = int(payload.get("blocks", 1))
                if blocks <= 0:
                    raise ValueError("blocks must be positive")
                with self.chain_operation_lock:
                    output = run_command(
                        self.repo_root,
                        ["scripts/ironwood-regtest/mine.sh", str(blocks)],
                        timeout=300,
                        env=self.ironwood_env(),
                    )
                self.respond(200, {"ok": True, "output": output})
                return

            if self.path == "/reorg":
                fork_height = int(payload["forkHeight"])
                with self.chain_operation_lock:
                    output = run_command(
                        self.repo_root,
                        ["scripts/ironwood-regtest/reorg.sh", str(fork_height)],
                        timeout=300,
                        env=self.ironwood_env(),
                    )
                self.respond(200, json.loads(output))
                return

            if self.path == "/reorg/release":
                txids = payload.get("txids", [])
                if not isinstance(txids, list) or not txids:
                    raise ValueError("txids must be a non-empty list")
                with self.chain_operation_lock:
                    output = run_command(
                        self.repo_root,
                        [
                            "scripts/ironwood-regtest/release-reorg-transactions.sh",
                            *[str(txid) for txid in txids],
                        ],
                        timeout=120,
                        env=self.ironwood_env(),
                    )
                self.respond(200, json.loads(output))
                return

            if self.path in {"/lightwalletd/stop", "/lightwalletd/start"}:
                action = "stop" if self.path.endswith("/stop") else "start"
                with self.chain_operation_lock:
                    run_command(
                        self.repo_root,
                        [
                            "docker",
                            "compose",
                            "-f",
                            self.compose_file(),
                            action,
                            "lightwalletd",
                        ],
                        timeout=240,
                        env=self.ironwood_env(),
                    )
                    if action == "start":
                        run_command(
                            self.repo_root,
                            ["scripts/ironwood-regtest/status.sh"],
                            timeout=240,
                            env=self.ironwood_env(),
                        )
                self.respond(200, {"ok": True})
                return

            if self.path == "/node/restart":
                with self.chain_operation_lock:
                    run_command(
                        self.repo_root,
                        [
                            "docker",
                            "compose",
                            "-f",
                            self.compose_file(),
                            "up",
                            "-d",
                            "--force-recreate",
                            "zcashd",
                            "lightwalletd",
                        ],
                        timeout=300,
                        env=self.ironwood_env(),
                    )
                    output = run_command(
                        self.repo_root,
                        ["scripts/ironwood-regtest/status.sh"],
                        timeout=240,
                        env=self.ironwood_env(),
                    )
                self.respond(200, {"ok": True, "status": json.loads(output)})
                return

            if self.path == "/wallet-snapshot":
                files = payload.get("files")
                if not isinstance(files, dict) or not files:
                    raise ValueError("wallet snapshot files must be a non-empty object")
                snapshot: Dict[str, str] = {}
                for name, contents in files.items():
                    if name not in {"db", "wal", "shm"}:
                        raise ValueError(f"unsupported wallet snapshot file: {name}")
                    if not isinstance(contents, str) or not contents:
                        raise ValueError(f"wallet snapshot file {name} is empty")
                    snapshot[name] = contents
                if "db" not in snapshot:
                    raise ValueError("wallet snapshot must include the database")
                with self.wallet_snapshot_lock:
                    type(self).wallet_snapshot = snapshot
                self.respond(200, {"ok": True, "files": sorted(snapshot)})
                return

            self.respond(404, {"error": "not found"})
        except Exception as exc:
            self.respond(500, {"error": str(exc)})

    def read_json(self) -> dict:
        length = int(self.headers.get("content-length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8"))

    def respond(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        print(f"[ironwood-driver] {self.address_string()} - {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--activation-height", type=int, required=True)
    parser.add_argument("--gift-funder-db")
    parser.add_argument("--gift-funder-binary")
    parser.add_argument("--lightwalletd-url")
    args = parser.parse_args()

    handler = DriverHandler
    handler.repo_root = Path(args.repo_root).resolve()
    handler.activation_height = str(args.activation_height)
    handler.gift_funder_db = args.gift_funder_db
    handler.gift_funder_binary = args.gift_funder_binary
    handler.lightwalletd_url = args.lightwalletd_url
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[ironwood-driver] listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
