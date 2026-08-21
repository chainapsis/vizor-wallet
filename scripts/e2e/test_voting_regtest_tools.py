#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import io
import unittest
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
