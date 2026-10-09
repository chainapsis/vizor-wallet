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
from unittest.mock import Mock, patch

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
        self.args = SimpleNamespace(workers=2,repeat=2,build_jobs=4,order="short-first",timing_reports=[],
            flutter=self.root/"bin/flutter", grpcurl=self.root/"grpcurl",
            zakura_cache=self.root,proto_dir=self.root)
        self.catalog = e2e_catalog.load_catalog()
        self.scenarios = (self.catalog.scenarios_by_id["flutter.macos.import-sync"],)
        self.helper = object()
        self.macos_build_proof = {"app_build_count":1, "helper_build_count":1}
        self.ios_build_proof = {"ios_app_build_count":1, "ios_helper_build_count":1}
        self.signer = SimpleNamespace(identity=lambda: {"cargo_build_count":1, "cache_hit":False, "cache_key":"a"*64})
        self.voting = object()
        self.voting_build_proof = {"build_count": 1}
        self.barrier = threading.Barrier(2)
        self.observed = []
        self.fail = False

    def git(self, command, **kwargs):
        if "runtimes" in command:
            return subprocess.CompletedProcess(command,0,json.dumps({"runtimes":[{
                "identifier":"model-runtime", "isAvailable":True,
                "supportedArchitectures":[SUITE.platform.machine()],
                "supportedDeviceTypes":[{"identifier":"model-device"}]}]}), "")
        return subprocess.CompletedProcess(command,0,"a"*40+"\n" if "rev-parse" in command else "","")

    def execute(self, root, run_id, worker_id, scenario, **kwargs):
        self.observed.append((root,run_id,worker_id,kwargs["helper"],kwargs["artifact"],kwargs["voting_artifact"]))
        self.barrier.wait(timeout=2)
        return {"scenario_id":scenario.id,"target":scenario.target,"test":scenario.test,
                "status":"failed" if self.fail and root.name == "repetition-0" else "passed"}

    def invoke(self):
        output = io.StringIO()
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git), \
             patch.object(SUITE,"NativeCaseLifecycle",side_effect=lambda x:x), \
             patch.object(SUITE,"prepare_native_case_workspace",return_value=object()), \
             patch.object(SUITE,"build_native_macos_cohort",return_value=(self.helper,self.macos_build_proof)) as build, \
             patch.object(SUITE,"build_native_ios_cohort",return_value=(self.helper,self.ios_build_proof)) as ios_build, \
             patch.object(SUITE,"build_regtest_funder",return_value=self.signer) as signer, \
             patch.object(SUITE,"build_voting_artifacts",return_value=(self.voting,self.voting_build_proof)) as voting, \
             patch.object(SUITE,"derive_payment_addresses",return_value={"desktop_transparent":"tm-public-sdk-model",
                 "receiver_tex":"texregtest1publicsdkmodel"}), \
             patch.object(SUITE,"derive_ios_migration_addresses", return_value={
                 "note_addresses":tuple("uregtest1model"+str(index) for index in range(500)),
                 "send_recipient":"uregtest1receivermodel"}) as ios_addresses, \
             patch.object(SUITE,"execute_case",side_effect=self.execute), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            code = SUITE.run_native_suite(self.args,self.catalog,self.scenarios,
                {"kind":"scenario","values":[self.scenarios[0].id]},source_root=self.root)
        self.voting_builder = voting
        self.ios_builder = ios_build
        self.ios_address_deriver = ios_addresses
        return code,json.loads(output.getvalue()),build,signer

    def test_two_concurrent_repetitions_share_only_one_build_and_signer(self):
        code,summary,build,signer = self.invoke()
        self.assertEqual(code,0)
        build.assert_called_once()
        signer.assert_called_once()
        self.voting_builder.assert_not_called()
        self.assertEqual(len({item[0] for item in self.observed}),2)
        self.assertEqual(len({item[1] for item in self.observed}),2)
        self.assertTrue(all(item[3] is self.helper and item[4] is self.signer for item in self.observed))
        for item in summary["repetition_reports"]:
            report = json.loads(Path(item["report"]).read_text())
            self.assertEqual(report["schema_version"],2)
            self.assertEqual(report["results"][0]["status"],"passed")
            with self.assertRaisesRegex(e2e_catalog.CatalogError,"zero scenarios"):
                e2e_catalog.select_scenarios(self.catalog,failed_from=Path(item["report"]))

    def test_short_dispatch_keeps_catalog_result_order_and_separate_budgets(self):
        self.args.workers, self.args.repeat = 1, 1
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "rust.receive.sync", "rust.send.basic", "flutter.macos.import-sync"))
        report = self.root/"timings.json"
        report.write_text(json.dumps({"schema_version":2,"catalog_sha256":self.catalog.fingerprint,
            "source_commit":"b" * 40,"results":[{
                "scenario_id":case.id,"profile":case.profile,"target":case.target,"test":case.test,
                "status":"passed","duration_seconds":duration,
            } for case,duration in zip(self.scenarios,(8,2,20))]}))
        self.args.timing_reports = [report]
        observed = []
        def execute(root, run_id, worker_id, case, **kwargs):
            observed.append((case.id,worker_id))
            return {"scenario_id":case.id,"target":case.target,"test":case.test,
                    "status":"passed","duration_seconds":1}
        self.execute = execute
        code,summary,_,_ = self.invoke()
        self.assertEqual(code,0)
        self.assertEqual(observed,[(self.scenarios[1].id,1),(self.scenarios[0].id,0),(self.scenarios[2].id,2)])
        final = json.loads(Path(summary["repetition_reports"][0]["report"]).read_text())
        self.assertEqual([case["scenario_id"] for case in final["results"]],[case.id for case in self.scenarios])
        self.assertEqual(summary["schedule"],final["schedule"])
        self.assertEqual(summary["resource_budget"],{
            "artifact_producer_slots":1,"cargo_jobs":4,"case_slots":1})

    def test_invalid_timing_input_is_rejected_before_resources_or_builds(self):
        self.args.timing_reports = [self.root/"missing.json"]
        with patch.object(SUITE.sys,"platform","darwin"):
            with self.assertRaises(OSError):
                SUITE.run_native_suite(self.args,self.catalog,self.scenarios,{},source_root=self.root)
        self.assertFalse((self.root/".regtest-logs").exists())

    def test_unproven_retention_cancels_following_case_before_allocation(self):
        cancel = threading.Event()
        worker = SimpleNamespace(prepare_case=Mock(side_effect=RuntimeError("case failed")),
                                 retain=Mock(side_effect=RuntimeError("writer join unproven")))
        with patch.object(SUITE,"prepare_native_worker_lifecycle",return_value=worker) as allocate:
            first = SUITE.execute_case(self.root,"a" * 10,0,self.scenarios[0],helper=self.helper,
                artifact=self.signer,source_root=self.root,dart=Path("/model/dart"),args=self.args,cancel=cancel)
            second = SUITE.execute_case(self.root,"a" * 10,1,self.scenarios[0],helper=self.helper,
                artifact=self.signer,source_root=self.root,dart=Path("/model/dart"),args=self.args,cancel=cancel)
        self.assertEqual(first["status"],"failed")
        self.assertEqual(first["cleanup_errors"],["writer join unproven"])
        self.assertEqual(second["status"],"cancelled")
        allocate.assert_called_once()

    def test_cache_hit_reports_zero_builds_without_changing_case_execution(self):
        self.signer = SimpleNamespace(identity=lambda: {
            "cargo_build_count":0, "cache_hit":True, "cache_key":"b"*64})
        self.scenarios = (self.catalog.scenarios_by_id["rust.receive.sync"],)
        code, summary, app, signer = self.invoke()
        self.assertEqual(code, 0)
        app.assert_not_called()
        signer.assert_called_once()
        self.assertEqual(summary["builds"]["signer_build_count"], 0)
        self.assertEqual(summary["builds"]["rust_build_count"], 0)
        self.assertTrue(summary["builds"]["signer_cache_hit"])
        self.assertEqual(summary["builds"]["signer_cache_key"], "b"*64)
        self.assertEqual(len(self.observed), 2)
        self.assertTrue(all(item[4] is self.signer for item in self.observed))
        self.assertTrue(signer.call_args.kwargs["cache_root"].is_relative_to(self.root/".regtest-logs/build-cache"))

    def test_native_cache_hit_keeps_fresh_repetitions_and_reports_zero_app_helper_builds(self):
        self.macos_build_proof = {"app_build_count":0, "helper_build_count":0, "cache_hit":True}
        code,summary,build,_ = self.invoke()
        self.assertEqual(code,0)
        self.assertEqual(summary["builds"]["app_build_count"],0)
        self.assertEqual(summary["builds"]["helper_build_count"],0)
        self.assertTrue(summary["builds"]["cache_hit"])
        self.assertEqual(len({item[1] for item in self.observed}),2)
        self.assertTrue(build.call_args.kwargs["cache_root"].is_relative_to(self.root/".regtest-logs/build-cache"))

    def test_ios_cache_hit_reports_zero_builds_and_keeps_new_cases(self):
        self.scenarios = (self.catalog.scenarios_by_id["flutter.ios.import-sync"],)
        self.args.ios_runtime,self.args.ios_device_type = "model-runtime","model-device"
        self.ios_build_proof = {"ios_app_build_count":0, "ios_helper_build_count":0, "cache_hit":True}
        code,summary,build,_ = self.invoke()
        self.assertEqual(code,0)
        build.assert_not_called()
        self.assertEqual(summary["builds"]["ios"]["ios_app_build_count"],0)
        self.assertEqual(summary["builds"]["ios"]["ios_helper_build_count"],0)
        self.assertTrue(summary["builds"]["ios"]["cache_hit"])
        self.assertEqual(len({item[1] for item in self.observed}),2)
        self.assertTrue(self.ios_builder.call_args.kwargs["cache_root"].is_relative_to(self.root/".regtest-logs/build-cache"))

    def test_ios_repetitions_build_one_cohort_and_do_not_build_macos(self):
        self.scenarios = (self.catalog.scenarios_by_id["flutter.ios.import-sync"],)
        self.args.ios_runtime, self.args.ios_device_type = "model-runtime", "model-device"
        code, summary, mac_build, signer = self.invoke()
        self.assertEqual(code, 0)
        mac_build.assert_not_called()
        self.ios_builder.assert_called_once()
        signer.assert_called_once()
        self.assertEqual(summary["builds"]["ios"]["ios_app_build_count"], 1)

    def test_ios_unavailable_selection_is_rejected_before_run_writes(self):
        self.args.ios_runtime, self.args.ios_device_type = "other-runtime", "model-device"
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git):
            with self.assertRaisesRegex(ValueError,"not available"):
                SUITE.validate_options(self.args,(self.catalog.scenarios_by_id["flutter.ios.import-sync"],))
        self.assertFalse((self.root/".regtest-logs").exists())

    def test_ios_migration_group_derives_maximum_dataset_once_and_shares_one_build(self):
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "flutter.ios.ironwood-pre-migration-send", "flutter.ios.ironwood-migration-500-notes"))
        self.args.ios_runtime, self.args.ios_device_type = "model-runtime", "model-device"
        code, summary, mac_build, signer = self.invoke()
        self.assertEqual(code, 0)
        mac_build.assert_not_called()
        signer.assert_called_once()
        self.assertTrue(signer.call_args.kwargs["wallet_addresses"])
        self.ios_builder.assert_called_once()
        self.ios_address_deriver.assert_called_once()
        self.assertEqual(self.ios_address_deriver.call_args.args[2], self.scenarios)
        self.assertEqual(summary["builds"]["ios_note_address_count"], 500)

    def test_mobile_migration_profile_mismatch_is_rejected_before_build_or_run_writes(self):
        self.args.ios_runtime, self.args.ios_device_type = "model-runtime", "model-device"
        migration = self.catalog.scenarios_by_id["flutter.ios.ironwood-migration"]
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git):
            with self.assertRaisesRegex(ValueError, "profile does not match"):
                SUITE.validate_options(self.args, (replace(migration, profile="flutter-direct-height1"),))
        self.assertFalse((self.root/".regtest-logs").exists())

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

    def test_mempool_cases_are_publicly_runnable_without_host_prefunding(self):
        scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "flutter.macos.mempool-receive-history", "flutter.macos.mempool-during-sync",
            "flutter.macos.mempool-expiry"))
        with patch.object(SUITE.sys, "platform", "darwin"):
            SUITE.validate_options(self.args, scenarios)
        for scenario in scenarios:
            self.assertEqual(SUITE.scenario_funding(scenario.id), ())
            self.assertTrue(scenario.supported)
        self.assertTrue(e2e_catalog.plan(self.catalog, scenarios).runnable)

    def test_gift_cases_are_publicly_runnable_with_exact_funding(self):
        scenarios = tuple(self.catalog.scenarios_by_id[name] for name in (
            "flutter.macos.payment-link-round-trip", "flutter.macos.payment-link-restart",
            "flutter.macos.payment-link-recovery"))
        with patch.object(SUITE.sys, "platform", "darwin"):
            SUITE.validate_options(self.args, scenarios)
        for scenario in scenarios:
            self.assertEqual(SUITE.scenario_funding(scenario.id), (
                (SUITE._DESKTOP_UA,125000000,"ironwood",1),))
            self.assertTrue(scenario.supported)
        self.assertTrue(e2e_catalog.plan(self.catalog, scenarios).runnable)

    def test_voting_repetitions_share_one_producer_and_exact_preactivation_funding(self):
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in sorted(SUITE.VOTING_SCENARIOS))
        self.args.voting_sdk_cache = self.args.voting_pir_cache = self.root
        code, summary, app, signer = self.invoke()
        self.assertEqual(code, 0)
        self.voting_builder.assert_called_once()
        app.assert_called_once()
        signer.assert_called_once()
        self.assertEqual(summary["builds"]["voting_build_count"], 1)
        self.assertTrue(all(item[5] is self.voting for item in self.observed))
        for scenario in self.scenarios:
            self.assertEqual(SUITE.scenario_funding(scenario.id), (
                (SUITE._DESKTOP_UA,13000000,"orchard",1),))
            # Existing phase deadlines remain 15+45 minutes; service/restart
            # allowance is additional, not a shorter whole-case override.
            self.assertGreaterEqual(scenario.timeout_seconds, 15*60+45*60+15*60)

    def test_voting_requires_both_source_caches_and_activation500_before_writes(self):
        scenario = self.catalog.scenarios_by_id["flutter.macos.voting"]
        with patch.object(SUITE.sys, "platform", "darwin"):
            with self.assertRaisesRegex(ValueError, "voting-sdk-cache"):
                SUITE.validate_options(self.args, (scenario,))
            self.args.voting_sdk_cache = self.root
            with self.assertRaisesRegex(ValueError, "voting-pir-cache"):
                SUITE.validate_options(self.args, (scenario,))
            self.args.voting_pir_cache = self.root
            with self.assertRaisesRegex(ValueError, "preactivation"):
                SUITE.validate_options(self.args, (replace(scenario, profile="flutter-direct-height1"),))
        self.assertFalse((self.root/".regtest-logs").exists())

    def test_warm_voting_cache_reports_zero_builds_and_keeps_cases_isolated(self):
        self.scenarios = tuple(self.catalog.scenarios_by_id[name] for name in sorted(SUITE.VOTING_SCENARIOS))
        self.args.voting_sdk_cache = self.args.voting_pir_cache = self.root
        self.voting_build_proof = {"build_count": 0, "cache_hit": True, "cache_key": "b"*64}
        code, summary, _, _ = self.invoke()
        self.assertEqual(code, 0)
        self.voting_builder.assert_called_once()
        self.assertEqual(self.voting_builder.call_args.kwargs["cache_root"],
                         self.root/".regtest-logs/build-cache/voting-v1")
        self.assertEqual(summary["builds"]["voting_build_count"], 0)
        self.assertEqual(summary["builds"]["voting_proof"], self.voting_build_proof)
        self.assertEqual(len(self.observed), len(self.scenarios)*self.args.repeat)
        self.assertEqual(len({item[0] for item in self.observed}), self.args.repeat)
        self.assertTrue(all(item[5] is self.voting for item in self.observed))

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
