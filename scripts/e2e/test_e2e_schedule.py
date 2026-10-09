"""Timing and dispatch models; no wallet, compiler or backend is launched."""
from dataclasses import replace
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import e2e_catalog
from e2e_schedule import schedule_scenarios


class ScheduleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="e2e-schedule-model-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.catalog = e2e_catalog.load_catalog()
        self.cases = tuple(self.catalog.scenarios_by_id[name] for name in (
            "rust.receive.sync", "flutter.macos.import-sync", "flutter.ios.import-sync"))

    def history(self, name="run.json", durations=(8, 2, 20), statuses=None):
        statuses = statuses or ("passed",) * len(self.cases)
        raw = {"schema_version":2, "catalog_sha256":self.catalog.fingerprint,
               "source_commit":"a" * 40, "results":[{
                   "scenario_id":case.id, "profile":case.profile, "target":case.target,
                   "test":case.test, "status":status, "duration_seconds":duration,
               } for case, duration, status in zip(self.cases, durations, statuses)]}
        path = self.root/name
        path.write_text(json.dumps(raw))
        return path

    def test_short_long_and_catalog_preserve_the_same_case_set(self):
        report = self.history()
        for order, indices in (("short-first", (1, 0, 2)), ("long-first", (2, 0, 1)),
                               ("catalog", (0, 1, 2))):
            with self.subTest(order=order):
                schedule = schedule_scenarios(self.catalog, self.cases, order=order, timing_reports=[report])
                self.assertEqual(schedule.indices, indices)
                self.assertEqual(set(schedule.record["dispatch_scenarios"]), {case.id for case in self.cases})
                self.assertEqual(schedule.record["estimated_seconds"][self.cases[0].id], 8)
                self.assertEqual(schedule.record["history_sources"][0]["source_commit"], "a" * 40)

    def test_without_timings_catalog_order_is_deterministic(self):
        self.assertEqual(schedule_scenarios(self.catalog, self.cases[::-1]).indices, (2, 1, 0))
        self.assertEqual(schedule_scenarios(self.catalog, ()).indices, ())

    def test_median_successful_durations_ignore_failed_or_unstarted_attempts(self):
        reports = [self.history("one.json"), self.history("two.json", (4, 50, 99)),
                   self.history("failed.json", (100, 0, 0), ("failed", "cancelled", "not_run"))]
        schedule = schedule_scenarios(self.catalog, self.cases, timing_reports=reports)
        self.assertEqual(schedule.record["estimated_seconds"], {
            self.cases[0].id:6, self.cases[1].id:26, self.cases[2].id:59.5})
        self.assertEqual(schedule.record["estimate_samples"], {case.id:2 for case in self.cases})

    def test_unknown_timings_follow_measured_cases_without_using_timeouts(self):
        report = self.history(statuses=("failed", "passed", "timed_out"))
        schedule = schedule_scenarios(self.catalog, self.cases, timing_reports=[report])
        self.assertEqual(schedule.indices, (1, 0, 2))
        self.assertEqual(schedule.record["estimated_seconds"], {self.cases[1].id:2})

    def test_reports_are_read_only_and_fingerprint_bytes_are_recorded(self):
        report = self.history()
        before = report.read_bytes()
        schedule = schedule_scenarios(self.catalog, self.cases, timing_reports=[report])
        self.assertEqual(report.read_bytes(), before)
        self.assertEqual(len(schedule.record["history_sources"][0]["sha256"]), 64)
        self.assertEqual(set(self.root.iterdir()), {report})

    def test_wrong_catalog_source_or_result_identity_is_rejected(self):
        for location, field, value in (("report", "catalog_sha256", "bad"),
            ("report", "source_commit", "bad"), ("report", "schema_version", True),
            ("result", "profile", "wrong"), ("result", "target", "wrong"),
            ("result", "test", "wrong"), ("result", "scenario_id", "unknown"),
            ("result", "status", "unknown")):
            with self.subTest(field=field):
                report = self.history()
                raw = json.loads(report.read_text())
                (raw if location == "report" else raw["results"][0])[field] = value
                report.write_text(json.dumps(raw))
                with self.assertRaises(e2e_catalog.CatalogError):
                    schedule_scenarios(self.catalog, self.cases, timing_reports=[report])

    def test_invalid_or_zero_success_duration_is_rejected(self):
        for duration in (True, -1, float("nan"), float("inf"), "1", 0):
            with self.subTest(duration=duration):
                report = self.history(durations=(duration, 2, 20))
                with self.assertRaises(e2e_catalog.CatalogError):
                    schedule_scenarios(self.catalog, self.cases, timing_reports=[report])

    def test_duplicate_history_and_duplicate_results_are_rejected(self):
        report = self.history()
        clone = self.root/"copy.json"
        clone.write_bytes(report.read_bytes())
        for reports in ([report, report], [report, clone]):
            with self.assertRaises(e2e_catalog.CatalogError):
                schedule_scenarios(self.catalog, self.cases, timing_reports=reports)
        raw = json.loads(report.read_text())
        raw["results"].append(raw["results"][0])
        report.write_text(json.dumps(raw))
        with self.assertRaises(e2e_catalog.CatalogError):
            schedule_scenarios(self.catalog, self.cases, timing_reports=[report])

    def test_mutated_or_duplicate_selection_and_invalid_order_are_rejected(self):
        for cases in ((self.cases[0], self.cases[0]), (replace(self.cases[0], target="wrong"),), (object(),)):
            with self.assertRaises(e2e_catalog.CatalogError):
                schedule_scenarios(self.catalog, cases)
        with self.assertRaises(e2e_catalog.CatalogError):
            schedule_scenarios(self.catalog, self.cases, order="random")


if __name__ == "__main__":
    unittest.main()
