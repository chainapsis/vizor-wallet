"""Real Git archives, original children/files/leases; compiler/service transport modeled."""
import fcntl
import json
import os
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import native_voting as VOTE
import native_voting_build as BUILD
import test_funder_build as FIXTURE


class VotingBuildTests(unittest.TestCase):
    def setUp(self):
        self.model = FIXTURE.FunderBuildTests()
        self.model.setUp()
        self.addCleanup(self.model.doCleanups)
        for name in ("scripts/init.sh", "e2e-tests/tests/create_round_for_zashi.rs"):
            path = self.model.source/name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            path.write_text("original model input\n")
        self.model.git("add", ".")
        self.model.git("commit", "-qm", "pinned voting model sources")
        self.pin = self.model.git("rev-parse", "HEAD").strip()
        self.case = self.model.case()
        self.make_calls = 0
        self.wrong_round = False

    def build(self):
        original = self.case.run_command

        def command(arguments, **kwargs):
            if arguments[0] == "git":
                return original(arguments, **kwargs)
            actual = arguments[5:] if arguments[0] == sys.executable else arguments
            cwd = Path(arguments[4]) if arguments[0] == sys.executable else self.case.workspace.root
            target = Path(kwargs["env"]["CARGO_TARGET_DIR"])
            if actual[0] == "make":
                self.make_calls += 1
                self.assertIn("CIRCUITS_CARGO_FLAGS=--locked --no-default-features --features zakura", actual)
                sdk = Path(actual[actual.index("-C")+1])
                outputs = [sdk/"svoted", sdk/"voting-config"]
            elif actual[:2] == ["cargo", "build"]:
                self.assertIn("--locked", actual)
                outputs = [target/"release/pir-export", target/"release/nf-server"]
            elif actual[:2] == ["cargo", "test"]:
                self.assertIn("--no-run", actual)
                sdk = Path(actual[actual.index("--manifest-path")+1]).parent.parent
                output = target/"release/deps/create_round-modeled"
                outputs = [output]
                record = {"reason":"compiler-artifact", "executable":str(output),
                    "target":{"name":"create_round_for_zashi", "kind":["test"],
                              "src_path":str(sdk/"e2e-tests/tests/create_round_for_zashi.rs")},
                    "profile":{"test":not self.wrong_round}}
            else:
                return original([sys.executable,"-c","print('modeled tool identity')"], **kwargs)
            script = "from pathlib import Path; import json; "
            for output in outputs:
                script += (f"p=Path({str(output)!r}); p.parent.mkdir(mode=0o700,parents=True,exist_ok=True); "
                           "p.write_text('modeled original build output'); p.chmod(0o700); ")
            if actual[:2] == ["cargo", "test"]:
                script += f"print(json.dumps({record!r})); "
            return original([sys.executable,"-c",script], **kwargs)

        with patch.object(BUILD,"VOTE_SDK_REV",self.pin), patch.object(BUILD,"PIR_REV",self.pin), \
             patch.object(self.case,"run_command",side_effect=command):
            return BUILD.build_voting_artifacts(self.case, sdk_cache=self.model.source,
                pir_cache=self.model.source, timeout=10)

    def test_build_once_publishes_original_joined_outputs_not_dirty_checkout(self):
        (self.model.source/"scripts/init.sh").write_text("dirty checkout")
        artifact, proof = self.build()
        self.assertEqual(self.make_calls, 1)
        self.assertFalse(self.case.accepting_launches)
        self.assertEqual((artifact.sdk/"scripts/init.sh").read_text(), "original model input\n")
        self.assertEqual(set(artifact.binaries), {"svoted","voting-config","pir-export","nf-server","create-round"})
        self.assertEqual(proof["build_count"], 1)
        self.assertFalse(proof["wallet_or_catalog_pass"])
        artifact.verify_unchanged()
        (artifact.sdk/"scripts/init.sh").write_text("changed runtime script")
        with self.assertRaisesRegex(BUILD.VotingBuildError, "runtime source changed"):
            artifact.verify_unchanged()

    def test_wrong_round_harness_cannot_become_published_artifact(self):
        self.wrong_round = True
        with self.assertRaisesRegex(BUILD.VotingBuildError, "original Cargo test"):
            self.build()
        self.assertFalse(self.case.accepting_launches)

    def test_receipt_cannot_reconstruct_original_producer(self):
        with self.assertRaises(BUILD.VotingBuildError):
            BUILD.ProducedVotingArtifacts(None, None, {}, {}, None, object())


class VotingOracleTests(unittest.TestCase):
    def test_real_oracles_require_discovery_nonempty_tree_and_parallel_slow_shares(self):
        metrics = {"discovery_successes":1,"config_requests":1,"round_list_requests":1,
                   "slow_share_requests":2,"slow_share_max_inflight":2}
        for index in (1, "1"):
            VOTE.verify_participation(metrics,{"tree":{"next_index":index}},slow_helper=True)
        for index in (0,"0",True,None):
            with self.assertRaises(VOTE.RunnerError):
                VOTE.verify_participation(metrics,{"tree":{"next_index":index}},slow_helper=False)
        metrics["slow_share_max_inflight"] = 1
        with self.assertRaises(VOTE.RunnerError):
            VOTE.verify_participation(metrics,{"tree":{"next_index":1}},slow_helper=True)

    def test_missing_generated_binding_does_not_fall_back_to_shared_default(self):
        with self.assertRaisesRegex(VOTE.RunnerError, "missing generated"):
            VOTE.patch_toml('[api]\naddress = "shared"\n', {("grpc","address"):"127.0.0.1:1234"})
        self.assertIn('address = "127.0.0.1:1234"', VOTE.patch_toml(
            '[api]\naddress = "shared"\n', {("api","address"):"127.0.0.1:1234"}))

    def test_unproven_original_service_join_keeps_all_port_locks(self):
        model = FIXTURE.FunderBuildTests()
        model.setUp()
        self.addCleanup(model.doCleanups)
        case = model.case()
        services = object.__new__(VOTE.NativeVotingServices)
        services.closed = services._failed = False
        services.session = Mock(case=case)
        services.artifact = Mock()
        services.lease = VOTE.lease_native_ports(0,"a1b2c3d4e5",
            port_names=VOTE.PORT_NAMES, lock_root=model.root/"locks")
        self.addCleanup(services.lease.close)
        services.lease.release_sockets()
        services.processes = [case.start_process([sys.executable,"-u","-c","import time; time.sleep(30)"],
                                                env=os.environ.copy())]
        with patch.object(case,"stop_process",side_effect=RuntimeError("join unproved")):
            with self.assertRaisesRegex(VOTE.RunnerError,"retain state and port locks"):
                services.close()
        for port in services.lease.ports.values():
            descriptor = os.open(model.root/"locks"/f"{port}.lock",os.O_RDWR)
            try:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(descriptor,fcntl.LOCK_EX|fcntl.LOCK_NB)
            finally:
                os.close(descriptor)
        case.close()  # Join the test's original writer before releasing its leases.


if __name__ == "__main__":
    unittest.main()
