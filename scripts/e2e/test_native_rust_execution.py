"""Rust libtest output models, not wallet/financial E2E results."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_rust_execution as EXECUTION
import e2e_catalog


class RustExecutionTests(unittest.TestCase):
    def output(self, test="selected", status="ok", passed=1, ignored=0):
        return ["\nrunning 1 test\n", f"test {test} ... {status}\n",
            f"test result: ok. {passed} passed; 0 failed; {ignored} ignored; 0 measured; 2 filtered out; finished in 1.23s\n"]

    def test_exact_single_test_and_its_summary_are_required(self):
        EXECUTION.verify_test_output(self.output(), "selected")
        for output in (self.output("other"), self.output(status="ignored", passed=0, ignored=1),
                       ["running 0 tests\n", "test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 3 filtered out; finished in 0.00s\n"],
                       self.output() * 2, self.output()[:-1]):
            with self.subTest(output=output), self.assertRaises(EXECUTION.runtime.RunnerError):
                EXECUTION.verify_test_output(output, "selected")

    def test_exact_names_and_unchanged_catalog_targets(self):
        catalog = e2e_catalog.load_catalog()
        for name, target in EXECUTION.RUST_CASES.items():
            scenario = catalog.scenarios_by_id[name]
            self.assertEqual((scenario.target, scenario.test), target)
            self.assertEqual(scenario.profile, EXECUTION.RUST_PROFILES[name])
        with self.assertRaises(EXECUTION.runtime.RunnerError):
            EXECUTION.verify_test_output(self.output("selected_extra"), "selected")


if __name__ == "__main__":
    unittest.main()
