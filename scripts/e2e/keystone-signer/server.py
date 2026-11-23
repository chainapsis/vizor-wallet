#!/usr/bin/env python3
"""Pass local simulator requests to the fixed-key Keystone firmware harness."""
import argparse
import base64
import gzip
import json
import signal
import time
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--send-signer')
parser.add_argument('--voting-signer')
parser.add_argument('--fixture-dir', required=True, type=Path)
parser.add_argument('--fixture-tool', required=True)
parser.add_argument('--gui-dir', type=Path, help='Isolated Keystone SDL simulator and fixture wallet')
parser.add_argument('--port-file', required=True, type=Path)
args = parser.parse_args()
if not args.gui_dir and not (args.send_signer and args.voting_signer):
    parser.error('Host mode requires both firmware signers')


def check_review(lines, kind, expected):
    titles = (['Confirm Transaction (1/2)', 'Confirm Transaction (2/2)']
              if kind == 'vote' else ['Confirm Transaction'])
    reviews = [line.removeprefix('review: ') for line in lines if line.startswith('review: ')]
    if reviews != titles:
        raise ValueError(f'Expected Keystone reviews {titles}, saw {reviews}')
    observed = [line.removeprefix('request: ') for line in lines if line.startswith('request: ')]
    if not observed or not set(observed).issubset(expected):
        raise ValueError('Keystone GUI decoded frames outside the displayed signing request')
    print(f'Keystone GUI scanned {len(set(observed))} distinct {kind} frames and displayed {", ".join(reviews)}', flush=True)


class SigningWindow:
    """Own one live signing window until Vizor finishes scanning its response."""
    def __init__(self, directory, kind, expected):
        self.snapshot = directory / 'signature.png'
        events = directory / 'scan.events'
        events.write_text('')
        self.process = subprocess.Popen([directory / 'simulator', kind], cwd=directory,
                                        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline and self.process.poll() is None:
                lines = events.read_text().splitlines()
                if lines and lines[-1].startswith('signature window: '):
                    check_review(lines, kind, expected)
                    self.window_id = str(int(lines[-1].removeprefix('signature window: ')))
                    return
                time.sleep(0.1)
            raise ValueError('Keystone did not reach the signature screen after review and PIN approval')
        except BaseException:
            self.close()
            raise

    def frame(self):
        if self.process.poll() is not None:
            raise ValueError('Keystone signature window exited during capture')
        subprocess.run(['/usr/sbin/screencapture', '-x', '-o', '-l', self.window_id, self.snapshot],
                       check=True, timeout=5)
        return self.snapshot.read_bytes()

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/signature-frame' and self.server.signing_window is not None:
            try:
                image = self.server.signing_window.frame()
                return self.respond(200, json.dumps({'png': base64.b64encode(image).decode()}).encode())
            except (ValueError, OSError, subprocess.SubprocessError) as error:
                return self.send_error(422, str(error))
        if self.path == '/voting-fixture':
            fixture = json.loads((args.fixture_dir / 'voting.json').read_bytes())
            sidecar = (args.fixture_dir / 'wallet.db.voting').read_bytes()
            fixture['db'] = base64.b64encode(gzip.compress(sidecar)).decode()
            return self.respond(200, json.dumps(fixture).encode())
        return self.send_error(404)

    def do_POST(self):
        if self.path not in ('/sign', '/approve-payment', '/approve-votes', '/close-signing', '/sign-votes', '/verify-votes'):
            return self.send_error(404)
        if self.headers.get_content_type() != 'application/json':
            return self.send_error(415)
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 1_048_576:
                return self.send_error(413)
            request = json.loads(self.rfile.read(size))
            if self.path == '/close-signing':
                if self.server.signing_window is not None:
                    self.server.signing_window.close()
                    self.server.signing_window = None
                return self.respond(200, b'{}')
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
        if self.path in ('/approve-payment', '/approve-votes'):
            if not args.gui_dir or self.server.signing_window is not None:
                return self.send_error(409, 'Expected an idle Keystone GUI')
            voting = self.path == '/approve-votes'
            if voting and mode != 'batch':
                return self.send_error(400, 'Expected a voting batch')
            directory = args.gui_dir / ('vote' if voting else 'payment')
            try:
                self.server.signing_window = SigningWindow(directory, 'vote' if voting else mode, parts)
                return self.respond(200, b'{}')
            except (OSError, ValueError) as error:
                return self.send_error(422, str(error))
        if args.gui_dir:
            return self.send_error(409, 'Signing requires approval on the Keystone GUI')
        signer = args.voting_signer if self.path == '/sign-votes' else args.send_signer
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
    server.signing_window = None
    try:
        server.serve_forever()
    finally:
        if server.signing_window is not None:
            server.signing_window.close()
