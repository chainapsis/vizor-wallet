"""Mobile dataset/owner models, not signed funding or wallet PASS evidence."""
import json
from pathlib import Path
import sys
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_ios_migration as MIGRATION
import native_worker_lifecycle as WORKER
import test_native_worker_lifecycle as FIXTURES


class MigrationFixtureTests(unittest.TestCase):
    def setUp(self):
        self.model = FIXTURES.IosWorkerTests()
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        self.cancel = threading.Event()
        self.addresses = {"note_addresses": tuple(f"uregtest1fixture{index}" for index in range(500)),
                          "send_recipient": None}

    def session(self, name, activation=500):
        session = self.model.worker.prepare_case(platform="ios", scenario_id=name,
            case_index=0, activation_height=activation, helper=self.model.native.cohort,
            runtime_identifier=FIXTURES.IOS_FIXTURES.RUNTIME_ID,
            device_type_identifier=FIXTURES.IOS_FIXTURES.DEVICE_ID, timeout=15)
        with patch.object(WORKER.zakura, "load_zakura_fixture_source",
                          return_value=FIXTURES.BACKEND_FIXTURES.modeled_source(
                              FIXTURES.BACKEND_FIXTURES.FixtureModel)):
            session.prepare_zakura_backend(grpcurl=Path("unused"),
                proto_dir=Path("unused"), miner_address="explicit-regtest-miner-model", timeout=3)
        return session

    def proof(self, *args, **options):
        return {"payment_count":len(options["payments"]),
                "amount_zatoshi":sum(item["amount_zatoshi"] for item in options["payments"])}

    def test_all_eleven_original_datasets_keep_exact_default_amounts_and_counts(self):
        expected = {
            "ironwood-pre-migration-send": (1_095_000, 1, 1),
            "ironwood-migration": (1_095_000, 1, 1),
            "ironwood-migration-many-notes": (1_000_020_000, 20, 1),
            "ironwood-migration-multi-account": (1_100_000, 1, 1),
            "ironwood-migration-reorg": (1_100_000, 1, 1),
            "ironwood-migration-restart": (123_000_000, 1, 1),
            "ironwood-migration-network-recovery": (1_100_000, 1, 1),
            "ironwood-background-migration": (123_000_000, 1, 1),
            "ironwood-background-restart": (123_000_000, 1, 1),
            "ironwood-migration-account-reimport": (123_000_000, 1, 1),
            "ironwood-migration-500-notes": (500_000_000, 500, 10),
        }
        self.assertEqual(MIGRATION.IOS_MIGRATION_FUNDING,
                         {"flutter.ios."+name:value for name,value in expected.items()})

    def test_twenty_notes_use_original_two_coinbase_inputs(self):
        session = self.session("flutter.ios.ironwood-migration-many-notes")
        with patch.object(MIGRATION, "fund_zakura_batch", side_effect=self.proof) as fund:
            result = MIGRATION.fund_ios_migration(session, object(), self.addresses, cancel=self.cancel)
        self.assertEqual(result, [{"payment_count":20, "amount_zatoshi":1_000_020_000}])
        self.assertEqual(fund.call_args.kwargs["source_heights"], (1, 2))
        self.assertEqual({item["amount_zatoshi"] for item in fund.call_args.kwargs["payments"]}, {50_001_000})

    def test_five_hundred_notes_keep_ten_weighted_transactions_and_independent_sources(self):
        session = self.session("flutter.ios.ironwood-migration-500-notes")
        with patch.object(MIGRATION, "fund_zakura_batch", side_effect=self.proof) as fund:
            result = MIGRATION.fund_ios_migration(session, object(), self.addresses, cancel=self.cancel)
        self.assertEqual(len(result), 10)
        self.assertEqual(sum(item["amount_zatoshi"] for item in result), 500_000_000)
        self.assertEqual([call.kwargs["source_heights"] for call in fund.call_args_list],
                         [(height,) for height in range(1, 11)])
        self.assertEqual([len(call.kwargs["payments"]) for call in fund.call_args_list], [50]*10)

    def test_missing_notes_and_wrong_activation_are_rejected_before_signing(self):
        session = self.session("flutter.ios.ironwood-migration-many-notes", activation=1)
        with patch.object(MIGRATION, "fund_zakura_batch") as fund:
            with self.assertRaisesRegex(MIGRATION.runtime.RunnerError, "activation500"):
                MIGRATION.fund_ios_migration(session, object(), self.addresses, cancel=self.cancel)
            fund.assert_not_called()

    def test_derivation_selects_maximum_note_count_and_separate_send_recipient(self):
        session = self.session("flutter.ios.ironwood-pre-migration-send")
        artifact = Mock()
        artifact.wallet_addresses_binary.return_value = Path("/model/sdk-address-tool")
        calls = []
        def derive(command, **options):
            calls.append(command)
            count = int(command[-1])
            prefix = "uregtest1sender" if count == 500 else "uregtest1receiver"
            addresses = [prefix+str(index) for index in range(count)]
            return SimpleNamespace(returncode=0, lines=[json.dumps({
                "unifiedAddress":addresses[0], "unifiedAddresses":addresses})+"\n"])
        selected = [SimpleNamespace(id=name) for name in (
            "flutter.ios.ironwood-pre-migration-send", "flutter.ios.ironwood-migration-500-notes")]
        with patch.object(session.case, "run_command", side_effect=derive):
            result = MIGRATION.derive_ios_migration_addresses(session.case, artifact, selected,
                                                            cancel=self.cancel)
        self.assertEqual([command[-1] for command in calls], ["500", "1"])
        self.assertEqual(len(result["note_addresses"]), 500)
        self.assertEqual(result["send_recipient"], "uregtest1receiver0")
        self.assertFalse(session.case.accepting_launches)
        self.assertEqual(artifact.verify_unchanged.call_count, 4)

    def test_invalid_sdk_addresses_never_become_migration_fixtures(self):
        session = self.session("flutter.ios.ironwood-migration-many-notes")
        artifact = Mock()
        artifact.wallet_addresses_binary.return_value = Path("/model/sdk-address-tool")
        selected = [SimpleNamespace(id="flutter.ios.ironwood-migration-many-notes")]
        malformed = SimpleNamespace(returncode=0, lines=[json.dumps({
            "unifiedAddress":"uregtest1same", "unifiedAddresses":["uregtest1same"]*20})+"\n"])
        with patch.object(session.case, "run_command", return_value=malformed):
            with self.assertRaisesRegex(MIGRATION.runtime.RunnerError, "distinct exact"):
                MIGRATION.derive_ios_migration_addresses(session.case, artifact, selected, cancel=self.cancel)
        self.assertFalse(session.case.accepting_launches)


if __name__ == "__main__":
    unittest.main()
