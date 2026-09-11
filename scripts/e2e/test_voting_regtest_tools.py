#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import io
import unittest
from unittest.mock import patch
import threading
import urllib.request
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent


def load_script(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


exporter = load_script(
    "export_regtest_ironwood_nullifiers",
    "export-regtest-ironwood-nullifiers.py",
)
gateway = load_script("voting_regtest_gateway", "voting-regtest-gateway.py")


class ExporterTests(unittest.TestCase):
    def test_decodes_concatenated_grpcurl_stream(self) -> None:
        self.assertEqual(
            exporter.decode_stream('{"height":"1"}\n{"height":"2"}\n'),
            [{"height": "1"}, {"height": "2"}],
        )

    def test_rejects_non_object_stream_item(self) -> None:
        with self.assertRaisesRegex(ValueError, "non-object"):
            exporter.decode_stream("[]")


class GatewayTests(unittest.TestCase):
    def test_home_resync_mines_fixed_batch_and_returns_synced_tip(self) -> None:
        handler = type("MiningGateway", (gateway.GatewayHandler,), {
            "enable_zcash_mining": True,
        })
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            with patch.object(gateway.subprocess, "run") as mine, patch.object(
                gateway.subprocess, "check_output", return_value=b"650\n"
            ) as tip:
                request = urllib.request.Request(
                    f"http://127.0.0.1:{server.server_port}/mine-for-home-sync",
                    data=b"{}", headers={"Content-Type": "application/json"},
                )
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(json.load(response), {"height": 650})
                self.assertEqual(mine.call_args.args[0][-1], "20")
                self.assertTrue(mine.call_args.args[0][0].endswith("ironwood-regtest/mine.sh"))
                self.assertEqual(tip.call_args.args[0][-1], "getblockcount")
        finally:
            server.shutdown()
            server.server_close()

    def test_participation_proxy_preserves_query_and_counts_requests(self) -> None:
        seen = []
        class Upstream(BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append(self.path)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"result":{"proof":"unmodified"}}')
            def log_message(self, *_):
                pass
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        handler = type("TestGateway", (gateway.GatewayHandler,), {
            "rpc_target": upstream.server_address,
            "participation_requests": 0,
        })
        proxy = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        for server in (upstream, proxy):
            threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            route = '/abci_query?path=%22/store/vote/key%22&data=0x0100&height=7&prove=true'
            with urllib.request.urlopen(f'http://127.0.0.1:{proxy.server_port}{route}') as response:
                self.assertEqual(json.load(response), {"result": {"proof": "unmodified"}})
            self.assertEqual(seen, [route])
            self.assertEqual(handler.participation_requests, 1)
        finally:
            for server in (proxy, upstream):
                server.shutdown()
                server.server_close()

    def test_accepts_only_loopback_http_origins(self) -> None:
        self.assertEqual(gateway.parse_target("http://127.0.0.1:3000"), ("127.0.0.1", 3000))
        with self.assertRaisesRegex(Exception, "loopback HTTP"):
            gateway.parse_target("https://127.0.0.1:3000")
        with self.assertRaisesRegex(Exception, "loopback HTTP"):
            gateway.parse_target("http://example.com:3000")

    def test_decodes_chunked_request_body(self) -> None:
        stream = io.BytesIO(b"4\r\ntest\r\n6;ignored=yes\r\n-body!\r\n0\r\n\r\n")
        self.assertEqual(
            gateway.read_request_body(stream, {"Transfer-Encoding": "chunked"}),
            b"test-body!",
        )

    def test_rejects_truncated_chunked_request_body(self) -> None:
        with self.assertRaisesRegex(ValueError, "truncated"):
            gateway.read_request_body(
                io.BytesIO(b"4\r\nabc\r\n"),
                {"Transfer-Encoding": "chunked"},
            )


if __name__ == "__main__":
    unittest.main()
