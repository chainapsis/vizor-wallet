import importlib.util
import sys
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "e2e_report", Path(__file__).with_name("e2e_report.py")
)
assert SPEC is not None and SPEC.loader is not None
REPORT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = REPORT
SPEC.loader.exec_module(REPORT)


def selected():
    return [
        {
            "scenario_id": f"rust.send.{name}",
            "profile": "zakura-height1",
            "target": "regtest_send",
            "test": name,
        }
        for name in ("first", "second")
    ]


def attempt(name="first", code=0, error=None):
    return {
        "target": "regtest_send",
        "test": name,
        "worker_id": 0,
        "returncode": code,
        "duration_seconds": 1.25,
        "log": f"worker-0/{name}.log",
        "error": error,
    }


class ReportTest(unittest.TestCase):
    def test_reports_unstarted_scenarios_without_claiming_they_passed(self):
        results = REPORT.normalize_results(selected(), [attempt(code=101)])
        self.assertEqual([item["status"] for item in results], ["failed", "not_run"])
        self.assertEqual(results[0]["returncode"], 101)
        self.assertEqual(results[0]["scenario_id"], "rust.send.first")
        self.assertEqual(results[1]["attempt"], 0)
        self.assertIsNone(results[1]["returncode"])

    def test_distinguishes_timeout_cancel_spawn_failure_and_pass(self):
        for code, error, status, kind in (
            (0, None, "passed", None),
            (124, "command timed out", "timed_out", "timeout"),
            (130, "peer cancelled", "cancelled", "cancelled"),
            (1, "failed to start", "failed", "process"),
            (101, None, "failed", "test"),
        ):
            with self.subTest(code=code, error=error):
                result = REPORT.normalize_results(selected(), [attempt(code=code, error=error)])[0]
                self.assertEqual(result["status"], status)
                self.assertEqual(result["failure_kind"], kind)
                self.assertEqual(result["attempt"], 1)

    def test_preserves_catalog_order_when_workers_complete_out_of_order(self):
        results = REPORT.normalize_results(selected(), [attempt("second"), attempt("first")])
        self.assertEqual([item["test"] for item in results], ["first", "second"])

    def test_attempt_metadata_cannot_replace_catalog_identity(self):
        raw = {**attempt(), "scenario_id": "wrong", "profile": "wrong", "status": "failed"}
        result = REPORT.normalize_results(selected(), [raw])[0]
        self.assertEqual(result["scenario_id"], "rust.send.first")
        self.assertEqual(result["profile"], "zakura-height1")
        self.assertEqual(result["status"], "passed")

    def test_rejects_duplicate_attempts(self):
        with self.assertRaisesRegex(ValueError, "more than once"):
            REPORT.normalize_results(selected(), [attempt(), attempt()])

    def test_rejects_unselected_attempts(self):
        with self.assertRaisesRegex(ValueError, "unselected"):
            REPORT.normalize_results(selected(), [attempt("third")])

    def test_rejects_duplicate_selected_identity(self):
        items = selected()
        items.append({**items[0], "scenario_id": "different"})
        with self.assertRaisesRegex(ValueError, "duplicate test"):
            REPORT.normalize_results(items, [])

    def test_rejects_duplicate_selected_id(self):
        items = selected()
        items[1]["scenario_id"] = items[0]["scenario_id"]
        with self.assertRaisesRegex(ValueError, "duplicate scenario"):
            REPORT.normalize_results(items, [])

    def test_rejects_boolean_float_and_incomplete_spawn_returncodes(self):
        for code, error in ((False, None), (0.0, None), (None, None), (None, "")):
            with self.subTest(code=code, error=error), self.assertRaisesRegex(
                ValueError, "returncode"
            ):
                REPORT.normalize_results(selected(), [attempt(code=code, error=error)])

    def test_spawn_failure_may_use_none_returncode_with_nonempty_error(self):
        result = REPORT.normalize_results(
            selected(), [attempt(code=None, error="failed to spawn")]
        )[0]
        self.assertEqual("failed", result["status"])
        self.assertEqual("process", result["failure_kind"])
        self.assertIsNone(result["returncode"])

    def test_rejects_missing_returncode_even_for_spawn_error(self):
        raw = attempt(code=None, error="failed to spawn")
        del raw["returncode"]
        with self.assertRaisesRegex(ValueError, "returncode"):
            REPORT.normalize_results(selected(), [raw])


if __name__ == "__main__":
    unittest.main()
