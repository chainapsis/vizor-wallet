"""Original case/backend attachment; signing and node transport are modeled."""
import copy
import json
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_batch_funding as BATCH
import e2e_runtime as runtime
import test_zakura_funding as models
import test_native_zakura_backend as fixtures


class BatchModel(models.FundingFixture):
    def rpc(self, method, params=None, *, deadline=None):
        if method == "getblockhash":
            self.operations.append(method)
            return f"{10000+params[0]:064x}"
        if method == "getblock" and 10000 < int(params[0], 16) <= 10064:
            height = int(params[0], 16)-10000
            source = copy.deepcopy(self.source)
            source.update(hash=params[0], height=height)
            source["tx"][0]["txid"] = f"{20000+height:064x}"
            return source
        if method == "getrawtransaction":
            return {"txid":models.TXID, "hex":"05", "confirmations":0,
                    "height":0, "expiryheight":self.funding["expiry_height"]}
        return super().rpc(method, params, deadline=deadline)

    def grpc(self, method, payload=None, *, deadline=None):
        result = super().grpc(method, payload, deadline=deadline)
        if result["vtx"]:
            field = "actions" if self.funding["pools"][-1] == "orchard" else "ironwoodActions"
            count = len(self.funding["payments"])
            result["vtx"][0][field] = [{}]*(count-1 if self.mode == "missing-action" else count)
        return result


class BatchFundingTests(unittest.TestCase):
    def setUp(self):
        self.owner = fixtures.BackendTests(methodName="runTest")
        self.owner.setUp()
        self.addCleanup(self.owner.doCleanups)
        self.owner.loader.return_value = fixtures.modeled_source(BatchModel)
        self.case = self.owner.case(500)
        self.backend = fixtures.BACKEND.prepare_native_zakura_backend(self.case,
            grpcurl=Path("unused"), proto_dir=Path("unused"),
            miner_address=models.MINER)
        self.owner.backends.append(self.backend)
        self.backend.start()
        self.changes = {}
        self.calls = []

    def signer(self, case, artifact, command, request=None, **options):
        self.assertIs(case, self.case)
        self.calls.append(command)
        if command == "identity":
            return {"schema_version":1, "miner_address":models.MINER}
        self.assertEqual(command, "build-batch")
        total = sum(item["amount_zatoshi"] for item in request["payments"])
        value = models.VALUE*len(request["coinbase_inputs"])
        result = {"schema_version":1, "raw_tx_hex":"05", "txid":models.TXID,
            "fee_zatoshi":models.FEE, "input_value_zatoshi":value, "amount_zatoshi":total,
            "change_zatoshi":value-total-models.FEE, "target_height":request["target_height"],
            "expiry_height":request["target_height"]+40, "maturity_validated":True,
            "pools":["transparent", request["recipient_pool"]], "payments":copy.deepcopy(request["payments"]),
            "coinbase_inputs":[{"coinbase_source_height":item["coinbase_height"],
                "coinbase_txid":f"{20000+item['coinbase_height']:064x}", "coinbase_vout":0,
                "input_value_zatoshi":models.VALUE} for item in request["coinbase_inputs"]]}
        result.update(copy.deepcopy(self.changes))
        self.backend._fixture.funding = copy.deepcopy(result)
        return result

    def fund(self, count=20, **options):
        options.setdefault("payments", [{"recipient_address":f"distinct-test-address-{index}",
            "amount_zatoshi":1000+index} for index in range(count)])
        options.setdefault("source_heights", [1, 2])
        with patch.object(BATCH, "run_offline_funder", side_effect=self.signer):
            return BATCH.fund_zakura_batch(self.case, self.backend, object(), **options)

    def test_twenty_distinct_notes_two_sources_exact_inclusion_and_evidence(self):
        proof = self.fund()
        self.assertEqual(self.calls, ["identity", "build-batch"])
        self.assertEqual(proof["payment_count"], 20)
        self.assertEqual(proof["compact_action_count"], 20)
        self.assertEqual(proof["source_heights"], [1, 2])
        self.assertEqual(proof["mined_height"], 102)
        self.assertEqual(proof["final_tip_height"], 111)
        self.assertFalse(proof["wallet_or_catalog_pass"])
        evidence = list(self.backend.root.glob("funding-batch-*.json"))
        self.assertEqual(len(evidence), 1)
        self.assertEqual(json.loads(evidence[0].read_text())["proof"], proof)

    def test_bounded_five_hundred_distinct_notes(self):
        self.assertEqual(self.fund(count=500)["payment_count"], 500)
        self.assertEqual(len(self.backend._fixture.funding["payments"]), 500)

    def test_invalid_notes_or_repeated_sources_never_start_signer(self):
        for options in ({"payments":[]}, {"payments":[{}]}, {"payments":[
            {"recipient_address":"same", "amount_zatoshi":1}]*2}, {"source_heights":[1, 1]},
            {"source_heights":[True]}, {"recipient_pool":[]}, {"payments":[
                {"recipient_address":"a", "amount_zatoshi":True}]}):
            with self.subTest(options=options), self.assertRaises(BATCH.ZakuraFundingError):
                self.fund(**options)
        self.assertEqual(self.calls, [])

    def test_immature_or_cross_activation_range_never_submits(self):
        for tip in (100, 490):
            self.backend._fixture.tip = tip
            with self.subTest(tip=tip), self.assertRaises(BATCH.ZakuraFundingError):
                self.fund()
        self.assertNotIn("sendrawtransaction", self.backend._fixture.operations)

    def test_wrong_signer_notes_sources_pool_conservation_or_boolean_never_submits(self):
        for changes in ({"payments":[]}, {"coinbase_inputs":[]}, {"amount_zatoshi":True},
                        {"pools":["transparent", "ironwood"]}, {"change_zatoshi":1},
                        {"maturity_validated":False}, {"schema_version":True}):
            self.changes = changes
            with self.subTest(changes=changes), self.assertRaises(BATCH.ZakuraFundingError):
                self.fund()
        self.assertNotIn("sendrawtransaction", self.backend._fixture.operations)

    def test_raw_compact_or_action_count_failure_retains_failure(self):
        for mode in ("wrong-raw", "wrong-compact", "missing-compact", "missing-action"):
            self.backend._fixture.tip = 101
            self.backend._fixture.mode = mode
            with self.subTest(mode=mode), self.assertRaises(BATCH.ZakuraFundingError):
                self.fund()
        self.assertEqual(list(self.backend.root.glob("funding-batch-*.json")), [])

    def test_precancel_never_starts_signer(self):
        cancel = threading.Event()
        cancel.set()
        with self.assertRaises(runtime.Cancelled):
            self.fund(cancel_event=cancel)
        self.assertEqual(self.calls, [])


class MigrationNoteLayoutTests(unittest.TestCase):
    def test_twenty_note_original_single_batch_values(self):
        addresses = [f"uregtest1test{index}" for index in range(20)]
        batches = BATCH.migration_note_batches(addresses, total_zatoshi=1_000_020_000, tx_count=1)
        self.assertEqual(len(batches), 1)
        self.assertEqual([item["recipient_address"] for item in batches[0]], addresses)
        self.assertEqual({item["amount_zatoshi"] for item in batches[0]}, {50_001_000})

    def test_five_hundred_note_original_ten_weighted_batches_and_remainders(self):
        addresses = [f"uregtest1test{index}" for index in range(500)]
        batches = BATCH.migration_note_batches(addresses, total_zatoshi=500_000_000, tx_count=10)
        totals = [500_000_000*weight//55 for weight in range(1, 11)]
        totals[-1] += 500_000_000-sum(totals)
        self.assertEqual([len(batch) for batch in batches], [50]*10)
        self.assertEqual([sum(item["amount_zatoshi"] for item in batch) for batch in batches], totals)
        self.assertEqual([item["recipient_address"] for batch in batches for item in batch], addresses)
        for batch, total in zip(batches, totals):
            base, remainder = divmod(total, 50)
            self.assertEqual([item["amount_zatoshi"] for item in batch],
                             [base+(1 if index < remainder else 0) for index in range(50)])

    def test_invalid_layout_does_not_round_or_merge_notes(self):
        for addresses, total, count in ((["uregtest1a"]*2, 100, 1), (["uregtest1a"], True, 1),
                                      (["uregtest1a"], 100, True), (["uregtest1a", "uregtest1b"], 2, 2)):
            with self.subTest(addresses=addresses, total=total, count=count), self.assertRaises(BATCH.ZakuraFundingError):
                BATCH.migration_note_batches(addresses, total_zatoshi=total, tx_count=count)


if __name__ == "__main__":
    unittest.main()
