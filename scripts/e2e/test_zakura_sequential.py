"""Sequential Zakura runner: selection, pass proof, source guard and failure cleanup."""
import dataclasses
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_sequential as SEQUENTIAL

PASS_OUTPUT = ["running 1 test\n", "test funded_wallet_can_send_to_second_wallet ... ok\n", "\n",
               "test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 1 filtered out; finished in 4.20s\n"]


class SelectionTests(unittest.TestCase):
    def test_exact_ids_and_dotted_prefixes_select_in_catalog_order_without_duplicates(self):
        selected = SEQUENTIAL.select_scenarios(["rust.import", "rust.import.bip39-passphrase"])
        self.assertEqual([s.id for s in selected], [s.id for s in SEQUENTIAL.RUST_SCENARIOS
                                                    if s.id.startswith("rust.import.")])
        self.assertEqual(len(SEQUENTIAL.select_scenarios(["rust"])), len(SEQUENTIAL.RUST_SCENARIOS))
        self.assertEqual([s.id for s in SEQUENTIAL.select_scenarios(["rust.send.basic"])], ["rust.send.basic"])

    def test_unknown_names_and_partial_segments_are_rejected(self):
        for name in ("rust.unknown", "rust.imp", "flutter.macos.unknown", "flutter.mac"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                SEQUENTIAL.select_scenarios([name])

    def test_only_ironwood_scenarios_fund_orchard_before_a_controlled_activation(self):
        for scenario in SEQUENTIAL.RUST_SCENARIOS:
            expected = 500 if scenario.id.startswith("rust.ironwood.") else 1
            self.assertEqual(scenario.activation_height, expected, scenario.id)
        self.assertEqual(len({s.id for s in SEQUENTIAL.RUST_SCENARIOS}), len(SEQUENTIAL.RUST_SCENARIOS))

    def test_flutter_catalog_funds_each_coinbase_once_and_orchard_only_before_activation(self):
        flutter = SEQUENTIAL.flutter_cases
        ids = [s.id for s in SEQUENTIAL.ALL_SCENARIOS]
        self.assertEqual(len(set(ids)), len(ids))
        for scenario in flutter.FLUTTER_SCENARIOS:
            with self.subTest(scenario=scenario.id):
                notes = scenario.orchard_notes
                transactions = flutter.runner_sources(scenario)
                sources = [height for heights in transactions for height in heights]
                self.assertEqual(len(sources), len(set(sources)))
                # Each funding transaction mines 10 blocks, and spending the
                # coinbase of height h needs a tip of h + 99 or more.
                for index, heights in enumerate(transactions):
                    self.assertGreaterEqual(scenario.initial_blocks + 10 * index, max(heights) + 99)
                # The tests' own payments may spend before mining anything.
                last = scenario.phases[-1]
                test_sources = flutter.funding_source_height(scenario, last) + last.fundings - 1
                self.assertGreaterEqual(scenario.initial_blocks + 10 * len(transactions), test_sources + 99)
                self.assertEqual(scenario.activation_height, 500 if notes else 1)
                for value in flutter.derived_addresses(scenario):
                    self.assertIn(value.field, {"unifiedAddress", "transparentAddress", "texAddress"})


class OutputTests(unittest.TestCase):
    def test_only_the_selected_test_passing_alone_counts(self):
        SEQUENTIAL.verify_test_output(PASS_OUTPUT, "funded_wallet_can_send_to_second_wallet")
        cases = {
            "other test": (PASS_OUTPUT, "imported_second_account_can_send_using_its_own_seed"),
            "zero tests": (["running 0 tests\n", "test result: ok. 0 passed; 0 failed; 0 ignored; "
                            "0 measured; 2 filtered out; finished in 0.00s\n"], "funded_wallet_can_send_to_second_wallet"),
            "ignored": (["running 1 test\n", "test funded_wallet_can_send_to_second_wallet ... ignored\n",
                         "test result: ok. 0 passed; 0 failed; 1 ignored; 0 measured; 1 filtered out; "
                         "finished in 0.00s\n"], "funded_wallet_can_send_to_second_wallet"),
        }
        for label, (lines, test) in cases.items():
            with self.subTest(label), self.assertRaises(SEQUENTIAL.runtime.RunnerError):
                SEQUENTIAL.verify_test_output(lines, test)


class SourceGuardTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="zakura-source-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        for command in (["init", "-q"], ["config", "user.email", "model@example.invalid"],
                        ["config", "user.name", "model"]):
            subprocess.run(["git", "-C", str(self.root), *command], check=True)
        (self.root / "rust").mkdir()
        (self.root / "rust" / "lib.rs").write_text("// committed\n")
        (self.root / "README.md").write_text("committed\n")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.root), "commit", "-q", "-m", "model"], check=True)

    def test_committed_rust_inputs_return_head(self):
        (self.root / "README.md").write_text("changes outside rust/ do not matter\n")
        root, commit = SEQUENTIAL.committed_source(self.root)
        head = subprocess.run(["git", "-C", str(self.root), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True).stdout.strip()
        self.assertEqual((root, commit), (self.root, head))

    def test_modified_or_untracked_rust_inputs_are_refused(self):
        for change in (lambda: (self.root / "rust" / "lib.rs").write_text("// edited\n"),
                       lambda: (self.root / "rust" / "new.rs").write_text("// untracked\n")):
            subprocess.run(["git", "-C", str(self.root), "checkout", "-q", "--", "."], check=True)
            subprocess.run(["git", "-C", str(self.root), "clean", "-qfd", "rust"], check=True)
            change()
            with self.assertRaisesRegex(ValueError, "commit the changes under rust/"):
                SEQUENTIAL.committed_source(self.root)


class FakeCase:
    """Records the calls run_case makes on a sequential case."""
    def __init__(self, *_args, fail=None, close_fails=False, **_kwargs):
        self.calls = []
        self._finished = False
        self.fail = fail
        self.close_fails = close_fails
        self.case = type("Case", (), {"workspace": type("Workspace", (), {"root": Path("/model/evidence")})()})()

    def start(self, **_kwargs):
        self.calls.append("start")
        if self.fail == "start":
            raise SEQUENTIAL.runtime.RunnerError("fixture failed")

    def run_rust(self, *_args, **_kwargs):
        self.calls.append("run")
        if isinstance(self.fail, BaseException):
            raise self.fail

    def run_flutter(self, *_args, dart_defines=(), **_kwargs):
        self.calls.append("run flutter")
        self.dart_defines = dart_defines

    def close(self, **_kwargs):
        self.calls.append("close")
        self._finished = True
        if self.close_fails:
            raise SEQUENTIAL.runtime.RunnerError("cleanup unproven")

    def retain(self):
        self.calls.append("retain")
        self._finished = True

    def retained_resources(self):
        return {"evidence": "/model/evidence"}


class RunCaseTests(unittest.TestCase):
    def run_case(self, keep_failed=False, **fake):
        created = []

        def factory(*args, **kwargs):
            created.append(FakeCase(*args, **kwargs, **fake))
            return created[-1]

        with patch.object(SEQUENTIAL, "SequentialCase", side_effect=factory):
            result = SEQUENTIAL.run_case(Path("/model/cases"), "a1b2c3d4e5", 1, SEQUENTIAL.SCENARIOS["rust.send.basic"],
                artifact=object(), grpcurl=Path("/model/grpcurl"), proto_dir=Path("/model/protos"),
                dart=Path("/model/dart"), source_root=Path("/model/root"), keep_failed=keep_failed,
                cancel_event=threading.Event())
        return result, created[0].calls

    def test_pass_closes_the_case(self):
        result, calls = self.run_case()
        self.assertEqual((result["status"], result["returncode"]), ("passed", 0))
        self.assertEqual(calls, ["start", "run", "close"])
        self.assertEqual(set(result["phase_seconds"]), {"prepare", "chain", "execute", "close"})

    def test_failure_cleans_up_by_default_and_keeps_state_on_request(self):
        result, calls = self.run_case(fail="start")
        self.assertEqual((result["status"], result["failed_phase"]), ("failed", "chain"))
        self.assertEqual(calls, ["start", "close"])
        self.assertNotIn("retained", result)
        result, calls = self.run_case(keep_failed=True, fail="start")
        self.assertEqual(calls, ["start", "retain"])
        self.assertEqual(result["retained"], {"evidence": "/model/evidence"})

    def test_unproven_cleanup_retains_and_reports_it(self):
        result, calls = self.run_case(fail=SEQUENTIAL.runtime.RunnerError("assertion failed", 101), close_fails=True)
        self.assertEqual((result["status"], result["returncode"]), ("failed", 101))
        self.assertEqual(calls, ["start", "run", "close", "retain"])
        self.assertEqual(result["cleanup_error"], "cleanup unproven")
        self.assertIn("retained", result)

    def test_flutter_scenarios_use_the_fixed_ports_and_run_their_phases(self):
        created = []

        def factory(*args, **kwargs):
            created.append((kwargs, FakeCase(*args, **kwargs)))
            return created[-1][1]

        scenario = SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"]
        with patch.object(SEQUENTIAL, "SequentialCase", side_effect=factory):
            result = SEQUENTIAL.run_case(Path("/model/cases"), "a1b2c3d4e5", 1, scenario,
                artifact=object(), grpcurl=Path("/model/grpcurl"), proto_dir=Path("/model/protos"),
                dart=Path("/model/dart"), source_root=Path("/model/root"), keep_failed=False,
                cancel_event=threading.Event(), flutter=Path("/model/flutter"), device="macos",
                dart_defines=(("GIFT_CARD_E2E_AMOUNT_MODE", "usd"),))
        kwargs, case = created[0]
        self.assertEqual(kwargs["ports"], {"rpc": 18232, "lwd": 9067, "proxy": 19068})
        self.assertEqual(kwargs["platform"], "macos")
        self.assertEqual(case.calls, ["start", "run flutter", "close"])
        self.assertEqual(case.dart_defines, (("GIFT_CARD_E2E_AMOUNT_MODE", "usd"),))
        self.assertEqual((result["status"], result["tests"]),
                         ("passed", ["integration_test/regtest_import_sync_test.dart"]))

    def test_voting_cases_prune_their_regenerated_data_once_stopped(self):
        for scenario_id, fail, pruned in (("flutter.macos.voting", None, True),
                                          ("flutter.macos.voting", "start", True),
                                          ("flutter.macos.import-sync", None, False)):
            with self.subTest(scenario=scenario_id, fail=fail), \
                 patch.object(SEQUENTIAL, "SequentialCase", side_effect=lambda *a, **kw: FakeCase(*a, fail=fail, **kw)), \
                 patch.object(SEQUENTIAL.tree, "prune_voting_data", return_value={"removed": []}) as prune:
                result = SEQUENTIAL.run_case(Path("/model/cases"), "a1b2c3d4e5", 1, SEQUENTIAL.SCENARIOS[scenario_id],
                    artifact=object(), grpcurl=Path("/model/grpcurl"), proto_dir=Path("/model/protos"),
                    dart=Path("/model/dart"), source_root=Path("/model/root"), keep_failed=False,
                    cancel_event=threading.Event(), flutter=Path("/model/flutter"), device="macos")
                if pruned:
                    prune.assert_called_once_with(Path("/model/evidence"))
                    self.assertEqual(result["voting_prune"], {"removed": []})
                else:
                    prune.assert_not_called()

    def test_a_case_whose_cleanup_failed_keeps_its_voting_data(self):
        with patch.object(SEQUENTIAL, "SequentialCase",
                          side_effect=lambda *a, **kw: FakeCase(*a, fail="start", close_fails=True, **kw)), \
             patch.object(SEQUENTIAL.tree, "prune_voting_data") as prune:
            result = SEQUENTIAL.run_case(Path("/model/cases"), "a1b2c3d4e5", 1, SEQUENTIAL.SCENARIOS["flutter.macos.voting"],
                artifact=object(), grpcurl=Path("/model/grpcurl"), proto_dir=Path("/model/protos"),
                dart=Path("/model/dart"), source_root=Path("/model/root"), keep_failed=False,
                cancel_event=threading.Event(), flutter=Path("/model/flutter"), device="macos")
        self.assertEqual(result["cleanup_error"], "cleanup unproven")
        prune.assert_not_called()

    def test_deadline_and_cancellation_have_their_own_status(self):
        result, _ = self.run_case(fail=SEQUENTIAL.runtime.RunnerError("deadline", 124))
        self.assertEqual(result["status"], "timed_out")
        result, _ = self.run_case(fail=SEQUENTIAL.runtime.Cancelled())
        self.assertEqual(result["status"], "cancelled")


class FlutterCommandTests(unittest.TestCase):
    def command(self, scenario):
        return SEQUENTIAL.flutter_cases.flutter_command(scenario, scenario.phases[0],
            flutter=Path("/model/flutter"), device="DEVICE", source_root=Path("/model/root"))

    def test_phases_run_from_the_checkout_with_the_fixture_defines(self):
        command = self.command(SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"])
        self.assertEqual(command[3:8], ["/model/root", "/model/flutter", "test",
                                        "integration_test/regtest_import_sync_test.dart", "-d"])
        self.assertIn("--dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=1", command)
        self.assertIn("--dart-define=ZCASH_E2E_LIGHTWALLETD_URL=http://127.0.0.1:9067", command)
        self.assertIn("--dart-define=ZCASH_E2E_DRIVER_URL=http://127.0.0.1:18232", command)
        self.assertIn("--dart-define=VIZOR_E2E_HIDDEN_WINDOW=true", command)
        self.assertNotIn("--dart-define=VIZOR_FORM_FACTOR=mobile", command)
        fallback = self.command(SEQUENTIAL.SCENARIOS["flutter.macos.fallback-endpoint"])
        self.assertFalse(any(part.startswith("--dart-define=ZCASH_E2E_LIGHTWALLETD_URL=")
                             for part in fallback))
        moved = subprocess.run([sys.executable, "-c", command[2], tempfile.gettempdir(), "pwd"],
            check=True, capture_output=True, text=True).stdout.strip()
        self.assertEqual(Path(moved).resolve(), Path(tempfile.gettempdir()).resolve())

    def test_macos_windows_stay_hidden_unless_the_environment_shows_them(self):
        scenario = SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"]
        for value, expected in (("", "true"), ("false", "false")):
            with self.subTest(value=value), patch.dict(os.environ, {"VIZOR_E2E_HIDDEN_WINDOW": value}):
                self.assertIn(f"--dart-define=VIZOR_E2E_HIDDEN_WINDOW={expected}", self.command(scenario))

    def test_mobile_phases_use_the_mobile_form_factor_and_cannot_move_the_fixture(self):
        flutter = SEQUENTIAL.flutter_cases
        mobile = flutter.FlutterScenario("flutter.ios.model", "ios",
            (flutter.Phase("integration_test/model_test.dart", args=("--no-uninstall",)),),
            activation_height=500)
        command = self.command(mobile)
        self.assertIn("--no-uninstall", command)
        self.assertIn("--dart-define=VIZOR_FORM_FACTOR=mobile", command)
        self.assertIn("--dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=500", command)
        self.assertNotIn("--dart-define=VIZOR_E2E_HIDDEN_WINDOW=true", command)
        moving = dataclasses.replace(mobile, defines=(("ZCASH_E2E_DRIVER_URL", "http://127.0.0.1:1"),))
        with self.assertRaises(ValueError):
            self.command(moving)

    def test_each_phase_starts_spending_after_the_runner_and_earlier_phases(self):
        flutter = SEQUENTIAL.flutter_cases
        scenario = flutter.FlutterScenario("flutter.macos.model", "macos",
            (flutter.Phase("integration_test/a_test.dart", fundings=2),
             flutter.Phase("integration_test/b_test.dart", fundings=1)),
            funding=(flutter.Funding(flutter.DESKTOP_UA, 1, "ironwood", 1),
                     flutter.Funding(flutter.IMPORT_TRANSPARENT, 1, "transparent", 2)))
        self.assertEqual([flutter.funding_source_height(scenario, phase) for phase in scenario.phases], [3, 5])
        command = flutter.flutter_command(scenario, scenario.phases[1], flutter=Path("/model/flutter"),
            device="DEVICE", source_root=Path("/model/root"))
        self.assertIn("--dart-define=ZCASH_E2E_FUNDING_SOURCE_HEIGHT=5", command)

    def test_screenshot_scenarios_also_hold_the_screenshot_port(self):
        flutter = SEQUENTIAL.flutter_cases
        self.assertEqual(flutter.fixed_ports(SEQUENTIAL.SCENARIOS["flutter.ios.screenshot-tour"]),
                         {**flutter.FIXED_PORTS, "screenshots": 39070})
        self.assertEqual(flutter.fixed_ports(SEQUENTIAL.SCENARIOS["flutter.ios.import-sync"]),
                         flutter.FIXED_PORTS)

    def test_derived_defines_need_their_address(self):
        flutter = SEQUENTIAL.flutter_cases
        scenario = SEQUENTIAL.SCENARIOS["flutter.ios.ironwood-pre-migration-send"]
        command = SEQUENTIAL.flutter_cases.flutter_command(scenario, scenario.phases[0],
            flutter=Path("/model/flutter"), device="DEVICE", source_root=Path("/model/root"),
            derived={flutter.RECEIVER_UA: "uregtest1model"})
        self.assertIn("--dart-define=ZCASH_E2E_SEND_RECIPIENT_ADDRESS=uregtest1model", command)
        self.assertIn("--dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=500", command)
        with self.assertRaises(ValueError):
            self.command(scenario)

    def test_only_a_reported_pass_counts(self):
        verify = SEQUENTIAL.flutter_cases.verify_flutter_output
        verify(["00:24 +1: All tests passed!\n"])
        verify(["01:02 +3 ~1: All tests passed!\n"])
        for lines in (["Xcode build done.\n"], ["00:00 +0: All tests passed!\n"],
                      ["00:03 +0 ~1: All tests skipped.\n"],
                      ["00:24 +1: All tests passed!\n", "00:30 +1 -1: Some tests failed.\n"]):
            with self.subTest(lines=lines), self.assertRaises(SEQUENTIAL.runtime.RunnerError):
                verify(lines)


class Signer:
    """The model build's handle; only its cache identity is read here."""
    def __init__(self, hit=False):
        self.hit = hit

    def identity(self):
        return {"cache_hit": self.hit, "cache_key": "c" * 64}


class SequenceHarness(unittest.TestCase):
    """Runs run_sequence with a model build and model cases."""
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="zakura-run-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        for target, value in (("committed_source", lambda root: (self.root, "a" * 40)),
                              ("resolve_dart", lambda flutter, root: Path("/model/dart")),
                              ("ensure_pinned_images", lambda *args, **kwargs: {})):
            patcher = patch.object(SEQUENTIAL, target, side_effect=value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(SEQUENTIAL.diagnostics, "session_locked", return_value=False)
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_sequence(self, status, keep_failed, scenarios=None, run_case=None, dart_defines=()):
        def build(producer, **_kwargs):
            output = producer.workspace.root / "funder-build" / "target"
            output.mkdir(parents=True)
            (output / "test-binary").write_bytes(b"0" * 4096)
            producer.close()
            return Signer()

        result = {"status": status, "duration_seconds": 1.0, "error": None if status == "passed" else "failed"}
        with patch.object(SEQUENTIAL, "build_regtest_funder", side_effect=build), \
             patch.object(SEQUENTIAL, "run_case", side_effect=run_case, return_value=result):
            report, _ = SEQUENTIAL.run_sequence(self.root,
                scenarios or [SEQUENTIAL.SCENARIOS["rust.send.basic"]],
                flutter=Path("/model/flutter"), grpcurl=self.root, proto_dir=self.root,
                keep_failed=keep_failed, out=lambda _text: None, ios_runtime="iOS-26-3",
                dart_defines=dart_defines)
        producer = next((self.root / ".regtest-logs" / f"zakura-{report['run_id']}" / "builds" / "e2e").iterdir())
        return report, producer


class SignerCacheTests(SequenceHarness):
    """Every run asks the build cache for the same signer, whatever it selects."""

    def test_the_signer_carries_every_catalog_target_and_the_address_tool(self):
        calls = []

        def build(producer, **kwargs):
            calls.append(kwargs)
            producer.close()
            return Signer(hit=len(calls) > 1)

        passed = lambda *_args, **_kwargs: {"status": "passed", "duration_seconds": 1.0, "error": None}
        reports = []
        for selection in (["rust.send.basic"], ["flutter.macos.import-sync"]):
            with patch.object(SEQUENTIAL, "build_regtest_funder", side_effect=build), \
                 patch.object(SEQUENTIAL, "run_case", side_effect=passed):
                report, _ = SEQUENTIAL.run_sequence(self.root, [SEQUENTIAL.SCENARIOS[i] for i in selection],
                    flutter=Path("/model/flutter"), grpcurl=self.root, proto_dir=self.root, out=lambda _text: None)
            reports.append(report)
        catalog = list(dict.fromkeys(s.target for s in SEQUENTIAL.RUST_SCENARIOS))
        for kwargs in calls:
            self.assertEqual(kwargs["test_targets"], tuple(catalog))
            self.assertIs(kwargs["wallet_addresses"], True)
            self.assertEqual(kwargs["cache_root"], self.root / ".regtest-logs" / "build-cache" / "funder-v1")
        self.assertEqual([r["builds"]["signer_cache_hit"] for r in reports], [False, True])
        self.assertEqual([r["builds"]["rust_test_targets"] for r in reports],
                         [[SEQUENTIAL.SCENARIOS["rust.send.basic"].target], []])
        self.assertEqual(reports[1]["builds"]["rust_built_test_targets"], catalog)


class SessionLockTests(SequenceHarness):
    """Flutter scenarios do not start while the macOS session is locked."""

    def run_locked(self, locked, scenarios, run_case):
        def build(producer, **_kwargs):
            producer.close()
            return Signer()

        with patch.object(SEQUENTIAL.diagnostics, "session_locked", side_effect=locked) as probe, \
             patch.object(SEQUENTIAL, "build_regtest_funder", side_effect=build) as built, \
             patch.object(SEQUENTIAL, "run_case", side_effect=run_case) as ran:
            report, _ = SEQUENTIAL.run_sequence(self.root, scenarios, flutter=Path("/model/flutter"),
                grpcurl=self.root, proto_dir=self.root, out=lambda _text: None)
        return report, probe, built, ran

    def test_a_locked_session_stops_the_run_before_the_build(self):
        report, _, built, ran = self.run_locked([True], [SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"]],
                                                run_case=None)
        self.assertEqual(report["error"], SEQUENTIAL.SESSION_LOCKED)
        built.assert_not_called()
        ran.assert_not_called()

    def test_a_lock_during_the_run_marks_the_failure_and_stops_the_next_case(self):
        failed = lambda *_args, **_kwargs: {"status": "timed_out", "duration_seconds": 1.0,
                                            "error": "control deadline expired"}
        scenarios = [SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"],
                     SEQUENTIAL.SCENARIOS["flutter.macos.payment-link-round-trip"]]
        report, _, _, ran = self.run_locked([False, False, True, True], scenarios, run_case=failed)
        self.assertEqual(ran.call_count, 1)
        self.assertEqual(report["results"][0]["error"],
                         "control deadline expired (the macOS session was locked)")
        self.assertEqual(report["error"], SEQUENTIAL.SESSION_LOCKED)

    def test_rust_runs_do_not_check_the_session(self):
        passed = lambda *_args, **_kwargs: {"status": "passed", "duration_seconds": 1.0, "error": None}
        report, probe, _, _ = self.run_locked([True], [SEQUENTIAL.SCENARIOS["rust.send.basic"]],
                                              run_case=passed)
        probe.assert_not_called()
        self.assertIsNone(report["error"])


class StallStackTests(unittest.TestCase):
    """A Flutter phase that misses its deadline leaves the app's stacks in the case evidence."""

    def test_a_missed_deadline_samples_the_app_before_teardown(self):
        from native_zakura_control import NativeZakuraControlError

        class Control:
            def pump(self, **_kwargs):
                raise NativeZakuraControlError("control deadline expired", 124)

        running = type("Running", (), {"process": type("Popen", (), {"poll": lambda self: None})()})()
        case = SEQUENTIAL.SequentialCase.__new__(SEQUENTIAL.SequentialCase)
        case.control, case.derived = Control(), {}
        case.front = type("Front", (), {"assert_running": lambda self: None})()
        case.case = type("Case", (), {"start_process": lambda self, *a, **kw: running,
                                      "workspace": type("Workspace", (), {"root": Path("/model/evidence")})()})()
        samples = []
        with patch.object(SEQUENTIAL.diagnostics, "app_pids", return_value=[42]) as pids, \
             patch.object(SEQUENTIAL.diagnostics, "sample_stacks",
                          side_effect=lambda found, directory, label: samples.append((found, directory, label))):
            with self.assertRaises(SEQUENTIAL.runtime.RunnerError) as raised:
                case.run_flutter(SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"], flutter=Path("/model/flutter"),
                                 device="macos", source_root=Path("/model/root"), cancel_event=threading.Event())
        self.assertEqual(raised.exception.exit_code, 124)
        self.assertEqual(samples, [([42], Path("/model/evidence/stacks"), "phase-1-deadline")])
        pids.assert_called_once_with("macos", source_root=Path("/model/root"), device="macos")


class BuildOutputTests(SequenceHarness):
    """A run's fresh signer build is removed when the run ends, even beside kept fixtures."""

    def test_every_run_removes_the_build_but_keeps_its_logs(self):
        for status, keep_failed in (("passed", True), ("failed", True), ("failed", False)):
            with self.subTest(status=status, keep_failed=keep_failed):
                report, producer = self.run_sequence(status, keep_failed=keep_failed)
                self.assertFalse((producer / "funder-build").exists())
                self.assertTrue((producer / "case-manifest.json").exists())
                self.assertEqual(report["build_prune"]["errors"], [])
                self.assertGreaterEqual(report["build_prune"]["bytes"], 4096)


class DefineTests(SequenceHarness):
    def test_extra_defines_reach_each_case_and_the_report(self):
        seen = []

        def run_case(*_args, dart_defines=(), **_kwargs):
            seen.append(dart_defines)
            return {"status": "passed", "duration_seconds": 1.0, "error": None}

        mode = (("GIFT_CARD_E2E_AMOUNT_MODE", "usd"),)
        report, _ = self.run_sequence("passed", keep_failed=False, run_case=run_case, dart_defines=mode,
            scenarios=[SEQUENTIAL.SCENARIOS["flutter.macos.payment-link-round-trip"]])
        self.assertEqual(seen, [mode])
        self.assertEqual(report["dart_defines"], ["GIFT_CARD_E2E_AMOUNT_MODE=usd"])


class FixtureStartTests(unittest.TestCase):
    """Derived addresses resolve before funding; Orchard notes go out in their batches."""
    def start(self, scenario):
        flutter = SEQUENTIAL.flutter_cases
        records = {flutter.DESKTOP_MNEMONIC: {"unifiedAddresses": [f"uregtest1note{n}" for n in range(500)]},
                   flutter.RECEIVER_MNEMONIC: {"unifiedAddress": "uregtest1receiver"}}
        calls = {"funding": [], "batches": [], "derived": []}
        case = object.__new__(SEQUENTIAL.SequentialCase)
        case.case = object()
        case.derived = {}
        case.lease = type("Lease", (), {"release_sockets": lambda self: None})()

        def wallet_addresses(artifact, mnemonic, count=1, *, cancel_event):
            calls["derived"].append((mnemonic, count))
            record = dict(records[mnemonic])
            record["unifiedAddresses"] = record.get("unifiedAddresses", ["uregtest1receiver"])[:count]
            return record

        case.wallet_addresses = wallet_addresses
        backend = type("Backend", (), {"start": lambda self: None, "mine": lambda self, count: None})()
        front = type("Front", (), {"start": lambda self, **_kwargs: None})()
        with patch.object(SEQUENTIAL, "prepare_native_zakura_backend", return_value=backend), \
             patch.object(SEQUENTIAL, "fund_zakura",
                          side_effect=lambda *_a, **kw: calls["funding"].append(kw["recipient_address"])), \
             patch.object(SEQUENTIAL, "fund_zakura_batch",
                          side_effect=lambda *_a, **kw: calls["batches"].append(
                              (len(kw["payments"]), kw["source_heights"], kw["recipient_pool"]))), \
             patch.object(SEQUENTIAL, "create_zakura_genesis_proof"), \
             patch.object(SEQUENTIAL, "prepare_native_zakura_front", return_value=front), \
             patch.object(SEQUENTIAL, "prepare_native_zakura_control"):
            case.start(grpcurl=None, proto_dir=None, dart=None, source_root=None, artifact=None,
                cancel_event=threading.Event(), initial_blocks=scenario.initial_blocks,
                funding=scenario.funding, orchard_notes=scenario.orchard_notes,
                derive=flutter.derived_addresses(scenario))
        return case, calls

    def test_receiver_address_is_derived_and_notes_are_funded_in_orchard(self):
        flutter = SEQUENTIAL.flutter_cases
        case, calls = self.start(SEQUENTIAL.SCENARIOS["flutter.ios.ironwood-pre-migration-send"])
        self.assertEqual(case.derived, {flutter.RECEIVER_UA: "uregtest1receiver"})
        self.assertEqual(calls["batches"], [(1, (1,), "orchard")])
        self.assertEqual(calls["derived"], [(flutter.RECEIVER_MNEMONIC, 1), (flutter.DESKTOP_MNEMONIC, 1)])

    def test_five_hundred_notes_go_out_in_ten_transactions(self):
        _case, calls = self.start(SEQUENTIAL.SCENARIOS["flutter.ios.ironwood-migration-500-notes"])
        self.assertEqual([count for count, _sources, _pool in calls["batches"]], [50] * 10)
        self.assertEqual([sources for _count, sources, _pool in calls["batches"]],
                         [(height,) for height in range(1, 11)])


class VotingPhaseTests(unittest.TestCase):
    """The setup phase runs on the desktop app; the services' defines reach the later phases."""
    def test_services_start_after_the_setup_phase_and_are_checked_last(self):
        flutter = SEQUENTIAL.flutter_cases
        scenario = SEQUENTIAL.SCENARIOS["flutter.ios.voting-reinstall"]
        commands, events = [], []
        case = object.__new__(SEQUENTIAL.SequentialCase)
        case.derived = {}
        case.control = type("Control", (), {"pump": lambda self, **_kwargs: None})()
        case.front = type("Front", (), {"assert_running": lambda self: None})()
        case.backend = type("Backend", (), {"mine": lambda self, count: events.append(f"mine {count}")})()

        class Process:
            def poll(self):
                return 0

        def start_process(command, *, env, raw_lines, max_output_bytes):
            commands.append(command)
            events.append("flutter")
            raw_lines.append("00:01 +1: All tests passed!\n")
            return type("Managed", (), {"process": Process()})()

        case.case = type("Case", (), {
            "start_process": staticmethod(start_process),
            "wait_process": staticmethod(lambda *_a, **_kw: 0),
            "workspace": type("Workspace", (), {"root": Path("/model/evidence")})()})()
        with patch.object(SEQUENTIAL.SequentialCase, "_start_voting",
                          side_effect=lambda *_a: events.append("services") or (("ZCASH_E2E_VOTE_ROUND_ID", "ab"),)), \
             patch.object(SEQUENTIAL.SequentialCase, "_check_voting",
                          side_effect=lambda *_a: events.append("check")), \
             patch.object(SEQUENTIAL, "uninstall_app",
                          side_effect=lambda *args: events.append(("uninstall", *args))):
            case.run_flutter(scenario, flutter=Path("/model/flutter"), device="MODEL-UDID",
                             source_root=Path("/model/root"), cancel_event=threading.Event())
        self.assertEqual(events, ["flutter", "services", "flutter",
            ("uninstall", "MODEL-UDID", Path("/model/root/build/ios/iphonesimulator/Runner.app")),
            "flutter", "check"])
        devices = [command[command.index("-d") + 1] for command in commands]
        self.assertEqual(devices, ["macos", "MODEL-UDID", "MODEL-UDID"])
        self.assertIn("--dart-define=VIZOR_E2E_HIDDEN_WINDOW=true", commands[0])
        self.assertNotIn("--dart-define=ZCASH_E2E_VOTE_ROUND_ID=ab", commands[0])
        for command in commands[1:]:
            self.assertIn("--dart-define=VIZOR_FORM_FACTOR=mobile", command)
            self.assertIn("--dart-define=ZCASH_E2E_VOTE_ROUND_ID=ab", command)
            self.assertIn("--dart-define=ZCASH_E2E_VOTING_KEEP_APP_STATE=1", command)
        self.assertEqual(flutter.fixed_ports(scenario)["voting_gateway"], 18080)


class CasePortTests(unittest.TestCase):
    def test_service_ports_are_leased_but_kept_out_of_the_fixture_workspace(self):
        ports = SEQUENTIAL.flutter_cases.fixed_ports(SEQUENTIAL.SCENARIOS["flutter.ios.voting"])
        lease = type("Lease", (), {"ports": dict(ports), "close": lambda self: None})()
        with patch.object(SEQUENTIAL, "_require_unbound"), \
             patch.object(SEQUENTIAL, "lease_fixed_ports", return_value=lease) as leased, \
             patch.object(SEQUENTIAL, "prepare_native_case_workspace") as workspace, \
             patch.object(SEQUENTIAL, "NativeCaseLifecycle"):
            SEQUENTIAL.SequentialCase(Path("/model/cases"), run_id="a1b2c3d4e5", case_index=1,
                scenario_id="flutter.ios.voting", platform="ios", activation_height=500, ports=ports)
        self.assertEqual(leased.call_args.args[1], ports)
        self.assertEqual(workspace.call_args.kwargs["ports"], {"rpc": 18232, "lwd": 9067, "proxy": 19068})


class CaptureTests(unittest.TestCase):
    def test_marked_sandbox_pngs_are_copied_into_the_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sandbox = root / "support" / SEQUENTIAL.CAPTURE_DIRECTORY
            sandbox.mkdir(parents=True)
            (sandbox / "unused.png").write_bytes(b"png")
            (root / "support" / "wallet.png").write_bytes(b"other")
            case = object.__new__(SEQUENTIAL.SequentialCase)
            evidence = root / "evidence"
            evidence.mkdir()
            case.case = type("Case", (), {"workspace": type("Workspace", (), {"root": evidence})()})()
            case._collect_captures([
                f"flutter: {SEQUENTIAL.CAPTURE_MARKER}{sandbox / 'unused.png'}\n",
                f"flutter: {SEQUENTIAL.CAPTURE_MARKER}{root / 'support' / 'wallet.png'}\n",
                f"flutter: {SEQUENTIAL.CAPTURE_MARKER}{sandbox / 'missing.png'}\n",
                "00:24 +1: All tests passed!\n"])
            self.assertEqual(sorted(path.name for path in (evidence / "captures").iterdir()), ["unused.png"])


class VotingModeTests(unittest.TestCase):
    def test_final_tally_and_ledger_modes_reach_the_services(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, {}, clear=False):
            os.environ.pop("E2E_VOTE_WINDOW_SECS", None)
            evidence = Path(directory)
            (evidence / "voting").mkdir()
            (evidence / "voting" / "ready.json").write_text('{"defines": {"ZCASH_E2E_FINAL_TALLY": "true"}}')
            envs = []

            def start_process(command, *, env, max_output_bytes):
                envs.append(env)
                return type("Managed", (), {"process": type("Process", (), {"poll": lambda self: None})()})()

            case = object.__new__(SEQUENTIAL.SequentialCase)
            case.control = type("Control", (), {"pump": lambda self, **_kwargs: None})()
            case.case = type("Case", (), {"workspace": type("Workspace", (), {"root": evidence})(),
                                          "start_process": staticmethod(start_process)})()
            for scenario, modes in (("flutter.macos.voting", ("0", "0")),
                                    ("flutter.macos.voting-final-tally", ("1", "0")),
                                    ("flutter.macos.voting-ledger-final-tally", ("1", "1"))):
                defines = case._start_voting(SEQUENTIAL.SCENARIOS[scenario].voting, Path("/model/root"),
                    "macos", float("inf"), threading.Event())
                self.assertEqual((envs[-1]["E2E_FINAL_TALLY"], envs[-1]["E2E_LEDGER_VOTING"]), modes)
                self.assertEqual(envs[-1].get("E2E_VOTE_WINDOW_SECS"), "300" if modes[0] == "1" else None)
            self.assertEqual(defines, (("ZCASH_E2E_FINAL_TALLY", "true"),))


class FakeSimulator:
    created = []

    def __init__(self, run_id, runtime_identifier):
        self.name, self.udid, self.runtime = f"model {run_id}", "MODEL-UDID", runtime_identifier
        self.deleted = False
        FakeSimulator.created.append(self)

    def describe(self):
        return {"name": self.name, "udid": self.udid, "runtime": self.runtime}

    def delete(self):
        self.deleted = True


class SimulatorTests(SequenceHarness):
    """iOS scenarios run on a simulator the run creates after its build."""
    def setUp(self):
        super().setUp()
        FakeSimulator.created = []
        patcher = patch.object(SEQUENTIAL, "RunSimulator", FakeSimulator)
        patcher.start()
        self.addCleanup(patcher.stop)
        flutter = SEQUENTIAL.flutter_cases
        self.ios = flutter.FlutterScenario("flutter.ios.model", "ios",
            (flutter.Phase("integration_test/model_test.dart"),))
        self.devices = []

    def record(self, status):
        def run_case(*_args, device=None, **_kwargs):
            self.devices.append(device)
            return {"status": status, "duration_seconds": 1.0, "error": None if status == "passed" else "failed"}
        return run_case

    def test_ios_scenarios_get_the_run_simulator_which_is_deleted_after_a_pass(self):
        macos = SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"]
        report, _ = self.run_sequence("passed", keep_failed=False, scenarios=[macos, self.ios],
                                      run_case=self.record("passed"))
        self.assertEqual(self.devices, ["macos", "MODEL-UDID"])
        self.assertEqual(report["ios_simulator"]["runtime"], "iOS-26-3")
        self.assertTrue(FakeSimulator.created[0].deleted)

    def test_failed_runs_keep_the_simulator_only_when_asked(self):
        report, _ = self.run_sequence("failed", keep_failed=True, scenarios=[self.ios],
                                      run_case=self.record("failed"))
        self.assertTrue(report["ios_simulator"]["kept"])
        self.assertFalse(FakeSimulator.created[0].deleted)
        self.run_sequence("failed", keep_failed=False, scenarios=[self.ios], run_case=self.record("failed"))
        self.assertTrue(FakeSimulator.created[1].deleted)

    def test_macos_runs_create_no_simulator(self):
        report, _ = self.run_sequence("passed", keep_failed=False,
            scenarios=[SEQUENTIAL.SCENARIOS["flutter.macos.import-sync"]], run_case=self.record("passed"))
        self.assertNotIn("ios_simulator", report)
        self.assertEqual(FakeSimulator.created, [])


if __name__ == "__main__":
    unittest.main()
