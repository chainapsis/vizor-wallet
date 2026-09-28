#!/usr/bin/env python3
"""Expose the Speculos helper on loopback for the sandboxed macOS E2E app."""
import argparse
import json
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--helper', required=True)
parser.add_argument('--speculos-url', required=True)
parser.add_argument('--account', type=Path, required=True)
parser.add_argument('--port-file', type=Path, required=True)
args = parser.parse_args()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/account':
            self.send_error(404)
            return
        self.respond(200, args.account.read_bytes())

    def do_POST(self):
        if self.path != '/sign':
            self.send_error(404)
            return
        size = int(self.headers.get('Content-Length', 0))
        if not 0 < size <= 1024 * 1024:
            self.send_error(400)
            return
        with tempfile.TemporaryDirectory(prefix='vizor-ledger-regtest-') as tmp:
            pczt, signatures = Path(tmp) / 'unsigned.pczt', Path(tmp) / 'signatures.json'
            pczt.write_bytes(self.rfile.read(size))
            try:
                subprocess.run(
                    [args.helper, 'regtest-sign', args.speculos_url, str(pczt), str(signatures)],
                    check=True, capture_output=True, timeout=330,
                )
                self.respond(200, signatures.read_bytes())
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                self.respond(500, json.dumps({'error': str(error), 'stderr': (error.stderr or b'').decode(errors='replace')}).encode())

    def respond(self, status, body):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


with HTTPServer(('127.0.0.1', 0), Handler) as server:
    args.port_file.write_text(str(server.server_port))
    server.serve_forever()
