#!/usr/bin/env python3
"""Pass local simulator requests to the fixed-key Keystone firmware harness."""
import argparse
import base64
import gzip
import json
import signal
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--send-signer', required=True)
parser.add_argument('--voting-signer', required=True)
parser.add_argument('--fixture-dir', required=True, type=Path)
parser.add_argument('--fixture-tool', required=True)
parser.add_argument('--gui-dir', type=Path, help='Isolated Keystone SDL simulator and fixture wallet')
parser.add_argument('--port-file', required=True, type=Path)
args = parser.parse_args()


def scan_signing_screen(directory, kind, expected):
    # Keep the expected URs on the host. The GUI only receives screen pixels.
    try:
        run = subprocess.run([directory / 'simulator', kind], cwd=directory, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45)
    except subprocess.TimeoutExpired as error:
        raise ValueError('Keystone GUI scan timed out after 45 seconds. Check that the signing QR '
                         'is visible on the primary display and Screen Recording is enabled.') from error
    lines = run.stdout.splitlines()
    title = 'Confirm Transaction (1/2)' if kind == 'vote' else 'Confirm Transaction'
    if run.returncode or f'Keystone GUI review: {title}' not in lines:
        raise ValueError(f'Keystone GUI did not display {title}. '
                         'Check the unlocked primary display and Screen Recording permission.')
    observed = [line[len('qrString: '):] for line in lines if line.startswith('qrString: ')]
    if not observed or not set(observed).issubset(expected):
        raise ValueError('Keystone GUI decoded frames outside the displayed signing request')
    print(f'Keystone GUI scanned {len(set(observed))} distinct {kind} frames and displayed {title}', flush=True)
    return observed


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/voting-fixture':
            fixture = json.loads((args.fixture_dir / 'voting.json').read_bytes())
            sidecar = (args.fixture_dir / 'wallet.db.voting').read_bytes()
            fixture['db'] = base64.b64encode(gzip.compress(sidecar)).decode()
            return self.respond(200, json.dumps(fixture).encode())
        return self.send_error(404)

    def do_POST(self):
        if self.path not in ('/sign', '/sign-votes', '/verify-votes'):
            return self.send_error(404)
        if self.headers.get_content_type() != 'application/json':
            return self.send_error(415)
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 1_048_576:
                return self.send_error(413)
            request = json.loads(self.rfile.read(size))
            if self.path == '/verify-votes':
                command = [args.fixture_tool, 'verify-votes', str(args.fixture_dir / 'voting.json')]
                return self.run_tool(command, json.dumps(request), frames=False)
            mode = request['mode']
            prefix = {'single': 'ur:zcash-pczt/', 'batch': 'ur:zcash-sign-batch/'}[mode]
            parts = request['parts']
            if not isinstance(parts, list) or not parts:
                raise ValueError('Expected request frames')
            if not all(isinstance(p, str) and p.isascii() and p.isprintable()
                       and p.lower().startswith(prefix) for p in parts):
                raise ValueError('Invalid PCZT frame')
        except (KeyError, TypeError, ValueError) as error:
            return self.send_error(400, str(error))
        voting = self.path == '/sign-votes'
        if args.gui_dir:
            try:
                directory = args.gui_dir / ('vote' if voting else 'payment')
                parts = scan_signing_screen(directory, 'vote' if voting else mode, parts)
            except (OSError, ValueError) as error:
                return self.send_error(422, str(error))
        signer = args.voting_signer if voting else args.send_signer
        self.run_tool([signer, mode], '\n'.join(parts), frames=True)

    def run_tool(self, command, input_text, *, frames):
        try:
            run = subprocess.run(command, input=input_text, text=True,
                                 capture_output=True, check=True, timeout=60)
            result = {'parts': run.stdout.splitlines()} if frames else {'verified': True}
            body = json.dumps(result).encode()
            status = 200
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            status = 422
            body = json.dumps({'error': str(error.stderr or error)}).encode()
        self.respond(status, body)

    def respond(self, status, body):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


# Unwind subprocess.run on runner cleanup so it kills and reaps its GUI child.
def stop_server(_signum, _frame):
    raise SystemExit


signal.signal(signal.SIGTERM, stop_server)
with HTTPServer(('127.0.0.1', 0), Handler) as server:
    args.port_file.write_text(str(server.server_port))
    server.serve_forever()
