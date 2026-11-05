#!/usr/bin/env python3
"""Offline updater tests using real signed headers and ICS23 proofs."""
import copy
from datetime import timedelta
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("updater", Path(__file__).with_name("update-voting-validators.py"))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
ROOT = updater.ROOT


class UpdaterTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for path in (updater.TRUST, updater.FIXTURES):
            shutil.copytree(ROOT / path, self.root / path)
        (self.root / "docs").mkdir()
        shutil.copy(ROOT / "docs/voting-participation.md", self.root / "docs/voting-participation.md")
        # Historical test scenarios must survive any number of real updates.
        # Reset active pins, evidence and transitions in the temporary tree.
        self.fixtures = {}
        anchors = {}
        for network, capture in (("main", "20261102"), ("test", "20260910")):
            fixture = updater.read(ROOT, updater.FIXTURES / f"{network}-{capture}.json")
            self.fixtures[network] = fixture
            header = fixture["commit"]["result"]["signed_header"]["header"]
            anchors[network] = {
                "chain_id": header["chain_id"], "validator_set_hash": header["validators_hash"],
                "height": int(header["height"]), "captured_at": header["time"][:10],
            }
            (self.root / updater.FIXTURES / f"{network}.json").write_text(updater.encode(fixture))
            (self.root / updater.TRUST / f"{network}-validators.json").write_text(
                updater.encode(fixture["validators"]["result"]["validators"]))
            (self.root / updater.TRUST / f"{network}-transition.json").unlink(missing_ok=True)
        (self.root / updater.TRUST / "anchors.json").write_text(updater.encode(anchors))
        doc = self.root / "docs/voting-participation.md"
        doc.write_text(updater.render_docs(doc.read_text(), anchors))
        self.fixtures["main"]["commit"] = updater.read(ROOT, updater.FIXTURES / "main-20261102-canonical-commit.json")
        self.now = updater.timestamp(self.fixtures["main"]["commit"])
        # Use independent per-network capture clocks; neither test contacts RPC.
        self.fixtures["test"]["commit"]["result"]["canonical"] = True

    def old_anchor(self):
        previous = updater.read(ROOT, updater.FIXTURES / "main-20260910.json")
        anchor = previous["commit"]["result"]["signed_header"]["header"]
        anchors = updater.read(self.root, updater.TRUST / "anchors.json")
        anchors["main"] = {"chain_id": "zvote-1", "validator_set_hash": anchor["validators_hash"],
                           "captured_at": "2026-09-10", "height": int(anchor["height"])}
        (self.root / updater.TRUST / "anchors.json").write_text(updater.encode(anchors))
        (self.root / updater.TRUST / "main-validators.json").write_text(updater.encode(previous["validators"]["result"]["validators"]))
        (self.root / updater.FIXTURES / "main.json").write_text(updater.encode(previous))
        doc = self.root / "docs/voting-participation.md"
        doc.write_text(updater.render_docs(doc.read_text(), anchors))

    def get(self, base, path, params=None):
        network = "test" if "stage." in base else "main"
        f = self.fixtures[network]
        if path == "/commit":
            commit = copy.deepcopy(f["commit"])
            if params is None:
                header = commit["result"]["signed_header"]["header"]
                header["height"] = str(int(header["height"]) + 1)
            elif int(params["height"]) != int(commit["result"]["signed_header"]["header"]["height"]):
                raise updater.UpdateError("No such fixture height")
            return commit
        if path == "/validators":
            return copy.deepcopy(f["validators"])
        if path == "/abci_query":
            index = f["keys"].index(params["data"][2:])
            return copy.deepcopy(f["queries"][index])
        self.fail(f"Unexpected RPC path: {path}")

    def tree(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}

    def update(self, networks=("main",), get=None):
        return updater.update(self.root, networks, get=get or self.get, clock=lambda: self.now)

    def test_fortnight_gate_crosses_53_week_year_and_month_boundaries(self):
        for weeks in range(120):
            day = updater.EPOCH + timedelta(weeks=weeks)
            self.assertEqual(updater.scheduled_week(day), weeks % 2 == 0)

    def test_real_transition_updates_all_data_and_second_run_is_noop(self):
        self.old_anchor()
        changed, summary = self.update()
        self.assertTrue(changed)
        self.assertIn("90/100", summary)
        self.assertIn("130/130", summary)
        self.assertIn("Added", summary)
        updater.check_local(self.root)
        before = self.tree()
        self.assertEqual(self.update()[0], False)
        self.assertEqual(self.tree(), before)

    def test_scenarios_stay_reproducible_after_generated_transition_is_committed(self):
        self.old_anchor()
        self.update()
        global ROOT
        original = ROOT
        ROOT = self.root
        try:
            scenario = UpdaterTests("test_real_transition_updates_all_data_and_second_run_is_noop")
            scenario.setUp()
            try:
                scenario.test_real_transition_updates_all_data_and_second_run_is_noop()
            finally:
                scenario.doCleanups()
        finally:
            ROOT = original

    def test_proposer_priority_and_order_changes_do_not_create_updates(self):
        for v in self.fixtures["main"]["validators"]["result"]["validators"]:
            v["proposer_priority"] = "98765"
        self.fixtures["main"]["validators"]["result"]["validators"].reverse()
        before = self.tree()
        self.assertFalse(self.update()[0])
        self.assertEqual(before, self.tree())

    def test_invalid_proofs_or_missing_validators_do_not_write(self):
        for defect in ("proof", "validators", "signature"):
            with self.subTest(defect=defect):
                self.old_anchor()
                saved = copy.deepcopy(self.fixtures)
                f = self.fixtures["main"]
                if defect == "proof":
                    f["queries"][0]["result"]["response"]["proofOps"]["ops"][0]["data"] = "AA=="
                elif defect == "validators":
                    f["validators"]["result"]["total"] = "14"
                else:
                    f["commit"]["result"]["signed_header"]["commit"]["signatures"][0]["signature"] = "AA=="
                before = self.tree()
                with self.assertRaises(updater.UpdateError):
                    self.update()
                self.assertEqual(before, self.tree())
                self.fixtures = saved

    def test_no_old_quorum_aborts_without_trusting_current_set(self):
        self.old_anchor()
        self.fixtures["main"] = updater.read(ROOT, updater.FIXTURES / "main-20261102.json")
        self.fixtures["main"]["commit"]["result"]["canonical"] = True
        before = self.tree()
        with self.assertRaisesRegex(updater.UpdateError, "both quorums"):
            self.update()
        self.assertEqual(before, self.tree())

    def test_second_network_failure_does_not_publish_first_network_update(self):
        self.old_anchor()
        before = self.tree()
        def get(base, path, params=None):
            if "stage." in base:
                raise updater.UpdateError("Unavailable stage RPC")
            return self.get(base, path, params)
        with self.assertRaises(updater.UpdateError):
            self.update(("main", "test"), get)
        self.assertEqual(before, self.tree())

    def test_stale_docs_abort_before_writes(self):
        self.old_anchor()
        doc = self.root / "docs/voting-participation.md"
        doc.write_text(doc.read_text().replace(updater.START_MARKER, ""))
        before = self.tree()
        with self.assertRaisesRegex(updater.UpdateError, "markers"):
            self.update()
        self.assertEqual(before, self.tree())


class ProposalTests(unittest.TestCase):
    def commands(self, changed, existing=""):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shim = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
tool=Path(sys.argv[0]).name
with open(os.environ['CALLS'],'a') as f: f.write(json.dumps([tool]+sys.argv[1:])+'\\n')
if tool=='gh' and sys.argv[1:3]==['pr','list']: print(os.environ['GH_EXISTING'])
if tool=='git' and sys.argv[1]=='ls-remote': print('a'*40+'\\trefs/heads/automation/voting-validators')
'''
            for name in ("gh", "git"):
                binary = root / name
                binary.write_text(shim)
                binary.chmod(0o755)
            env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                   "CALLS": str(root / "calls"), "GH_EXISTING": existing,
                   "BRANCH": "automation/voting-validators", "CHANGED": changed,
                   "RUNNER_TEMP": str(root), "DATA_FILES": "trust fixture"}
            subprocess.run(["bash", str(ROOT / "scripts/update-voting-validators-pr.sh")], env=env, check=True)
            return [json.loads(line) for line in (root / "calls").read_text().splitlines()]

    def test_no_change_does_not_push_or_create_a_proposal(self):
        commands = self.commands("false")
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0][:3], ["gh", "pr", "list"])
        self.assertIn("isCrossRepository == false", commands[0][-1])

    def test_obsolete_proposal_is_closed_on_verified_no_change(self):
        commands = self.commands("false", "42")
        self.assertEqual(commands[-1][:4], ["gh", "pr", "close", "42"])
        self.assertFalse(any(c[0] == "git" for c in commands))

    def test_change_creates_or_updates_one_proposal_with_a_leased_push(self):
        for existing, verb in (("", "create"), ("42", "edit")):
            commands = self.commands("true", existing)
            push = next(c for c in commands if c[:2] == ["git", "push"])
            self.assertIn("--force-with-lease=refs/heads/automation/voting-validators:" + "a" * 40, push)
            self.assertEqual(commands[-1][:3], ["gh", "pr", verb])
            self.assertIn("--body-file", commands[-1])


if __name__ == "__main__":
    unittest.main()
