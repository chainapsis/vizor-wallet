"""Host-only checks for catalog previews; no E2E backends are needed."""

from __future__ import annotations

import builtins
import contextlib
from dataclasses import replace
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
SPEC = importlib.util.spec_from_file_location("vizor_e2e_preview", SCRIPT_DIR / "run-suite.py")
assert SPEC is not None and SPEC.loader is not None
CLI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLI)


class PreviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = CLI.e2e_catalog.load_catalog()

    def invoke(self, *arguments: str):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = CLI.main(arguments)
        return code, json.loads(output.getvalue()) if output.getvalue() else None, errors.getvalue()

    def test_list_inventory_marks_only_the_wired_scenarios_runnable(self) -> None:
        code, output, errors = self.invoke("--list")
        self.assertEqual((code, errors), (0, ""))
        self.assertEqual(len(output["scenarios"]), 64)
        self.assertEqual(output["catalog_sha256"], self.catalog.fingerprint)
        wired_ids = {"flutter.macos.import-sync", "flutter.macos.fallback-endpoint",
            "flutter.macos.custom-endpoint-no-fallback", "flutter.macos.slow-height-fallback",
            "flutter.macos.sync-startup-stall-recovery",
            "flutter.macos.shield-transparent", "flutter.macos.shield-transparent-retry",
            "flutter.macos.multi-account-send", "flutter.macos.tex-send",
            "flutter.macos.payment-uri-send", "flutter.macos.payment-uri-locked-send",
            "flutter.macos.payment-request-round-trip",
            "flutter.macos.mempool-receive-history", "flutter.macos.mempool-during-sync",
            "flutter.macos.mempool-expiry", "flutter.macos.payment-link-round-trip",
            "flutter.macos.payment-link-restart", "flutter.macos.payment-link-recovery",
            "flutter.macos.voting", "flutter.macos.voting-slow-helper",
            "rust.receive.sync", "rust.send.basic",
            "rust.send.second-account", "rust.import.bip39-passphrase", "rust.import.historical-birthday",
            "rust.import.future-birthday", "rust.import.receive-after-sync", "rust.import.deterministic-reimport",
            "rust.multi-account.orphaned-range", "rust.multi-account.deleted-range",
            "rust.multi-account.late-add-history-future", "rust.multi-account.tip-birthday-history",
            "rust.multi-account.two-before-sync", "rust.multi-account.preserve-history",
            "rust.multi-account.isolated-balances", "rust.multi-account.idempotent-sync",
            "rust.receive.direct-zakura", "rust.import.direct-zakura", "rust.gift-card.tracking-multiple",
            "rust.gift-card.empty-db-reuse", "rust.gift-card.competition",
            "rust.ironwood.migration", "rust.ironwood.gift-card-claim",
            "flutter.ios.create-sync",
            "flutter.ios.import-sync",
            "flutter.ios.account-management",
            "flutter.ios.multi-account-send",
            "flutter.ios.mempool-receive",
            "flutter.ios.fallback-endpoint",
            "flutter.ios.slow-height-fallback",
            "flutter.ios.ironwood-pre-migration-send",
            "flutter.ios.ironwood-migration",
            "flutter.ios.ironwood-migration-many-notes",
            "flutter.ios.ironwood-migration-multi-account",
            "flutter.ios.ironwood-migration-reorg",
            "flutter.ios.ironwood-migration-restart",
            "flutter.ios.ironwood-migration-network-recovery",
            "flutter.ios.ironwood-background-migration",
            "flutter.ios.ironwood-background-restart",
            "flutter.ios.payment-link-round-trip",
            "flutter.ios.payment-uri-send",
            "flutter.ios.gift-onboarding",
            "flutter.ios.ironwood-migration-account-reimport",
            "flutter.ios.ironwood-migration-500-notes"}
        for record in output["scenarios"]:
            wired = record["scenario_id"] in wired_ids
            self.assertEqual(record["supported"], wired)
            self.assertEqual(record["runnable"], wired)
            self.assertEqual(bool(record["pending_reason"]), not wired)

    def test_exact_selection_deduplicates_in_catalog_order(self) -> None:
        first, second = self.catalog.scenarios[:2]
        code, output, _ = self.invoke(
            "--scenario", second.id, "--scenario", first.id,
            "--scenario", second.id, "--plan",
        )
        self.assertEqual(code, 0)
        self.assertEqual(
            [item["scenario_id"] for item in output["selected_scenarios"]],
            [first.id, second.id],
        )
        self.assertTrue(output["runnable"])
        self.assertEqual(output["execution_mode"], "ready")
        self.assertEqual(output["pending_blockers"], [])

    def test_repeated_tags_are_an_intersection(self) -> None:
        code, output, _ = self.invoke("--suite", "all", "--tag", "ios", "--tag", "ironwood", "--list")
        expected = [
            scenario.id for scenario in self.catalog.scenarios
            if {"ios", "ironwood"}.issubset(scenario.tags)
        ]
        self.assertTrue(expected)
        self.assertEqual(code, 0)
        self.assertEqual([item["scenario_id"] for item in output["scenarios"]], expected)

    def test_failed_from_selects_failures_and_timeouts_not_cancelled(self) -> None:
        scenarios = self.catalog.scenarios[:4]
        statuses = ("passed", "failed", "timed_out", "cancelled")
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "run.json"
            report.write_text(json.dumps({
                "schema_version": 2,
                "results": [
                    {"scenario_id": scenario.id, "target": scenario.target,
                     "test": scenario.test, "status": status}
                    for scenario, status in zip(scenarios, statuses)
                ],
            }))
            original = report.read_bytes()
            code, output, _ = self.invoke("--failed-from", str(report), "--plan")
            self.assertEqual(report.read_bytes(), original)
        self.assertEqual(code, 0)
        self.assertEqual(
            [item["scenario_id"] for item in output["selected_scenarios"]],
            [scenarios[1].id, scenarios[2].id],
        )

    def test_unknown_changed_path_widens_to_all_ready_cases(self) -> None:
        code, output, _ = self.invoke("--changed-file", "unknown/runtime.file", "--plan")
        self.assertEqual(code, 0)
        self.assertEqual(len(output["selected_scenarios"]), 64)
        self.assertEqual(output["execution_mode"], "ready")
        self.assertTrue(output["runnable"])
        self.assertEqual(output["selection"]["impact"]["fallback_files"], ["unknown/runtime.file"])
        self.assertEqual(output["selection"]["impact"]["coverage_gaps"], [])

    def test_shared_test_helper_selects_its_e2e_consumer(self) -> None:
        code, output, errors = self.invoke(
            "--changed-file", "test/support/legacy_payment_link.dart", "--plan"
        )
        self.assertEqual((code, errors), (0, ""))
        self.assertEqual(output["execution_mode"], "ready")
        self.assertIn(
            "flutter.macos.payment-link-round-trip",
            [item["scenario_id"] for item in output["selected_scenarios"]],
        )
        self.assertEqual([], output["selection"]["impact"]["ignored_files"])

    def test_duplicate_report_status_cannot_hide_a_failed_scenario(self) -> None:
        first, second = self.catalog.scenarios[:2]
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "run.json"
            report.write_text(
                '{"schema_version":2,"results":['
                + json.dumps({"scenario_id": first.id, "target": first.target, "test": first.test})[:-1]
                + ',"status":"failed","status":"passed"},'
                + json.dumps({"scenario_id": second.id, "target": second.target,
                              "test": second.test, "status": "failed"})
                + ']}'
            )
            code, output, error = self.invoke("--failed-from", str(report), "--plan")
        self.assertEqual(code, 2)
        self.assertIsNone(output)
        self.assertIn("duplicate JSON key", error)

    def test_documentation_only_is_a_true_empty_selection(self) -> None:
        code, output, _ = self.invoke("--changed-file", "docs/example.md", "--plan")
        self.assertEqual(code, 0)
        self.assertEqual(output["selected_scenarios"], [])
        self.assertEqual(output["execution_mode"], "no-tests")
        self.assertEqual(output["pending_blockers"], [])
        self.assertEqual(output["selection"]["impact"]["coverage_gaps"], [])

    def test_deleted_script_uses_lexical_mapping_without_existence_checks(self) -> None:
        scenario = next(item for item in self.catalog.scenarios if item.script)
        with patch.object(Path, "exists", side_effect=AssertionError("must not inspect deleted path")):
            code, output, _ = self.invoke("--changed-file", scenario.script, "--plan")
        self.assertEqual(code, 0)
        self.assertIn(scenario.id, [item["scenario_id"] for item in output["selected_scenarios"]])

    def test_changed_from_collects_once_from_the_checkout_root(self) -> None:
        changes = CLI.e2e_changes.ChangedFiles(
            paths=("unknown/runtime.file",),
            git={"base_ref": "main", "base_commit": "a" * 40,
                 "merge_bases": ["a" * 40], "head_commit": "b" * 40,
                 "include_worktree": True},
        )
        with patch.object(CLI.e2e_changes, "collect_changed_files", return_value=changes) as collect:
            code, output, _ = self.invoke("--changed-from", "main", "--plan")
        collect.assert_called_once_with(CLI.REPO_ROOT, "main")
        self.assertEqual(code, 0)
        self.assertEqual(output["selection"]["impact"]["git"], changes.git)
        self.assertEqual(len(output["selected_scenarios"]), 64)

    def test_empty_git_changes_are_no_tests(self) -> None:
        changes = CLI.e2e_changes.ChangedFiles(
            paths=(),
            git={"base_ref": "HEAD", "base_commit": "a" * 40,
                 "merge_bases": ["a" * 40], "head_commit": "a" * 40,
                 "include_worktree": True},
        )
        with patch.object(CLI.e2e_changes, "collect_changed_files", return_value=changes):
            code, output, _ = self.invoke("--changed-from", "HEAD", "--plan")
        self.assertEqual(code, 0)
        self.assertEqual(output["execution_mode"], "no-tests")

    def test_invalid_selection_returns_error_without_output(self) -> None:
        for arguments in (
            ("--plan",), ("--suite", "unknown", "--plan"),
            ("--scenario", "unknown", "--list"), ("--list", "--tag", ""),
            ("--list", "--tag", "ios", "--tag", "ios"),
            ("--list", "--tag", " ios"), ("--changed-file", "../outside", "--plan"),
        ):
            with self.subTest(arguments=arguments):
                code, output, error = self.invoke(*arguments)
                self.assertEqual(code, 2)
                self.assertIsNone(output)
                self.assertTrue(error.startswith("error:"))

    def test_conflicting_selectors_and_display_flags_are_rejected(self) -> None:
        for arguments in (
            ("--suite", "all", "--scenario", self.catalog.scenarios[0].id, "--plan"),
            ("--list", "--plan"), ("--changed-file", "a", "--changed-from", "HEAD", "--plan"),
        ):
            with self.subTest(arguments=arguments), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    CLI.parse_args(arguments)
                self.assertEqual(error.exception.code, 2)

    def test_execution_is_rejected_before_catalog_or_git_access(self) -> None:
        with patch.object(CLI.e2e_catalog, "load_catalog", side_effect=AssertionError("catalog access")), \
             patch.object(CLI.e2e_changes, "collect_changed_files", side_effect=AssertionError("Git access")):
            code, output, error = self.invoke("--changed-from", "HEAD")
        self.assertEqual(code, 2)
        self.assertIsNone(output)
        self.assertIn("execution requires --run", error)

    def test_supported_case_is_ready_without_importing_its_backend(self) -> None:
        code, output, errors = self.invoke("--scenario", "flutter.macos.import-sync", "--plan")
        self.assertEqual((code, errors), (0, ""))
        self.assertTrue(output["runnable"])
        self.assertEqual(output["execution_mode"], "ready")
        self.assertEqual(output["pending_blockers"], [])

    def test_pending_run_is_refused_before_any_backend_import(self) -> None:
        selected = self.catalog.scenarios_by_id["flutter.ios.import-sync"]
        pending = replace(selected, supported=False, pending_reason="synthetic unwired case")
        catalog = replace(self.catalog, scenarios=tuple(
            pending if item.id == selected.id else item for item in self.catalog.scenarios))
        with patch.object(CLI.e2e_catalog, "load_catalog", return_value=catalog), \
             patch.dict(sys.modules, {"native_macos_suite":None}):
            code, output, error = self.invoke("--scenario", selected.id, "--run")
        self.assertEqual(code, 2)
        self.assertIsNone(output)
        self.assertIn("selected execution is pending", error)

    def test_ios_suite_is_ready_and_reaches_the_existing_executor(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        arguments = ("--suite", "flutter-ios-full", "--ios-runtime", "modeled-runtime",
                     "--ios-device-type", "modeled-device")
        with patch.dict(sys.modules, {"native_macos_suite":None}):
            code, preview, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(preview["runnable"])
        self.assertEqual(len(preview["selected_scenarios"]), 21)
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite":SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        args, catalog, scenarios, selection = execute.call_args.args
        self.assertEqual(len(scenarios), 21)
        self.assertTrue(all(item.engine == "flutter-ios" for item in scenarios))
        self.assertEqual(args.ios_runtime, "modeled-runtime")
        self.assertEqual(args.ios_device_type, "modeled-device")
        self.assertEqual(selection["values"], ["flutter-ios-full"])

    def test_explicit_run_passes_the_existing_selection_to_the_executor(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite":SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke("--scenario", "flutter.macos.import-sync", "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        args, catalog, scenarios, selection = execute.call_args.args
        self.assertTrue(args.run)
        self.assertEqual([s.id for s in scenarios], ["flutter.macos.import-sync"])
        self.assertEqual(selection["values"], ["flutter.macos.import-sync"])

    def test_endpoint_selection_is_ready_and_reaches_the_existing_executor(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        ids = ("flutter.macos.fallback-endpoint", "flutter.macos.custom-endpoint-no-fallback",
            "flutter.macos.slow-height-fallback", "flutter.macos.sync-startup-stall-recovery")
        arguments = tuple(value for name in ids for value in ("--scenario", name))
        with patch.dict(sys.modules, {"native_macos_suite": None}):
            code, plan, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(plan["runnable"])
        self.assertEqual(plan["pending_blockers"], [])
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite": SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        self.assertEqual({s.id for s in execute.call_args.args[2]}, set(ids))

    def test_mempool_and_gift_selection_is_ready_and_reaches_the_exact_executor(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        ids = ("flutter.macos.mempool-receive-history", "flutter.macos.mempool-during-sync",
            "flutter.macos.mempool-expiry", "flutter.macos.payment-link-round-trip",
            "flutter.macos.payment-link-restart", "flutter.macos.payment-link-recovery")
        arguments = tuple(value for name in ids for value in ("--scenario", name))
        with patch.dict(sys.modules, {"native_macos_suite": None}):
            code, plan, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(plan["runnable"])
        self.assertEqual(plan["pending_blockers"], [])
        self.assertEqual([s["scenario_id"] for s in plan["selected_scenarios"]], list(ids))
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite": SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        self.assertEqual([s.id for s in execute.call_args.args[2]], list(ids))

    def test_multi_account_changed_file_selection_is_ready_and_reaches_executor(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        expected = {s.id for s in self.catalog.scenarios if s.target == "regtest_multi_account"}
        self.assertEqual(len(expected), 8)
        arguments = ("--changed-file", "rust/tests/regtest_multi_account.rs")
        with patch.dict(sys.modules, {"native_macos_suite": None}):
            code, plan, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(plan["runnable"])
        self.assertEqual(plan["required_targets"], ["regtest_multi_account"])
        self.assertEqual(plan["pending_blockers"], [])
        self.assertEqual({s["scenario_id"] for s in plan["selected_scenarios"]}, expected)
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite": SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        self.assertEqual({s.id for s in execute.call_args.args[2]}, expected)

    def test_voting_preview_needs_no_tools_and_run_passes_both_source_caches(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        ids = ("flutter.macos.voting", "flutter.macos.voting-slow-helper")
        arguments = tuple(value for name in ids for value in ("--scenario", name))
        with patch.dict(sys.modules, {"native_macos_suite": None}):
            code, plan, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(plan["runnable"])
        self.assertEqual(plan["pending_blockers"], [])
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite": SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run",
                "--voting-sdk-cache", "/model/sdk.git", "--voting-pir-cache", "/model/pir.git")
        self.assertEqual((code, output, error), (0, None, ""))
        self.assertEqual([s.id for s in execute.call_args.args[2]], list(ids))
        self.assertEqual(execute.call_args.args[0].voting_sdk_cache, Path("/model/sdk.git"))
        self.assertEqual(execute.call_args.args[0].voting_pir_cache, Path("/model/pir.git"))

    def test_gift_and_direct_cases_are_ready_and_reach_the_exact_executor(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        ids = {"rust.receive.direct-zakura", "rust.import.direct-zakura",
            "rust.gift-card.tracking-multiple", "rust.gift-card.empty-db-reuse", "rust.gift-card.competition"}
        arguments = tuple(value for name in sorted(ids) for value in ("--scenario", name))
        with patch.dict(sys.modules, {"native_macos_suite": None}):
            code, plan, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(plan["runnable"])
        self.assertEqual(plan["pending_blockers"], [])
        self.assertEqual({s["scenario_id"] for s in plan["selected_scenarios"]}, ids)
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite": SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        self.assertEqual({s.id for s in execute.call_args.args[2]}, ids)

    def test_ironwood_selection_is_ready_with_its_exact_controlled_profile(self) -> None:
        from types import SimpleNamespace
        from unittest.mock import Mock
        ids = {"rust.ironwood.migration", "rust.ironwood.gift-card-claim"}
        arguments = tuple(value for name in sorted(ids) for value in ("--scenario", name))
        with patch.dict(sys.modules, {"native_macos_suite": None}):
            code, plan, error = self.invoke(*arguments, "--plan")
        self.assertEqual((code, error), (0, ""))
        self.assertTrue(plan["runnable"])
        self.assertEqual(plan["pending_blockers"], [])
        self.assertEqual({s["scenario_id"] for s in plan["selected_scenarios"]}, ids)
        self.assertEqual({s["profile"] for s in plan["selected_scenarios"]}, {"zakura-direct-activation500"})
        execute = Mock(return_value=0)
        with patch.dict(sys.modules, {"native_macos_suite": SimpleNamespace(run_native_suite=execute)}):
            code, output, error = self.invoke(*arguments, "--run")
        self.assertEqual((code, output, error), (0, None, ""))
        self.assertEqual({s.id for s in execute.call_args.args[2]}, ids)

    def test_previews_never_load_backends_start_processes_or_write_artifacts(self) -> None:
        original_import = builtins.__import__

        def guarded_import(name, *args, **kwargs):
            if name.startswith(("native_", "e2e_schedule", "e2e_runtime", "direct_zakura", "ths_fixture")):
                raise AssertionError(f"preview imported backend: {name}")
            return original_import(name, *args, **kwargs)

        with patch("builtins.__import__", side_effect=guarded_import), \
             patch("subprocess.run", side_effect=AssertionError("spawned a process")), \
             patch.object(Path, "mkdir", side_effect=AssertionError("created artifacts")), \
             patch.object(Path, "write_text", side_effect=AssertionError("wrote a file")), \
             patch.object(Path, "write_bytes", side_effect=AssertionError("wrote a file")):
            for arguments in (
                ("--list",), ("--suite", "all", "--plan"),
                ("--changed-file", "unknown/runtime.file", "--plan"),
            ):
                with self.subTest(arguments=arguments):
                    code, _, errors = self.invoke(*arguments)
                    self.assertEqual((code, errors), (0, ""))

    def test_fresh_cli_invocations_do_not_create_checkout_artifacts(self) -> None:
        files = ("run-suite.py", "catalog.json", "e2e_catalog.py", "e2e_changes.py", "e2e_impact.py")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename in files:
                shutil.copyfile(SCRIPT_DIR / filename, root / filename)
            before = {item.name: item.read_bytes() for item in root.iterdir()}
            for arguments in (("--list",), ("--suite", "all", "--plan")):
                result = subprocess.run(
                    [sys.executable, str(root / "run-suite.py"), *arguments],
                    cwd=root, capture_output=True, text=True, check=False, timeout=15,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(json.loads(result.stdout))
            self.assertEqual({item.name: item.read_bytes() for item in root.iterdir()}, before)


if __name__ == "__main__":
    unittest.main()
