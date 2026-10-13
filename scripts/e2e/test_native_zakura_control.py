"""Real owned files/groups/HTTP; modeled Dart/node/native transport, not wallet PASS."""
import http.client
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import native_zakura_control as CONTROL
    from native_ports import lease_native_ports
    import test_native_zakura_front as FRONT_FIXTURES
    from native_zakura_backend import NativeZakuraError
finally:
    sys.path.pop(0)


class ControlFixture(unittest.TestCase):
    activation_height = 1

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="vizor-control-owner-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name).resolve()
        self.clipboard_root = root / "clipboard"
        self.lease = lease_native_ports(0, "a1b2c3d4e5", lock_root=root / "ports")
        self.addCleanup(self.lease.close)
        self.model = FRONT_FIXTURES.FrontTests()
        workspace_api = FRONT_FIXTURES.WORKSPACE
        prepare = workspace_api.prepare_native_case_workspace
        def with_ports(*args, **kwargs):
            kwargs["ports"] = self.lease.ports
            kwargs["activation_height"] = self.activation_height
            if hasattr(self, "scenario_id"):
                kwargs["scenario_id"] = self.scenario_id
            return prepare(*args, **kwargs)
        with patch.object(workspace_api, "prepare_native_case_workspace", side_effect=with_ports):
            self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.case, self.backend = self.model.case, self.model.backend
        self.front = self.model.prepare()
        first, second = self.model.patches()
        self.lease.release_sockets()
        with first, second:
            self.front.start()
        self.control = None
        self.addCleanup(self.close_control)
        self.cancel = threading.Event()
        self.calls = []

    def close_control(self):
        if self.backend._control is not None:
            self.backend._control.close()
            self.case.close()
            self.backend._control.release_clipboard_after_writers()

    def prepare(self):
        self.control = CONTROL.prepare_native_zakura_control(self.case, self.backend, self.front)
        self.control._clipboard._root = self.clipboard_root
        return self.control

    def request(self, method, path, body=None, headers=None):
        if self.control is None:
            self.prepare()
        result = []
        failures = []
        def client():
            connection = http.client.HTTPConnection("127.0.0.1", self.lease.ports["rpc"], timeout=3)
            try:
                connection.request(method, path, body=body, headers=headers or {})
                response = connection.getresponse()
                result.append((response.status, response.read()))
            except BaseException as error:
                failures.append(error)
            finally:
                connection.close()
        thread = threading.Thread(target=client)
        thread.start()
        deadline = time.monotonic() + 4
        try:
            while thread.is_alive():
                self.control.pump(deadline=deadline, cancel_event=self.cancel)
        finally:
            thread.join(timeout=4)
        if failures:
            raise failures[0]
        self.assertFalse(thread.is_alive())
        return result[0]

    def mine(self, count):
        self.calls.append((count, threading.get_ident()))
        return {"hashes":["34"*32]*count, "tip":{"height":1+count}}


class ControlTests(ControlFixture):

    def test_unmined_controls_bind_original_owner_and_reject_legacy_payloads(self):
        self.prepare()
        artifact = object()  # Signer transport modeled; not real artifact production.
        self.control._artifact = artifact
        self.backend.rpc = lambda method, **kwargs: 101
        with patch.object(CONTROL, "fund_zakura_unmined", return_value={"txid_hex":"ab"*32}) as fund:
            for payload in ({"address":"public", "amount":"0.25"},
                            {"address":"public", "amount_zatoshi":True, "source_height":1},
                            {"address":"public", "amount_zatoshi":25000000, "source_height":0}):
                self.assertEqual(self.request("POST", "/fund-unmined", json.dumps(payload))[0], 400)
            fund.assert_not_called()
            for path, expiry in (("/fund-unmined", None), ("/fund-unmined-expiring", 121)):
                status, _body = self.request("POST", path, json.dumps({
                    "address":"public", "amount_zatoshi":25000000, "source_height":1}))
                self.assertEqual(status, 200)
                self.assertEqual(fund.call_args.args, (self.case, self.backend, artifact))
                self.assertEqual(fund.call_args.kwargs["amount_zatoshi"], 25000000)
                self.assertEqual(fund.call_args.kwargs["expiry_height"], expiry)
                self.assertIs(fund.call_args.kwargs["cancel_event"], self.cancel)

    def test_expiry_control_preserves_exact_hash_integer_and_original_owner(self):
        self.prepare()
        with patch.object(CONTROL, "expire_zakura_unmined", return_value={"final_tip_height":121}) as expire:
            for payload in ({"txid":"bad", "expiry_height":121},
                            {"txid":"ab"*32, "expiry_height":True},
                            {"txid":"ab"*32, "expiryHeight":121}):
                self.assertEqual(self.request("POST", "/mine-to-expiry", json.dumps(payload))[0], 400)
            expire.assert_not_called()
            status, _body = self.request("POST", "/mine-to-expiry", json.dumps({
                "txid":"ab"*32, "expiry_height":121}))
            self.assertEqual(status, 200)
            self.assertEqual(expire.call_args.args, (self.case, self.backend))
            self.assertEqual(expire.call_args.kwargs["txid"], "ab"*32)
            self.assertEqual(expire.call_args.kwargs["expiry_height"], 121)
            self.assertIs(expire.call_args.kwargs["cancel_event"], self.cancel)

    def test_clipboard_close_retains_lease_until_original_writers_join(self):
        self.assertEqual(self.request("POST", "/host-resource/clipboard/acquire", "{}")[0], 200)
        self.assertEqual(self.request("POST", "/host-resource/clipboard/acquire", "{}")[0], 400)
        self.control.close()
        self.assertTrue(self.control._clipboard.held)
        with self.assertRaisesRegex(CONTROL.NativeZakuraControlError, "writer stop"):
            self.control.release_clipboard_after_writers()
        self.case.close()
        self.control.release_clipboard_after_writers()
        self.assertFalse(self.control._clipboard.held)

    def test_clipboard_exact_empty_payload_and_explicit_release(self):
        self.assertEqual(self.request("POST", "/host-resource/clipboard/release", "{}")[0], 400)
        self.assertEqual(self.request("POST", "/host-resource/clipboard/acquire", '{"pid":1}')[0], 400)
        self.assertEqual(self.request("POST", "/host-resource/clipboard/acquire", "{}")[0], 200)
        self.assertEqual(self.request("POST", "/host-resource/clipboard/release", "{}")[0], 200)
        self.assertFalse(self.control._clipboard.held)

    def test_raw_transaction_oracle_forwards_only_a_valid_exact_hash(self):
        calls = []
        self.backend.rpc = lambda method, params, **_kwargs: calls.append((method, params)) or {"vin":[]}
        for body in ('{}', '{"txid":"bad"}', '{"txid":1}', '{"txid":"'+'ab'*32+'","method":"reset"}'):
            self.assertEqual(self.request("POST", "/raw-transaction", body)[0], 400)
        self.assertEqual(calls, [])
        status, body = self.request("POST", "/raw-transaction", json.dumps({"txid":"ab"*32}))
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"vin":[]})
        self.assertEqual(calls, [("getrawtransaction", ["ab"*32, 1])])

    def test_loopback_request_runs_mutation_only_on_original_owner(self):
        self.backend.mine = self.mine
        status, body = self.request("POST", "/mine", json.dumps({"blocks":2}))
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["tip"]["height"], 3)
        self.assertEqual(self.calls, [(2, threading.get_ident())])
        self.assertEqual(self.control.url, f"http://127.0.0.1:{self.lease.ports['rpc']}")
        self.assertFalse(self.backend.closed)
        self.front.assert_running()

    def test_status_and_health_use_original_front_and_parity(self):
        self.backend.wait_synced = lambda **_kwargs: {"height":123, "consensus_branch_id":"e9ff75a6"}
        self.assertEqual(json.loads(self.request("GET", "/health")[1]), {"ok":True})
        status, body = self.request("GET", "/status")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"zcashdHeight":123,"lightwalletdHeight":123,
            "ironwoodActivationHeight":1,"ironwoodActive":True,"consensusBranchId":"e9ff75a6"})

    def test_wrong_body_path_json_and_funding_without_original_producer_do_not_mutate(self):
        self.backend.mine = self.mine
        for path, body in (("/mine", '{"blocks":true}'), ("/mine", '{"blocks":0}'),
                ("/mine", '{"blocks":1,"blocks":2}'), ("/mine", '{"blocks":1.0}'),
                ("/mine", '{"blocks":NaN}'), ("/mine", '[]'), ("/mine", '{"blocks":1,"extra":1}'),
                ("/node/wallet/reset", '{}'), ("/mine?blocks=1", '{"blocks":1}'),
                ("/fund-confirmed", '{"address":"public-model","amount_zatoshi":1,"source_height":1,"recipient_pool":"ironwood","confirmations":1}')):
            with self.subTest(path=path, body=body):
                self.assertEqual(self.request("POST", path, body)[0], 400)
        self.assertEqual(self.calls, [])
        self.assertIsNone(self.control._failure)

    def test_bounded_header_and_body_fail_before_dispatch(self):
        self.backend.mine = self.mine
        self.assertEqual(self.request("GET", "/health", headers={"X-Too-Large":"x"*20000})[0], 431)
        self.assertEqual(self.request("POST", "/mine", "", {"Content-Length":"65537"})[0], 400)
        self.assertEqual(self.request("POST", "/mine", "{}", {"Transfer-Encoding":"chunked"})[0], 400)
        self.assertEqual(self.calls, [])

    def test_other_thread_cannot_pump_or_close_original_listener(self):
        self.prepare()
        failures = []
        def other():
            for action in (self.control.close, lambda:self.control.pump(
                    deadline=time.monotonic()+1, cancel_event=self.cancel)):
                try:
                    action()
                except CONTROL.NativeZakuraControlError as error:
                    failures.append(error)
        thread = threading.Thread(target=other)
        thread.start()
        thread.join(timeout=2)
        self.assertEqual(len(failures), 2)
        self.assertFalse(self.control.closed)
        self.assertEqual(self.request("GET", "/health")[0], 200)

    def test_original_owned_child_can_use_controls_while_drive_observes_it(self):
        self.prepare()
        self.backend.mine = self.mine
        code = "import urllib.request; r=urllib.request.urlopen(urllib.request.Request("+repr(self.control.url+"/mine")+",data=b'{\"blocks\":2}')); print(r.read().decode())"
        child = self.case.start_process([sys.executable, "-u", "-c", code], env=os.environ)
        self.assertEqual(self.control.drive(child, timeout=4, cancel_event=self.cancel), 0)
        self.assertTrue(child.cleanup_completed)
        self.assertEqual(self.calls, [(2, threading.get_ident())])
        self.assertFalse(self.control.closed)

    def test_backend_close_is_blocked_until_original_control_socket_closes(self):
        self.prepare()
        self.case.close()
        with self.assertRaisesRegex(NativeZakuraError, "control listener"):
            self.backend.close()
        self.control.close()
        self.backend.close()
        self.assertTrue(self.backend.closed)
        self.assertTrue(self.control.closed)

    def test_failed_bind_closes_partial_socket_and_remains_registered(self):
        import socket
        occupied = socket.socket()
        self.addCleanup(occupied.close)
        occupied.bind(("127.0.0.1", self.lease.ports["rpc"]))
        occupied.listen()
        with self.assertRaises(OSError):
            self.prepare()
        self.assertTrue(self.backend._control.closed)
        self.assertEqual(self.backend._control._server.socket.fileno(), -1)
        self.assertFalse(self.backend.closed)

    def test_backend_value_error_is_failure_not_bad_client_input(self):
        primary = ValueError("original backend failed")
        def fail(_count):
            raise primary
        self.backend.mine = fail
        with self.assertRaises(ValueError) as caught:
            self.request("POST", "/mine", '{"blocks":1}')
        self.assertIs(caught.exception, primary)
        self.assertIs(self.control._failure, primary)

    def test_precancellation_dispatches_nothing(self):
        self.prepare()
        self.cancel.set()
        with self.assertRaises(CONTROL.runtime.Cancelled):
            self.control.pump(deadline=time.monotonic()+1, cancel_event=self.cancel)
        self.assertEqual(self.control._requests, 0)

    def test_height1_cannot_activate_or_reorganize_its_chain(self):
        self.backend.mine = self.mine
        for path, payload in (("/activate", {}),
                ("/reorg-hold-tip", {"required_txids":["12"*32]}),
                ("/release-held", {"txids":["12"*32]})):
            self.assertEqual(self.request("POST", path, json.dumps(payload))[0], 400)
        self.assertEqual(self.calls, [])


class GiftRecoveryControlTests(ControlFixture):
    scenario_id = "flutter.macos.payment-link-recovery"

    def test_exact_fork_and_release_delegate_to_original_fixture_on_owner_thread(self):
        self.prepare()
        txids = ["12"*32, "34"*32]
        threads = []
        def replace(required, *, fork_height, deadline):
            threads.append(threading.get_ident())
            self.assertEqual(required, txids)
            self.assertEqual(fork_height, 121)
            self.assertGreater(deadline, time.monotonic())
            return {"held_txids":required, "fork_height":fork_height}
        with patch.object(self.backend._fixture, "replace_fork_holding", side_effect=replace) as reorg:
            for payload in ({"required_txids":txids, "fork_height":True},
                            {"required_txids":txids, "fork_height":0},
                            {"required_txids":["bad"], "fork_height":121},
                            {"required_txids":txids, "fork_height":121, "reset":True}):
                self.assertEqual(self.request("POST", "/reorg-hold-fork", json.dumps(payload))[0], 400)
            reorg.assert_not_called()
            status, _body = self.request("POST", "/reorg-hold-fork", json.dumps({
                "required_txids":txids, "fork_height":121}))
            self.assertEqual(status, 200)
            reorg.assert_called_once()
        self.assertEqual(threads, [threading.get_ident()])
        status, body = self.request("POST", "/release-held", json.dumps({"txids":txids}))
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["released_txids"], txids)

    def test_another_height1_case_cannot_replace_a_fork(self):
        self.prepare()
        self.control._scenario = "flutter.macos.payment-link-round-trip"
        with patch.object(self.backend._fixture, "replace_fork_holding") as reorg:
            self.assertEqual(self.request("POST", "/reorg-hold-fork", json.dumps({
                "required_txids":["12"*32], "fork_height":121}))[0], 400)
            reorg.assert_not_called()


class ActivationControlTests(ControlFixture):
    activation_height = 500

    def test_mobile_recovery_outages_use_only_original_front_on_owner_thread(self):
        self.prepare()
        self.control._scenario = "flutter.ios.ironwood-migration-network-recovery"
        calls = []
        def available(value, **kwargs):
            calls.append((value, threading.get_ident(), kwargs))
            return {"available":value, "sequence":len(calls), "fixture_run_id":"original"}
        with patch.object(self.front, "set_available", side_effect=available):
            for path, expected in (("/lightwalletd/stop", False), ("/lightwalletd/start", True)):
                status, body = self.request("POST", path, "{}")
                self.assertEqual(status, 200)
                self.assertIs(json.loads(body)["available"], expected)
                self.assertEqual(json.loads(body)["scope"], "owned-lightwalletd-front")
            self.assertEqual([item[:2] for item in calls], [(False, threading.get_ident()), (True, threading.get_ident())])
            self.assertTrue(all(item[2]["cancel_event"] is self.cancel for item in calls))

    def test_front_outage_rejects_neighbor_cases_wrong_profile_and_nonempty_payload(self):
        self.prepare()
        with patch.object(self.front, "set_available") as change:
            for scenario in ("flutter.ios.ironwood-background-restart", "flutter.macos.import-sync"):
                self.control._scenario = scenario
                self.assertEqual(self.request("POST", "/lightwalletd/stop", "{}")[0], 400)
            self.control._scenario = "flutter.ios.ironwood-background-migration"
            self.assertEqual(self.request("POST", "/lightwalletd/stop", '{"pid":1}')[0], 400)
            self.control._activation = 1
            self.assertEqual(self.request("POST", "/lightwalletd/start", "{}")[0], 400)
            change.assert_not_called()

    def test_mobile_reorg_binds_exact_activation_fork_and_original_backend(self):
        self.prepare()
        self.control._scenario = "flutter.ios.ironwood-migration-reorg"
        with patch.object(self.backend, "replace_fork_holding", return_value={"held_txids":["12"*32]}) as replace:
            for height in (499, 501, True):
                self.assertEqual(self.request("POST", "/reorg-hold-fork", json.dumps({
                    "required_txids":["12"*32], "fork_height":height}))[0], 400)
            replace.assert_not_called()
            self.assertEqual(self.request("POST", "/reorg-hold-fork", json.dumps({
                "required_txids":["12"*32], "fork_height":500}))[0], 200)
            self.assertEqual(replace.call_args.args, (["12"*32],))
            self.assertEqual(replace.call_args.kwargs["fork_height"], 500)

    def test_activation_mines_only_to_fixed_height_and_proves_branch(self):
        self.backend.wait_synced = lambda **_kwargs: {"height":111}
        def activate(count):
            self.calls.append((count, threading.get_ident()))
            return {"tip":{"height":500,"consensus_branch_id":"37a5165b"}}
        self.backend.mine = activate
        status, body = self.request("POST", "/activate", "{}")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["tip"]["height"], 500)
        self.assertEqual(self.calls, [(389, threading.get_ident())])
        self.backend.wait_synced = lambda **_kwargs: {"height":500}
        self.assertEqual(self.request("POST", "/activate", "{}")[0], 400)
        self.assertEqual(len(self.calls), 1)

    def test_reorg_and_release_forward_only_to_original_owner(self):
        def mutate(txids, *, deadline=None):
            self.calls.append((txids, threading.get_ident(), deadline))
            return {"modeled": True}
        self.backend.replace_tip_holding = mutate
        self.backend.release_held_transactions = mutate
        for path, key in (("/reorg-hold-tip", "required_txids"), ("/release-held", "txids")):
            self.assertEqual(self.request("POST", path, json.dumps({key:["34"*32,"12"*32]}))[0], 200)
        self.assertEqual(len(self.calls), 2)
        self.assertTrue(all(call[0] == ["12"*32,"34"*32]
                            and call[1] == threading.get_ident() and call[2] > 0 for call in self.calls))

    def test_malformed_reorg_sets_and_unknown_fields_never_mutate(self):
        with patch.object(self.backend, "replace_tip_holding") as reorg, \
             patch.object(self.backend, "release_held_transactions") as release:
            for path, key in (("/reorg-hold-tip", "required_txids"), ("/release-held", "txids")):
                for value in ([], ["12"*32]*2, ["ab"*32]*9, ["AB"*32], [1], "12"*32, ["12"]):
                    self.assertEqual(self.request("POST", path, json.dumps({key:value}))[0], 400)
                self.assertEqual(self.request("POST", path, json.dumps({key:["12"*32],"extra":True}))[0], 400)
            reorg.assert_not_called()
            release.assert_not_called()

    def test_failed_original_release_stays_failed_and_retains_evidence(self):
        primary = ValueError("release differs from original captured held set")
        with patch.object(self.backend, "release_held_transactions", side_effect=primary):
            with self.assertRaises(ValueError) as caught:
                self.request("POST", "/release-held", json.dumps({"txids":["12"*32]}))
        self.assertIs(caught.exception, primary)
        self.assertIs(self.control._failure, primary)


if __name__ == "__main__":
    unittest.main()
