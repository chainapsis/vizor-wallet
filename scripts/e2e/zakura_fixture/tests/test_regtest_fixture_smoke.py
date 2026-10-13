import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SCRIPTS = Path(__file__).parents[1]
SCRIPT = SCRIPTS / "regtest_fixture_smoke.py"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("zakura_regtest_fixture_smoke", SCRIPT)
assert SPEC and SPEC.loader
smoke = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = smoke
SPEC.loader.exec_module(smoke)


HASH = "11" * 32
OTHER_HASH = "22" * 32
RUN_ID = "11" * 16


class FakeFixture:
    instances = []
    start_error = None
    mine_error = None
    parity_error = None
    close_error = None
    cleanup = {
        "schema_version": 1,
        "run_id": RUN_ID,
        "removed": [],
        "errors": [],
        "complete": True,
    }
    start_proof = None
    mining = None
    final_parity = None
    peers = []
    run_id_value = RUN_ID

    def __init__(self, artifacts, grpcurl, proto_dir, *, timeout, profile, network_subnet):
        self.artifacts = Path(artifacts)
        self.grpcurl = Path(grpcurl)
        self.proto_dir = Path(proto_dir)
        self.timeout = timeout
        self.profile = profile
        self.network_subnet = network_subnet
        self.run_id = type(self).run_id_value
        self.calls = []
        type(self).instances.append(self)

    @classmethod
    def reset(cls, profile=smoke.DIRECT_HEIGHT1_PROFILE, blocks=2):
        cls.instances = []
        cls.start_error = None
        cls.mine_error = None
        cls.parity_error = None
        cls.close_error = None
        cls.peers = []
        cls.run_id_value = RUN_ID
        branch = (
            smoke.NU63_BRANCH_ID
            if profile == smoke.DIRECT_HEIGHT1_PROFILE
            else smoke.NU62_BRANCH_ID
        )
        pools = (
            {"sapling": "aa", "orchard": "bb", "ironwood": "cc"}
            if profile == smoke.DIRECT_HEIGHT1_PROFILE
            else {"sapling": "aa", "orchard": "bb"}
        )
        cls.start_proof = {
            "schema_version": 1,
            "identity": {"run_id": RUN_ID},
            "endpoints": {
                "node_rpc_url": "http://127.0.0.1:49100",
                "lightwalletd_url": "127.0.0.1:49200",
            },
            "profile": {
                "name": profile,
                "nu6_3_activation_height": (
                    1 if profile == smoke.DIRECT_HEIGHT1_PROFILE else 500
                ),
            },
            "bootstrap": {
                "node_ready": {"peers": []},
                "hashes": [HASH],
            },
            "parity": {
                "height": 1,
                "hash": HASH,
                "trees": pools,
                "consensus_branch_id": branch,
            },
        }
        final_pools = {name: f"final-{value}" for name, value in pools.items()}
        cls.final_parity = {
            "height": 1 + blocks,
            "hash": OTHER_HASH,
            "trees": final_pools,
            "consensus_branch_id": branch,
        }
        cls.mining = {
            "hashes": [f"{index + 3:02x}" * 32 for index in range(blocks - 1)]
            + [OTHER_HASH],
            "tip": dict(cls.final_parity),
        }
        cls.cleanup = {
            "schema_version": 1,
            "run_id": RUN_ID,
            "removed": [],
            "errors": [],
            "complete": True,
        }

    def start(self):
        self.calls.append("start")
        if self.start_error is not None:
            raise self.start_error
        return self.start_proof

    def mine(self, blocks):
        self.calls.append(("mine", blocks))
        if self.mine_error is not None:
            raise self.mine_error
        return self.mining

    def rpc(self, method, params=None):
        self.calls.append(("rpc", method, [] if params is None else params))
        if method != "getpeerinfo":
            raise AssertionError(f"unexpected smoke RPC: {method}")
        return list(self.peers)

    def wait_synced(self):
        self.calls.append("wait_synced")
        if self.parity_error is not None:
            raise self.parity_error
        return self.final_parity

    def close(self):
        self.calls.append("close")
        if self.close_error is not None:
            raise self.close_error
        return dict(self.cleanup)


class RegtestFixtureSmokeTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.grpcurl = self.root / "grpcurl"
        self.grpcurl.write_text("#!/bin/sh\n", encoding="utf-8")
        self.grpcurl.chmod(0o700)
        self.protos = self.root / "protos"
        self.protos.mkdir()
        (self.protos / "service.proto").write_text('syntax = "proto3";\n')
        FakeFixture.reset()

    def tearDown(self):
        self.temporary_directory.cleanup()

    def args(self, *extra):
        return smoke.parse_args(
            [
                "--grpcurl",
                str(self.grpcurl),
                "--proto-dir",
                str(self.protos),
                *extra,
            ]
        )

    def run_smoke(self, args):
        output = io.StringIO()
        with mock.patch.object(smoke, "RegtestFixture", FakeFixture), mock.patch(
            "sys.stdout", output
        ):
            code = smoke.run(args)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 1, output.getvalue())
        return code, json.loads(lines[0])

    def test_cli_requires_tools_and_validates_numeric_bounds_without_resources(self):
        invalid = [
            ["--blocks", "0"],
            ["--blocks", "1001"],
            ["--blocks", "1.0"],
            ["--timeout", "0"],
            ["--timeout", "301"],
            ["--timeout", "nan"],
            ["--timeout", "inf"],
        ]
        for extra in invalid:
            with self.subTest(extra=extra), contextlib.redirect_stderr(
                io.StringIO()
            ), self.assertRaises(SystemExit):
                self.args(*extra)
        for argv in ([], ["--grpcurl", str(self.grpcurl)]):
            with self.subTest(argv=argv), contextlib.redirect_stderr(
                io.StringIO()
            ), self.assertRaises(SystemExit):
                smoke.parse_args(argv)
        with mock.patch.object(smoke, "RegtestFixture") as constructor:
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(
                SystemExit
            ) as help_exit:
                smoke.parse_args(["--help"])
            self.assertEqual(help_exit.exception.code, 0)
            constructor.assert_not_called()
        defaults = self.args()
        self.assertEqual(defaults.profile, smoke.DIRECT_HEIGHT1_PROFILE)
        self.assertEqual(defaults.blocks, 2)
        self.assertEqual(defaults.timeout, 60.0)

    def test_passed_run_writes_one_private_report_and_closes_after_final_parity(self):
        artifacts = self.root / "artifacts"
        args = self.args("--artifacts-dir", str(artifacts), "--blocks", "3",
                         "--network-subnet", "10.42.0.0/28")
        FakeFixture.reset(blocks=3)

        code, report = self.run_smoke(args)

        self.assertEqual(code, 0)
        self.assertEqual(FakeFixture.instances[0].network_subnet, "10.42.0.0/28")
        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["exit_code"], 0)
        self.assertEqual(report["artifacts"], str(artifacts.resolve()))
        self.assertEqual(report["profile"], smoke.DIRECT_HEIGHT1_PROFILE)
        self.assertEqual(report["blocks"], 3)
        self.assertIsNone(report["error"])
        self.assertEqual(report["start_proof"], FakeFixture.start_proof)
        self.assertEqual(report["mining"], FakeFixture.mining)
        self.assertEqual(report["final_parity"], FakeFixture.final_parity)
        self.assertEqual(report["cleanup"], FakeFixture.cleanup)
        self.assertEqual(
            FakeFixture.instances[0].calls,
            [
                "start",
                ("rpc", "getpeerinfo", []),
                ("mine", 3),
                "wait_synced",
                ("rpc", "getpeerinfo", []),
                "close",
            ],
        )
        self.assertEqual(artifacts.stat().st_mode & 0o777, 0o700)
        report_path = artifacts / "smoke-report.json"
        self.assertEqual(report_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(report_path.read_text()), report)

    def test_omitted_artifacts_uses_a_new_private_temporary_directory(self):
        args = self.args()
        FakeFixture.reset()
        artifacts = self.root / "automatic-artifacts"

        def owned_mkdtemp(*, prefix):
            self.assertEqual(prefix, "zakura-regtest-smoke-")
            artifacts.mkdir(mode=0o700)
            return str(artifacts)

        with mock.patch.object(smoke.tempfile, "mkdtemp", side_effect=owned_mkdtemp):
            code, report = self.run_smoke(args)

        self.assertEqual(code, 0)
        self.assertEqual(Path(report["artifacts"]), artifacts.resolve())
        self.assertTrue(artifacts.is_dir())
        self.assertEqual(artifacts.stat().st_mode & 0o777, 0o700)
        self.assertEqual(FakeFixture.instances[0].artifacts, artifacts.resolve())

    def test_activation_profile_preserves_pre_activation_branch_evidence(self):
        profile = smoke.CONTROLLED_ACTIVATION_PROFILE
        artifacts = self.root / "activation"
        FakeFixture.reset(profile=profile, blocks=2)
        args = self.args(
            "--artifacts-dir",
            str(artifacts),
            "--profile",
            profile,
        )

        code, report = self.run_smoke(args)

        self.assertEqual(code, 0)
        self.assertEqual(report["profile"], profile)
        self.assertEqual(
            report["start_proof"]["parity"]["consensus_branch_id"],
            smoke.NU62_BRANCH_ID,
        )
        self.assertEqual(
            report["final_parity"]["consensus_branch_id"],
            smoke.NU62_BRANCH_ID,
        )

    def test_bootstrap_profile_and_peer_mismatch_fail_before_mining_and_cleanup(self):
        cases = ("profile", "activation-height", "activation-height-bool", "peers")
        for index, case in enumerate(cases):
            with self.subTest(case=case):
                FakeFixture.reset()
                if case == "profile":
                    FakeFixture.start_proof["profile"]["name"] = (
                        smoke.CONTROLLED_ACTIVATION_PROFILE
                    )
                elif case == "activation-height":
                    FakeFixture.start_proof["profile"][
                        "nu6_3_activation_height"
                    ] = 500
                elif case == "activation-height-bool":
                    FakeFixture.start_proof["profile"][
                        "nu6_3_activation_height"
                    ] = True
                else:
                    FakeFixture.peers = [{"addr": "198.51.100.1:8233"}]
                code, report = self.run_smoke(
                    self.args(
                        "--artifacts-dir",
                        str(self.root / f"bootstrap-{index}"),
                    )
                )
                self.assertEqual(code, 1)
                self.assertEqual(report["error"]["phase"], "bootstrap")
                self.assertFalse(
                    any(
                        isinstance(call, tuple) and call[0] == "mine"
                        for call in FakeFixture.instances[-1].calls
                    )
                )
                self.assertEqual(FakeFixture.instances[-1].calls[-1], "close")

    def test_final_parity_must_repeat_the_mined_hash_and_tree_profile(self):
        FakeFixture.reset()
        FakeFixture.final_parity = dict(FakeFixture.final_parity, hash="44" * 32)

        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(self.root / "final-mismatch"))
        )

        self.assertEqual(code, 1)
        self.assertEqual(report["error"]["phase"], "parity")
        self.assertEqual(report["mining"], FakeFixture.mining)
        self.assertEqual(report["final_parity"], FakeFixture.final_parity)
        self.assertTrue(report["cleanup"]["complete"])

    def test_start_mine_and_final_parity_failures_always_close(self):
        failures = [
            ("start_error", RuntimeError("start failed"), "start", ["start"]),
            (
                "mine_error",
                ValueError("mine failed"),
                "mine",
                ["start", ("rpc", "getpeerinfo", []), ("mine", 2)],
            ),
            (
                "parity_error",
                OSError("parity failed"),
                "parity",
                [
                    "start",
                    ("rpc", "getpeerinfo", []),
                    ("mine", 2),
                    "wait_synced",
                ],
            ),
        ]
        for index, (attribute, error, phase, prefix) in enumerate(failures):
            with self.subTest(phase=phase):
                FakeFixture.reset()
                setattr(FakeFixture, attribute, error)
                artifacts = self.root / f"failure-{index}"
                code, report = self.run_smoke(
                    self.args("--artifacts-dir", str(artifacts))
                )
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "failed")
                self.assertEqual(report["error"]["phase"], phase)
                self.assertEqual(report["error"]["type"], type(error).__name__)
                self.assertEqual(report["error"]["message"], str(error))
                self.assertEqual(FakeFixture.instances[-1].calls[-1], "close")
                self.assertEqual(FakeFixture.instances[-1].calls[:-1], prefix)

    def test_cleanup_failure_fails_success_but_does_not_replace_primary_failure(self):
        FakeFixture.reset()
        FakeFixture.cleanup = {
            "schema_version": 1,
            "run_id": RUN_ID,
            "removed": [],
            "errors": ["owned network still exists"],
            "complete": False,
        }
        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(self.root / "cleanup-only"))
        )
        self.assertEqual(code, 1)
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["error"]["phase"], "cleanup")
        self.assertFalse(report["cleanup"]["complete"])

        FakeFixture.reset()
        FakeFixture.mine_error = RuntimeError("primary mine failure")
        FakeFixture.cleanup = {
            "schema_version": 1,
            "run_id": RUN_ID,
            "removed": [],
            "errors": ["cleanup also failed"],
            "complete": False,
        }
        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(self.root / "primary-and-cleanup"))
        )
        self.assertEqual(code, 1)
        self.assertEqual(report["error"]["phase"], "mine")
        self.assertEqual(report["error"]["message"], "primary mine failure")
        self.assertEqual(report["cleanup"]["errors"], ["cleanup also failed"])

        FakeFixture.reset()
        FakeFixture.start_error = RuntimeError("start is primary")
        FakeFixture.close_error = OSError("close raised")
        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(self.root / "raised-cleanup"))
        )
        self.assertEqual(code, 1)
        self.assertEqual(report["error"]["message"], "start is primary")
        self.assertFalse(report["cleanup"]["complete"])
        self.assertIn("close raised", " ".join(report["cleanup"]["errors"]))

    def test_cleanup_proof_schema_and_fixture_identity_are_fail_closed(self):
        valid = {
            "schema_version": 1,
            "run_id": RUN_ID,
            "removed": [
                {"kind": "container", "name": "owned-node", "id": "container-id"},
                {"kind": "network", "name": "owned-network", "id": "network-id"},
                {"kind": "volume", "name": "owned-volume", "id": "volume-id"},
            ],
            "errors": [],
            "complete": True,
        }

        def mutation(label):
            proof = json.loads(json.dumps(valid))
            if label == "missing-fields":
                proof.pop("removed")
            elif label == "wrong-schema":
                proof["schema_version"] = 2
            elif label == "bool-schema":
                proof["schema_version"] = True
            elif label == "wrong-owner":
                proof["run_id"] = "22" * 16
            elif label == "errors-boolean":
                proof["errors"] = True
            elif label == "errors-entry":
                proof["errors"] = [1]
            elif label == "nonbool-complete":
                proof["complete"] = 1
            elif label == "complete-with-errors":
                proof["errors"] = ["owned network remains"]
            elif label == "malformed-removed":
                proof["removed"] = [
                    {"kind": "image", "name": "foreign", "id": "image-id"}
                ]
            elif label == "empty-removed-name":
                proof["removed"] = [
                    {"kind": "container", "name": "", "id": "container-id"}
                ]
            elif label == "nontext-removed-id":
                proof["removed"] = [
                    {"kind": "volume", "name": "owned-volume", "id": 1}
                ]
            elif label == "uppercase-owner":
                proof["run_id"] = "AA" * 16
            else:
                raise AssertionError(label)
            return proof

        labels = (
            "missing-fields",
            "wrong-schema",
            "bool-schema",
            "wrong-owner",
            "uppercase-owner",
            "errors-boolean",
            "errors-entry",
            "nonbool-complete",
            "complete-with-errors",
            "malformed-removed",
            "empty-removed-name",
            "nontext-removed-id",
        )
        for index, label in enumerate(labels):
            with self.subTest(label=label, primary=False):
                FakeFixture.reset()
                if label == "uppercase-owner":
                    FakeFixture.run_id_value = "AA" * 16
                FakeFixture.cleanup = mutation(label)
                code, report = self.run_smoke(
                    self.args(
                        "--artifacts-dir", str(self.root / f"cleanup-schema-{index}")
                    )
                )
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "failed")
                self.assertEqual(report["error"]["phase"], "cleanup")
                self.assertFalse(report["cleanup"]["complete"])

            with self.subTest(label=label, primary=True):
                FakeFixture.reset()
                if label == "uppercase-owner":
                    FakeFixture.run_id_value = "AA" * 16
                FakeFixture.mine_error = RuntimeError("primary mine failure")
                FakeFixture.cleanup = mutation(label)
                code, report = self.run_smoke(
                    self.args(
                        "--artifacts-dir",
                        str(self.root / f"cleanup-primary-{index}"),
                    )
                )
                self.assertEqual(code, 1)
                self.assertEqual(report["error"]["phase"], "mine")
                self.assertEqual(report["error"]["message"], "primary mine failure")
                self.assertFalse(report["cleanup"]["complete"])

    def test_keyboard_interrupt_preserves_130_and_cleanup_evidence(self):
        FakeFixture.reset()
        FakeFixture.mine_error = KeyboardInterrupt()

        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(self.root / "interrupted"))
        )

        self.assertEqual(code, 130)
        self.assertEqual(report["status"], "interrupted")
        self.assertEqual(report["exit_code"], 130)
        self.assertEqual(report["error"]["phase"], "mine")
        self.assertEqual(report["error"]["type"], "KeyboardInterrupt")
        self.assertTrue(report["cleanup"]["complete"])
        self.assertEqual(FakeFixture.instances[0].calls[-1], "close")

    def test_cleanup_keyboard_interrupt_sets_130_after_success(self):
        FakeFixture.reset()
        FakeFixture.close_error = KeyboardInterrupt()

        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(self.root / "cleanup-interrupted"))
        )

        self.assertEqual(code, 130)
        self.assertEqual(report["status"], "interrupted")
        self.assertEqual(report["error"]["phase"], "cleanup")
        self.assertEqual(report["error"]["type"], "KeyboardInterrupt")
        self.assertFalse(report["cleanup"]["complete"])

    def test_report_write_failure_does_not_replace_primary_failure(self):
        FakeFixture.reset()
        FakeFixture.mine_error = RuntimeError("primary mine failure")
        artifacts = self.root / "report-write-failure"
        args = self.args("--artifacts-dir", str(artifacts))
        output = io.StringIO()
        real_open = smoke.os.open

        def fail_report_open(path, flags, mode=0o777):
            if Path(path).name == "smoke-report.json":
                raise OSError("report storage unavailable")
            return real_open(path, flags, mode)

        with mock.patch.object(smoke, "RegtestFixture", FakeFixture), mock.patch.object(
            smoke.os, "open", side_effect=fail_report_open
        ), mock.patch("sys.stdout", output):
            code = smoke.run(args)

        report = json.loads(output.getvalue())
        self.assertEqual(code, 1)
        self.assertEqual(report["error"]["phase"], "mine")
        self.assertEqual(report["error"]["message"], "primary mine failure")
        self.assertEqual(report["report_error"]["phase"], "report")
        self.assertEqual(
            report["report_error"]["message"], "report storage unavailable"
        )
        self.assertTrue(report["cleanup"]["complete"])
        self.assertFalse((artifacts / "smoke-report.json").exists())

    def test_existing_or_symlink_artifact_targets_are_untouched(self):
        existing = self.root / "existing"
        existing.mkdir()
        sentinel = existing / "keep.txt"
        sentinel.write_text("owned by user", encoding="utf-8")
        real = self.root / "real"
        real.mkdir()
        link = self.root / "link"
        link.symlink_to(real, target_is_directory=True)
        existing_file = self.root / "existing-file"
        existing_file.write_text("owned by user", encoding="utf-8")

        for target in (existing, link, existing_file):
            with self.subTest(target=target):
                FakeFixture.reset()
                code, report = self.run_smoke(
                    self.args("--artifacts-dir", str(target))
                )
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "failed")
                self.assertIsNone(report["artifacts"])
                self.assertEqual(report["error"]["phase"], "artifacts")
                self.assertEqual(FakeFixture.instances, [])
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "owned by user")
        self.assertEqual(existing_file.read_text(encoding="utf-8"), "owned by user")
        self.assertEqual(list(real.iterdir()), [])

    def test_artifact_parent_must_exist_and_creation_failure_prints_only_report(self):
        target = self.root / "missing-parent" / "artifacts"

        code, report = self.run_smoke(
            self.args("--artifacts-dir", str(target))
        )

        self.assertEqual(code, 1)
        self.assertIsNone(report["artifacts"])
        self.assertEqual(report["error"]["phase"], "artifacts")
        self.assertFalse(target.exists())
        self.assertEqual(FakeFixture.instances, [])

    def test_main_returns_run_exit_code(self):
        namespace = argparse.Namespace()
        with mock.patch.object(smoke, "parse_args", return_value=namespace) as parse, mock.patch.object(
            smoke, "run", return_value=130
        ) as run:
            self.assertEqual(smoke.main(["--ignored-by-mock"]), 130)
        parse.assert_called_once_with(["--ignored-by-mock"])
        run.assert_called_once_with(namespace)


if __name__ == "__main__":
    unittest.main()
