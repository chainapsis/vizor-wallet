"""Real original Git publication/owned Python signer; Rust compiler modeled."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import funder_execution as EXECUTION
    import test_funder_build as fixtures
finally:
    sys.path.pop(0)


class FunderExecutionTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.FunderBuildTests(methodName="runTest")
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)

    def artifact(self, *, extra="", response=None, exit_code=0):
        contents = ("#!/usr/bin/env python3\nimport json,os,sys,time\n" + extra + "\n"
            "request = None if sys.argv[1] == 'identity' else json.load(sys.stdin)\n"
            "value = {'schema_version':1,'miner_address':'tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX'} "
            "if request is None else {'schema_version':1,'request':request,"
            "'namespace':os.environ['VIZOR_E2E_NAMESPACE'],'cwd':os.getcwd(),"
            "'input_mode':os.fstat(0).st_mode & 0o777}\n")
        contents += "print(json.dumps(value))\n" if response is None else f"print({response!r})\n"
        contents += f"raise SystemExit({exit_code})\n"
        self.fixture.binary_contents = contents
        return self.fixture.build()

    def execute(self, artifact, command="identity", request=None, case=None, **options):
        case = case or self.fixture.case()
        return EXECUTION.run_offline_funder(case, artifact, command, request, timeout=3, **options)

    def test_two_original_consumers_reuse_one_publication_and_join_their_outputs(self):
        artifact = self.artifact()
        for _ in range(2):
            case = self.fixture.case()
            value = self.execute(artifact, case=case)
            self.assertEqual(value["miner_address"], "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX")
            self.assertEqual(case.launched_process_count, 1)
            self.assertTrue(case._processes[0].cleanup_completed)
            self.assertEqual(case.close().exit_codes, (0,))
        self.assertEqual(self.fixture.compile_calls, 1)
        artifact.verify_unchanged()

    def test_owned_readonly_input_exact_request_identity_and_private_log(self):
        artifact = self.artifact()
        case = self.fixture.case()
        request = {"schema_version": 1, "amount_zatoshi": 1234567, "text": "검증"}
        result = self.execute(artifact, "build-transparent", request, case)
        self.assertEqual(result["request"], request)
        self.assertEqual(result["namespace"], case.workspace.namespace)
        self.assertEqual(result["cwd"], str(case.workspace.root))
        self.assertEqual(result["input_mode"], 0o400)
        saved = case.workspace.root / "funder-input-0000.json"
        self.assertEqual(json.loads(saved.read_text()), request)
        self.assertEqual(saved.stat().st_mode & 0o777, 0o400)
        self.assertEqual(case._processes[0].log_path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(case._processes[0].cleanup_completed)

    def test_signer_stdin_descriptor_is_readonly_not_only_its_file_mode(self):
        artifact = self.artifact(extra=(
            "import errno,fcntl\n"
            "assert fcntl.fcntl(0,fcntl.F_GETFL) & os.O_ACCMODE == os.O_RDONLY\n"
            "try: os.write(0,b'overwrite')\n"
            "except OSError as error: assert error.errno == errno.EBADF\n"
            "else: raise AssertionError('stdin descriptor retained write access')"))
        request = {"schema_version":1,"amount_zatoshi":1234567}
        case = self.fixture.case()
        value = self.execute(artifact,"build",request,case)
        self.assertEqual(value["request"],request)
        self.assertEqual(json.loads((case.workspace.root / "funder-input-0000.json").read_text()),request)
        self.assertTrue(case._processes[0].cleanup_completed)

    def test_invalid_request_command_timeout_or_external_handle_launches_nothing(self):
        artifact = self.artifact()
        case = self.fixture.case()
        attempts = [(artifact, "other", None, {}), (artifact, "identity", {}, {}),
            (artifact, "build", None, {}), (artifact, "build", {"amount": float("nan")}, {}),
            (artifact, "build", {"value": "x" * (2 * 1024 * 1024)}, {}),
            (str(artifact.binary), "identity", None, {}),
            (artifact, "identity", None, {"timeout": False})]
        for handle, command, request, options in attempts:
            with self.subTest(command=command, options=options), self.assertRaises(EXECUTION.FunderExecutionError):
                EXECUTION.run_offline_funder(case, handle, command, request, timeout=options.get("timeout", 3))
        self.assertEqual(case.launched_process_count, 0)
        self.assertFalse((case.workspace.root / "funder-input-0000.json").exists())

    def test_nonzero_exit_remains_failure_even_with_success_json(self):
        artifact = self.artifact(exit_code=23)
        case = self.fixture.case()
        with self.assertRaises(EXECUTION.FunderExecutionError) as caught:
            self.execute(artifact, case=case)
        self.assertEqual(caught.exception.exit_code, 23)
        self.assertTrue(case._processes[0].cleanup_completed)
        self.assertEqual(case.close().exit_codes, (23,))

    def test_malformed_multiple_duplicate_nonfinite_or_wrong_identity_never_returns(self):
        for response in ("not JSON", '{}\n{}', '{"schema_version":1,"schema_version":1}',
            '{"schema_version":1,"value":NaN}', '{"schema_version":true}',
            '{"schema_version":1,"miner_address":"wrong"}'):
            artifact = self.artifact(response=response)
            case = self.fixture.case()
            with self.subTest(response=response), self.assertRaises(EXECUTION.FunderExecutionError):
                self.execute(artifact, case=case)
            self.assertTrue(case._processes[0].cleanup_completed)

    def test_pre_cancellation_launches_nothing_and_timeout_joins_original_child(self):
        artifact = self.artifact(extra="time.sleep(30)")
        case = self.fixture.case()
        cancellation = threading.Event()
        cancellation.set()
        with self.assertRaises(EXECUTION.runtime.Cancelled):
            self.execute(artifact, case=case, cancel_event=cancellation)
        self.assertEqual(case.launched_process_count, 0)
        with self.assertRaises(EXECUTION.runtime.RunnerError) as caught:
            EXECUTION.run_offline_funder(case, artifact, "build", {"schema_version":1}, timeout=0.15)
        self.assertEqual(caught.exception.exit_code, 124)
        self.assertTrue(case._processes[0].cleanup_completed)
        self.assertTrue((case.workspace.root / "funder-input-0000.json").exists())

    def test_build_json_exponent_overflow_is_rejected_at_every_depth(self):
        for response in ('{"schema_version":1,"number":1e400}',
                         '{"schema_version":1,"nested":{"numbers":[-1e400]}}'):
            artifact = self.artifact(response=response)
            case = self.fixture.case()
            with self.subTest(response=response), self.assertRaisesRegex(
                    EXECUTION.FunderExecutionError, "overflows its finite range"):
                self.execute(artifact, "build", {"schema_version":1}, case)
            self.assertTrue(case._processes[0].cleanup_completed)
        artifact = self.artifact(response='{"schema_version":1,"number":1e-3}')
        value = self.execute(artifact, "build", {"schema_version":1})
        self.assertEqual(value["number"], 0.001)

    def test_oversized_signer_output_stops_before_timeout_or_unbounded_log(self):
        artifact = self.artifact(extra="sys.stdout.write('x'*(2*1024*1024+4096)); sys.stdout.flush(); time.sleep(30)")
        case = self.fixture.case()
        with self.assertRaises(EXECUTION.runtime.OutputLimitExceeded):
            self.execute(artifact, "build", {"schema_version":1}, case)
        self.assertTrue(case._processes[0].cleanup_completed)
        self.assertLessEqual(case._processes[0].log_path.stat().st_size, 2*1024*1024)
        self.assertTrue((case.workspace.root / "funder-input-0000.json").exists())
        case.close()

    def test_replaced_or_changed_publication_prevents_next_consumer_launch(self):
        artifact = self.artifact()
        case = self.fixture.case()
        artifact.binary.chmod(0o700)
        artifact.binary.write_text("changed")
        with self.assertRaises(fixtures.BUILD.FunderBuildError):
            self.execute(artifact, case=case)
        self.assertEqual(case.launched_process_count, 0)

    def test_existing_input_symlink_never_overwrites_its_target_or_launches(self):
        artifact = self.artifact()
        case = self.fixture.case()
        target = self.fixture.root / "outside-input"
        target.write_text("preserve")
        (case.workspace.root / "funder-input-0000.json").symlink_to(target)
        with self.assertRaises(FileExistsError):
            self.execute(artifact, "build", {"schema_version":1}, case)
        self.assertEqual(target.read_text(), "preserve")
        self.assertEqual(case.launched_process_count, 0)

    def test_signer_input_replacement_cannot_become_valid_output(self):
        artifact = self.artifact(extra=(
            "from pathlib import Path\n"
            "p=Path('funder-input-0000.json'); p.rename('original-input.json'); "
            "p.write_text('{\"schema_version\":1}'); p.chmod(0o400)"))
        case = self.fixture.case()
        with self.assertRaisesRegex(EXECUTION.FunderExecutionError, "input attachment changed"):
            self.execute(artifact, "build", {"schema_version":1}, case)
        self.assertTrue(case._processes[0].cleanup_completed)

    def test_replaced_input_after_timeout_or_output_limit_keeps_primary_error(self):
        replace = ("from pathlib import Path\n"
            "p=Path('funder-input-0000.json'); p.rename('original-input.json'); "
            "p.write_text('{\"replaced\":true}'); p.chmod(0o400)\n")
        for extra, expected, code in (
            ("time.sleep(30)", EXECUTION.runtime.RunnerError, 124),
            ("sys.stdout.write('x'*(2*1024*1024+4096)); sys.stdout.flush(); time.sleep(30)",
             EXECUTION.runtime.OutputLimitExceeded, 1),
        ):
            artifact = self.artifact(extra=replace + extra)
            case = self.fixture.case()
            with self.subTest(error=expected.__name__), self.assertRaises(expected) as caught:
                EXECUTION.run_offline_funder(case, artifact, "build", {"schema_version":1}, timeout=0.5)
            self.assertEqual(caught.exception.exit_code, code)
            self.assertIn("input attachment changed", str(caught.exception.__cause__))
            self.assertEqual(json.loads((case.workspace.root / "original-input.json").read_text()),
                             {"schema_version":1})
            self.assertTrue(case._processes[0].cleanup_completed)
            artifact.verify_unchanged()

    def test_every_attachment_checked_on_cancel_interrupt_or_capture_error(self):
        for primary in (EXECUTION.runtime.Cancelled(), KeyboardInterrupt(),
                        EXECUTION.runtime.RunnerError("modeled capture failure", 17)):
            artifact = self.artifact()
            original_bytes = artifact.binary.read_bytes()
            case = self.fixture.case()
            workspace_type = type(case.workspace)
            original_workspace_check = workspace_type.verify_owned
            execution_failed = False

            def verify_workspace(workspace):
                if workspace is case.workspace and execution_failed:
                    raise EXECUTION.FunderExecutionError("changed consumer workspace")
                return original_workspace_check(workspace)

            def fail_execution(*args, **kwargs):
                nonlocal execution_failed
                artifact.binary.chmod(0o700)
                artifact.binary.write_text("changed publication")
                saved = case.workspace.root / "funder-input-0000.json"
                saved.rename(case.workspace.root / "original-input.json")
                saved.write_text("changed input")
                execution_failed = True
                raise primary

            with patch.object(case, "run_command", side_effect=fail_execution), patch.object(
                    workspace_type, "verify_owned", verify_workspace):
                with self.subTest(error=type(primary).__name__), self.assertRaises(type(primary)) as caught:
                    self.execute(artifact, "build", {"schema_version":1}, case)
            self.assertIs(caught.exception, primary)
            self.assertEqual(getattr(caught.exception, "exit_code", None), getattr(primary, "exit_code", None))
            failures = str(caught.exception.__cause__.__cause__)
            for text in ("changed consumer workspace", "original funder executable changed", "input attachment changed"):
                self.assertIn(text, failures)
            self.assertEqual(json.loads((case.workspace.root / "original-input.json").read_text()),
                             {"schema_version":1})
            artifact.binary.write_bytes(original_bytes)
            artifact.binary.chmod(0o500)
            with self.assertRaisesRegex(fixtures.BUILD.FunderBuildError, "already failed verification"):
                artifact.verify_unchanged()


if __name__ == "__main__":
    unittest.main()
