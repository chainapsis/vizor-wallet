#!/usr/bin/env python3
import importlib.util
import contextlib
import json
import threading
import time
import unittest
import urllib.request
import urllib.error
from pathlib import Path
from unittest.mock import patch


DRIVER_PATH = Path(__file__).with_name("ironwood-regtest-driver.py")
SPEC = importlib.util.spec_from_file_location("ironwood_regtest_driver", DRIVER_PATH)
assert SPEC is not None and SPEC.loader is not None
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


class GiftFundingTest(unittest.TestCase):
    @contextlib.contextmanager
    def server(self, run_command):
        handler = DRIVER.DriverHandler
        handler.repo_root = DRIVER_PATH.parent
        handler.activation_height = "150"
        handler.gift_funder_db = "/tmp/gift-funder.db"
        handler.gift_funder_binary = "/tmp/regtest_gift_funder"
        handler.lightwalletd_url = "http://127.0.0.1:19067"
        server = DRIVER.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        with patch.object(DRIVER, "run_command", run_command):
            thread.start()
            try:
                yield f"http://127.0.0.1:{server.server_port}/fund-confirmed"
            finally:
                server.shutdown()
                server.server_close()
                thread.join()
                handler.gift_funder_db = None
                handler.gift_funder_binary = None
                handler.lightwalletd_url = None

    def request(self, url, amount="0.1001", confirmations=2):
        request = urllib.request.Request(
            url,
            data=json.dumps({"address": "uregtest1fixture", "amount": amount,
                             "confirmations": confirmations}).encode(),
            headers={"content-type": "application/json"}, method="POST",
        )
        return urllib.request.urlopen(request, timeout=5)

    def test_funding_uses_exact_zatoshis_then_mines_confirmations(self):
        calls = []

        def command(repo_root, args, timeout, env=None):
            calls.append(args)
            if args[0] == "/tmp/regtest_gift_funder":
                return json.dumps({"txids": "funding-txid"})
            return "mined"

        with self.server(command) as url, self.request(url) as response:
            self.assertEqual(json.load(response), {"txid": "funding-txid"})
        self.assertEqual(calls, [
            ["/tmp/regtest_gift_funder", "fund", "/tmp/gift-funder.db", "150",
             "http://127.0.0.1:19067", "uregtest1fixture", "10010000"],
            ["scripts/ironwood-regtest/mine.sh", "2"],
        ])

    def test_failed_broadcast_never_mines(self):
        calls = []

        def command(repo_root, args, timeout, env=None):
            calls.append(args)
            raise RuntimeError("Gift funding did not fully broadcast")

        with self.server(command) as url:
            with self.assertRaises(urllib.error.HTTPError) as error:
                self.request(url)
            self.assertEqual(error.exception.code, 500)
        self.assertEqual(len(calls), 1)

    def test_invalid_amount_or_confirmation_never_mutates_chain(self):
        def command(*args, **kwargs):
            self.fail("invalid funding input must not execute commands")

        with self.server(command) as url:
            for amount, confirmations in [("0", 2), ("0.000000001", 2),
                                           ("NaN", 2), ("0.1", 0), ("0.1", 1.5)]:
                with self.subTest(amount=amount, confirmations=confirmations):
                    with self.assertRaises(urllib.error.HTTPError):
                        self.request(url, amount, confirmations)

    def test_docker_lifecycle_requests_use_the_selected_compose_file(self):
        calls = []

        def command(repo_root, args, timeout, env=None):
            calls.append(args)
            return "{}"

        with patch.dict(DRIVER.os.environ, {"IRONWOOD_COMPOSE_FILE": "/tmp/isolated-compose.yml"}):
            with self.server(command) as url:
                for endpoint in ("/lightwalletd/stop", "/node/restart"):
                    request = urllib.request.Request(
                        url.replace("/fund-confirmed", endpoint), data=b"{}",
                        headers={"content-type": "application/json"}, method="POST",
                    )
                    with urllib.request.urlopen(request, timeout=5) as response:
                        self.assertEqual(response.status, 200)
        compose_calls = [args for args in calls if args[0] == "docker"]
        self.assertEqual(len(compose_calls), 2)
        self.assertTrue(all(args[3] == "/tmp/isolated-compose.yml" for args in compose_calls))


class DriverConcurrencyTest(unittest.TestCase):
    def test_concurrent_mining_requests_are_serialized(self) -> None:
        state = {"active": 0, "max_active": 0, "calls": 0}
        state_lock = threading.Lock()

        def fake_run_command(repo_root, args, timeout, env=None):
            del repo_root, timeout, env
            self.assertEqual(args[0], "scripts/ironwood-regtest/mine.sh")
            with state_lock:
                state["active"] += 1
                state["max_active"] = max(state["max_active"], state["active"])
                state["calls"] += 1
            time.sleep(0.1)
            with state_lock:
                state["active"] -= 1
            return "mined"

        DRIVER.DriverHandler.repo_root = DRIVER_PATH.parent
        DRIVER.DriverHandler.activation_height = "500"
        server = DRIVER.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            DRIVER.DriverHandler,
        )
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        errors = []
        responses = []
        start_barrier = threading.Barrier(3)

        def request_mine(blocks: int) -> None:
            try:
                start_barrier.wait()
                request = urllib.request.Request(
                    f"http://127.0.0.1:{server.server_port}/mine",
                    data=json.dumps({"blocks": blocks}).encode(),
                    headers={"content-type": "application/json"},
                    method="POST",
                )
                with urllib.request.urlopen(request, timeout=5) as response:
                    responses.append((response.status, json.load(response)))
            except Exception as error:  # pragma: no cover - asserted below
                errors.append(error)

        with patch.object(DRIVER, "run_command", fake_run_command):
            server_thread.start()
            workers = [
                threading.Thread(target=request_mine, args=(blocks,))
                for blocks in (2, 3)
            ]
            for worker in workers:
                worker.start()
            start_barrier.wait()
            for worker in workers:
                worker.join()
            server.shutdown()
            server.server_close()
            server_thread.join()

        self.assertEqual(errors, [])
        self.assertEqual(len(responses), 2)
        self.assertTrue(all(status == 200 for status, _ in responses))
        self.assertEqual(state, {"active": 0, "max_active": 1, "calls": 2})


if __name__ == "__main__":
    unittest.main()
