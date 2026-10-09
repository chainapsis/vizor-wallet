import copy
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
import e2e_catalog as catalog_module


class E2eCatalogTest(unittest.TestCase):
    def setUp(self):
        self.catalog = catalog_module.load_catalog()

    def raw_catalog(self):
        return json.loads(Path(__file__).with_name("catalog.json").read_text())

    def write_catalog(self, value):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "catalog.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def result(self, scenario_id, status):
        scenario = self.catalog.scenarios_by_id[scenario_id]
        return {
            "scenario_id": scenario.id,
            "target": scenario.target,
            "test": scenario.test,
            "status": status,
        }

    def test_inventory_bindings_and_suites_preserve_pending_coverage(self):
        self.assertEqual(64, len(self.catalog.scenarios))
        self.assertEqual(
            {"rust": 23, "flutter-macos": 20, "flutter-ios": 21},
            {
                engine: sum(item.engine == engine for item in self.catalog.scenarios)
                for engine in ("rust", "flutter-macos", "flutter-ios")
            },
        )
        self.assertEqual(64, len(self.catalog.suites["all"]))
        self.assertEqual(
            set(self.catalog.suites["all"]),
            {item.id for item in self.catalog.scenarios},
        )
        self.assertEqual(64, len(self.catalog.fingerprint))
        self.assertEqual({item.id for item in self.catalog.profiles if item.supported},
                         {"flutter-direct-height1"})
        self.assertEqual({item.id for item in self.catalog.scenarios if item.supported},
                         {"flutter.macos.import-sync"})
        self.assertTrue(all(item.pending_reason for item in self.catalog.profiles if not item.supported))
        self.assertTrue(all(item.pending_reason for item in self.catalog.scenarios if not item.supported))
        self.assertEqual(
            {item.id for item in self.catalog.profiles},
            {item.profile for item in self.catalog.scenarios},
        )

    def test_exact_selection_deduplicates_in_catalog_order(self):
        selected = catalog_module.select_scenarios(
            self.catalog,
            scenario_ids=("rust.import.bip39-passphrase", "rust.send.basic",
                          "rust.import.bip39-passphrase"),
        )
        self.assertEqual(
            ("rust.send.basic", "rust.import.bip39-passphrase"),
            tuple(item.id for item in selected),
        )

    def test_suite_tags_require_every_requested_tag(self):
        selected = catalog_module.select_scenarios(
            self.catalog, suite="all", tags=("rust", "birthday")
        )
        self.assertTrue(selected)
        self.assertTrue(all({"rust", "birthday"} <= set(item.tags)
                            for item in selected))

    def test_selector_rejects_ambiguous_unknown_duplicate_tags_and_zero(self):
        with self.assertRaisesRegex(catalog_module.CatalogError, "exactly one"):
            catalog_module.select_scenarios(self.catalog)
        with self.assertRaisesRegex(catalog_module.CatalogError, "exactly one"):
            catalog_module.select_scenarios(
                self.catalog, suite="all", scenario_ids=("rust.send.basic",)
            )
        with self.assertRaisesRegex(catalog_module.CatalogError, "unknown scenarios"):
            catalog_module.select_scenarios(self.catalog, scenario_ids=("rust.unknown",))
        with self.assertRaisesRegex(catalog_module.CatalogError, "duplicates"):
            catalog_module.select_scenarios(
                self.catalog, suite="all", tags=("rust", "rust")
            )
        with self.assertRaisesRegex(catalog_module.CatalogError, "zero scenarios"):
            catalog_module.select_scenarios(
                self.catalog, suite="all", tags=("not-a-real-tag",)
            )

    def test_plan_is_catalog_ordered_pure_and_blocked(self):
        first = self.catalog.scenarios_by_id["rust.send.basic"]
        second = self.catalog.scenarios_by_id["flutter.ios.create-sync"]
        preview = catalog_module.plan(self.catalog, (second, first, second))
        self.assertEqual((first.id, second.id), tuple(item.id for item in preview.selected))
        self.assertFalse(preview.runnable)
        self.assertEqual(2, len(preview.blockers))
        self.assertEqual(
            tuple(dict.fromkeys(item.profile for item in preview.selected)),
            preview.required_profiles,
        )
        self.assertEqual(
            tuple(dict.fromkeys(item.target for item in preview.selected)),
            preview.required_targets,
        )

    def test_plan_rejects_zero_and_foreign_scenarios(self):
        with self.assertRaisesRegex(catalog_module.CatalogError, "zero"):
            catalog_module.plan(self.catalog, ())
        foreign = copy.copy(self.catalog.scenarios[0])
        object.__setattr__(foreign, "timeout_seconds", foreign.timeout_seconds + 1)
        with self.assertRaisesRegex(catalog_module.CatalogError, "not from this catalog"):
            catalog_module.plan(self.catalog, (foreign,))

    def test_failed_report_selects_failures_and_timeouts_in_catalog_order(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        report = Path(directory.name) / "run.json"
        report.write_text(json.dumps({"schema_version": 2, "results": [
            self.result("rust.import.bip39-passphrase", "timed_out"),
            self.result("rust.receive.sync", "passed"),
            self.result("rust.send.basic", "failed"),
            self.result("flutter.macos.import-sync", "cancelled"),
            self.result("flutter.ios.create-sync", "not_run"),
        ]}), encoding="utf-8")
        selected = catalog_module.select_scenarios(self.catalog, failed_from=report)
        self.assertEqual(
            ("rust.send.basic", "rust.import.bip39-passphrase"),
            tuple(item.id for item in selected),
        )

    def test_failed_report_rejects_noninteger_schema_and_identity_drift(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        report = Path(directory.name) / "run.json"
        for version in (True, 2.0):
            report.write_text(json.dumps({"schema_version": version, "results": []}),
                              encoding="utf-8")
            with self.subTest(version=version), self.assertRaisesRegex(
                catalog_module.CatalogError, "integer"
            ):
                catalog_module.select_scenarios(self.catalog, failed_from=report)
        result = self.result("rust.send.basic", "failed")
        result["test"] = "wrong-test"
        report.write_text(json.dumps({"schema_version": 2, "results": [result]}),
                          encoding="utf-8")
        with self.assertRaisesRegex(catalog_module.CatalogError, "identity"):
            catalog_module.select_scenarios(self.catalog, failed_from=report)

    def test_json_duplicate_keys_are_rejected_in_catalog_and_failed_report(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        duplicate_catalog = Path(directory.name) / "catalog.json"
        duplicate_catalog.write_text(
            '{"schema_version":1,"schema_version":2,"profiles":[],"scenarios":[],"suites":{}}',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(catalog_module.CatalogError, "duplicate JSON key"):
            catalog_module.load_catalog(duplicate_catalog)

        scenario = self.catalog.scenarios_by_id["rust.send.basic"]
        report = Path(directory.name) / "run.json"
        report.write_text(
            '{"schema_version":2,"results":['
            '{"scenario_id":' + json.dumps(scenario.id)
            + ',"target":' + json.dumps(scenario.target)
            + ',"test":' + json.dumps(scenario.test)
            + ',"status":"failed","status":"passed"},'
            + json.dumps(self.result("rust.import.bip39-passphrase", "failed"))
            + ']}',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(catalog_module.CatalogError, "duplicate JSON key"):
            catalog_module.select_scenarios(self.catalog, failed_from=report)

    def test_failed_report_rejects_duplicate_unknown_status_and_no_failures(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        report = Path(directory.name) / "run.json"
        failed = self.result("rust.send.basic", "failed")
        cases = (([failed, failed], "duplicate"),
                 ([{**failed, "status": "unknown"}], "status is unknown"),
                 ([self.result("rust.send.basic", "passed")], "zero scenarios"))
        for results, message in cases:
            report.write_text(json.dumps({"schema_version": 2, "results": results}),
                              encoding="utf-8")
            with self.subTest(message=message), self.assertRaisesRegex(
                catalog_module.CatalogError, message
            ):
                catalog_module.select_scenarios(self.catalog, failed_from=report)

    def test_catalog_rejects_unknown_fields_duplicate_mappings_and_suite_refs(self):
        raw = self.raw_catalog()
        raw["extra"] = True
        with self.assertRaisesRegex(catalog_module.CatalogError, "unknown fields"):
            catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["scenarios"][1]["target"] = raw["scenarios"][0]["target"]
        raw["scenarios"][1]["test"] = raw["scenarios"][0]["test"]
        with self.assertRaisesRegex(catalog_module.CatalogError, "duplicate .*test mapping"):
            catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["suites"]["all"].append("rust.unknown")
        with self.assertRaisesRegex(catalog_module.CatalogError, "unknown scenarios"):
            catalog_module.load_catalog(self.write_catalog(raw))

    def test_catalog_rejects_unreferenced_profiles_and_bad_pending_contract(self):
        raw = self.raw_catalog()
        raw["profiles"].append(
            {"id": "unused", "supported": False, "pending_reason": "unused"}
        )
        with self.assertRaisesRegex(catalog_module.CatalogError, "unreferenced"):
            catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["profiles"][0]["pending_reason"] = None
        with self.assertRaisesRegex(catalog_module.CatalogError, "requires pending_reason"):
            catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["scenarios"][0]["supported"] = True
        raw["scenarios"][0]["pending_reason"] = None
        with self.assertRaisesRegex(catalog_module.CatalogError, "unsupported"):
            catalog_module.load_catalog(self.write_catalog(raw))

    def test_catalog_rejects_timeout_outside_float_range(self):
        raw = self.raw_catalog()
        raw["scenarios"][0]["timeout_seconds"] = 10 ** 1000
        with self.assertRaisesRegex(catalog_module.CatalogError, "positive and finite"):
            catalog_module.load_catalog(self.write_catalog(raw))

    def test_catalog_rejects_bad_timeout_engine_script_and_tags(self):
        for timeout in (True, 0, -1, math.inf):
            raw = self.raw_catalog()
            raw["scenarios"][0]["timeout_seconds"] = timeout
            with self.subTest(timeout=timeout), self.assertRaisesRegex(
                catalog_module.CatalogError, "positive and finite|non-finite"
            ):
                catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["scenarios"][0]["engine"] = "browser"
        with self.assertRaisesRegex(catalog_module.CatalogError, "engine is unknown"):
            catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["scenarios"][0]["script"] = "scripts/e2e/not-rust.sh"
        with self.assertRaisesRegex(catalog_module.CatalogError, "null for Rust"):
            catalog_module.load_catalog(self.write_catalog(raw))
        raw = self.raw_catalog()
        raw["scenarios"][0]["tags"] = []
        with self.assertRaisesRegex(catalog_module.CatalogError, "must not be empty"):
            catalog_module.load_catalog(self.write_catalog(raw))


if __name__ == "__main__":
    unittest.main()
