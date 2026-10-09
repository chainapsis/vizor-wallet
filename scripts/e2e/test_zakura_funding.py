"""Original case/backend attachment; signing and node/LWD transport modeled."""
import base64
import copy
import json
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import zakura_funding as FUNDING
    import test_native_zakura_backend as fixtures
finally:
    sys.path.pop(0)

MINER = "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX"
SOURCE_HASH, SOURCE_TXID, TXID = "01"*32, "02"*32, "03"*32
VALUE, AMOUNT, FEE = 1_000_000_000, 1_234_567, 10_000

def encoded(value, reverse=False):
    data = bytes.fromhex(value)
    return base64.b64encode(data[::-1] if reverse else data).decode()


class FundingFixture(fixtures.FixtureModel):
    def __init__(self, *args, **options):
        super().__init__(*args, **options)
        self.tip = 101
        self.operations = []
        self.mode = None
        self.funding = None
        self.source = {"hash":SOURCE_HASH,"height":1,"tx":[{"txid":SOURCE_TXID,"hex":"04",
            "vin":[{"coinbase":"00"}],"vout":[{"n":0,"valueZat":VALUE,
                                                       "scriptPubKey":{"addresses":[MINER]}}]}]}

    def rpc(self, method, params=None, *, deadline=None):
        self.operations.append(method)
        if method == "getblockcount":
            return self.tip
        if method == "getblockhash":
            return SOURCE_HASH
        if method == "gettxout":
            return None if self.mode == "spent" else {"valueZat":VALUE}
        if method == "sendrawtransaction":
            return "ff"*32 if self.mode == "wrong-submitted" else TXID
        if method == "getrawmempool":
            return [TXID]
        if method == "getblock":
            if params[0] == SOURCE_HASH:
                return copy.deepcopy(self.source)
            tx = {"txid":TXID,"hex":"ff" if self.mode == "wrong-raw" else "05"}
            if "recipient_output" in self.funding:
                output = self.funding["recipient_output"]
                tx["vout"] = [{"n":output["vout"],"valueZat":output["amount_zatoshi"],
                    "scriptPubKey":{"hex":output["script_hex"],"addresses":[output["address"]]}}]
            return {"hash":params[0],"height":self.funding["target_height"],"tx":[tx]}
        raise AssertionError(method)

    def mine(self, count):
        self.operations.append("mine")
        hashes = [f"{height:064x}" for height in range(self.tip+1,self.tip+count+1)]
        self.tip += count
        return {"hashes":hashes,"tip":{"height":self.tip,"hash":hashes[-1]}}

    def grpc(self, method, payload=None, *, deadline=None):
        self.operations.append(method)
        assert method == "GetBlock"
        field = "actions" if self.funding["pools"][-1] == "orchard" else "ironwoodActions"
        target = self.funding["target_height"]
        return {"height":str(target),"hash":encoded(f"{target:064x}" if self.mode != "wrong-compact" else "ff"*32,True),
            "vtx":[] if self.mode == "missing-compact" else [{"txid":encoded(TXID,True),field:[{}]}]}

    def grpc_stream(self, method, payload=None, *, deadline=None):
        self.operations.append(method)
        output = self.funding["recipient_output"]
        if self.mode == "missing-stream":
            return []
        if method == "GetTaddressTxids":
            return [{"height":str(self.funding["target_height"]),"data":encoded("05")}]
        assert method == "GetAddressUtxosStream"
        return [{"txid":encoded(TXID,True),"index":output["vout"],"address":output["address"],
            "script":encoded(output["script_hex"]),"height":str(self.funding["target_height"]),
            "valueZat":str(output["amount_zatoshi"] if self.mode != "wrong-utxo" else 1)}]


class ZakuraFundingTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.BackendTests(methodName="runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.loader.return_value = fixtures.modeled_source(FundingFixture)
        self.case = self.fixture.case(1)
        self.backend = self.backend_for(self.case)
        self.funding_changes = {}
        self.sign_calls = []

    def backend_for(self, case):
        owner = fixtures.BACKEND.prepare_native_zakura_backend(case,
            tooling_root=Path("unused-source"),grpcurl=Path("unused-grpcurl"),
            proto_dir=Path("unused-protos"),miner_address=MINER)
        self.fixture.backends.append(owner)
        owner.start()
        return owner

    def signer(self, case, artifact, command, request=None, **options):
        self.assertIs(case, self.case)
        self.sign_calls.append(command)
        if command == "identity":
            return {"schema_version":1,"miner_address":MINER}
        pool = {"build":"ironwood","build-orchard":"orchard","build-transparent":"transparent"}[command]
        value = {"schema_version":1,"raw_tx_hex":"05","txid":TXID,"fee_zatoshi":FEE,
            "input_value_zatoshi":VALUE,"amount_zatoshi":request["amount_zatoshi"],
            "coinbase_source_height":request["coinbase_height"],"coinbase_txid":SOURCE_TXID,
            "coinbase_vout":0,"change_zatoshi":VALUE-request["amount_zatoshi"]-FEE,
            "target_height":request["target_height"],"maturity_validated":True,
            "pools":["transparent"] if pool == "transparent" else ["transparent",pool]}
        if pool == "transparent":
            value["recipient_output"] = {"address":request["recipient_address"],"vout":0,
                                         "script_hex":"76a9","amount_zatoshi":request["amount_zatoshi"]}
        value.update(self.funding_changes)
        self.backend._fixture.funding = copy.deepcopy(value)
        return value

    def fund(self, **updates):
        options = dict(recipient_address=MINER, amount_zatoshi=AMOUNT, recipient_pool="transparent", confirmations=2)
        options.update(updates)
        with patch.object(FUNDING,"run_offline_funder",side_effect=self.signer):
            return FUNDING.fund_zakura(self.case,self.backend,object(),**options)

    def test_transparent_exact_integer_raw_compact_stream_and_evidence(self):
        proof = self.fund()
        self.assertEqual(proof["amount_zatoshi"], AMOUNT)
        self.assertEqual(proof["mined_height"],102)
        self.assertEqual(proof["final_tip_height"],103)
        self.assertEqual(proof["input_value_zatoshi"], proof["amount_zatoshi"]+proof["fee_zatoshi"]+proof["change_zatoshi"])
        self.assertTrue(proof["transparent_output"]["lwd_utxo_exact"])
        self.assertFalse(proof["wallet_or_catalog_pass"])
        evidence = list(self.backend.root.glob("funding-inclusion-*.json"))
        self.assertEqual(len(evidence),1)
        self.assertEqual(json.loads(evidence[0].read_text())["proof"],proof)

    def test_ironwood_compact_pool_and_orchard_rejected_on_height1_profile(self):
        proof = self.fund(recipient_pool="ironwood")
        self.assertEqual(proof["compact_action_count"],1)
        self.assertIsNone(proof["transparent_output"])
        self.backend._fixture.tip = 101
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"Orchard"):
            self.fund(recipient_pool="orchard")

    def test_orchard_original_activation500_case_has_exact_pool_oracle(self):
        self.case = self.fixture.case(500)
        self.backend = self.backend_for(self.case)
        proof = self.fund(recipient_pool="orchard")
        self.assertEqual(proof["pool"],"orchard")
        self.assertEqual(proof["compact_action_count"],1)
        self.assertEqual(self.sign_calls,["identity","build-orchard"])

    def test_exact_maturity_is_accepted_but_one_block_before_is_rejected(self):
        self.backend._fixture.tip = 99
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"not mature"):
            self.fund(confirmations=1)
        self.assertNotIn("sendrawtransaction",self.backend._fixture.operations)
        self.backend._fixture.tip = 100
        proof = self.fund(confirmations=1)
        self.assertEqual(proof["mined_height"],101)
        self.assertEqual(proof["final_tip_height"],101)

    def test_exact_orchard_maturity_at_last_preactivation_block_is_valid(self):
        self.case = self.fixture.case(500)
        self.backend = self.backend_for(self.case)
        self.backend._fixture.source["height"] = 399
        self.backend._fixture.tip = 498
        proof = self.fund(source_height=399,recipient_pool="orchard",confirmations=1)
        self.assertEqual(proof["mined_height"],499)
        self.assertEqual(proof["final_tip_height"],499)
        self.assertEqual(proof["compact_action_count"],1)

    def test_invalid_inputs_and_precancellation_never_sign_or_mutate_node(self):
        for updates in ({"amount_zatoshi":True},{"amount_zatoshi":0},{"amount_zatoshi":1.0},
                        {"confirmations":0},{"source_height":True},{"timeout":False}):
            with self.subTest(updates=updates),self.assertRaises(FUNDING.ZakuraFundingError):
                self.fund(**updates)
        cancellation = threading.Event()
        cancellation.set()
        with self.assertRaises(FUNDING.runtime.Cancelled):
            self.fund(cancel_event=cancellation)
        self.assertEqual(self.sign_calls,[])
        self.assertEqual(self.backend._fixture.operations,[])

    def test_immature_spent_wrong_source_or_miner_never_broadcasts(self):
        model = self.backend._fixture
        model.tip = 99
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"not mature"):
            self.fund()
        model.tip, model.mode = 101,"spent"
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"already spent"):
            self.fund()
        model.mode = None
        model.source["height"] = 2
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"wrong coinbase"):
            self.fund()
        model.source["height"] = 1
        model.miner_address = "wrong"
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"miner differs"):
            self.fund()
        self.assertNotIn("sendrawtransaction",model.operations)

    def test_float_bool_bad_conservation_wrong_source_or_schema_never_broadcasts(self):
        for changes in ({"amount_zatoshi":float(AMOUNT)},{"coinbase_vout":False},
            {"change_zatoshi":1},{"coinbase_txid":"ff"*32},{"schema_version":True},
            {"unexpected":True},{"maturity_validated":False},{"target_height":103}):
            self.funding_changes = changes
            with self.subTest(changes=changes),self.assertRaises(FUNDING.ZakuraFundingError):
                self.fund()
        self.assertNotIn("sendrawtransaction",self.backend._fixture.operations)

    def test_wrong_submission_raw_compact_or_transparent_stream_never_proves_payment(self):
        for mode in ("wrong-submitted","wrong-raw","wrong-compact","missing-stream","wrong-utxo"):
            self.backend._fixture.mode, self.backend._fixture.tip = mode,101
            with self.subTest(mode=mode),self.assertRaises(FUNDING.ZakuraFundingError):
                self.fund()
        self.assertEqual(list(self.backend.root.glob("funding-inclusion-*.json")),[])

    def test_shielded_missing_compact_transaction_fails(self):
        self.backend._fixture.mode = "missing-compact"
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"compact block omitted"):
            self.fund(recipient_pool="ironwood")

    def test_foreign_case_cannot_use_backend(self):
        foreign = self.fixture.case(1)
        with self.assertRaisesRegex(FUNDING.ZakuraFundingError,"original accepting"):
            FUNDING.fund_zakura(foreign,self.backend,object(),recipient_address=MINER,amount_zatoshi=AMOUNT)


if __name__ == "__main__":
    unittest.main()
