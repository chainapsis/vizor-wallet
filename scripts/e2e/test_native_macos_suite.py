"""Coordinator models; native signing, wallet assertions and Docker are not real."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

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
        self.args = SimpleNamespace(workers=2,repeat=2,build_jobs=4,
            flutter=self.root/"bin/flutter", grpcurl=self.root/"grpcurl",
            zakura_cache=self.root,proto_dir=self.root)
        self.catalog = e2e_catalog.load_catalog()
        self.scenarios = (self.catalog.scenarios_by_id["flutter.macos.import-sync"],)
        self.helper, self.signer = object(), object()
        self.barrier = threading.Barrier(2)
        self.observed = []
        self.fail = False

    def git(self, command, **kwargs):
        return subprocess.CompletedProcess(command,0,"a"*40+"\n" if "rev-parse" in command else "","")

    def execute(self, root, run_id, worker_id, scenario, **kwargs):
        self.observed.append((root,run_id,worker_id,kwargs["helper"],kwargs["artifact"]))
        self.barrier.wait(timeout=2)
        return {"scenario_id":scenario.id,"target":scenario.target,"test":scenario.test,
                "status":"failed" if self.fail and root.name == "repetition-0" else "passed"}

    def invoke(self):
        output = io.StringIO()
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git), \
             patch.object(SUITE,"NativeCaseLifecycle",side_effect=lambda x:x), \
             patch.object(SUITE,"prepare_native_case_workspace",return_value=object()), \
             patch.object(SUITE,"build_native_macos_cohort",return_value=(self.helper,{"app_build_count":1})) as build, \
             patch.object(SUITE,"build_regtest_funder",return_value=self.signer) as signer, \
             patch.object(SUITE,"execute_case",side_effect=self.execute), \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            code = SUITE.run_native_macos_suite(self.args,self.catalog,self.scenarios,
                {"kind":"scenario","values":[self.scenarios[0].id]},source_root=self.root)
        return code,json.loads(output.getvalue()),build,signer

    def test_two_concurrent_repetitions_share_only_one_build_and_signer(self):
        code,summary,build,signer = self.invoke()
        self.assertEqual(code,0)
        build.assert_called_once()
        signer.assert_called_once()
        self.assertEqual(len({item[0] for item in self.observed}),2)
        self.assertEqual(len({item[1] for item in self.observed}),2)
        self.assertTrue(all(item[3] is self.helper and item[4] is self.signer for item in self.observed))
        for item in summary["repetition_reports"]:
            report = json.loads(Path(item["report"]).read_text())
            self.assertEqual(report["schema_version"],2)
            self.assertEqual(report["results"][0]["status"],"passed")
            with self.assertRaisesRegex(e2e_catalog.CatalogError,"zero scenarios"):
                e2e_catalog.select_scenarios(self.catalog,failed_from=Path(item["report"]))

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
                SUITE.validate_options(self.args,(self.catalog.scenarios[0],))
            self.args.flutter = None
            with self.assertRaises(ValueError):
                SUITE.validate_options(self.args,self.scenarios)
        self.assertFalse((self.root/".regtest-logs").exists())

    def test_build_failure_never_creates_a_passing_empty_batch(self):
        with patch.object(SUITE.sys,"platform","darwin"), \
             patch.object(SUITE.subprocess,"run",side_effect=self.git), \
             patch.object(SUITE,"NativeCaseLifecycle",side_effect=lambda x:x), \
             patch.object(SUITE,"prepare_native_case_workspace",return_value=object()), \
             patch.object(SUITE,"build_native_macos_cohort",side_effect=RuntimeError("compiler failed")), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = SUITE.run_native_macos_suite(self.args,self.catalog,self.scenarios,{},source_root=self.root)
        self.assertEqual(code,1)
        summary = json.loads(next((self.root/".regtest-logs").glob("native-suite-*/summary.json")).read_text())
        self.assertEqual(summary["error"],"compiler failed")
        self.assertEqual(summary["repetition_reports"],[])


if __name__ == "__main__":
    unittest.main()
