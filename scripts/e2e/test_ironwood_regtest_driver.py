#!/usr/bin/env python3
import importlib.util
import json
import threading
import time
import unittest
import urllib.request
from pathlib import Path
from unittest.mock import patch


DRIVER_PATH = Path(__file__).with_name("ironwood-regtest-driver.py")
SPEC = importlib.util.spec_from_file_location("ironwood_regtest_driver", DRIVER_PATH)
assert SPEC is not None and SPEC.loader is not None
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


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
