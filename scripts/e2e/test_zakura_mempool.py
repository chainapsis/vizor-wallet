"""Original owning case/backend files; signer/node/LWD transport is modeled."""
import base64
import copy
import json
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_mempool as MEMPOOL
import test_zakura_funding as funding_models
import test_native_zakura_backend as fixtures

TXID = funding_models.TXID
SOURCE_TXID = funding_models.SOURCE_TXID
VALUE, AMOUNT, FEE = funding_models.VALUE, 25_000_000, funding_models.FEE


class MempoolModel(funding_models.FundingFixture):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.pending = False
        self.hold_calls = []

    def wait_synced(self, *, deadline=None):
        return {"height":self.tip, "hash":f"{self.tip:064x}"}

    def rpc(self, method, params=None, *, deadline=None):
        if method == "sendrawtransaction":
            self.pending = True
            return super().rpc(method, params, deadline=deadline)
        if method == "getrawmempool":
            self.operations.append(method)
            return [TXID] if self.pending and self.tip < self.funding["expiry_height"] and not (
                self.mode == "early-absence" and self.tip > 101) else []
        if method == "getrawtransaction":
            self.operations.append(method)
            return {"txid":TXID, "hex":"06" if self.mode == "wrong-raw" else "05",
                    "expiryheight":self.funding["expiry_height"], "confirmations":0, "height":0}
        if method == "getblock" and params[0] != funding_models.SOURCE_HASH:
            self.operations.append(method)
            height = int(params[0], 16)
            return {"height":height, "hash":params[0], "tx":[{"txid":TXID}] if self.mode == "included" else []}
        return super().rpc(method, params, deadline=deadline)

    def grpc(self, method, payload=None, *, deadline=None):
        assert method == "GetBlock"
        self.operations.append(method)
        height = int(payload["height"])
        return {"height":str(height), "hash":funding_models.encoded(f"{height:064x}", True),
                "vtx":[{"txid":funding_models.encoded(TXID, True)}] if self.mode == "compact-included" else []}

    def hold_pending_transactions(self, txids, *, expiry_height, deadline=None):
        self.hold_calls.append((list(txids), expiry_height))
        return {"initial_tip_height":self.tip, "initial_tip_hash":f"{self.tip:064x}",
                "held_txids":txids, "expiry_height":expiry_height}


class MempoolTests(unittest.TestCase):
    def setUp(self):
        self.owner = fixtures.BackendTests(methodName="runTest")
        self.owner.setUp()
        self.addCleanup(self.owner.doCleanups)
        self.owner.loader.return_value = fixtures.modeled_source(MempoolModel)
        self.case = self.owner.case(1)
        self.backend = fixtures.BACKEND.prepare_native_zakura_backend(self.case,
            grpcurl=Path("unused"), proto_dir=Path("unused"),
            miner_address=funding_models.MINER)
        self.owner.backends.append(self.backend)
        self.backend.start()
        self.sign_calls = []
        self.changes = {}

    def signer(self, case, artifact, command, request=None, **kwargs):
        self.assertIs(case, self.case)
        self.sign_calls.append(command)
        if command == "identity":
            return {"schema_version":1, "miner_address":funding_models.MINER}
        self.assertEqual(command, "build-batch")
        result = {"schema_version":1, "txid":TXID, "raw_tx_hex":"05",
            "fee_zatoshi":FEE, "input_value_zatoshi":VALUE, "amount_zatoshi":AMOUNT,
            "change_zatoshi":VALUE-AMOUNT-FEE, "target_height":request["target_height"],
            "expiry_height":request["expiry_height"] or request["target_height"]+40,
            "maturity_validated":True, "pools":["transparent", "ironwood"],
            "coinbase_inputs":[{"coinbase_source_height":1, "coinbase_txid":SOURCE_TXID,
                               "coinbase_vout":0, "input_value_zatoshi":VALUE}],
            "payments":copy.deepcopy(request["payments"])}
        result.update(copy.deepcopy(self.changes))
        self.backend._fixture.funding = result
        return result

    def fund(self, **options):
        with patch.object(MEMPOOL, "run_offline_funder", side_effect=self.signer):
            return MEMPOOL.fund_zakura_unmined(self.case, self.backend, object(),
                recipient_address="public-test-address", amount_zatoshi=options.pop("amount_zatoshi", AMOUNT),
                **options)

    def expire(self, expiry=104, **options):
        return MEMPOOL.expire_zakura_unmined(self.case, self.backend,
            txid=TXID, expiry_height=expiry, **options)

    def test_original_unmined_funding_preserves_tip_integer_amount_and_evidence(self):
        proof = self.fund(expiry_height=104)
        self.assertEqual(self.sign_calls, ["identity", "build-batch"])
        self.assertEqual(proof["confirmations"], 0)
        self.assertIsNone(proof["mined_height"])
        self.assertEqual(proof["amount_zatoshi"], AMOUNT)
        self.assertEqual(proof["final_tip_height"], 101)
        self.assertNotIn("mine", self.backend._fixture.operations)
        self.assertFalse(proof["wallet_or_catalog_pass"])
        self.assertEqual(len(list(self.backend.root.glob("funding-unmined-*.json"))), 1)

    def test_signer_wrong_amount_pool_source_or_expiry_never_broadcasts(self):
        for changes in ({"amount_zatoshi":AMOUNT+1}, {"pools":["transparent", "orchard"]},
                        {"expiry_height":105}, {"payments":[{"recipient_address":"other", "amount_zatoshi":AMOUNT}]},
                        {"coinbase_inputs":[{"coinbase_source_height":True, "coinbase_txid":SOURCE_TXID,
                                            "coinbase_vout":0, "input_value_zatoshi":VALUE}]}):
            self.changes = changes
            with self.subTest(changes=changes), self.assertRaises(MEMPOOL.ZakuraFundingError):
                self.fund(expiry_height=104)
        self.assertNotIn("sendrawtransaction", self.backend._fixture.operations)

    def test_raw_transaction_mutation_is_not_unmined_proof(self):
        self.backend._fixture.mode = "wrong-raw"
        with self.assertRaisesRegex(MEMPOOL.ZakuraFundingError, "raw transaction"):
            self.fund(expiry_height=104)
        self.assertEqual(list(self.backend.root.glob("funding-unmined-*.json")), [])

    def test_precancellation_wrong_owner_bool_amount_and_immature_source_do_not_sign(self):
        event = threading.Event()
        event.set()
        with self.assertRaises(MEMPOOL.runtime.Cancelled):
            self.fund(cancel_event=event)
        with self.assertRaises(MEMPOOL.ZakuraFundingError):
            self.fund(amount_zatoshi=True)
        self.backend._fixture.tip = 99
        with self.assertRaisesRegex(MEMPOOL.ZakuraFundingError, "not mature"):
            self.fund()
        with self.assertRaisesRegex(MEMPOOL.ZakuraFundingError, "original accepting"):
            MEMPOOL.fund_zakura_unmined(self.owner.case(1), self.backend, object(),
                recipient_address="public", amount_zatoshi=AMOUNT)
        self.assertEqual(self.sign_calls, [])

    def test_original_hold_and_every_raw_compact_block_prove_expiry(self):
        self.fund(expiry_height=104)
        proof = self.expire()
        self.assertEqual(self.backend._fixture.hold_calls, [([TXID], 104)])
        self.assertEqual(proof["final_tip_height"], 104)
        self.assertTrue(proof["raw_compact_exclusion_verified"])
        self.assertTrue(proof["expired_mempool_absence_verified"])
        self.assertFalse(proof["wallet_or_catalog_pass"])
        record = json.loads(next(self.backend.root.glob("funding-expiry-*.json")).read_text())
        self.assertEqual([item["pending"] for item in record["blocks"]], [True, True, False])

    def test_raw_inclusion_cannot_be_called_expiry(self):
        self.fund(expiry_height=104)
        self.backend._fixture.mode = "included"
        with self.assertRaisesRegex(MEMPOOL.ZakuraFundingError, "exclusion"):
            self.expire()

    def test_compact_inclusion_cannot_be_called_expiry(self):
        self.fund(expiry_height=104)
        self.backend._fixture.mode = "compact-included"
        with self.assertRaisesRegex(MEMPOOL.ZakuraFundingError, "exclusion"):
            self.expire()

    def test_early_absence_or_changed_pending_bytes_is_not_expiry(self):
        self.fund(expiry_height=104)
        self.backend._fixture.mode = "early-absence"
        with self.assertRaisesRegex(MEMPOOL.ZakuraFundingError, "vanished"):
            self.expire()

    def test_invalid_expiry_and_cancellation_never_hold(self):
        self.fund(expiry_height=104)
        for expiry in (True, 101, 2000):
            with self.subTest(expiry=expiry), self.assertRaises(MEMPOOL.ZakuraFundingError):
                self.expire(expiry)
        event = threading.Event()
        event.set()
        with self.assertRaises(MEMPOOL.runtime.Cancelled):
            self.expire(cancel_event=event)
        self.assertEqual(self.backend._fixture.hold_calls, [])


if __name__ == "__main__":
    unittest.main()
