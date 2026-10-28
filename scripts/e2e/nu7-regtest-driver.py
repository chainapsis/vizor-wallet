#!/usr/bin/env python3
"""HTTP driver that lets a running Flutter E2E mine and inspect the NU7 regtest chain."""
import argparse
import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import List


def run_command(repo_root: Path, args: List[str], timeout: int) -> str:
    result = subprocess.run(
        args,
        cwd=repo_root,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
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
    # One chain mutation at a time, so each waits for lightwalletd's own tip.
    chain_operation_lock = threading.Lock()

    def rpc(self, method: str, params: str = "[]") -> object:
        output = run_command(
            self.repo_root, ["scripts/nu7-regtest/rpc.sh", method, params], timeout=120
        )
        return json.loads(output)

    def do_GET(self) -> None:
        try:
            if self.path == "/health":
                self.respond(200, {"ok": True})
                return
            if self.path == "/status":
                info = self.rpc("getblockchaininfo")
                upgrades = {
                    upgrade["name"]: upgrade["activationheight"]
                    for upgrade in info.get("upgrades", {}).values()
                }
                height = info["blocks"]
                nu7 = upgrades["NU7"]
                # zcashdHeight keeps the key the shared desktop helpers read.
                self.respond(
                    200,
                    {
                        "zcashdHeight": height,
                        "nu63ActivationHeight": upgrades["NU6.3"],
                        "nu7ActivationHeight": nu7,
                        "nu7Active": height >= nu7,
                        "consensusBranchId": info["consensus"]["chaintip"],
                    },
                )
                return
            if self.path == "/mempool":
                txids = self.rpc("getrawmempool")
                self.respond(200, {"size": len(txids), "txids": txids})
                return
            self.respond(404, {"error": "not found"})
        except Exception as exc:
            self.respond(500, {"error": str(exc)})

    def do_POST(self) -> None:
        try:
            payload = self.read_json()
            if self.path == "/mine":
                blocks = payload.get("blocks", 1)
                if type(blocks) is not int or blocks < 1:
                    raise ValueError("blocks must be a positive integer")
                with self.chain_operation_lock:
                    height = run_command(
                        self.repo_root,
                        ["scripts/nu7-regtest/mine.sh", str(blocks)],
                        timeout=240,
                    )
                self.respond(200, {"height": int(height)})
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
        print(f"[nu7-driver] {self.address_string()} - {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    DriverHandler.repo_root = Path(args.repo_root).resolve()
    server = ThreadingHTTPServer((args.host, args.port), DriverHandler)
    print(f"[nu7-driver] listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
