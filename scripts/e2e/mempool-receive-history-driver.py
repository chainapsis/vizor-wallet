#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, List, Optional


def run_command(
    repo_root: Path,
    args: List[str],
    timeout: int,
    env: Optional[Dict[str, str]] = None,
) -> str:
    command_env = None
    if env is not None:
        command_env = os.environ.copy()
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
    prepared_faucet_zaddr: str

    def do_GET(self) -> None:
        if self.path == "/health":
            self.respond(200, {"ok": True})
            return
        self.respond(404, {"error": "not found"})

    def do_POST(self) -> None:
        try:
            payload = self.read_json()
            if self.path == "/fund-unmined":
                address = str(payload["address"])
                amount = str(payload.get("amount", "0.25"))
                output = run_command(
                    self.repo_root,
                    ["scripts/regtest/fund-wallet-unmined.sh", address, amount],
                    timeout=300,
                )
                txid = output.splitlines()[-1].strip() if output else ""
                if not txid:
                    raise RuntimeError("fund-wallet-unmined.sh returned no txid")
                self.respond(200, {"txid": txid})
                return

            if self.path == "/fund-unmined-prepared":
                if not self.prepared_faucet_zaddr:
                    raise RuntimeError("No prepared faucet zaddr was configured")
                address = str(payload["address"])
                amount = str(payload.get("amount", "0.25"))
                output = run_command(
                    self.repo_root,
                    ["scripts/regtest/fund-wallet-unmined.sh", address, amount],
                    timeout=120,
                    env={
                        "REGTEST_UNMINED_FAUCET_ZADDR": self.prepared_faucet_zaddr,
                    },
                )
                txid = output.splitlines()[-1].strip() if output else ""
                if not txid:
                    raise RuntimeError("fund-wallet-unmined.sh returned no txid")
                self.respond(200, {"txid": txid})
                return

            if self.path == "/mine":
                blocks = int(payload.get("blocks", 1))
                run_command(
                    self.repo_root,
                    ["scripts/regtest/mine.sh", str(blocks)],
                    timeout=180,
                )
                self.respond(200, {"ok": True})
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
        print(f"[mempool-driver] {self.address_string()} - {format % args}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--prepared-faucet-zaddr", default="")
    args = parser.parse_args()

    handler = DriverHandler
    handler.repo_root = Path(args.repo_root).resolve()
    handler.prepared_faucet_zaddr = args.prepared_faucet_zaddr
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[mempool-driver] listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
