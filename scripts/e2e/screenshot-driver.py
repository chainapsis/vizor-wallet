#!/usr/bin/env python3
"""Host-side capture endpoint for the mobile screenshot tour.

The in-app tour test POSTs {"name": "..."} to /screenshot and this
driver runs `xcrun simctl io <udid> screenshot` into the output dir.
"""
import argparse
import json
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

UDID = None
OUT_DIR = None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: N802
        print(f"[screenshot-driver] {fmt % args}", flush=True)

    def _respond(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        if self.path == "/health":
            self._respond(200, {"ok": True})
            return
        self._respond(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path != "/screenshot":
            self._respond(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
            name = re.sub(r"[^a-zA-Z0-9_-]", "_", str(payload.get("name", "")))
            if not name:
                raise ValueError("missing name")
            out = OUT_DIR / f"{name}.png"
            subprocess.run(
                ["xcrun", "simctl", "io", UDID, "screenshot", str(out)],
                check=True,
                capture_output=True,
                timeout=30,
            )
            print(f"[screenshot-driver] captured {out}", flush=True)
            self._respond(200, {"ok": True, "path": str(out)})
        except Exception as e:  # noqa: BLE001
            self._respond(500, {"error": str(e)})


def main():
    global UDID, OUT_DIR
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--port", type=int, default=39070)
    args = parser.parse_args()

    UDID = args.udid
    OUT_DIR = Path(args.out_dir)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"[screenshot-driver] listening on http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
