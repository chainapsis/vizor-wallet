"""Sequential Zakura runner: selection, pass proof, source guard and failure cleanup."""
import dataclasses
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

    def run_flutter(self, *_args, **_kwargs):
        self.calls.append("run flutter")

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
        self.assertEqual(set(result["phase_seconds"]), {"prepare", "fixture", "execute", "close"})

    def test_failure_cleans_up_by_default_and_keeps_state_on_request(self):
        result, calls = self.run_case(fail="start")
        self.assertEqual((result["status"], result["failed_phase"]), ("failed", "fixture"))
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
                cancel_event=threading.Event(), flutter=Path("/model/flutter"), device="macos")
        kwargs, case = created[0]
        self.assertEqual(kwargs["ports"], {"rpc": 18232, "lwd": 9067, "proxy": 19068})
        self.assertEqual(kwargs["platform"], "macos")
        self.assertEqual(case.calls, ["start", "run flutter", "close"])
        self.assertEqual((result["status"], result["tests"]),
                         ("passed", ["integration_test/regtest_import_sync_test.dart"]))

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
        moved = subprocess.run([sys.executable, "-c", command[2], tempfile.gettempdir(), "pwd"],
            check=True, capture_output=True, text=True).stdout.strip()
        self.assertEqual(Path(moved).resolve(), Path(tempfile.gettempdir()).resolve())

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

    def test_only_a_reported_pass_counts(self):
        verify = SEQUENTIAL.flutter_cases.verify_flutter_output
        verify(["00:24 +1: All tests passed!\n"])
        verify(["01:02 +3 ~1: All tests passed!\n"])
        for lines in (["Xcode build done.\n"], ["00:00 +0: All tests passed!\n"],
                      ["00:03 +0 ~1: All tests skipped.\n"],
                      ["00:24 +1: All tests passed!\n", "00:30 +1 -1: Some tests failed.\n"]):
            with self.subTest(lines=lines), self.assertRaises(SEQUENTIAL.runtime.RunnerError):
                verify(lines)


class BuildOutputTests(unittest.TestCase):
    """A run's fresh signer build is removed unless failed fixtures are kept beside it."""
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

    def run_sequence(self, status, keep_failed):
        def build(producer, **_kwargs):
            output = producer.workspace.root / "funder-build" / "target"
            output.mkdir(parents=True)
            (output / "test-binary").write_bytes(b"0" * 4096)
            producer.close()
            return object()

        result = {"status": status, "duration_seconds": 1.0, "error": None if status == "passed" else "failed"}
        with patch.object(SEQUENTIAL, "build_regtest_funder", side_effect=build), \
             patch.object(SEQUENTIAL, "run_case", return_value=result):
            report, _ = SEQUENTIAL.run_sequence(self.root, [SEQUENTIAL.SCENARIOS["rust.send.basic"]],
                flutter=Path("/model/flutter"), grpcurl=self.root, proto_dir=self.root,
                keep_failed=keep_failed, out=lambda _text: None)
        producer = next((self.root / ".regtest-logs" / f"zakura-{report['run_id']}" / "builds" / "e2e").iterdir())
        return report, producer

    def test_passing_run_removes_the_build_but_keeps_its_logs(self):
        report, producer = self.run_sequence("passed", keep_failed=True)
        self.assertFalse((producer / "funder-build").exists())
        self.assertTrue((producer / "case-manifest.json").exists())
        self.assertEqual(report["build_prune"]["errors"], [])
        self.assertGreaterEqual(report["build_prune"]["bytes"], 4096)

    def test_failed_run_keeps_the_build_only_beside_kept_fixtures(self):
        report, producer = self.run_sequence("failed", keep_failed=True)
        self.assertTrue((producer / "funder-build" / "target" / "test-binary").exists())
        self.assertNotIn("build_prune", report)
        report, producer = self.run_sequence("failed", keep_failed=False)
        self.assertFalse((producer / "funder-build").exists())


if __name__ == "__main__":
    unittest.main()
