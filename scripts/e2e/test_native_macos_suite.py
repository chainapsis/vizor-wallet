"""Coordinator models; native signing, wallet assertions and Docker are not real."""
import contextlib
from dataclasses import replace
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e2e_catalog
import native_macos_suite as SUITE


class SuiteTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="native-suite-model-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        (self.root/"bin/cache/dart-sdk/bin").mkdir(parents=True)
        for name in ("bin/flutter", "grpcurl", "bin/cache/dart-sdk/bin/dart"):
            tool = self.root/name
            tool.write_text("model-only")
            tool.chmod(0o700)
        self.args = SimpleNamespace(workers=2,repeat=2,build_jobs=4,
            flutter=self.root/"bin/flutter", grpcurl=self.root/"grpcurl",
            zakura_cache=self.root,proto_dir=self.root)
        self.catalog = e2e_catalog.load_catalog()
        self.scenarios = (self.catalog.scenarios_by_id["flutter.macos.import-sync"],)
        self.helper, self.signer = object(), object()
        self.barrier = threading.Barrier(2)
        self.observed = []
        self.fail = False

    def git(self, command, **kwargs):
        return subprocess.CompletedProcess(command,0,"a"*40+"\n" if "rev-parse" in command else "","")

    def execute(self, root, run_id, worker_id, scenario, **kwargs):
        self.observed.append((root,run_id,worker_id,kwargs["helper"],kwargs["artifact"]))
        self.barrier.wait(timeout=2)
        return {"scenario_id":scenario.id,"target":scenario.target,"test":scenario.test,
                "status":"failed" if self.fail and root.name == "repetition-0" else "passed"}

    def invoke(self):
        output = io.StringIO()
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git), \
             patch.object(SUITE,"NativeCaseLifecycle",side_effect=lambda x:x), \
             patch.object(SUITE,"prepare_native_case_workspace",return_value=object()), \
             patch.object(SUITE,"build_native_macos_cohort",return_value=(self.helper,{"app_build_count":1})) as build, \
             patch.object(SUITE,"build_regtest_funder",return_value=self.signer) as signer, \
             patch.object(SUITE,"derive_payment_addresses",return_value={"desktop_transparent":"tm-public-sdk-model",
                 "receiver_tex":"texregtest1publicsdkmodel"}), \
             patch.object(SUITE,"execute_case",side_effect=self.execute), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            code = SUITE.run_native_suite(self.args,self.catalog,self.scenarios,
                {"kind":"scenario","values":[self.scenarios[0].id]},source_root=self.root)
        return code,json.loads(output.getvalue()),build,signer

    def test_two_concurrent_repetitions_share_only_one_build_and_signer(self):
        code,summary,build,signer = self.invoke()
        self.assertEqual(code,0)
        build.assert_called_once()
        signer.assert_called_once()
        self.assertEqual(len({item[0] for item in self.observed}),2)
        self.assertEqual(len({item[1] for item in self.observed}),2)
        self.assertTrue(all(item[3] is self.helper and item[4] is self.signer for item in self.observed))
        for item in summary["repetition_reports"]:
            report = json.loads(Path(item["report"]).read_text())
            self.assertEqual(report["schema_version"],2)
            self.assertEqual(report["results"][0]["status"],"passed")
            with self.assertRaisesRegex(e2e_catalog.CatalogError,"zero scenarios"):
                e2e_catalog.select_scenarios(self.catalog,failed_from=Path(item["report"]))

    def test_a_failed_repetition_remains_rerunnable_and_makes_the_batch_fail(self):
        self.fail = True
        code,summary,_,_ = self.invoke()
        self.assertEqual(code,1)
        failed = next(item for item in summary["repetition_reports"] if item["failed"])
        selected = e2e_catalog.select_scenarios(self.catalog,failed_from=Path(failed["report"]))
        self.assertEqual(tuple(s.id for s in selected),("flutter.macos.import-sync",))

    def test_options_refuse_pending_cases_and_missing_tools_before_writes(self):
        with patch.object(SUITE.sys,"platform","darwin"):
            with self.assertRaises(ValueError):
                SUITE.validate_options(self.args,(self.catalog.scenarios_by_id["flutter.ios.import-sync"],))
            self.args.flutter = None
            with self.assertRaises(ValueError):
                SUITE.validate_options(self.args,self.scenarios)
        self.assertFalse((self.root/".regtest-logs").exists())

    def test_rust_cases_build_selected_targets_once_without_an_app_or_helper(self):
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "rust.receive.sync", "rust.send.basic", "rust.import.bip39-passphrase"))
        code, summary, app, signer = self.invoke()
        self.assertEqual(code, 0)
        app.assert_not_called()
        signer.assert_called_once()
        self.assertEqual(signer.call_args.kwargs["test_targets"],
                         ("regtest_receive_sync", "regtest_send", "regtest_import"))
        self.assertEqual(summary["builds"]["rust_build_count"], 1)
        self.assertTrue(all(item[3] is None for item in self.observed))

    def test_ironwood_group_builds_two_exact_targets_and_rejects_wrong_profile(self):
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "rust.ironwood.migration", "rust.ironwood.gift-card-claim"))
        code, summary, app, signer = self.invoke()
        self.assertEqual(code, 0)
        app.assert_not_called()
        self.assertEqual(signer.call_args.kwargs["test_targets"],
                         ("ironwood_regtest_migration", "ironwood_regtest_gift_card_claim"))
        self.assertEqual(summary["builds"]["rust_build_count"], 1)
        with patch.object(SUITE.sys, "platform", "darwin"):
            with self.assertRaises(ValueError):
                SUITE.validate_options(self.args, (replace(self.scenarios[0], profile="zakura-direct-height1"),))

    def test_multi_account_selection_builds_its_one_target_and_signer_without_native_builds(self):
        self.scenarios = tuple(s for s in self.catalog.scenarios if s.target == "regtest_multi_account")
        self.assertEqual(len(self.scenarios), 8)
        code, summary, app, signer = self.invoke()
        self.assertEqual(code, 0)
        app.assert_not_called()
        signer.assert_called_once()
        self.assertEqual(signer.call_args.kwargs["test_targets"], ("regtest_multi_account",))
        self.assertEqual(summary["builds"]["rust_build_count"], 1)
        self.assertTrue(all(item[3] is None for item in self.observed))

    def test_mixed_engine_selection_shares_the_signer_and_worker_budget(self):
        self.scenarios += (self.catalog.scenarios_by_id["rust.receive.sync"],)
        code, _, app, signer = self.invoke()
        self.assertEqual(code, 0)
        app.assert_called_once()
        signer.assert_called_once()
        self.assertEqual(signer.call_args.kwargs["test_targets"], ("regtest_receive_sync",))

    def test_build_failure_never_creates_a_passing_empty_batch(self):
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git), \
             patch.object(SUITE,"NativeCaseLifecycle",side_effect=lambda x:x), \
             patch.object(SUITE,"prepare_native_case_workspace",return_value=object()), \
             patch.object(SUITE,"build_regtest_funder",return_value=self.signer), \
             patch.object(SUITE,"build_native_macos_cohort",side_effect=RuntimeError("compiler failed")), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = SUITE.run_native_suite(self.args,self.catalog,self.scenarios,{},source_root=self.root)
        self.assertEqual(code,1)
        summary = json.loads(next((self.root/".regtest-logs").glob("native-suite-*/summary.json")).read_text())
        self.assertEqual(summary["error"],"compiler failed")
        self.assertEqual(summary["repetition_reports"],[])

    def test_endpoint_cases_are_supported_without_enabling_other_domains(self):
        scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "flutter.macos.fallback-endpoint", "flutter.macos.custom-endpoint-no-fallback",
            "flutter.macos.slow-height-fallback", "flutter.macos.sync-startup-stall-recovery"))
        with patch.object(SUITE.sys, "platform", "darwin"):
            SUITE.validate_options(self.args, scenarios)
        self.assertNotIn("flutter.macos.send", SUITE.SUPPORTED_SCENARIOS)

    def test_import_keeps_both_exact_balances_and_independent_sources(self):
        self.assertEqual(SUITE.scenario_funding("flutter.macos.import-sync"), (
            (SUITE._IMPORT_UA, 125000000, "ironwood", 1),
            (SUITE._IMPORT_TRANSPARENT, 75000000, "transparent", 2),
        ))

    def test_payment_group_keeps_exact_balances_and_independent_funding_sources(self):
        names = ("flutter.macos.shield-transparent", "flutter.macos.shield-transparent-retry",
            "flutter.macos.multi-account-send", "flutter.macos.tex-send", "flutter.macos.payment-uri-send",
            "flutter.macos.payment-uri-locked-send", "flutter.macos.payment-request-round-trip")
        with patch.object(SUITE.sys, "platform", "darwin"):
            SUITE.validate_options(self.args, tuple(self.catalog.scenarios_by_id[name] for name in names))
        self.assertEqual(SUITE.scenario_funding(names[0]), ())
        self.assertEqual(SUITE.scenario_funding(names[1]), ())
        with self.assertRaises(ValueError):
            SUITE.scenario_funding(names[2])
        self.assertEqual(SUITE.scenario_funding(names[2], desktop_transparent="tm-public-sdk-model"), (
            (SUITE._DESKTOP_UA,125000000,"ironwood",1),
            ("tm-public-sdk-model",75000000,"transparent",2)))
        for name in names[3:]:
            self.assertEqual(SUITE.scenario_funding(name), ((SUITE._DESKTOP_UA,125000000,"ironwood",1),))

    def test_payment_selection_derives_addresses_before_the_one_common_app_build(self):
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "flutter.macos.multi-account-send", "flutter.macos.tex-send"))
        code, summary, app, signer = self.invoke()
        self.assertEqual(code, 0)
        signer.assert_called_once()
        self.assertTrue(signer.call_args.kwargs["wallet_addresses"])
        app.assert_called_once()
        self.assertEqual(app.call_args.kwargs["tex_address"], "texregtest1publicsdkmodel")
        self.assertEqual(summary["builds"]["payment_addresses"]["desktop_transparent"], "tm-public-sdk-model")

    def test_fallback_cases_fund_the_existing_desktop_fixture_only(self):
        for name in ("flutter.macos.fallback-endpoint", "flutter.macos.slow-height-fallback"):
            with self.subTest(scenario=name):
                self.assertEqual(SUITE.scenario_funding(name), (
                    (SUITE._DESKTOP_UA, 125000000, "ironwood", 1),
                ))

    def test_unreachable_endpoint_and_startup_recovery_need_no_payment(self):
        for name in ("flutter.macos.custom-endpoint-no-fallback", "flutter.macos.sync-startup-stall-recovery"):
            self.assertEqual(SUITE.scenario_funding(name), ())
        with self.assertRaises(ValueError):
            SUITE.scenario_funding("flutter.macos.send")


if __name__ == "__main__":
    unittest.main()
