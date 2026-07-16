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

    @classmethod
    def ironwood_env(cls) -> Dict[str, str]:
        return {"IRONWOOD_ACTIVATION_HEIGHT": cls.activation_height}

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
            self.respond(404, {"error": "not found"})
        except Exception as exc:
            self.respond(500, {"error": str(exc)})

    def do_POST(self) -> None:
        try:
            payload = self.read_json()
            if self.path == "/activate":
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
                output = run_command(
                    self.repo_root,
                    ["scripts/ironwood-regtest/mine.sh", str(blocks)],
                    timeout=300,
                    env=self.ironwood_env(),
                )
                self.respond(200, {"ok": True, "output": output})
                return

            if self.path in {"/lightwalletd/stop", "/lightwalletd/start"}:
                action = "stop" if self.path.endswith("/stop") else "start"
                run_command(
                    self.repo_root,
                    [
                        "docker",
                        "compose",
                        "-f",
                        "docker-compose.zcash-ironwood-regtest.yml",
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
    args = parser.parse_args()

    handler = DriverHandler
    handler.repo_root = Path(args.repo_root).resolve()
    handler.activation_height = str(args.activation_height)
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print(f"[ironwood-driver] listening on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
