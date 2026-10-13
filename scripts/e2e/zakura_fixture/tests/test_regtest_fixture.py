import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "regtest_fixture.py"
SPEC = importlib.util.spec_from_file_location("zakura_regtest_fixture", SCRIPT)
assert SPEC and SPEC.loader
fixture = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = fixture
SPEC.loader.exec_module(fixture)


HASH = "11" * 32
OTHER_HASH = "22" * 32


class RegtestFixtureTests(unittest.TestCase):
    def test_only_exact_daemon_resource_absence_can_prove_cleanup(self):
        target = self.make_fixture()
        deadline = time.monotonic() + 5
        for kind, name, message in (
            ("container", target.node_name, f"Error response from daemon: No such container: {target.node_name}"),
            ("network", target.network_name, f"Error response from daemon: network {target.network_name} not found"),
            ("volume", target.lwd_volume, f"Error response from daemon: get {target.lwd_volume}: no such volume"),
        ):
            with self.subTest(kind=kind), mock.patch.object(target, "_docker",
                return_value=self.completed(stdout="[]\n", stderr=message, returncode=1)):
                target._ensure_resource_absent(kind, name, deadline)
                self.assertIsNone(target._owned_resource_id_if_present(kind, name, deadline))

    def test_transport_failure_or_other_resource_is_never_absence(self):
        target = self.make_fixture()
        deadline = time.monotonic() + 5
        for stdout, message, code in (
            ("", "cannot connect to Docker: no such file or directory", 1),
            ("[]", "credential helper not found", 1),
            ("[]", "Error response from daemon: No such container: another-node", 1),
            ("not-json", f"Error response from daemon: No such container: {target.node_name}", 1),
            ("[{}]", f"Error response from daemon: No such container: {target.node_name}", 1),
            ("[]", f"Error response from daemon: No such container: {target.node_name}", 2),
        ):
            with self.subTest(message=message, code=code), mock.patch.object(target, "_docker",
                return_value=self.completed(stdout=stdout, stderr=message, returncode=code)):
                with self.assertRaises(fixture.FixtureError):
                    target._ensure_resource_absent("container", target.node_name, deadline)
                with self.assertRaises(fixture.FixtureError):
                    target._owned_resource_id_if_present("container", target.node_name, deadline)

    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.grpcurl = self.root / "grpcurl"
        self.grpcurl.write_text("#!/bin/sh\n", encoding="utf-8")
        self.grpcurl.chmod(0o700)
        self.protos = self.root / "protos"
        self.protos.mkdir()
        (self.protos / "service.proto").write_text("syntax = \"proto3\";\n")
        self.port_root = self.root / "port-temp"
        self.port_root.mkdir(mode=0o700)
        self.port_temp_patch = mock.patch.object(fixture.tempfile, "gettempdir", return_value=str(self.port_root))
        self.port_temp_patch.start()
        self.addCleanup(self.port_temp_patch.stop)
        self.targets = []

    def tearDown(self):
        for target in self.targets:
            # All Docker calls in this suite are mocked; these are only the
            # test process's real sockets and advisory lock descriptors.
            for lease in target._port_leases.values():
                lease.close()
        self.temporary_directory.cleanup()

    def make_fixture(
        self,
        name="artifacts",
        *,
        run_id=None,
        timeout=5,
        miner_address=fixture.MINER_ADDRESS,
        profile=fixture.DIRECT_HEIGHT1_PROFILE,
        network_subnet=None,
    ):
        target = fixture.RegtestFixture(
            self.root / name,
            self.grpcurl,
            self.protos,
            timeout=timeout,
            run_id=run_id or uuid.uuid4(),
            miner_address=miner_address,
            profile=profile,
            network_subnet=network_subnet,
        )
        self.targets.append(target)
        return target

    @staticmethod
    def completed(stdout="", stderr="", returncode=0):
        return subprocess.CompletedProcess([], returncode, stdout, stderr)

    def test_explicit_network_subnet_is_validated_before_artifacts_or_docker(self):
        for value in (False, 1, "", "10.42.0.1/28", "10.42.0.0/30", "::/64",
                      "8.8.8.0/24", "127.0.0.0/8", "224.0.0.0/8"):
            with self.subTest(value=value), mock.patch.object(fixture.subprocess, "run") as run:
                with self.assertRaisesRegex(fixture.FixtureError, "network_subnet"):
                    self.make_fixture(network_subnet=value)
                run.assert_not_called()
                self.assertFalse((self.root / "artifacts").exists())
        for index, value in enumerate(("10.42.0.0/28", "172.16.1.0/29", "192.168.42.0/24")):
            target = self.make_fixture(f"subnet-{index}", network_subnet=value)
            self.assertEqual(target.network_subnet, value)

    def test_subnet_overlap_preserves_the_original_error_and_creates_no_other_resources(self):
        target = self.make_fixture(network_subnet="10.42.0.0/28")
        with mock.patch.object(target, "_verify_image", return_value={}), mock.patch.object(
            target, "_ensure_resource_absent"
        ), mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
            target, "_owned_resource_id_if_present", return_value=None
        ), mock.patch.object(
            target, "_docker", side_effect=fixture.FixtureError("Pool overlaps with other one on this address space")
        ) as docker:
            with self.assertRaisesRegex(fixture.FixtureError, "Pool overlaps"):
                target.start()
        self.assertEqual(docker.call_count, 1)
        self.assertEqual(docker.call_args.args[0][:2], ["network", "create"])
        proof = json.loads((target.artifacts / "cleanup-proof.json").read_text())
        self.assertTrue(proof["complete"])
        self.assertEqual(proof["removed"], [])

    def parity_responses(
        self, *, height=3, branch=fixture.NU63_BRANCH_ID,
        info=None, latest=None, tree=None, node_tree=None
    ):
        node_tree = node_tree or {
            "height": height,
            "hash": HASH,
            "time": 123,
            "sapling": {"commitments": {"finalState": "aa"}},
            "orchard": {"commitments": {"finalState": "bb"}},
            "ironwood": {"commitments": {"finalState": "cc"}},
        }
        info = info or {
            "blockHeight": height,
            "chainName": "test",
            "consensusBranchId": branch,
        }
        latest = latest or {
            "height": height,
            "hash": base64.b64encode(bytes.fromhex(HASH)).decode("ascii"),
        }
        tree = tree or {
            "height": height,
            "hash": HASH,
            "time": 123,
            "network": "test",
            "saplingTree": "aa",
            "orchardTree": "bb",
            "ironwoodTree": "cc",
        }

        def rpc(method, params=None, **_kwargs):
            return {
                "getblockchaininfo": {"blocks": height},
                "getbestblockhash": HASH,
                "z_gettreestate": node_tree,
            }[method]

        def grpc(method, payload=None, **_kwargs):
            return {
                "GetLightdInfo": info,
                "GetLatestBlock": latest,
                "GetTreeState": tree,
            }[method]

        return rpc, grpc

    def test_constructor_creates_isolated_run_owned_identities(self):
        first = self.make_fixture("one", run_id="11111111-1111-1111-1111-111111111111")
        second = self.make_fixture("two", run_id="22222222-2222-2222-2222-222222222222")

        self.assertNotEqual(first.network_name, second.network_name)
        self.assertNotEqual(first.node_name, second.node_name)
        self.assertNotEqual(first.lwd_name, second.lwd_name)
        self.assertEqual(first.labels[fixture.OWNER_LABEL], "1")
        self.assertEqual(first.labels[fixture.RUN_LABEL], first.run_id)
        self.assertEqual(first.miner_address, fixture.MINER_ADDRESS)
        self.assertEqual(first.artifacts.stat().st_mode & 0o777, 0o700)

    def test_constructor_rejects_invalid_miner_addresses_before_artifact_creation(self):
        invalid_addresses = (
            None,
            42,
            "t1" + "1" * 33,
            "tm" + "1" * 32,
            "tm" + "1" * 34,
            "tm" + "0" * 33,
            "tm" + "1" * 32 + "\n",
            'tm' + "1" * 31 + '"' + "1",
        )
        for index, miner_address in enumerate(invalid_addresses):
            with self.subTest(miner_address=miner_address):
                artifacts = self.root / f"invalid-miner-{index}"
                with self.assertRaisesRegex(fixture.FixtureError, "miner_address"):
                    fixture.RegtestFixture(
                        artifacts,
                        self.grpcurl,
                        self.protos,
                        miner_address=miner_address,
                    )
                self.assertFalse(artifacts.exists())

    def test_constructor_rejects_unknown_profiles_before_artifact_creation(self):
        for index, profile in enumerate((None, 1, "", "zakura-direct-activation499")):
            with self.subTest(profile=profile):
                artifacts = self.root / f"invalid-profile-{index}"
                with self.assertRaisesRegex(fixture.FixtureError, "profile"):
                    fixture.RegtestFixture(
                        artifacts, self.grpcurl, self.protos, profile=profile
                    )
                self.assertFalse(artifacts.exists())

    def test_container_creation_uses_stable_explicit_loopback_host_ports(self):
        target = self.make_fixture()
        commands = []

        def docker(args, **_kwargs):
            commands.append(args)
            return self.completed("node-id\n" if args[0] == "create" and target.node_name in args else "lwd-id\n")

        with mock.patch.object(target, "_docker", side_effect=docker), mock.patch.object(
            target, "_assert_owned", return_value={"Image": fixture.ZAKURA_IMAGE_ID},
        ):
            target._create_node(time.monotonic() + 5)
        with mock.patch.object(target, "_docker", side_effect=docker), mock.patch.object(
            target, "_assert_owned", return_value={"Image": fixture.LIGHTWALLETD_IMAGE_ID},
        ):
            target._create_lightwalletd(time.monotonic() + 5)

        create_commands = [command for command in commands if command[0] == "create"]
        self.assertEqual(len(create_commands), 2)
        for command in create_commands:
            published = command[command.index("--publish") + 1]
            self.assertRegex(published, r"^127\.0\.0\.1:[1-9][0-9]*:(18232|9067)$")
        self.assertEqual(len({lease.port for lease in target._port_leases.values()}), 2)
        self.assertTrue(all(lease.reserved is None for lease in target._port_leases.values()))

    def test_port_handoff_retains_cooperative_lock_until_close(self):
        target = self.make_fixture()
        port = target._lease_loopback_port("zakura", time.monotonic() + 5)
        lease = target._port_leases["zakura"]
        lock = self.port_root / f"vizor-wallet-native-e2e-{os.getuid()}" / "ports" / f"{port}.lock"
        self.assertEqual(lock.stat().st_mode & 0o777, 0o600)
        self.assertIn(f"run_id={target.run_id}", lock.read_text())
        with fixture.socket.socket() as contender:
            with self.assertRaises(OSError):
                contender.bind(("127.0.0.1", port))
        lease.handoff()
        self.assertIsNone(lease.reserved)
        fd = os.open(lock, os.O_RDWR)
        try:
            with self.assertRaises(BlockingIOError):
                fixture.fcntl.flock(fd, fixture.fcntl.LOCK_EX | fixture.fcntl.LOCK_NB)
            lease.close()
            fixture.fcntl.flock(fd, fixture.fcntl.LOCK_EX | fixture.fcntl.LOCK_NB)
        finally:
            os.close(fd)

    def test_port_lock_collision_closes_candidate_socket_and_descriptor(self):
        target = self.make_fixture()
        factory = fixture.socket.socket
        sockets = []
        def create_socket(*args):
            reserved = factory(*args)
            sockets.append(reserved)
            return reserved
        with mock.patch.object(fixture.socket, "socket", side_effect=create_socket), mock.patch.object(
            fixture.fcntl, "flock", side_effect=[BlockingIOError(), None],
        ):
            target._lease_loopback_port("zakura", time.monotonic() + 5)
        self.assertEqual(len(sockets), 2)
        self.assertEqual(sockets[0].fileno(), -1)
        self.assertGreaterEqual(sockets[1].fileno(), 0)

    def test_port_lock_directory_rejects_symlink_and_shared_write_permissions(self):
        for unsafe in ("symlink", "mode"):
            with self.subTest(unsafe=unsafe):
                target = self.make_fixture(f"unsafe-{unsafe}")
                temporary = self.root / unsafe
                temporary.mkdir(mode=0o700)
                root = temporary / f"vizor-wallet-native-e2e-{os.getuid()}"
                if unsafe == "symlink":
                    root.symlink_to(self.port_root, target_is_directory=True)
                else:
                    root.mkdir(mode=0o777)
                    root.chmod(0o777)
                with mock.patch.object(fixture.tempfile, "gettempdir", return_value=str(temporary)):
                    with self.assertRaisesRegex(fixture.FixtureError, "directory is unsafe"):
                        target._lease_loopback_port("zakura", time.monotonic() + 5)
                self.assertEqual(target._port_leases, {})

    def test_port_lock_file_rejects_unsafe_identity_without_mutating_payload(self):
        for unsafe in ("mode", "owner", "hardlink"):
            with self.subTest(unsafe=unsafe):
                target = self.make_fixture(f"unsafe-file-{unsafe}")
                reserved = mock.Mock()
                reserved.getsockname.return_value = ("127.0.0.1", 49001)
                details = mock.Mock(st_mode=0o100600, st_uid=os.getuid(), st_nlink=1)
                if unsafe == "mode": details.st_mode = 0o100666
                if unsafe == "owner": details.st_uid = os.getuid() + 1
                if unsafe == "hardlink": details.st_nlink = 2
                with mock.patch.object(fixture.socket, "socket", return_value=reserved), mock.patch.object(
                    fixture.os, "fstat", return_value=details,
                ), mock.patch.object(fixture.os, "ftruncate") as truncate:
                    with self.assertRaisesRegex(fixture.FixtureError, "file is unsafe"):
                        target._lease_loopback_port("zakura", time.monotonic() + 5)
                truncate.assert_not_called()
                reserved.close.assert_called_once()
                self.assertEqual(target._port_leases, {})

    def test_published_port_must_equal_lease_and_never_retarget(self):
        target = self.make_fixture()
        port = target._lease_loopback_port("lightwalletd", time.monotonic() + 5)
        target._lightwalletd_url = f"127.0.0.1:{port}"
        with mock.patch.object(target, "_docker", return_value=self.completed(f"127.0.0.1:{port + 1}\n")):
            with self.assertRaisesRegex(fixture.FixtureError, "owned lease"):
                target._published_port(target.lwd_name, "9067/tcp", time.monotonic() + 5)
        self.assertEqual(target._lightwalletd_url, f"127.0.0.1:{port}")

    def test_failed_create_closes_lease_after_owned_absence_is_proven(self):
        target = self.make_fixture()
        with mock.patch.object(target, "_docker", side_effect=fixture.FixtureError("port binding unavailable")):
            with self.assertRaisesRegex(fixture.FixtureError, "binding unavailable"):
                target._create_node(time.monotonic() + 5)
        lease = target._port_leases["zakura"]
        self.assertIsNone(lease.reserved)
        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
            target, "_owned_resource_id_if_present", return_value=None,
        ):
            proof = target.close()
        self.assertTrue(proof["complete"])
        self.assertEqual(lease.descriptor, -1)
        self.assertEqual(proof["port_leases"], [{"role": "zakura", "port": lease.port, "lock_released": True}])

    def test_unproven_container_cleanup_retains_lock_but_closes_socket(self):
        target = self.make_fixture()
        target._lease_loopback_port("zakura", time.monotonic() + 5)
        target._container_ids["zakura"] = "owned-node-id"
        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
            target, "_assert_owned", side_effect=fixture.FixtureError("identity changed"),
        ), mock.patch.object(target, "_docker") as docker:
            proof = target.close()
        self.assertFalse(proof["complete"])
        self.assertIsNone(target._port_leases["zakura"].reserved)
        self.assertGreaterEqual(target._port_leases["zakura"].descriptor, 0)
        self.assertFalse(proof["port_leases"][0]["lock_released"])
        docker.assert_not_called()

    def test_donor_reset_reuses_port_with_same_cooperative_lease(self):
        target = self.make_fixture()
        deadline = time.monotonic() + 5
        port = target._lease_loopback_port("zakura_donor", deadline)
        target._port_leases["zakura_donor"].handoff()
        descriptor = target._port_leases["zakura_donor"].descriptor
        target._container_ids["zakura_donor"] = "owned-donor-id"
        target._donor_rpc_url = f"http://127.0.0.1:{port}"
        with mock.patch.object(target, "_assert_owned"), mock.patch.object(
            target, "_docker", return_value=self.completed(),
        ), mock.patch.object(target, "_ensure_resource_absent"):
            target._reset_owned_donor(deadline)
        self.assertEqual(target._lease_loopback_port("zakura_donor", deadline), port)
        self.assertEqual(target._port_leases["zakura_donor"].descriptor, descriptor)
        self.assertIsNone(target._donor_rpc_url)

    def test_start_returns_ready_isolated_profile_and_is_idempotent(self):
        target = self.make_fixture(
            run_id="33333333-3333-3333-3333-333333333333",
            miner_address=fixture.LOCKBOX_ADDRESS,
            network_subnet="10.42.0.0/28",
        )
        parity = {
            "height": 1,
            "hash": HASH,
            "time": 123,
            "trees": {"sapling": "aa", "orchard": "bb", "ironwood": "cc"},
            "latest_block_hash": HASH,
            "latest_block_hash_orientation": "display",
            "chain_name": "test",
            "consensus_branch_id": fixture.NU63_BRANCH_ID,
        }
        docker_commands = []

        def docker(args, **_kwargs):
            docker_commands.append(args)
            if args[:2] == ["network", "create"]:
                return self.completed("network-id\n")
            if args[:2] == ["volume", "create"]:
                return self.completed(target.lwd_volume + "\n")
            return self.completed()

        def create_node(_deadline):
            target._container_ids["zakura"] = "node-id"

        def create_lwd(_deadline):
            target._container_ids["lightwalletd"] = "lwd-id"

        with mock.patch.object(target, "_verify_image", side_effect=lambda image, expected, deadline: {"reference": image, "id": expected}), mock.patch.object(
            target, "_ensure_resource_absent",
        ), mock.patch.object(target, "_docker", side_effect=docker), mock.patch.object(
            target, "_assert_owned", return_value={},
        ), mock.patch.object(target, "_create_node", side_effect=create_node), mock.patch.object(
            target, "_create_lightwalletd", side_effect=create_lwd,
        ), mock.patch.object(target, "_published_port", side_effect=[49100, 49200]), mock.patch.object(
            target, "_wait_node", return_value={"best_hash": HASH},
        ), mock.patch.object(target, "rpc", return_value=[HASH]), mock.patch.object(
            target, "wait_synced", return_value=parity,
        ):
            proof = target.start()
            repeated = target.start()

        self.assertIs(repeated, proof)
        self.assertEqual(proof["profile"]["name"], fixture.DIRECT_HEIGHT1_PROFILE)
        self.assertEqual(proof["profile"]["network"], "Regtest")
        self.assertEqual(proof["profile"]["nu6_3_activation_height"], 1)
        self.assertIsNone(proof["profile"]["pre_activation_consensus_branch_id"])
        self.assertEqual(
            proof["profile"]["post_activation_consensus_branch_id"],
            fixture.NU63_BRANCH_ID,
        )
        self.assertEqual(proof["profile"]["pre_activation_pools"], [])
        self.assertEqual(
            proof["profile"]["post_activation_pools"],
            ["sapling", "orchard", "ironwood"],
        )
        self.assertEqual(proof["profile"]["miner_address"], fixture.LOCKBOX_ADDRESS)
        self.assertEqual(proof["profile"]["rpc_parallel_cpu_threads"], 1)
        self.assertEqual(proof["profile"]["sync_parallel_cpu_threads"], 1)
        self.assertEqual(
            proof["profile"]["nu6_1_lockbox_disbursement"],
            {
                "address": fixture.LOCKBOX_ADDRESS,
                "amount_zatoshi": 0,
                "purpose": "structural-only-not-funding",
            },
        )
        self.assertEqual(proof["endpoints"]["node_rpc_url"], "http://127.0.0.1:49100")
        self.assertEqual(proof["endpoints"]["lightwalletd_url"], "127.0.0.1:49200")
        self.assertEqual(proof["identity"]["containers"], {"zakura": "node-id", "lightwalletd": "lwd-id"})
        self.assertEqual(json.loads((target.artifacts / "start-proof.json").read_text()), proof)
        network_create = next(command for command in docker_commands if command[:2] == ["network", "create"])
        self.assertNotIn("--internal", network_create)
        self.assertEqual(network_create[network_create.index("--subnet") + 1], "10.42.0.0/28")
        self.assertEqual(proof["identity"]["network"]["requested_subnet"], "10.42.0.0/28")
        config = target.config_path.read_text()
        self.assertIn('network = "Regtest"', config)
        self.assertIn('"NU6.3" = 1', config)
        self.assertIn("[[network.testnet_parameters.lockbox_disbursements]]", config)
        self.assertIn(f'address = "{fixture.LOCKBOX_ADDRESS}"', config)
        self.assertIn("amount = 0", config)
        self.assertIn("[sync]\nparallel_cpu_threads = 1", config)
        self.assertIn("ephemeral = false", config)
        self.assertIn(f'cache_dir = "{fixture.NODE_STATE_CACHE_DIR}"', config)
        self.assertIn("should_backup_non_finalized_state = true", config)

    def test_controlled_activation_start_proves_pre_activation_profile(self):
        target = self.make_fixture(
            "controlled-start", profile=fixture.CONTROLLED_ACTIVATION_PROFILE
        )
        parity = {
            "height": 1,
            "hash": HASH,
            "time": 123,
            "trees": {"sapling": "aa", "orchard": "bb"},
            "latest_block_hash": HASH,
            "latest_block_hash_orientation": "display",
            "chain_name": "test",
            "consensus_branch_id": fixture.NU62_BRANCH_ID,
        }

        def docker(args, **_kwargs):
            if args[:2] == ["network", "create"]:
                return self.completed("network-id\n")
            if args[:2] == ["volume", "create"]:
                return self.completed(target.lwd_volume + "\n")
            return self.completed()

        def create_node(_deadline):
            target._container_ids["zakura"] = "node-id"

        def create_lwd(_deadline):
            target._container_ids["lightwalletd"] = "lwd-id"

        with mock.patch.object(
            target,
            "_verify_image",
            side_effect=lambda image, expected, deadline: {
                "reference": image,
                "id": expected,
            },
        ), mock.patch.object(target, "_ensure_resource_absent"), mock.patch.object(
            target, "_docker", side_effect=docker
        ), mock.patch.object(target, "_assert_owned", return_value={}), mock.patch.object(
            target, "_create_node", side_effect=create_node
        ), mock.patch.object(
            target, "_create_lightwalletd", side_effect=create_lwd
        ), mock.patch.object(
            target, "_published_port", side_effect=[49100, 49200]
        ), mock.patch.object(
            target, "_wait_node", return_value={"best_hash": HASH}
        ), mock.patch.object(target, "rpc", return_value=[HASH]), mock.patch.object(
            target, "wait_synced", return_value=parity
        ):
            proof = target.start()

        self.assertEqual(proof["profile"]["name"], fixture.CONTROLLED_ACTIVATION_PROFILE)
        self.assertEqual(proof["profile"]["nu6_3_activation_height"], 500)
        self.assertEqual(
            proof["profile"]["pre_activation_consensus_branch_id"],
            fixture.NU62_BRANCH_ID,
        )
        self.assertEqual(proof["parity"]["consensus_branch_id"], fixture.NU62_BRANCH_ID)
        self.assertIn('"NU6.2" = 1\n"NU6.3" = 500', target.config_path.read_text())

    def test_miner_address_override_is_written_to_config(self):
        target = self.make_fixture(miner_address=fixture.LOCKBOX_ADDRESS)
        target._write_config()
        self.assertIn(
            f'miner_address = "{fixture.LOCKBOX_ADDRESS}"',
            target.config_path.read_text(),
        )

    def test_controlled_activation_profile_writes_exact_config_and_evidence(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        target._write_config()

        config = target.config_path.read_text()
        self.assertIn('"NU6.2" = 1\n"NU6.3" = 500', config)
        self.assertNotIn('"NU6.3" = 1', config)
        self.assertEqual(target.profile, fixture.CONTROLLED_ACTIVATION_PROFILE)
        self.assertEqual(target.nu6_3_activation_height, 500)
        self.assertEqual(
            target._profile_proof(),
            {
                "name": fixture.CONTROLLED_ACTIVATION_PROFILE,
                "network": "Regtest",
                "nu6_3_activation_height": 500,
                "pre_activation_consensus_branch_id": fixture.NU62_BRANCH_ID,
                "post_activation_consensus_branch_id": fixture.NU63_BRANCH_ID,
                "pre_activation_pools": ["sapling", "orchard"],
                "post_activation_pools": ["sapling", "orchard", "ironwood"],
                "miner_address": fixture.MINER_ADDRESS,
                "mempool_debug_enable_at_height": 0,
                "node_state_ephemeral": False,
                "node_state_cache_dir": fixture.NODE_STATE_CACHE_DIR,
                "rpc_parallel_cpu_threads": 1,
                "sync_parallel_cpu_threads": 1,
                "container_network": "bridge",
                "egress_fenced": False,
                "nu6_1_lockbox_disbursement": {
                    "address": fixture.LOCKBOX_ADDRESS,
                    "amount_zatoshi": 0,
                    "purpose": "structural-only-not-funding",
                },
            },
        )

    def test_partial_start_failure_rolls_back_only_created_resources(self):
        target = self.make_fixture()
        calls = []

        def docker(args, **_kwargs):
            calls.append(args)
            if args[:2] == ["network", "create"]:
                return self.completed("network-id\n")
            if args[:2] == ["volume", "create"]:
                raise fixture.FixtureError("volume creation failed")
            if args[:2] == ["volume", "inspect"]:
                return self.completed(stdout="[]\n",
                    stderr=f"Error response from daemon: get {target.lwd_volume}: no such volume", returncode=1)
            if args[:2] == ["network", "rm"]:
                return self.completed()
            raise AssertionError(args)

        with mock.patch.object(target, "_verify_image", side_effect=lambda image, expected, deadline: {"reference": image, "id": expected}), mock.patch.object(
            target, "_ensure_resource_absent",
        ), mock.patch.object(target, "_docker", side_effect=docker), mock.patch.object(
            target, "_assert_owned", return_value={},
        ), mock.patch.object(target, "_capture_diagnostics"):
            with self.assertRaisesRegex(fixture.FixtureError, "volume creation failed"):
                target.start()

        self.assertIn(["network", "rm", "network-id"], calls)
        self.assertFalse(any(call[:2] == ["volume", "rm"] for call in calls))
        cleanup = json.loads((target.artifacts / "cleanup-proof.json").read_text())
        self.assertTrue(cleanup["complete"])
        self.assertEqual(cleanup["removed"][0]["id"], "network-id")

    def test_ambiguous_create_failure_recovers_only_exact_owned_resource(self):
        for ownership_matches in (True, False):
            with self.subTest(ownership_matches=ownership_matches):
                target = self.make_fixture(f"ambiguous-{ownership_matches}")
                removed = []
                inspected = {
                    "Id": "network-id",
                    "Labels": target.labels if ownership_matches else {
                        fixture.OWNER_LABEL: "1",
                        fixture.RUN_LABEL: uuid.uuid4().hex,
                    },
                }

                def docker(args, **_kwargs):
                    if args[:2] == ["network", "create"]:
                        raise fixture.FixtureError("docker create timed out after daemon commit")
                    if args[:2] == ["network", "inspect"]:
                        return self.completed(json.dumps([inspected]))
                    if args[:2] == ["network", "rm"]:
                        removed.append(args[-1])
                        return self.completed()
                    raise AssertionError(args)

                with mock.patch.object(target, "_verify_image", return_value={}), mock.patch.object(
                    target, "_ensure_resource_absent",
                ), mock.patch.object(target, "_docker", side_effect=docker), mock.patch.object(
                    target, "_inspect", return_value=inspected,
                ), mock.patch.object(target, "_capture_diagnostics"):
                    with self.assertRaisesRegex(fixture.FixtureError, "daemon commit"):
                        target.start()

                cleanup = json.loads((target.artifacts / "cleanup-proof.json").read_text())
                self.assertEqual(removed, ["network-id"] if ownership_matches else [])
                self.assertEqual(cleanup["complete"], ownership_matches)

    def test_cleanup_refuses_changed_resource_identity_or_labels(self):
        for problem in ("identity", "labels"):
            with self.subTest(problem=problem):
                target = self.make_fixture(f"artifacts-{problem}")
                target._network_id = "created-network-id"
                inspected = {
                    "Id": "other-network-id" if problem == "identity" else "created-network-id",
                    "Labels": target.labels if problem == "identity" else {fixture.OWNER_LABEL: "0", fixture.RUN_LABEL: target.run_id},
                }
                with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
                    target, "_inspect", return_value=inspected,
                ), mock.patch.object(target, "_docker") as docker:
                    proof = target.close()

                self.assertFalse(proof["complete"])
                self.assertEqual(proof["removed"], [])
                self.assertEqual(len(proof["errors"]), 1)
                docker.assert_not_called()

    def test_retain_stops_exact_owned_ids_without_deleting_state_or_unlocking_ports(self):
        target = self.make_fixture()
        target._network_id = "network-id"
        target._volume_name = target.lwd_volume
        target._container_ids = {"zakura": "node-id", "lightwalletd": "lwd-id", "zakura_donor": "donor-id"}
        for role in target._container_ids:
            target._lease_loopback_port(role, time.monotonic() + 5)
        evidence = target.artifacts / "failure.txt"
        evidence.write_bytes(b"original failure")
        ids = {target.node_name: "node-id", target.lwd_name: "lwd-id", target.donor_name: "donor-id"}
        commands = []

        def inspect(_kind, name, _deadline):
            return {"Id": ids[name], "Config": {"Labels": target.labels},
                    "State": {"Running": False, "Paused": False, "Restarting": False, "Pid": 0}}

        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(target, "_inspect", side_effect=inspect), mock.patch.object(
            target, "_docker", side_effect=lambda command, **kw: commands.append(command) or self.completed()
        ):
            proof = target.retain()
            self.assertIs(target.retain(), proof)
            for operation in (target.start, target.close, lambda: target.mine(1), target.wait_synced,
                              lambda: target.rpc("generate", [1]), lambda: target.grpc("GetLightdInfo"),
                              lambda: target.grpc_stream("GetBlockRange")):
                with self.assertRaisesRegex(fixture.FixtureError, "retained"):
                    operation()

        self.assertTrue(proof["complete"])
        self.assertEqual(commands, [["stop", "--time", "5", value] for value in ("donor-id", "lwd-id", "node-id")])
        self.assertEqual(proof["identity"]["containers"], target._container_ids)
        self.assertEqual(evidence.read_bytes(), b"original failure")
        self.assertEqual(json.loads((target.artifacts / "retention-proof.json").read_text()), proof)
        self.assertTrue(all(lease.descriptor >= 0 and lease.reserved is None for lease in target._port_leases.values()))
        self.assertFalse(target._closed)

    def test_retain_refuses_changed_identity_or_labels_before_stop(self):
        for changed in ("identity", "labels"):
            with self.subTest(changed=changed):
                target = self.make_fixture(f"retain-{changed}")
                target._container_ids["zakura"] = "original-id"
                target._lease_loopback_port("zakura", time.monotonic() + 5)
                inspected = {"Id": "replacement-id" if changed == "identity" else "original-id",
                             "Config": {"Labels": {} if changed == "labels" else target.labels}}
                with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(target, "_inspect", return_value=inspected), mock.patch.object(target, "_docker") as docker:
                    proof = target.retain()
                    self.assertIs(target.retain(), proof)
                    docker.assert_not_called()
                self.assertFalse(proof["complete"])
                self.assertEqual(proof["stopped"], [])
                self.assertTrue(target._port_leases["zakura"].descriptor >= 0)
                with self.assertRaisesRegex(fixture.FixtureError, "retained"):
                    target.close()

    def test_retain_requires_post_stop_owned_identity_and_process_absence(self):
        for changed in ("identity", "running", "paused", "restarting", "pid", "malformed"):
            with self.subTest(changed=changed):
                target = self.make_fixture(f"post-stop-{changed}")
                target._container_ids["zakura"] = "node-id"
                before = {"Id": "node-id", "Config": {"Labels": target.labels}, "State": {"Running": True}}
                after = {"Id": "node-id", "Config": {"Labels": target.labels},
                         "State": {"Running": False, "Paused": False, "Restarting": False, "Pid": 0}}
                if changed == "identity":
                    after["Id"] = "replacement-id"
                elif changed == "malformed":
                    after["State"] = {}
                else:
                    after["State"][{"running": "Running", "paused": "Paused", "restarting": "Restarting", "pid": "Pid"}[changed]] = 42 if changed == "pid" else True
                with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(target, "_inspect", side_effect=[before, after]), mock.patch.object(target, "_docker", return_value=self.completed()) as docker:
                    proof = target.retain()
                self.assertFalse(proof["complete"])
                self.assertEqual(proof["stopped"], [])
                self.assertEqual(docker.call_args.args[0], ["stop", "--time", "5", "node-id"])

    def test_retain_continues_owned_stops_after_failure_without_retry_or_deletion(self):
        target = self.make_fixture()
        target._container_ids = {"zakura": "node-id", "lightwalletd": "lwd-id"}
        ids = {target.node_name: "node-id", target.lwd_name: "lwd-id"}
        commands = []

        def inspect(_kind, name, _deadline):
            return {"Id": ids[name], "Config": {"Labels": target.labels},
                    "State": {"Running": False, "Paused": False, "Restarting": False, "Pid": 0}}

        def docker(command, **_kwargs):
            commands.append(command)
            if command[-1] == "lwd-id":
                raise fixture.FixtureError("stop timed out")
            return self.completed()

        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(target, "_inspect", side_effect=inspect), mock.patch.object(target, "_docker", side_effect=docker):
            first = target.retain()
            second = target.retain()
        self.assertIs(first, second)
        self.assertFalse(first["complete"])
        self.assertEqual(first["stopped"], [{"role": "zakura", "name": target.node_name, "id": "node-id"}])
        self.assertEqual(len(commands), 2)
        self.assertIn("stop timed out", first["errors"][0])

    def test_retain_recovers_only_original_run_attempted_container(self):
        target = self.make_fixture()
        target._attempted_resources.add(("container", target.node_name))
        inspected = {"Id": "ambiguous-id", "Config": {"Labels": target.labels},
                     "State": {"Running": False, "Paused": False, "Restarting": False, "Pid": 0}}
        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(target, "_owned_resource_id_if_present", return_value="ambiguous-id"), mock.patch.object(
            target, "_inspect", return_value=inspected
        ), mock.patch.object(target, "_docker", return_value=self.completed()) as docker:
            proof = target.retain()
        self.assertTrue(proof["complete"])
        self.assertEqual(docker.call_args.args[0], ["stop", "--time", "5", "ambiguous-id"])
        self.assertEqual(target._container_ids["zakura"], "ambiguous-id")

    def test_retention_report_failure_is_terminal_not_a_success_or_retry(self):
        target = self.make_fixture()
        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(target, "_write_json", side_effect=OSError("evidence unavailable")) as write:
            proof = target.retain()
            self.assertIs(target.retain(), proof)
        self.assertFalse(proof["complete"])
        self.assertIn("evidence unavailable", proof["errors"][0])
        write.assert_called_once()
        with self.assertRaisesRegex(fixture.FixtureError, "retained"):
            target.close()

    def test_expired_or_zero_deadline_fails_without_external_calls(self):
        target = self.make_fixture()
        target._node_rpc_url = "http://127.0.0.1:49001"
        target._lightwalletd_url = "127.0.0.1:49000"
        target._container_ids = {"zakura": "node-id", "lightwalletd": "lwd-id"}
        for deadline in (0, time.monotonic() - 1):
            for operation in (
                lambda: target.rpc("getblockcount", deadline=deadline),
                lambda: target.rpc("generate", [650], deadline=deadline),
                lambda: target.grpc("GetLightdInfo", deadline=deadline),
                lambda: target.grpc_stream("GetAddressUtxosStream", deadline=deadline),
                lambda: target.wait_synced(deadline=deadline),
            ):
                with self.subTest(deadline=deadline, operation=operation):
                    with mock.patch.object(target, "_run") as run, mock.patch.object(
                        fixture.urllib.request, "urlopen",
                    ) as urlopen:
                        with self.assertRaisesRegex(fixture.FixtureError, "timed out"):
                            operation()
                    run.assert_not_called()
                    urlopen.assert_not_called()

    def test_generate_rpc_uses_existing_operation_budget_for_main_and_donor(self):
        target = self.make_fixture(timeout=60)
        target._node_rpc_url = "http://127.0.0.1:49001"
        target._donor_rpc_url = "http://127.0.0.1:49003"
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            "id": target.run_id, "result": [HASH],
        }).encode()
        for rpc_call, expected_url in ((target.rpc, target._node_rpc_url),
                                       (target._donor_rpc, target._donor_rpc_url)):
            with self.subTest(url=expected_url), mock.patch.object(
                fixture.time, "monotonic", return_value=100,
            ), mock.patch.object(fixture.urllib.request, "urlopen", return_value=response) as urlopen:
                self.assertEqual(rpc_call("generate", [650], deadline=160), [HASH])
            urlopen.assert_called_once()
            request = urlopen.call_args.args[0]
            self.assertEqual(request.full_url, expected_url)
            self.assertEqual(json.loads(request.data), {
                "jsonrpc": "2.0", "id": target.run_id, "method": "generate", "params": [650],
            })
            self.assertEqual(urlopen.call_args.kwargs["timeout"], 60)

    def test_generate_default_and_short_budget_keep_read_rpc_five_second_cap(self):
        target = self.make_fixture(timeout=60)
        target._node_rpc_url = "http://127.0.0.1:49001"
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({
            "id": target.run_id, "result": 1,
        }).encode()
        for method, deadline, expected_timeout in (
            ("generate", None, 60), ("generate", 100.25, 0.25),
            ("getblockcount", None, 5), ("getblockcount", 100.25, 0.25),
        ):
            with self.subTest(method=method, deadline=deadline), mock.patch.object(
                fixture.time, "monotonic", return_value=100,
            ), mock.patch.object(fixture.urllib.request, "urlopen", return_value=response) as urlopen:
                target.rpc(method, [650] if method == "generate" else [], deadline=deadline)
            self.assertEqual(urlopen.call_args.kwargs["timeout"], expected_timeout)

    def test_generate_timeout_and_node_rejection_fail_without_mutation_retry(self):
        target = self.make_fixture(timeout=60)
        target._node_rpc_url = "http://127.0.0.1:49001"
        rejected = mock.MagicMock()
        rejected.__enter__.return_value.read.return_value = json.dumps({
            "id": target.run_id, "error": {"code": -8, "message": "rejected"},
        }).encode()
        for error, response, message in ((TimeoutError("timed out"), None, "RPC generate failed"),
                                         (None, rejected, "RPC generate returned an error")):
            with self.subTest(message=message), mock.patch.object(
                fixture.time, "monotonic", return_value=100,
            ), mock.patch.object(fixture.urllib.request, "urlopen", side_effect=error,
                                 return_value=response) as urlopen:
                with self.assertRaisesRegex(fixture.FixtureError, message):
                    target.rpc("generate", [650], deadline=160)
            urlopen.assert_called_once()

    def test_mine_generation_and_parity_share_original_operation_deadline(self):
        target = self.make_fixture(timeout=60)
        tip = {"height": 3, "hash": OTHER_HASH}
        with mock.patch.object(fixture.time, "monotonic", return_value=100), mock.patch.object(
            target, "rpc", side_effect=[1, [HASH, OTHER_HASH]],
        ) as rpc, mock.patch.object(target, "wait_synced", return_value=tip) as wait_synced:
            target.mine(2)
        self.assertEqual(rpc.call_args_list, [mock.call("getblockcount", deadline=160),
                                             mock.call("generate", [2], deadline=160)])
        wait_synced.assert_called_once_with(deadline=160)

    def test_rpc_and_grpc_validate_response_identity_and_commands(self):
        target = self.make_fixture()
        target._node_rpc_url = "http://127.0.0.1:49001"
        target._lightwalletd_url = "127.0.0.1:49002"
        bad_response = mock.MagicMock()
        bad_response.__enter__.return_value.read.return_value = json.dumps({
            "id": "wrong",
            "result": {},
        }).encode()
        with mock.patch.object(fixture.urllib.request, "urlopen", return_value=bad_response):
            with self.assertRaisesRegex(fixture.FixtureError, "invalid response identity"):
                target.rpc("getblockchaininfo")

        with mock.patch.object(target, "_run", return_value=self.completed('{"chainName":"test"}')) as run:
            result = target.grpc("GetLightdInfo")
        self.assertEqual(result, {"chainName": "test"})
        command = run.call_args.args[0]
        self.assertEqual(command[0], str(self.grpcurl.resolve()))
        self.assertIn("-plaintext", command)
        self.assertNotIn("-emit-defaults", command)
        self.assertIn("127.0.0.1:49002", command)
        self.assertEqual(command[-1], f"{fixture.GRPC_SERVICE}/GetLightdInfo")

    def test_grpc_stream_decodes_empty_single_and_concatenated_objects(self):
        target = self.make_fixture()
        target._lightwalletd_url = "127.0.0.1:49002"
        cases = (
            (" \n\t", []),
            ('{"txid":"aa"}', [{"txid": "aa"}]),
            (
                '{\n  "txid": "aa"\n}\n{\n  "txid": "bb",\n  "height": 3\n}\n',
                [{"txid": "aa"}, {"txid": "bb", "height": 3}],
            ),
        )
        for index, (stdout, expected) in enumerate(cases):
            with self.subTest(index=index), mock.patch.object(
                target, "_run", return_value=self.completed(stdout)
            ) as run:
                result = target.grpc_stream(
                    "GetTaddressTxids", {"address": "tmTest", "startHeight": 1}
                )
            self.assertEqual(result, expected)
            command = run.call_args.args[0]
            self.assertEqual(command[0], str(self.grpcurl.resolve()))
            self.assertIn("-emit-defaults", command)
            self.assertEqual(
                command[-1], f"{fixture.GRPC_SERVICE}/GetTaddressTxids"
            )
            self.assertEqual(
                json.loads(command[command.index("-d") + 1]),
                {"address": "tmTest", "startHeight": 1},
            )
            self.assertGreater(float(command[command.index("-max-time") + 1]), 0)

    def test_grpc_stream_rejects_invalid_arguments_and_outputs(self):
        target = self.make_fixture()
        target._lightwalletd_url = "127.0.0.1:49002"
        with mock.patch.object(target, "_run") as run:
            for method, payload in (("", {}), ("Service/Method", {}), ("Method", [])):
                with self.subTest(method=method, payload=payload):
                    with self.assertRaises(fixture.FixtureError):
                        target.grpc_stream(method, payload)
            run.assert_not_called()

        for stdout, message in (
            ('{"txid":"aa"', "invalid JSON"),
            ('{"txid":"aa"} trailing', "invalid JSON"),
            ("[]", "non-object"),
            ('{"txid":"aa"}\n42', "non-object"),
        ):
            with self.subTest(stdout=stdout), mock.patch.object(
                target, "_run", return_value=self.completed(stdout)
            ):
                with self.assertRaisesRegex(fixture.FixtureError, message):
                    target.grpc_stream("GetAddressUtxosStream")

    def test_grpc_stream_enforces_byte_and_message_limits(self):
        target = self.make_fixture()
        target._lightwalletd_url = "127.0.0.1:49002"

        with mock.patch.object(
            fixture, "MAX_GRPC_STREAM_RESPONSE_BYTES", 7
        ), mock.patch.object(
            target, "_run", return_value=self.completed('{"a":1} ')
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "exceeded 7 bytes"):
                target.grpc_stream("GetAddressUtxosStream")

        multibyte = '{"a":"é"}'
        self.assertEqual(len(multibyte), 9)
        self.assertEqual(len(multibyte.encode("utf-8")), 10)
        with mock.patch.object(
            fixture, "MAX_GRPC_STREAM_RESPONSE_BYTES", 9
        ), mock.patch.object(target, "_run", return_value=self.completed(multibyte)):
            with self.assertRaisesRegex(fixture.FixtureError, "exceeded 9 bytes"):
                target.grpc_stream("GetAddressUtxosStream")

        with mock.patch.object(
            fixture, "MAX_GRPC_STREAM_MESSAGES", 1
        ), mock.patch.object(
            target, "_run", return_value=self.completed('{"a":1}{"b":2}')
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "exceeded 1 messages"):
                target.grpc_stream("GetAddressUtxosStream")

    def test_parity_accepts_exact_tip_hash_time_trees_and_nu63(self):
        target = self.make_fixture()
        rpc, grpc = self.parity_responses()
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "grpc", side_effect=grpc,
        ):
            proof = target._parity_once(time.monotonic() + 5)

        self.assertEqual(proof["height"], 3)
        self.assertEqual(proof["hash"], HASH)
        self.assertEqual(proof["time"], 123)
        self.assertEqual(proof["trees"], {"sapling": "aa", "orchard": "bb", "ironwood": "cc"})
        self.assertEqual(proof["consensus_branch_id"], fixture.NU63_BRANCH_ID)

    def test_controlled_activation_parity_switches_exact_branch_and_pools_at_500(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        cases = (
            (
                499,
                fixture.NU62_BRANCH_ID,
                {"sapling": "aa", "orchard": "bb"},
            ),
            (
                500,
                fixture.NU63_BRANCH_ID,
                {"sapling": "aa", "orchard": "bb", "ironwood": "cc"},
            ),
        )
        for height, branch, expected_trees in cases:
            with self.subTest(height=height):
                rpc, grpc = self.parity_responses(height=height, branch=branch)
                with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
                    target, "grpc", side_effect=grpc,
                ):
                    proof = target._parity_once(time.monotonic() + 5)
                self.assertEqual(proof["height"], height)
                self.assertEqual(proof["consensus_branch_id"], branch)
                self.assertEqual(proof["trees"], expected_trees)

        rpc, grpc = self.parity_responses(
            height=499, branch=fixture.NU63_BRANCH_ID
        )
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "grpc", side_effect=grpc,
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "NU6.2"):
                target._parity_once(time.monotonic() + 5)

    def test_parity_rejects_height_hash_tree_branch_and_network_mismatches(self):
        cases = {
            "height": {"info": {"blockHeight": 2, "chainName": "test", "consensusBranchId": fixture.NU63_BRANCH_ID}},
            "hash": {"latest": {"height": 3, "hash": base64.b64encode(bytes.fromhex(OTHER_HASH)).decode("ascii")}},
            "tree": {"tree": {"height": 3, "hash": HASH, "time": 123, "network": "test", "saplingTree": "aa", "orchardTree": "wrong", "ironwoodTree": "cc"}},
            "branch": {"info": {"blockHeight": 3, "chainName": "test", "consensusBranchId": "deadbeef"}},
            "network": {"info": {"blockHeight": 3, "chainName": "main", "consensusBranchId": fixture.NU63_BRANCH_ID}},
        }
        for name, overrides in cases.items():
            with self.subTest(name=name):
                target = self.make_fixture(f"parity-{name}")
                rpc, grpc = self.parity_responses(**overrides)
                with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
                    target, "grpc", side_effect=grpc,
                ):
                    with self.assertRaises(fixture.FixtureError):
                        target._parity_once(time.monotonic() + 5)

    def test_parity_rejects_trees_missing_from_both_responses(self):
        target = self.make_fixture()
        node_tree = {"height": 3, "hash": HASH, "time": 123, "sapling": {"commitments": {}}}
        lwd_tree = {"height": 3, "hash": HASH, "time": 123, "network": "test"}
        rpc, grpc = self.parity_responses(node_tree=node_tree, tree=lwd_tree)
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "grpc", side_effect=grpc,
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "tree|commitments|finalState"):
                target._parity_once(time.monotonic() + 5)

    def test_mine_rejects_invalid_counts_and_records_verified_tip(self):
        target = self.make_fixture()
        for count in (True, 0, -1, 1.5):
            with self.subTest(count=count):
                with self.assertRaisesRegex(fixture.FixtureError, "positive integer"):
                    target.mine(count)

        tip = {"height": 3, "hash": OTHER_HASH}
        with mock.patch.object(target, "rpc", side_effect=[1, [HASH, OTHER_HASH]]) as rpc, mock.patch.object(
            target, "wait_synced", return_value=tip,
        ):
            result = target.mine(2)

        self.assertEqual(
            rpc.call_args_list,
            [
                mock.call("getblockcount", deadline=mock.ANY),
                mock.call("generate", [2], deadline=mock.ANY),
            ],
        )
        self.assertEqual(result, {"hashes": [HASH, OTHER_HASH], "tip": tip})
        self.assertEqual(json.loads((target.artifacts / "mine-3.json").read_text()), result)

    def test_mine_rejects_stale_height_or_unrelated_generated_tip(self):
        for name, tip in (
            ("stale-height", {"height": 10, "hash": HASH}),
            ("wrong-tip", {"height": 11, "hash": OTHER_HASH}),
        ):
            with self.subTest(name=name):
                target = self.make_fixture(f"mine-{name}")
                with mock.patch.object(
                    target, "rpc", side_effect=[10, [HASH]],
                ), mock.patch.object(target, "wait_synced", return_value=tip):
                    with self.assertRaisesRegex(fixture.FixtureError, "height|generated block"):
                        target.mine(1)

    def test_reorg_txid_contract_and_state_transitions_fail_closed(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        valid = "ab" * 32
        self.assertEqual(target._validated_txids([valid]), [valid])
        for invalid in (
            [],
            [valid, valid],
            ["AB" * 32],
            ["ab"],
            ["ab" * 32] * 9,
            "not-a-list",
        ):
            with self.subTest(invalid=invalid):
                with self.assertRaises(fixture.FixtureError):
                    target._validated_txids(invalid)

        for state in ("running", "held", "failed"):
            with self.subTest(state=state):
                target._reorg_state = state
                with self.assertRaisesRegex(fixture.FixtureError, state):
                    target.mine(1)
        target._reorg_state = "held"
        with self.assertRaisesRegex(fixture.FixtureError, "no held|differs"):
            target.release_held_transactions([valid])

    def test_replace_tip_holding_proves_donor_fork_and_release(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        target._started = True
        target._node_rpc_url = "http://127.0.0.1:18232"
        required = "ab" * 32
        reintroduced = "bc" * 32
        old_hash = "11" * 32
        fork_hash = "22" * 32
        first_replacement = "33" * 32
        second_replacement = "44" * 32
        genesis = "55" * 32
        held = {required: "aa", reintroduced: "bb"}
        before = {
            "height": 501,
            "hash": old_hash,
            "trees": {"sapling": "s", "orchard": "o", "ironwood": "i"},
        }
        after = {
            "height": 502,
            "hash": second_replacement,
            "trees": {"sapling": "s2", "orchard": "o2", "ironwood": "i2"},
        }
        main_tree = {"height": 499, "hash": fork_hash}
        submitted_main = []

        def main_rpc(method, params=None, **_kwargs):
            params = params or []
            if method == "getblockhash":
                height = params[0]
                if height == 0:
                    return genesis
                if height == 501 and submitted_main:
                    return first_replacement
                if height == 502:
                    return second_replacement
                return fork_hash
            if method == "getblock":
                return "aa"
            if method == "z_gettreestate":
                return main_tree
            if method == "invalidateblock":
                return None
            if method == "submitblock":
                submitted_main.append(params[0])
                return None
            raise AssertionError((method, params))

        def donor_rpc(method, params=None, **_kwargs):
            params = params or []
            if method in {"getpeerinfo", "getrawmempool"}:
                return []
            if method == "getblockhash":
                return genesis
            if method == "submitblock":
                return None
            if method == "getbestblockhash":
                return fork_hash
            if method == "z_gettreestate":
                return main_tree
            if method == "generate":
                return [first_replacement, second_replacement]
            if method == "getblock":
                if params[1] == 0:
                    return "cc"
                previous = fork_hash if params[0] == first_replacement else first_replacement
                height = 501 if params[0] == first_replacement else 502
                return {
                    "hash": params[0],
                    "height": height,
                    "previousblockhash": previous,
                    "tx": [
                        {
                            "txid": genesis,
                            "vin": [{"coinbase": "00"}],
                        }
                    ],
                }
            raise AssertionError((method, params))

        with (
            mock.patch.object(target, "rpc", side_effect=main_rpc),
            mock.patch.object(
                target, "_donor_rpc", side_effect=donor_rpc
            ) as donor_rpc_mock,
            mock.patch.object(
                target,
                "_ensure_donor",
                return_value={"name": target.donor_name, "id": "donor-id"},
            ),
            mock.patch.object(target, "wait_synced", side_effect=[before, after]),
            mock.patch.object(
                target, "_mempool_raw", side_effect=[{required: "aa"}, held, held]
            ),
            mock.patch.object(target, "_wait_invalidated_mempool", return_value=held),
            mock.patch.object(
                target,
                "_block_transactions",
                side_effect=[{reintroduced: "bb"}, {}, {}],
            ),
        ):
            result = target.replace_tip_holding([required], deadline=time.monotonic() + 5)

        self.assertEqual(result["fork_height"], 500)
        self.assertEqual(result["new_tip_height"], 502)
        self.assertEqual(result["replacement_hashes"], [first_replacement, second_replacement])
        self.assertEqual(result["held_txids"], sorted(held))
        self.assertEqual(result["reintroduced_txids"], [reintroduced])
        self.assertEqual(target._reorg_state, "held")
        self.assertEqual(len(submitted_main), 2)
        self.assertEqual(
            sum(call.args[0] == "getpeerinfo" for call in donor_rpc_mock.call_args_list),
            2,
        )
        self.assertEqual(
            sum(
                call.args[0] == "getrawmempool"
                for call in donor_rpc_mock.call_args_list
            ),
            2,
        )
        proof = json.loads((target.artifacts / "reorg-hold-proof.json").read_text())
        self.assertEqual(proof["donor"]["id"], "donor-id")
        self.assertEqual(set(proof["held_raw_sha256"]), set(held))

        with mock.patch.object(target, "_mempool_raw", return_value=held), mock.patch.object(
            target, "wait_synced", return_value=after,
        ):
            released = target.release_held_transactions(
                sorted(held), deadline=time.monotonic() + 5
            )
        self.assertEqual(released["released_txids"], sorted(held))
        self.assertEqual(released["tip_height"], 502)
        self.assertEqual(target._reorg_state, "released")
        with self.assertRaisesRegex(fixture.FixtureError, "no held"):
            target.release_held_transactions(sorted(held))

    def test_reorg_requires_tip_above_activation_height(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        target._started = True
        target._node_rpc_url = "http://127.0.0.1:18232"
        with mock.patch.object(
            target,
            "wait_synced",
            return_value={"height": 500, "hash": HASH},
        ):
            with self.assertRaisesRegex(
                fixture.FixtureError, "post-activation fork parent"
            ):
                target.replace_tip_holding(["ab" * 32])
        self.assertEqual(target._reorg_state, "failed")

    def test_explicit_reorg_preserves_every_invalidated_branch_and_longer_fork(self):
        for profile, fork, depth, branch_transactions, surviving_pending in (
            (fixture.DIRECT_HEIGHT1_PROFILE, 100, 5, True, True),
            (fixture.CONTROLLED_ACTIVATION_PROFILE, 500, 13, True, True),
            (fixture.DIRECT_HEIGHT1_PROFILE, 100, 2, False, True),
            (fixture.DIRECT_HEIGHT1_PROFILE, 100, 2, False, False),
        ):
            with self.subTest(profile=profile):
                target = self.make_fixture(profile, profile=profile)
                target._started = True
                if profile == fixture.CONTROLLED_ACTIVATION_PROFILE:
                    target._explicit_reorg = True
                    target._explicit_reorg_count = 1
                    target._reorg_state = "released"
                required = "ab" * 32
                branch = [f"{height:064x}" for height in range(fork + 1, fork + depth + 1)]
                replacement = [f"{10000 + index:064x}" for index in range(depth + 1)]
                fork_hash = "ff" * 32
                before = {"height": fork + depth, "hash": branch[-1]}
                after = {"height": fork + depth + 1, "hash": replacement[-1]}
                submitted = []
                invalidated = []
                branch_raw = ({block_hash: f"{index + 1:02x}" for index, block_hash in enumerate(branch)}
                              if branch_transactions else {})
                held = dict(branch_raw, **({required: "aa"} if surviving_pending else {}))

                def main_rpc(method, params=None, **_kwargs):
                    params = params or []
                    if method == "getpeerinfo":
                        return []
                    if method == "getblockhash":
                        height = params[0]
                        if height == 0:
                            return HASH
                        if height > fork and submitted:
                            return replacement[height - fork - 1]
                        return branch[height - fork - 1] if height > fork else fork_hash
                    if method == "getblock":
                        return "aa"
                    if method == "z_gettreestate":
                        return {"height": fork, "hash": fork_hash}
                    if method == "invalidateblock":
                        invalidated.append(params[0])
                        return None
                    if method == "submitblock":
                        submitted.append(params[0])
                        return None
                    raise AssertionError((method, params))

                def donor_rpc(method, params=None, **_kwargs):
                    params = params or []
                    if method in {"getpeerinfo", "getrawmempool"}:
                        return []
                    if method == "getblockhash":
                        return HASH
                    if method == "getbestblockhash":
                        return fork_hash
                    if method == "z_gettreestate":
                        return {"height": fork, "hash": fork_hash}
                    if method == "submitblock":
                        return None
                    if method == "generate":
                        self.assertEqual(params, [depth + 1])
                        return replacement
                    if method == "getblock":
                        if params[1] == 0:
                            return "cc"
                        index = replacement.index(params[0])
                        return {"hash": params[0], "height": fork + index + 1,
                                "previousblockhash": fork_hash if index == 0 else replacement[index - 1],
                                "tx": [{"txid": HASH, "vin": [{"coinbase": "00"}]}]}
                    raise AssertionError((method, params))

                def transactions(_rpc, block_hash, _deadline):
                    return {block_hash: branch_raw[block_hash]} if block_hash in branch_raw else {}

                with (
                    mock.patch.object(target, "rpc", side_effect=main_rpc),
                    mock.patch.object(target, "_donor_rpc", side_effect=donor_rpc),
                    mock.patch.object(target, "_ensure_donor", return_value={"id": "owned-donor"}),
                    mock.patch.object(target, "_reset_owned_donor") as reset_donor,
                    mock.patch.object(target, "wait_synced", side_effect=[before, after]),
                    mock.patch.object(target, "_mempool_raw", side_effect=[{required: "aa"}] + [held] * (depth + 1)),
                    mock.patch.object(target, "_restore_invalidated_mempool", return_value=(held, {"natural_txids": sorted(held), "resubmitted_txids": []})) as reverified,
                    mock.patch.object(target, "_block_transactions", side_effect=transactions),
                ):
                    required_txids = [required] if branch_transactions else []
                    result = target.replace_fork_holding(required_txids, fork_height=fork)
                self.assertEqual(invalidated, [branch[0]])
                self.assertEqual(len(submitted), depth + 1)
                self.assertEqual(result["invalidated_hash"], branch[0])
                self.assertEqual(result["reintroduced_txids"], sorted(branch_raw))
                self.assertEqual(reverified.call_args.args[4], branch_raw)
                self.assertEqual(reverified.call_args.args[2], required_txids)
                expected_count = 2 if profile == fixture.CONTROLLED_ACTIVATION_PROFILE else 1
                self.assertEqual(reset_donor.call_count, expected_count - 1)
                proof = json.loads((target.artifacts / f"reorg-hold-{expected_count}.json").read_text())
                self.assertEqual(proof["invalidated_branch_hashes"], branch)
                self.assertEqual(set(proof["invalidated_branch_raw_sha256"]), set(branch_raw))
                if not held:
                    self.assertEqual(result["held_txids"], [])
                    self.assertEqual(target._reorg_state, "released")
                    self.assertEqual(target._explicit_release_count, 0)
                    self.assertFalse(list(target.artifacts.glob("reorg-release-*.json")))
                    # A subsequent hold reaches the owned donor reset rather
                    # than failing its admission guard or inventing a release.
                    with (
                        mock.patch.object(target, "wait_synced", return_value=before),
                        mock.patch.object(target, "rpc", side_effect=main_rpc),
                        mock.patch.object(target, "_mempool_raw", return_value={}),
                        mock.patch.object(target, "_block_transactions", return_value={}),
                        mock.patch.object(target, "_reset_owned_donor") as next_reset,
                        mock.patch.object(target, "_ensure_donor", side_effect=fixture.FixtureError("next owned donor stage")),
                    ):
                        with self.assertRaisesRegex(fixture.FixtureError, "next owned donor stage"):
                            target.replace_fork_holding([], fork_height=fork)
                    next_reset.assert_called_once()

    def test_explicit_reorg_bounds_and_two_hold_limit_before_mutation(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        target._started = True
        for fork in (True, 499, 10_001, 500.0):
            with self.subTest(fork=fork), mock.patch.object(target, "rpc") as rpc:
                with self.assertRaisesRegex(fixture.FixtureError, "fork height"):
                    target.replace_fork_holding(["ab" * 32], fork_height=fork)
                rpc.assert_not_called()
        for state, count in (("held", 1), ("released", 2), ("failed", 1)):
            target._reorg_state = state
            target._explicit_reorg = True
            target._explicit_reorg_count = count
            with self.assertRaisesRegex(fixture.FixtureError, "at most two"):
                target.replace_fork_holding(["ab" * 32], fork_height=500)
        target._reorg_state = "ready"
        target._explicit_reorg_count = 0
        with mock.patch.object(target, "wait_synced", return_value={"height": 1013, "hash": HASH}):
            with self.assertRaisesRegex(fixture.FixtureError, "depth"):
                target.replace_fork_holding(["ab" * 32], fork_height=500)
        self.assertEqual(target._reorg_state, "failed")

    def test_empty_explicit_required_does_not_weaken_other_nonempty_contracts(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        with mock.patch.object(target, "rpc") as rpc:
            for operation in (target.replace_tip_holding, target.hold_pending_transactions,
                              target.release_held_transactions):
                with self.subTest(operation=operation.__name__):
                    with self.assertRaisesRegex(fixture.FixtureError, "1.."):
                        operation([])
            rpc.assert_not_called()

    def test_explicit_subset_release_preserves_gate_until_all_released(self):
        target = self.make_fixture()
        first, second = "ab" * 32, "bc" * 32
        target._explicit_reorg = True
        target._explicit_reorg_count = 1
        target._reorg_state = "held"
        target._held_transactions = {first: "aa", second: "bb"}
        with mock.patch.object(target, "_mempool_raw", side_effect=[{first: "aa", second: "bb"}, {second: "bb"}]), mock.patch.object(target, "wait_synced", return_value={"height": 514, "hash": HASH}):
            target.release_held_transactions([first])
            self.assertEqual(target._reorg_state, "held")
            # Original migration tests release denominations first, then the
            # complete held set including already-mined denominations.
            target.release_held_transactions([first, second])
            self.assertEqual(target._reorg_state, "released")
        with mock.patch.object(target, "_mempool_raw", return_value={}), mock.patch.object(target, "wait_synced", return_value={"height": 524, "hash": HASH}):
            count = target._explicit_release_count
            proofs = sorted(target.artifacts.glob("reorg-release-*.json"))
            target.release_held_transactions([second])
            target.release_held_transactions([first, second])
            self.assertEqual(target._explicit_release_count, count)
            self.assertEqual(sorted(target.artifacts.glob("reorg-release-*.json")), proofs)
            self.assertEqual(target._reorg_state, "released")
        with self.assertRaisesRegex(fixture.FixtureError, "captured held subset"):
            target.release_held_transactions(["cd" * 32])

    def test_explicit_repeat_subset_release_does_not_advance_gate(self):
        target = self.make_fixture()
        first, second = "ab" * 32, "bc" * 32
        target._explicit_reorg = True
        target._explicit_reorg_count = 1
        target._reorg_state = "held"
        target._held_transactions = {first: "aa", second: "bb"}
        with mock.patch.object(target, "_mempool_raw", side_effect=[{first: "aa", second: "bb"}, {second: "bb"}]), mock.patch.object(target, "wait_synced", return_value={"height": 514, "hash": HASH}):
            target.release_held_transactions([first])
            proof = (target.artifacts / "reorg-release-1-1.json").read_bytes()
            target.release_held_transactions([first])
            self.assertEqual(target._explicit_release_count, 1)
            self.assertEqual(target._released_transactions, {first})
            self.assertEqual(target._reorg_state, "held")
            self.assertEqual((target.artifacts / "reorg-release-1-1.json").read_bytes(), proof)
            self.assertFalse((target.artifacts / "reorg-release-1-2.json").exists())

    def test_held_safe_mine_proves_released_bytes_and_rejects_held_inclusion(self):
        for include_held in (False, True):
            with self.subTest(include_held=include_held):
                target = self.make_fixture(f"held-safe-{include_held}")
                held, released = "ab" * 32, "bc" * 32
                target._explicit_reorg = True
                target._reorg_state = "held"
                target._held_transactions = {held: "aa", released: "bb"}
                target._released_transactions = {released}
                before, after = {"height": 100, "hash": HASH}, {"height": 101, "hash": OTHER_HASH}
                committed = {HASH: "dd", released: "bb", **({held: "aa"} if include_held else {})}

                def donor_rpc(method, params=None, **_kwargs):
                    if method == "getpeerinfo": return []
                    if method == "sendrawtransaction": return released
                    if method == "generate": return [OTHER_HASH]
                    if method == "getblock":
                        if params[1] == 0: return "cc"
                        return {"hash": OTHER_HASH, "height": 101, "previousblockhash": HASH,
                                "tx": [{"txid": HASH, "vin": [{"coinbase": "00"}]}]}
                    raise AssertionError(method)

                with (
                    mock.patch.object(target, "rpc", side_effect=lambda method, *_a, **_k: [] if method == "getpeerinfo" else None),
                    mock.patch.object(target, "_donor_rpc", side_effect=donor_rpc),
                    mock.patch.object(target, "wait_synced", side_effect=[before, after]),
                    mock.patch.object(target, "_ensure_donor", return_value={"id": "owned-donor"}),
                    mock.patch.object(target, "_mempool_raw", side_effect=[{held: "aa", released: "bb"}, {released: "bb"}, {held: "aa"}]),
                    mock.patch.object(target, "_block_transactions", return_value=committed),
                ):
                    if include_held:
                        with self.assertRaisesRegex(fixture.FixtureError, "included held"):
                            target.mine(1)
                        self.assertEqual(target._reorg_state, "failed")
                    else:
                        result = target.mine(1)
                        self.assertEqual(result["tip"], after)
                        proof = json.loads((target.artifacts / "mine-101.json").read_text())
                        self.assertEqual(proof["held_safe_blocks"][0]["excluded_txids"], [held])
                        self.assertEqual(proof["held_safe_blocks"][0]["included_txids"], [released])

    def test_held_bytes_only_allow_absence_at_declared_expiry(self):
        target = self.make_fixture()
        held = {"ab" * 32: "aa"}
        target._held_expiry_height = 200
        target._require_held_bytes(held, held, 199)
        target._require_held_bytes({}, held, 200)
        for pool, height in (({}, 199), ({"ab" * 32: "bb"}, 200)):
            with self.assertRaisesRegex(fixture.FixtureError, "permitted expiry"):
                target._require_held_bytes(pool, held, height)

    def test_pending_hold_seeds_exact_prefix_without_replacing_main_tip(self):
        target = self.make_fixture()
        target._started = True
        held = "ab" * 32
        before = {"height": 2, "hash": OTHER_HASH}
        main_mutations = []
        submitted = []

        def main_rpc(method, params=None, **_kwargs):
            if method == "getpeerinfo": return []
            if method == "getblockhash": return HASH if params[0] < 2 else OTHER_HASH
            if method == "getblock": return "aa"
            if method == "z_gettreestate": return {"height": 2, "hash": OTHER_HASH}
            main_mutations.append(method)
            raise AssertionError(method)

        def donor_rpc(method, params=None, **_kwargs):
            if method in {"getpeerinfo", "getrawmempool"}: return []
            if method == "getblockhash": return HASH
            if method == "getbestblockhash": return OTHER_HASH
            if method == "z_gettreestate": return {"height": 2, "hash": OTHER_HASH}
            if method == "submitblock":
                submitted.append(params[0])
                return None
            raise AssertionError(method)

        with (
            mock.patch.object(target, "rpc", side_effect=main_rpc),
            mock.patch.object(target, "_donor_rpc", side_effect=donor_rpc),
            mock.patch.object(target, "wait_synced", return_value=before),
            mock.patch.object(target, "_ensure_donor", return_value={"id": "owned-donor"}),
            mock.patch.object(target, "_wait_required_mempool", return_value={held: "bb"}),
            mock.patch.object(target, "_mempool_raw", return_value={held: "bb"}),
        ):
            proof = target.hold_pending_transactions([held], expiry_height=5)
        self.assertEqual(proof["initial_tip_height"], 2)
        self.assertEqual(proof["initial_tip_hash"], OTHER_HASH)
        self.assertEqual(proof["held_txids"], [held])
        self.assertEqual(main_mutations, [])
        self.assertEqual(len(submitted), 2)
        self.assertEqual(target._reorg_state, "held")
        with self.assertRaisesRegex(fixture.FixtureError, "combined"):
            target.replace_fork_holding([held], fork_height=1)

    def test_owned_donor_reset_never_removes_an_identity_mismatch(self):
        target = self.make_fixture()
        target._container_ids["zakura_donor"] = "owned-id"
        with mock.patch.object(target, "_assert_owned", side_effect=fixture.FixtureError("identity changed")), mock.patch.object(target, "_docker") as docker:
            with self.assertRaisesRegex(fixture.FixtureError, "identity changed"):
                target._reset_owned_donor(time.monotonic() + 5)
            docker.assert_not_called()

    def test_replacement_block_requires_exact_identity_height_and_coinbase(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        expected = {
            "hash": HASH,
            "height": 501,
            "previousblockhash": OTHER_HASH,
            "tx": [{"txid": "33" * 32, "vin": [{"coinbase": "00"}]}],
        }
        target._validate_replacement_block(
            expected,
            expected_hash=HASH,
            expected_height=501,
            expected_parent=OTHER_HASH,
        )

        mutations = (
            {"hash": OTHER_HASH},
            {"height": 502},
            {"previousblockhash": HASH},
            {"tx": [{"txid": "33" * 32, "vin": [{}]}]},
            {"tx": expected["tx"] * 2},
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                block = dict(expected)
                block.update(mutation)
                with self.assertRaises(fixture.FixtureError):
                    target._validate_replacement_block(
                        block,
                        expected_hash=HASH,
                        expected_height=501,
                        expected_parent=OTHER_HASH,
                    )

    def test_reorg_rejects_wrong_profile_and_preserves_failed_state(self):
        txid = "ab" * 32
        baseline = self.make_fixture("baseline")
        baseline._started = True
        baseline._node_rpc_url = "http://127.0.0.1:18232"
        with self.assertRaisesRegex(fixture.FixtureError, "activation500"):
            baseline.replace_tip_holding([txid])

        controlled = self.make_fixture(
            "controlled", profile=fixture.CONTROLLED_ACTIVATION_PROFILE
        )
        controlled._started = True
        controlled._node_rpc_url = "http://127.0.0.1:18232"
        with mock.patch.object(
            controlled,
            "wait_synced",
            side_effect=fixture.FixtureError("parity failed"),
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "parity failed"):
                controlled.replace_tip_holding([txid])
        self.assertEqual(controlled._reorg_state, "failed")
        with self.assertRaisesRegex(fixture.FixtureError, "exactly one"):
            controlled.replace_tip_holding([txid])

    def test_invalidation_wait_requires_parent_required_subset_and_raw_identity(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        target._node_rpc_url = "http://127.0.0.1:18232"
        required = "ab" * 32
        fork_hash = "22" * 32

        def rpc(method, **_kwargs):
            return 499 if method == "getblockcount" else fork_hash

        with mock.patch.object(
            target,
            "rpc",
            side_effect=rpc,
        ), mock.patch.object(
            target, "_mempool_raw", return_value={required: "ff"}
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "raw transaction changed|timed out"):
                target._wait_invalidated_mempool(
                    499,
                    fork_hash,
                    [required],
                    {required: "aa"},
                    {},
                    time.monotonic() + 0.01,
                )

        other = "cd" * 32
        with mock.patch.object(
            target,
            "rpc",
            side_effect=rpc,
        ), mock.patch.object(
            target, "_mempool_raw", return_value={required: "aa"}
        ):
            with self.assertRaisesRegex(
                fixture.FixtureError, "pre-invalidation|timed out"
            ):
                target._wait_invalidated_mempool(
                    499,
                    fork_hash,
                    [required],
                    {required: "aa", other: "bb"},
                    {},
                    time.monotonic() + 0.01,
                )

    def test_reorg_waits_for_required_transaction_to_reach_main_mempool(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        required = "ab" * 32
        expected = {required: "aa"}

        with mock.patch.object(
            target, "_mempool_raw", side_effect=[{}, expected]
        ) as mempool, mock.patch.object(fixture.time, "sleep") as sleep:
            observed = target._wait_required_mempool(
                [required], time.monotonic() + 1
            )

        self.assertEqual(observed, expected)
        self.assertEqual(mempool.call_count, 2)
        sleep.assert_called_once()

    def test_controlled_restoration_submits_only_missing_captured_bytes_once(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        natural, restored = "ab" * 32, "cd" * 32
        pool = {natural: "aa"}
        sent = []
        def rpc(method, params=None, **_kwargs):
            if method == "getblockcount": return 500
            if method == "getbestblockhash": return HASH
            if method == "getpeerinfo": return []
            if method == "sendrawtransaction":
                sent.append(params[0])
                pool[restored] = params[0]
                return restored
            if method == "getrawtransaction":
                return {"txid": params[0], "hex": pool[params[0]], "confirmations": 0}
            raise AssertionError((method, params))
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "_mempool_raw", side_effect=lambda *_args: dict(pool),
        ):
            held, proof = target._restore_invalidated_mempool(
                500, HASH, [natural, restored], {}, {natural: "aa", restored: "bb"},
                time.monotonic() + 1,
            )
        self.assertEqual(held, {natural: "aa", restored: "bb"})
        self.assertEqual(sent, ["bb"])
        self.assertEqual(proof["natural_txids"], [natural])
        self.assertEqual(proof["resubmitted_txids"], [restored])
        self.assertEqual(proof["submission_attempts_per_txid"], {restored: 1})

    def test_controlled_restoration_observes_pending_survival_without_restoring_evicted_child(self):
        target = self.make_fixture(profile=fixture.CONTROLLED_ACTIVATION_PROFILE)
        survivor, evicted, parent = "ab" * 32, "bc" * 32, "cd" * 32
        pool, sent = {survivor: "aa"}, []
        def rpc(method, params=None, **_kwargs):
            if method == "getblockcount": return 500
            if method == "getbestblockhash": return HASH
            if method == "getpeerinfo": return []
            if method == "sendrawtransaction":
                self.assertEqual(params, ["cc"])
                sent.append(params[0])
                pool[parent] = params[0]
                return parent
            if method == "getrawtransaction":
                return {"txid": params[0], "hex": pool[params[0]], "confirmations": 0}
            raise AssertionError((method, params))
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "_mempool_raw", side_effect=lambda *_args: dict(pool),
        ):
            held, proof = target._restore_invalidated_mempool(
                500, HASH, [parent], {survivor: "aa", evicted: "bb"},
                {parent: "cc"}, time.monotonic() + 1,
            )
        self.assertEqual(held, {survivor: "aa", parent: "cc"})
        self.assertEqual(sent, ["cc"])
        self.assertEqual(proof["resubmitted_txids"], [parent])
        self.assertEqual(proof["preserved_pending_txids"], [survivor])
        self.assertEqual(proof["invalidated_pending_txids"], [evicted])
        self.assertEqual(proof["invalidated_pending_raw_sha256"], {
            evicted: fixture.hashlib.sha256(bytes.fromhex("bb")).hexdigest(),
        })
        self.assertNotIn(evicted, proof["submission_attempts_per_txid"])

    def test_controlled_restoration_rejects_changed_surviving_pending_bytes(self):
        target = self.make_fixture()
        pending = "ab" * 32
        def rpc(method, params=None, **_kwargs):
            if method == "getblockcount": return 500
            if method == "getbestblockhash": return HASH
            raise AssertionError((method, params))
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "_mempool_raw", return_value={pending: "bb"},
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "not captured"):
                target._restore_invalidated_mempool(
                    500, HASH, [], {pending: "aa"}, {}, time.monotonic() + 1,
                )

    def test_controlled_restoration_empty_required_observes_actual_pool(self):
        pending = "ab" * 32
        for survives in (True, False):
            with self.subTest(survives=survives):
                target = self.make_fixture(f"empty-required-{survives}")
                pool = {pending: "aa"} if survives else {}
                def rpc(method, params=None, **_kwargs):
                    if method == "getblockcount": return 500
                    if method == "getbestblockhash": return HASH
                    if method == "getpeerinfo": return []
                    if method == "getrawtransaction": return {"txid": pending, "hex": "aa"}
                    raise AssertionError((method, params))
                with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
                    target, "_mempool_raw", return_value=pool,
                ):
                    held, proof = target._restore_invalidated_mempool(
                        500, HASH, [], {pending: "aa"}, {}, time.monotonic() + 1,
                    )
                self.assertEqual(held, pool)
                self.assertEqual(proof["resubmitted_txids"], [])
                self.assertEqual(proof["preserved_pending_txids"], [pending] if survives else [])
                self.assertEqual(proof["invalidated_pending_txids"], [] if survives else [pending])

    def test_controlled_restoration_uses_branch_parent_order_and_no_natural_submission(self):
        target = self.make_fixture()
        parent, child = "cd" * 32, "ab" * 32
        pool, sent = {}, []
        def rpc(method, params=None, **_kwargs):
            if method == "getblockcount": return 1
            if method == "getbestblockhash": return HASH
            if method == "getpeerinfo": return []
            if method == "getrawtransaction": return {"txid": params[0], "hex": pool[params[0]]}
            if method == "sendrawtransaction":
                txid = parent if params[0] == "aa" else child
                if txid == child:
                    self.assertIn(parent, pool)
                sent.append(txid)
                pool[txid] = params[0]
                return txid
            raise AssertionError(method)
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "_mempool_raw", side_effect=lambda *_args: dict(pool),
        ):
            target._restore_invalidated_mempool(1, HASH, [child, parent], {},
                                                {parent: "aa", child: "bb"}, time.monotonic()+1)
            _held, proof = target._restore_invalidated_mempool(1, HASH, [child, parent], {},
                                                {parent: "aa", child: "bb"}, time.monotonic()+1)
        self.assertEqual(sent, [parent, child])
        self.assertEqual(proof["resubmitted_txids"], [])

    def test_controlled_restoration_rejects_rpc_wrong_id_raw_and_confirmed_state(self):
        txid = "ab" * 32
        for kind in ["reject", "wrong-id", "changed-raw", "confirmed", "mined-height", "blockhash", "bool-height", "absent"]:
            with self.subTest(kind=kind):
                target = self.make_fixture()
                sent, pool = [], {}
                def rpc(method, params=None, **_kwargs):
                    if method == "getblockcount": return 1
                    if method == "getbestblockhash": return HASH
                    if method == "getpeerinfo": return []
                    if method == "sendrawtransaction":
                        sent.append(params[0])
                        if kind == "reject": raise fixture.FixtureError("kernel rejected captured bytes")
                        if kind != "absent": pool[txid] = "aa"
                        return OTHER_HASH if kind == "wrong-id" else txid
                    if method == "getrawtransaction":
                        value = {"txid": txid, "hex": "aa"}
                        if kind == "changed-raw": value["hex"] = "bb"
                        if kind == "confirmed": value["confirmations"] = 1
                        if kind == "mined-height": value["height"] = 501
                        if kind == "blockhash": value["blockhash"] = HASH
                        if kind == "bool-height": value["height"] = False
                        return value
                    raise AssertionError(method)
                with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
                    target, "_mempool_raw", side_effect=lambda *_args: dict(pool),
                ):
                    with self.assertRaises(fixture.FixtureError):
                        target._restore_invalidated_mempool(1, HASH, [txid], {}, {txid: "aa"}, time.monotonic()+1)
                self.assertEqual(sent, ["aa"])

    def test_controlled_restoration_never_submits_uncaptured_or_changed_natural_raw(self):
        target = self.make_fixture()
        txid = "ab" * 32
        with mock.patch.object(target, "rpc") as rpc:
            with self.assertRaisesRegex(fixture.FixtureError, "not captured"):
                target._restore_invalidated_mempool(1, HASH, [txid], {}, {}, time.monotonic()+1)
            rpc.assert_not_called()
        def rpc(method, params=None, **_kwargs):
            if method == "getblockcount": return 1
            if method == "getbestblockhash": return HASH
            raise AssertionError(method)
        with mock.patch.object(target, "rpc", side_effect=rpc), mock.patch.object(
            target, "_mempool_raw", return_value={txid: "bb"},
        ):
            with self.assertRaisesRegex(fixture.FixtureError, "not captured"):
                target._restore_invalidated_mempool(1, HASH, [txid], {}, {txid: "aa"}, time.monotonic()+1)

    def test_cleanup_removes_exact_owned_donor_before_network(self):
        target = self.make_fixture()
        target._container_ids = {"zakura_donor": "donor-id"}
        target._network_id = "network-id"
        removed = []
        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
            target, "_assert_owned", return_value={},
        ), mock.patch.object(target, "_ensure_resource_absent"), mock.patch.object(
            target, "_docker", side_effect=lambda args, **_: removed.append(args) or self.completed(),
        ):
            proof = target.close()
        self.assertTrue(proof["complete"])
        self.assertEqual(removed[0], ["container", "rm", "--force", "donor-id"])
        self.assertEqual(removed[-1], ["network", "rm", "network-id"])
        self.assertIsNone(target._donor_rpc_url)

    def test_cleanup_preserves_partial_errors_and_does_not_repeat_removals(self):
        target = self.make_fixture()
        target._container_ids = {"zakura": "node-id", "lightwalletd": "lwd-id"}
        target._volume_name = target.lwd_volume
        target._network_id = "network-id"
        removed_commands = []

        def assert_owned(kind, name, expected_id, deadline):
            if name == target.node_name:
                raise fixture.FixtureError("node ownership changed")
            return {}

        def docker(args, **_kwargs):
            removed_commands.append(args)
            return self.completed()

        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
            target, "_assert_owned", side_effect=assert_owned,
        ), mock.patch.object(
            target, "_ensure_resource_absent",
        ), mock.patch.object(target, "_docker", side_effect=docker):
            first = target.close()
            second = target.close()

        self.assertFalse(first["complete"])
        self.assertFalse(second["complete"])
        self.assertEqual(second["removed"], [])
        self.assertEqual(second["errors"], first["errors"])
        self.assertEqual(len(first["errors"]), 1)
        self.assertIn("node ownership changed", first["errors"][0])
        self.assertEqual({entry["kind"] for entry in first["removed"]}, {"container", "volume", "network"})
        self.assertFalse(any(command[-1] == "node-id" for command in removed_commands))

    def test_incomplete_cleanup_can_retry_exact_owned_resource(self):
        target = self.make_fixture()
        target._network_id = "network-id"
        ownership_checks = 0

        def assert_owned(_kind, _name, _expected_id, _deadline):
            nonlocal ownership_checks
            ownership_checks += 1
            if ownership_checks == 1:
                raise fixture.FixtureError("temporary inspect failure")
            return {}

        with mock.patch.object(target, "_capture_diagnostics"), mock.patch.object(
            target, "_assert_owned", side_effect=assert_owned,
        ), mock.patch.object(target, "_ensure_resource_absent"), mock.patch.object(
            target, "_docker", return_value=self.completed(),
        ) as docker:
            first = target.close()
            second = target.close()
            third = target.close()

        self.assertFalse(first["complete"])
        self.assertTrue(second["complete"])
        self.assertEqual(third, second)
        docker.assert_called_once_with(["network", "rm", "network-id"], deadline=mock.ANY)


if __name__ == "__main__":
    unittest.main()
