#!/usr/bin/env python3

from __future__ import annotations

import builtins
import copy
import dataclasses
from pathlib import Path
import sys
import unittest
from unittest import mock


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from e2e_catalog import CatalogError, load_catalog
from e2e_impact import (
    make_changed_provenance,
    normalize_changed_paths,
    select_changed_scenarios,
    validate_changed_provenance,
)


class E2eImpactTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = load_catalog()

    @staticmethod
    def ids(impact) -> tuple[str, ...]:
        return tuple(scenario.id for scenario in impact.scenarios)

    def pending_ids(self, scenarios) -> tuple[str, ...]:
        profiles = self.catalog.profiles_by_id
        return tuple(
            scenario.id
            for scenario in scenarios
            if not scenario.supported or not profiles[scenario.profile].supported
        )

    def assert_gaps_match_pending(self, impact) -> None:
        self.assertEqual(
            self.pending_ids(impact.scenarios),
            tuple(item["scenario_id"] for item in impact.details["coverage_gaps"]),
        )

    def test_normalizes_lexically_preserving_unusual_filenames(self) -> None:
        self.assertEqual(
            ("lib/app.dart", "assets/name with space\nand newline.png"),
            normalize_changed_paths(
                ["./lib//app.dart", "lib/app.dart", "assets/name with space\nand newline.png"]
            ),
        )
        for unsafe in ("", "/tmp/file", "../file", "a/../file", "a\\b", "a\x00b", "."):
            with self.subTest(path=unsafe), self.assertRaises(CatalogError):
                normalize_changed_paths([unsafe])
        with self.assertRaises(CatalogError):
            normalize_changed_paths("lib/app.dart")

    def test_exact_script_and_integration_phase_select_pending_inventory(self) -> None:
        for path, expected in (
            (
                "scripts/e2e/flutter-macos-regtest-import-sync.sh",
                ("flutter.macos.import-sync",),
            ),
            (
                "integration_test/regtest_mempool_receive_history_test.dart",
                (
                    "flutter.macos.mempool-receive-history",
                    "flutter.macos.mempool-during-sync",
                    "flutter.macos.mempool-expiry",
                ),
            ),
        ):
            with self.subTest(path=path):
                impact = select_changed_scenarios(self.catalog, [path])
                self.assertEqual(expected, self.ids(impact))
                self.assert_gaps_match_pending(impact)
                self.assertEqual([], impact.details["fallback_files"])

    def test_shared_base_scripts_include_dependent_scenarios(self) -> None:
        impact = select_changed_scenarios(
            self.catalog, ["scripts/e2e/flutter-macos-regtest-payment-link.sh"]
        )
        self.assertEqual(
            (
                "flutter.macos.payment-link-restart",
                "flutter.macos.payment-link-recovery",
            ),
            self.ids(impact),
        )
        self.assert_gaps_match_pending(impact)

    def test_rust_target_selects_every_catalog_binding_for_that_target(self) -> None:
        target = "regtest_multi_account"
        expected = tuple(
            scenario.id
            for scenario in self.catalog.scenarios
            if scenario.engine == "rust" and scenario.target == target
        )
        impact = select_changed_scenarios(
            self.catalog, [f"rust/tests/{target}.rs"]
        )
        self.assertTrue(expected)
        self.assertEqual(expected, self.ids(impact))
        self.assert_gaps_match_pending(impact)

    def test_evidence_backed_helpers_keep_catalog_scopes(self) -> None:
        for path, expected, rule in (
            (
                "integration_test/support/desktop_regtest_flow.dart",
                tuple(s.id for s in self.catalog.scenarios if s.engine == "flutter-macos"),
                "desktop-regtest-flow",
            ),
            (
                "integration_test/support/mobile_regtest_flow.dart",
                tuple(s.id for s in self.catalog.scenarios if s.engine == "flutter-ios"),
                "mobile-regtest-flow",
            ),
            (
                "integration_test/support/payment_link_regtest_flow.dart",
                (
                    "flutter.macos.payment-link-round-trip",
                    "flutter.macos.payment-link-restart",
                    "flutter.macos.payment-link-recovery",
                ),
                "payment-link-regtest-flow",
            ),
        ):
            with self.subTest(path=path):
                impact = select_changed_scenarios(self.catalog, [path])
                self.assertEqual(expected, self.ids(impact))
                self.assertTrue(
                    all(item["rules"] == [rule] for item in impact.details["reasons"])
                )
                self.assert_gaps_match_pending(impact)

    def test_desktop_activity_flow_conservatively_selects_every_macos_case(self) -> None:
        impact = select_changed_scenarios(
            self.catalog, ["integration_test/support/desktop_activity_flow.dart"]
        )
        self.assertEqual(
            tuple(
                scenario.id
                for scenario in self.catalog.scenarios
                if scenario.engine == "flutter-macos"
            ),
            self.ids(impact),
        )
        self.assertTrue(
            all(
                item["rules"] == ["desktop-activity-flow"]
                for item in impact.details["reasons"]
            )
        )
        self.assert_gaps_match_pending(impact)

    def test_unproven_native_helpers_fall_back_to_the_entire_catalog(self) -> None:
        all_ids = tuple(scenario.id for scenario in self.catalog.scenarios)
        for path, rule, fallback in (
            (
                "integration_test/support/secure_storage_error_diagnostics.dart",
                "fallback",
                True,
            ),
            ("integration_test/support/native_clipboard.dart", "fallback", True),
            ("scripts/e2e/native_host_resources.py", "shared-runtime", False),
        ):
            with self.subTest(path=path):
                impact = select_changed_scenarios(self.catalog, [path])
                self.assertEqual(all_ids, self.ids(impact))
                self.assertEqual(
                    [path] if fallback else [], impact.details["fallback_files"]
                )
                self.assertTrue(
                    all(
                        item["rules"] == [rule]
                        for item in impact.details["reasons"]
                    )
                )
                self.assert_gaps_match_pending(impact)

    def test_direct_fixture_helpers_select_direct_profiles_without_backends(self) -> None:
        path = "scripts/e2e/direct_zakura.py"
        expected = tuple(
            scenario.id
            for scenario in self.catalog.scenarios
            if scenario.profile
            in {
                "zakura-direct-height1",
                "zakura-direct-activation500",
                "flutter-direct-height1",
                "flutter-direct-activation500",
            }
        )
        impact = select_changed_scenarios(self.catalog, [path])
        self.assertEqual(expected, self.ids(impact))
        self.assert_gaps_match_pending(impact)
        self.assertEqual([], impact.details["fallback_files"])

    def test_backend_topology_files_widen_without_importing_runtime_modules(self) -> None:
        original_import = builtins.__import__

        def guarded_import(name: str, *args: object, **kwargs: object):
            if name == "native_scenarios":
                raise AssertionError("impact selection imported a runtime module")
            return original_import(name, *args, **kwargs)

        with mock.patch("builtins.__import__", side_effect=guarded_import):
            impact = select_changed_scenarios(
                self.catalog, ["scripts/e2e/native_phase.py"]
            )
        self.assertEqual(
            tuple(scenario.id for scenario in self.catalog.scenarios),
            self.ids(impact),
        )
        self.assert_gaps_match_pending(impact)

    def test_production_send_changes_widen_to_all_flutter_scenarios(self) -> None:
        impact = select_changed_scenarios(
            self.catalog, ["lib/src/features/send/services/send_flow.dart"]
        )
        self.assertEqual(
            tuple(
                scenario.id
                for scenario in self.catalog.scenarios
                if scenario.engine.startswith("flutter-")
            ),
            self.ids(impact),
        )
        self.assertTrue(
            all(item["rules"] == ["flutter-production"] for item in impact.details["reasons"])
        )
        self.assert_gaps_match_pending(impact)

    def test_shared_test_helpers_widen_to_flutter_instead_of_being_ignored(self) -> None:
        expected = tuple(
            scenario.id
            for scenario in self.catalog.scenarios
            if scenario.engine.startswith("flutter-")
        )
        for path in (
            "test/support/legacy_payment_link.dart",
            "test/support/new_helper.dart",
            "test/e2e/new_helper.dart",
            "test/support",
        ):
            with self.subTest(path=path):
                impact = select_changed_scenarios(self.catalog, [path])
                self.assertEqual(expected, self.ids(impact))
                self.assertEqual([], impact.details["ignored_files"])
                self.assert_gaps_match_pending(impact)

    def test_docs_and_unit_only_changes_allow_zero_selection(self) -> None:
        impact = select_changed_scenarios(
            self.catalog, ["README.md", "test/providers/example_test.dart"]
        )
        self.assertEqual((), impact.scenarios)
        self.assertEqual([], impact.details["coverage_gaps"])
        self.assertEqual(
            ["documentation", "unit-test-only"],
            [item["reason"] for item in impact.details["ignored_files"]],
        )

    def test_broad_and_unknown_paths_select_pending_inventory(self) -> None:
        cases = (
            (
                "lib/app.dart",
                tuple(
                    scenario.id
                    for scenario in self.catalog.scenarios
                    if scenario.engine.startswith("flutter-")
                ),
                [],
            ),
            (
                "lib/src/rust/api/sync.dart",
                tuple(scenario.id for scenario in self.catalog.scenarios),
                [],
            ),
            (
                "assets/runtime.bin",
                tuple(scenario.id for scenario in self.catalog.scenarios),
                ["assets/runtime.bin"],
            ),
        )
        for path, expected, fallback in cases:
            with self.subTest(path=path):
                impact = select_changed_scenarios(self.catalog, [path])
                self.assertEqual(expected, self.ids(impact))
                self.assertEqual(fallback, impact.details["fallback_files"])
                self.assertEqual(
                    "catalog-selection-with-pending-gaps",
                    impact.details["coverage_scope"],
                )
                self.assert_gaps_match_pending(impact)

    def test_new_pending_scenario_is_automatically_included_by_broad_scope(self) -> None:
        template = self.catalog.scenarios_by_id["flutter.macos.import-sync"]
        future = dataclasses.replace(
            template,
            id="flutter.macos.future-pending",
            script="scripts/e2e/flutter-macos-regtest-future-pending.sh",
            test="flutter-macos-regtest-future-pending",
            supported=False,
            pending_reason="synthetic pending contract",
        )
        catalog = dataclasses.replace(
            self.catalog, scenarios=(*self.catalog.scenarios, future)
        )
        impact = select_changed_scenarios(catalog, ["lib/app.dart"])
        self.assertEqual(future.id, impact.scenarios[-1].id)
        self.assertEqual(future.id, impact.details["coverage_gaps"][-1]["scenario_id"])

    def test_tags_are_and_filters_and_cannot_hide_all_candidates(self) -> None:
        selected = select_changed_scenarios(
            self.catalog, ["lib/app.dart"], tags=("endpoint", "fallback")
        )
        self.assertEqual(
            ("flutter.macos.fallback-endpoint", "flutter.ios.fallback-endpoint"),
            self.ids(selected),
        )
        self.assert_gaps_match_pending(selected)
        with self.assertRaisesRegex(CatalogError, "tag filters"):
            select_changed_scenarios(
                self.catalog,
                ["scripts/e2e/flutter-macos-regtest-import-sync.sh"],
                tags=("voting",),
            )
        for tags in (("",), ("endpoint", "endpoint")):
            with self.subTest(tags=tags), self.assertRaises(CatalogError):
                select_changed_scenarios(self.catalog, ["lib/app.dart"], tags=tags)

    def test_changed_file_provenance_round_trips_and_rejects_stale_data(self) -> None:
        impact = select_changed_scenarios(
            self.catalog, ["./lib/app.dart"], tags=("macos",)
        )
        provenance = make_changed_provenance(
            impact,
            kind="changed_file",
            values=["./lib/app.dart"],
            tags=["macos"],
        )
        validate_changed_provenance(provenance, self.catalog, impact.scenarios)

        stale = copy.deepcopy(provenance)
        stale["impact"]["fallback_files"].append("stale")
        with self.assertRaisesRegex(ValueError, "stale or malformed"):
            validate_changed_provenance(stale, self.catalog, impact.scenarios)

        extra = copy.deepcopy(provenance)
        extra["impact"]["extra"] = True
        with self.assertRaisesRegex(ValueError, "impact fields"):
            validate_changed_provenance(extra, self.catalog, impact.scenarios)

        for invalid_version in (True, 1.0):
            with self.subTest(mapping_version=invalid_version):
                malformed = copy.deepcopy(provenance)
                malformed["impact"]["mapping_version"] = invalid_version
                with self.assertRaisesRegex(ValueError, "mapping_version"):
                    validate_changed_provenance(
                        malformed, self.catalog, impact.scenarios
                    )

        with self.assertRaises(CatalogError):
            validate_changed_provenance(
                provenance, self.catalog, impact.scenarios[:-1]
            )

    def test_changed_from_provenance_requires_exact_git_evidence(self) -> None:
        impact = select_changed_scenarios(self.catalog, ["lib/app.dart"])
        git = {
            "base_ref": "origin/main",
            "base_commit": "a" * 40,
            "merge_bases": ["b" * 40],
            "head_commit": "c" * 40,
            "include_worktree": True,
        }
        provenance = make_changed_provenance(
            impact,
            kind="changed_from",
            values=["origin/main"],
            tags=[],
            git=git,
        )
        validate_changed_provenance(provenance, self.catalog, impact.scenarios)

        for mutate in (
            lambda item: item["impact"]["git"].__setitem__("base_ref", "other"),
            lambda item: item["impact"]["git"].__setitem__("head_commit", "short"),
            lambda item: item["impact"]["git"].__setitem__("merge_bases", []),
            lambda item: item["impact"]["git"].__setitem__("merge_bases", [{}]),
            lambda item: item["impact"]["git"].__setitem__("include_worktree", False),
            lambda item: item["impact"]["git"].__setitem__("extra", True),
        ):
            with self.subTest(mutate=mutate):
                malformed = copy.deepcopy(provenance)
                mutate(malformed)
                with self.assertRaises(ValueError):
                    validate_changed_provenance(
                        malformed, self.catalog, impact.scenarios
                    )


if __name__ == "__main__":
    unittest.main()
