#!/usr/bin/env python3
"""Run-owned direct Zakura and lightwalletd regtest fixture."""

from __future__ import annotations

import base64
import fcntl
import hashlib
import ipaddress
import json
import math
import os
import re
import socket
import stat
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from dataclasses import dataclass
from typing import Any, Callable


ZAKURA_IMAGE = (
    "zakuracore/zakura@sha256:"
    "bf53c178e9549217fce7cfaa21efc85c478129ba6dc5307d55640514affeb0ac"
)
LIGHTWALLETD_IMAGE = (
    "ghcr.io/zcashlabs/thus-spoke-zakura-lightwalletd@sha256:"
    "ac78a456daee0bb98ceced333f5b8a2526b18b436ef90dc6033eef1686a92270"
)
ZAKURA_IMAGE_ID = "sha256:bf53c178e9549217fce7cfaa21efc85c478129ba6dc5307d55640514affeb0ac"
LIGHTWALLETD_IMAGE_ID = "sha256:ac78a456daee0bb98ceced333f5b8a2526b18b436ef90dc6033eef1686a92270"
MINER_ADDRESS = "tmJymvcUCn1ctbghvTJpXBwHiMEB8P6wxNV"
LOCKBOX_ADDRESS = "t2RnBRiqrN1nW4ecZs1Fj3WWjNdnSs4kiX8"
NU63_BRANCH_ID = "37a5165b"
NU62_BRANCH_ID = "5437f330"
DIRECT_HEIGHT1_PROFILE = "zakura-direct-height1"
CONTROLLED_ACTIVATION_PROFILE = "zakura-direct-activation500"
_PROFILE_ACTIVATION_HEIGHTS = {
    DIRECT_HEIGHT1_PROFILE: 1,
    CONTROLLED_ACTIVATION_PROFILE: 500,
}
GRPC_SERVICE = "cash.z.wallet.sdk.rpc.CompactTxStreamer"
MAX_GRPC_STREAM_RESPONSE_BYTES = 8 * 1024 * 1024
MAX_GRPC_STREAM_MESSAGES = 10_000
MAX_REORG_DEPTH = 512
MAX_REORG_FORK_HEIGHT = 10_000
OWNER_LABEL = "com.zakura.regtest-fixture"
RUN_LABEL = "com.zakura.regtest-fixture.run"
NODE_STATE_CACHE_DIR = "/home/zebra/.cache/zakura"
_HEX_HASH = re.compile(r"^[0-9a-fA-F]{64}$")
_SAFE_RUN_ID = re.compile(r"^[0-9a-f]{32}$")
_REGTEST_TRANSPARENT_ADDRESS = re.compile(r"^(?:tm|t2)[1-9A-HJ-NP-Za-km-z]{33}$")


class FixtureError(RuntimeError):
    """A bounded fixture operation failed."""

    exit_code = 1


@dataclass
class _LoopbackPortLease:
    port: int
    reserved: socket.socket | None
    descriptor: int

    def handoff(self) -> None:
        if self.reserved is not None:
            self.reserved.close()
            self.reserved = None

    def close(self) -> None:
        self.handoff()
        if self.descriptor >= 0:
            try:
                fcntl.flock(self.descriptor, fcntl.LOCK_UN)
            finally:
                os.close(self.descriptor)
                self.descriptor = -1


class RegtestFixture:
    """Own one isolated Zakura node, lightwalletd, network, and LWD volume."""

    def __init__(
        self,
        artifacts: Path,
        grpcurl: Path,
        proto_dir: Path,
        timeout: float = 60,
        run_id: str | uuid.UUID | None = None,
        miner_address: str = MINER_ADDRESS,
        profile: str = DIRECT_HEIGHT1_PROFILE,
        network_subnet: str | None = None,
    ) -> None:
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
            raise FixtureError("timeout must be a positive finite number")
        if not math.isfinite(timeout) or timeout <= 0:
            raise FixtureError("timeout must be a positive finite number")
        if not isinstance(miner_address, str) or not _REGTEST_TRANSPARENT_ADDRESS.fullmatch(
            miner_address
        ):
            raise FixtureError("miner_address must be a 35-character regtest transparent address")
        if not isinstance(profile, str) or profile not in _PROFILE_ACTIVATION_HEIGHTS:
            raise FixtureError("profile must be a supported fixed regtest profile")
        if network_subnet is not None:
            try:
                if not isinstance(network_subnet, str):
                    raise ValueError("expected a CIDR string")
                subnet = ipaddress.IPv4Network(network_subnet, strict=True)
                private_ranges = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
                if subnet.prefixlen > 29 or not any(
                    subnet.subnet_of(ipaddress.IPv4Network(value)) for value in private_ranges
                ):
                    raise ValueError("expected a private subnet with room for the fixture")
                network_subnet = str(subnet)
            except ValueError as error:
                raise FixtureError("network_subnet must be a canonical RFC1918 IPv4 CIDR of /29 or larger") from error

        self.timeout = float(timeout)
        self.miner_address = miner_address
        self.profile = profile
        self.network_subnet = network_subnet
        self.nu6_3_activation_height = _PROFILE_ACTIVATION_HEIGHTS[profile]
        self.grpcurl = Path(grpcurl).expanduser().resolve(strict=True)
        self.proto_dir = Path(proto_dir).expanduser().resolve(strict=True)
        self.service_proto = self.proto_dir / "service.proto"
        if not self.grpcurl.is_file() or not os.access(self.grpcurl, os.X_OK):
            raise FixtureError(f"grpcurl is not an executable file: {self.grpcurl}")
        if not self.service_proto.is_file():
            raise FixtureError(f"service.proto is missing: {self.service_proto}")

        parsed_run_id = uuid.uuid4() if run_id is None else uuid.UUID(str(run_id))
        self.run_id = parsed_run_id.hex
        if not _SAFE_RUN_ID.fullmatch(self.run_id):
            raise FixtureError("run_id must be a UUID")

        raw_artifacts = Path(artifacts).expanduser()
        if raw_artifacts.is_symlink():
            raise FixtureError("artifacts must not be a symlink")
        raw_artifacts.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.artifacts = raw_artifacts.resolve(strict=True)
        stat = self.artifacts.stat()
        if stat.st_uid != os.getuid() or not self.artifacts.is_dir():
            raise FixtureError("artifacts must be an owned directory")
        os.chmod(self.artifacts, 0o700)

        short = self.run_id[:12]
        prefix = f"zakura-proof-{short}"
        self.network_name = f"{prefix}-net"
        self.node_name = f"{prefix}-node"
        self.donor_name = f"{prefix}-donor"
        self.lwd_name = f"{prefix}-lwd"
        self.lwd_volume = f"{prefix}-lwd-data"
        self.labels = {OWNER_LABEL: "1", RUN_LABEL: self.run_id}
        self.config_path = self.artifacts / "zakurad.toml"

        self._network_id: str | None = None
        self._volume_name: str | None = None
        self._container_ids: dict[str, str] = {}
        self._port_leases: dict[str, _LoopbackPortLease] = {}
        self._attempted_resources: set[tuple[str, str]] = set()
        self._node_rpc_url: str | None = None
        self._donor_rpc_url: str | None = None
        self._lightwalletd_url: str | None = None
        self._started = False
        self._closed = False
        self._start_proof: dict[str, Any] | None = None
        self._cleanup_proof: dict[str, Any] | None = None
        self._retained = False
        self._retention_proof: dict[str, Any] | None = None
        self._reorg_state = "ready"
        self._held_transactions: dict[str, str] | None = None
        self._explicit_reorg = False
        self._explicit_reorg_count = 0
        self._released_transactions: set[str] = set()
        self._explicit_release_count = 0
        self._pending_hold = False
        self._held_expiry_height: int | None = None

    def start(self) -> dict[str, Any]:
        """Start the owned fixture and return its identity and initial parity proof."""
        self._assert_not_retained()
        if self._closed:
            raise FixtureError("fixture is already closed")
        if self._started:
            assert self._start_proof is not None
            return self._start_proof

        deadline = time.monotonic() + self.timeout
        try:
            images = {
                "zakura": self._verify_image(ZAKURA_IMAGE, ZAKURA_IMAGE_ID, deadline),
                "lightwalletd": self._verify_image(
                    LIGHTWALLETD_IMAGE, LIGHTWALLETD_IMAGE_ID, deadline
                ),
            }
            self._ensure_resource_absent("network", self.network_name, deadline)
            self._ensure_resource_absent("volume", self.lwd_volume, deadline)
            self._ensure_resource_absent("container", self.node_name, deadline)
            self._ensure_resource_absent("container", self.lwd_name, deadline)
            self._write_config()

            self._attempted_resources.add(("network", self.network_name))
            network = self._docker(
                [
                    "network",
                    "create",
                    *self._label_args(),
                    "--driver",
                    "bridge",
                    *(["--subnet", self.network_subnet] if self.network_subnet is not None else []),
                    self.network_name,
                ],
                deadline=deadline,
            ).stdout.strip()
            if not network:
                raise FixtureError("docker did not return the created network ID")
            self._network_id = network
            self._assert_owned("network", self.network_name, network, deadline)

            self._attempted_resources.add(("volume", self.lwd_volume))
            volume = self._docker(
                ["volume", "create", *self._label_args(), self.lwd_volume],
                deadline=deadline,
            ).stdout.strip()
            if volume != self.lwd_volume:
                raise FixtureError("docker returned an unexpected LWD volume name")
            self._volume_name = volume
            self._assert_owned("volume", self.lwd_volume, self.lwd_volume, deadline)

            self._create_node(deadline)
            self._docker(["start", self.node_name], deadline=deadline)
            node_port = self._published_port(self.node_name, "18232/tcp", deadline)
            self._node_rpc_url = f"http://127.0.0.1:{node_port}"
            node_ready = self._wait_node(deadline)

            bootstrap_hashes = self.rpc("generate", [1], deadline=deadline)
            self._validate_hashes(bootstrap_hashes, expected=1)

            self._create_lightwalletd(deadline)
            self._docker(["start", self.lwd_name], deadline=deadline)
            lwd_port = self._published_port(self.lwd_name, "9067/tcp", deadline)
            self._lightwalletd_url = f"127.0.0.1:{lwd_port}"
            parity = self.wait_synced(deadline=deadline)
            if parity["height"] != 1 or bootstrap_hashes[-1].lower() != parity["hash"]:
                raise FixtureError("bootstrap block does not match the synchronized chain tip")

            identity = {
                "run_id": self.run_id,
                "network": {"name": self.network_name, "id": self._network_id,
                            "requested_subnet": self.network_subnet},
                "containers": dict(self._container_ids),
                "lwd_volume": self._volume_name,
                "images": images,
            }
            proof = {
                "schema_version": 1,
                "identity": identity,
                "endpoints": {
                    "node_rpc_url": self._node_rpc_url,
                    "lightwalletd_url": self._lightwalletd_url,
                },
                "profile": self._profile_proof(),
                "bootstrap": {"node_ready": node_ready, "hashes": bootstrap_hashes},
                "parity": parity,
            }
            self._started = True
            self._start_proof = proof
            self._write_json("start-proof.json", proof)
            return proof
        except BaseException as error:
            self._capture_diagnostics("start-failure")
            try:
                cleanup = self.close()
            except BaseException as cleanup_error:
                cleanup = {"complete": False, "errors": [str(cleanup_error)]}
            if not cleanup["complete"]:
                try:
                    error.add_note(f"fixture rollback errors: {cleanup['errors']}")
                except AttributeError:
                    pass
            raise

    def _profile_proof(self) -> dict[str, Any]:
        controlled = self.profile == CONTROLLED_ACTIVATION_PROFILE
        return {
            "name": self.profile,
            "network": "Regtest",
            "nu6_3_activation_height": self.nu6_3_activation_height,
            "pre_activation_consensus_branch_id": NU62_BRANCH_ID if controlled else None,
            "post_activation_consensus_branch_id": NU63_BRANCH_ID,
            "pre_activation_pools": ["sapling", "orchard"] if controlled else [],
            "post_activation_pools": ["sapling", "orchard", "ironwood"],
            "miner_address": self.miner_address,
            "mempool_debug_enable_at_height": 0,
            "node_state_ephemeral": False,
            "node_state_cache_dir": NODE_STATE_CACHE_DIR,
            "rpc_parallel_cpu_threads": 1,
            "sync_parallel_cpu_threads": 1,
            "container_network": "bridge",
            "egress_fenced": False,
            "nu6_1_lockbox_disbursement": {
                "address": LOCKBOX_ADDRESS,
                "amount_zatoshi": 0,
                "purpose": "structural-only-not-funding",
            },
        }

    def rpc(
        self,
        method: str,
        params: list[Any] | None = None,
        *,
        deadline: float | None = None,
    ) -> Any:
        """Call Zakura JSON-RPC and return its result."""
        self._assert_not_retained()
        if not isinstance(method, str) or not method:
            raise FixtureError("RPC method must be a non-empty string")
        if params is None:
            params = []
        if not isinstance(params, list):
            raise FixtureError("RPC params must be a list")
        if self._node_rpc_url is None:
            raise FixtureError("Zakura RPC is not started")
        return self._rpc_at(
            self._node_rpc_url, method, params, deadline=deadline
        )

    def _rpc_at(
        self,
        url: str,
        method: str,
        params: list[Any],
        *,
        deadline: float | None,
    ) -> Any:
        active_deadline = (
            time.monotonic() + self.timeout if deadline is None else deadline
        )
        body = json.dumps(
            {"jsonrpc": "2.0", "id": self.run_id, "method": method, "params": params},
            separators=(",", ":"),
        ).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            remaining = self._remaining(active_deadline)
            # Generating a large batch is one mutation, not a readiness probe.
            # Keep its existing operation deadline rather than retrying it.
            rpc_timeout = remaining if method == "generate" else min(5.0, remaining)
            with urllib.request.urlopen(
                request, timeout=rpc_timeout
            ) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            raise FixtureError(f"RPC {method} failed: {error}") from error
        if not isinstance(payload, dict) or payload.get("id") != self.run_id:
            raise FixtureError(f"RPC {method} returned an invalid response identity")
        if payload.get("error") is not None:
            raise FixtureError(f"RPC {method} returned an error: {payload['error']}")
        if "result" not in payload:
            raise FixtureError(f"RPC {method} returned no result")
        return payload["result"]

    def _donor_rpc(
        self,
        method: str,
        params: list[Any] | None = None,
        *,
        deadline: float | None = None,
    ) -> Any:
        self._assert_not_retained()
        if not isinstance(method, str) or not method:
            raise FixtureError("donor RPC method must be a non-empty string")
        if params is None:
            params = []
        if not isinstance(params, list):
            raise FixtureError("donor RPC params must be a list")
        if self._donor_rpc_url is None:
            raise FixtureError("donor RPC is not started")
        return self._rpc_at(self._donor_rpc_url, method, params, deadline=deadline)

    def grpc(
        self,
        method: str,
        payload: dict[str, Any] | None = None,
        *,
        deadline: float | None = None,
    ) -> dict[str, Any]:
        """Call lightwalletd with the pinned service descriptor."""
        completed = self._grpc_call(method, payload, deadline=deadline)
        try:
            decoded = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise FixtureError(f"gRPC {method} returned invalid JSON") from error
        if not isinstance(decoded, dict):
            raise FixtureError(f"gRPC {method} returned a non-object response")
        return decoded

    def grpc_stream(
        self,
        method: str,
        payload: dict[str, Any] | None = None,
        *,
        deadline: float | None = None,
    ) -> list[dict[str, Any]]:
        """Call a server-streaming lightwalletd method and decode bounded JSON objects."""
        completed = self._grpc_call(
            method, payload, deadline=deadline, emit_defaults=True
        )
        output = completed.stdout
        if len(output) > MAX_GRPC_STREAM_RESPONSE_BYTES or len(
            output.encode("utf-8")
        ) > MAX_GRPC_STREAM_RESPONSE_BYTES:
            raise FixtureError(
                f"gRPC {method} stream exceeded {MAX_GRPC_STREAM_RESPONSE_BYTES} bytes"
            )

        decoder = json.JSONDecoder()
        messages: list[dict[str, Any]] = []
        offset = 0
        while True:
            while offset < len(output) and output[offset].isspace():
                offset += 1
            if offset == len(output):
                return messages
            if len(messages) >= MAX_GRPC_STREAM_MESSAGES:
                raise FixtureError(
                    f"gRPC {method} stream exceeded {MAX_GRPC_STREAM_MESSAGES} messages"
                )
            try:
                decoded, offset = decoder.raw_decode(output, offset)
            except json.JSONDecodeError as error:
                raise FixtureError(f"gRPC {method} stream returned invalid JSON") from error
            if not isinstance(decoded, dict):
                raise FixtureError(
                    f"gRPC {method} stream returned a non-object response"
                )
            messages.append(decoded)

    def _grpc_call(
        self,
        method: str,
        payload: dict[str, Any] | None,
        *,
        deadline: float | None,
        emit_defaults: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        self._assert_not_retained()
        if not isinstance(method, str) or not method or "/" in method:
            raise FixtureError("gRPC method must be a simple non-empty name")
        if payload is None:
            payload = {}
        if not isinstance(payload, dict):
            raise FixtureError("gRPC payload must be an object")
        if self._lightwalletd_url is None:
            raise FixtureError("lightwalletd is not started")
        active_deadline = (
            time.monotonic() + self.timeout if deadline is None else deadline
        )
        remaining = self._remaining(active_deadline)
        command = [str(self.grpcurl), "-plaintext"]
        if emit_defaults:
            command.append("-emit-defaults")
        command.extend(
            [
                "-max-time",
                f"{remaining:.3f}",
                "-import-path",
                str(self.proto_dir),
                "-proto",
                self.service_proto.name,
                "-d",
                json.dumps(payload, separators=(",", ":")),
                self._lightwalletd_url,
                f"{GRPC_SERVICE}/{method}",
            ]
        )
        return self._run(command, timeout=remaining)

    def mine(self, count: int) -> dict[str, Any]:
        """Mine blocks and wait until lightwalletd proves the resulting tip and trees."""
        self._assert_not_retained()
        if self._reorg_state == "held" and self._explicit_reorg:
            return self._mine_with_held_transactions(count)
        if self._reorg_state in {"running", "held", "failed"}:
            raise FixtureError(
                f"cannot mine while reorg state is {self._reorg_state}"
            )
        if isinstance(count, bool) or not isinstance(count, int) or count <= 0:
            raise FixtureError("mine count must be a positive integer")
        deadline = time.monotonic() + self.timeout
        before_height = self._integer(
            self.rpc("getblockcount", deadline=deadline), "pre-mine block height"
        )
        hashes = self.rpc("generate", [count], deadline=deadline)
        self._validate_hashes(hashes, expected=count)
        parity = self.wait_synced(deadline=deadline)
        if parity["height"] != before_height + count:
            raise FixtureError("mined tip height does not match the requested block count")
        if hashes[-1].lower() != parity["hash"]:
            raise FixtureError("last generated block does not match the synchronized chain tip")
        result = {"hashes": hashes, "tip": parity}
        self._write_json(f"mine-{parity['height']}.json", result)
        return result

    def replace_tip_holding(
        self,
        required_txids: list[str],
        *,
        deadline: float | None = None,
    ) -> dict[str, Any]:
        """Replace the tip with two donor blocks while preserving pending transactions."""
        return self._replace_fork_holding(required_txids, deadline=deadline)

    def replace_fork_holding(
        self,
        required_txids: list[str],
        *,
        fork_height: int,
        deadline: float | None = None,
    ) -> dict[str, Any]:
        """Replace a bounded branch and retain transactions until explicit release."""
        if (
            isinstance(fork_height, bool)
            or not isinstance(fork_height, int)
            or not self.nu6_3_activation_height <= fork_height <= MAX_REORG_FORK_HEIGHT
        ):
            raise FixtureError("fork height must be a bounded post-activation height")
        return self._replace_fork_holding(
            required_txids, fork_height=fork_height, deadline=deadline,
        )

    def _replace_fork_holding(
        self,
        required_txids: list[str],
        *,
        fork_height: int | None = None,
        deadline: float | None = None,
    ) -> dict[str, Any]:
        explicit = fork_height is not None
        required = self._validated_txids(required_txids, maximum=64 if explicit else 8,
                                         minimum=0 if explicit else 1)
        if not self._started or self._closed:
            raise FixtureError("fixture must be running before a reorg")
        if not explicit and self.profile != CONTROLLED_ACTIVATION_PROFILE:
            raise FixtureError("tip replacement requires the activation500 profile")
        if explicit:
            if self._pending_hold:
                raise FixtureError("pending expiry holds cannot be combined with reorgs")
            if self._explicit_reorg_count >= 2 or self._reorg_state not in {"ready", "released"}:
                raise FixtureError("explicit reorg requires release and permits at most two holds")
            if self._reorg_state == "released" and not self._explicit_reorg:
                raise FixtureError("cannot mix explicit and tip-only reorg operations")
        elif self._reorg_state != "ready":
            raise FixtureError("fixture permits exactly one reorg")
        active_deadline = (
            time.monotonic() + self.timeout if deadline is None else deadline
        )
        self._reorg_state = "running"
        started = time.monotonic()
        try:
            before = self.wait_synced(deadline=active_deadline)
            old_height = self._integer(before.get("height"), "old tip height")
            if old_height <= self.nu6_3_activation_height:
                raise FixtureError(
                    "tip replacement requires a post-activation tip with a "
                    "post-activation fork parent"
                )
            old_hash = self._required_hash(before.get("hash"), "old tip hash")
            fork_height = old_height - 1 if fork_height is None else fork_height
            depth = old_height - fork_height
            if not 1 <= depth <= MAX_REORG_DEPTH:
                raise FixtureError("reorg depth must be in 1..512")
            fork_hash = self._required_hash(
                self.rpc("getblockhash", [fork_height], deadline=active_deadline),
                "fork hash",
            )
            before_pool = (
                self._mempool_raw(self.rpc, active_deadline) if explicit
                else self._wait_required_mempool(required, active_deadline)
            )
            branch_hashes = []
            old_block: dict[str, str] = {}
            for height in range(fork_height + 1, old_height + 1):
                block_hash = old_hash if height == old_height else self._required_hash(
                    self.rpc("getblockhash", [height], deadline=active_deadline),
                    "invalidated branch hash",
                )
                branch_hashes.append(block_hash)
                transactions = self._block_transactions(self.rpc, block_hash, active_deadline)
                if set(old_block) & set(transactions):
                    raise FixtureError("invalidated branch contains duplicate transaction IDs")
                old_block.update(transactions)
            if explicit and not set(required) <= (set(before_pool) | set(old_block)):
                raise FixtureError("required transactions are absent from the branch and mempool")
            if explicit and self.rpc("getpeerinfo", deadline=active_deadline) != []:
                raise FixtureError("main node must remain peerless")
            if explicit and self._explicit_reorg_count:
                self._reset_owned_donor(active_deadline)

            donor_started = time.monotonic()
            donor_identity = self._ensure_donor(active_deadline)
            donor_ready_seconds = time.monotonic() - donor_started
            if self._donor_rpc("getpeerinfo", deadline=active_deadline) != []:
                raise FixtureError("donor node must remain peerless")
            if self._donor_rpc("getrawmempool", deadline=active_deadline) != []:
                raise FixtureError("donor mempool must start empty")
            main_genesis = self._required_hash(
                self.rpc("getblockhash", [0], deadline=active_deadline), "main genesis hash"
            )
            donor_genesis = self._required_hash(
                self._donor_rpc("getblockhash", [0], deadline=active_deadline),
                "donor genesis hash",
            )
            if donor_genesis != main_genesis:
                raise FixtureError("donor genesis differs from the main node")

            seed_started = time.monotonic()
            for height in range(1, fork_height + 1):
                block_hash = self._required_hash(
                    self.rpc("getblockhash", [height], deadline=active_deadline),
                    "main seed block hash",
                )
                raw_block = self.rpc("getblock", [block_hash, 0], deadline=active_deadline)
                self._required_hex(raw_block, "main seed block")
                if self._donor_rpc(
                    "submitblock", [raw_block], deadline=active_deadline
                ) is not None:
                    raise FixtureError("donor rejected a canonical main-chain block")
            if self._required_hash(
                self._donor_rpc("getbestblockhash", deadline=active_deadline),
                "donor seeded tip hash",
            ) != fork_hash:
                raise FixtureError("donor did not reach the exact fork hash")
            main_tree = self.rpc(
                "z_gettreestate", [str(fork_height)], deadline=active_deadline
            )
            donor_tree = self._donor_rpc(
                "z_gettreestate", [str(fork_height)], deadline=active_deadline
            )
            if donor_tree != main_tree:
                raise FixtureError("donor tree state differs at the fork")
            if self._donor_rpc("getpeerinfo", deadline=active_deadline) != []:
                raise FixtureError("donor node gained a peer while seeding the fork")
            if self._donor_rpc("getrawmempool", deadline=active_deadline) != []:
                raise FixtureError("donor mempool changed while seeding the fork")
            seed_seconds = time.monotonic() - seed_started

            generate_started = time.monotonic()
            replacement_hashes = self._donor_rpc(
                "generate", [depth + 1], deadline=active_deadline
            )
            self._validate_hashes(replacement_hashes, expected=depth + 1)
            replacement_hashes = [value.lower() for value in replacement_hashes]
            if len(set(replacement_hashes)) != depth + 1 or set(replacement_hashes) & set(branch_hashes):
                raise FixtureError("donor replacement hashes are not a distinct fork")
            replacement_raw: list[str] = []
            previous = fork_hash
            for index, block_hash in enumerate(replacement_hashes, start=1):
                block = self._donor_rpc(
                    "getblock", [block_hash, 2], deadline=active_deadline
                )
                self._validate_replacement_block(
                    block,
                    expected_hash=block_hash,
                    expected_height=fork_height + index,
                    expected_parent=previous,
                )
                raw_block = self._donor_rpc(
                    "getblock", [block_hash, 0], deadline=active_deadline
                )
                self._required_hex(raw_block, "donor replacement block")
                replacement_raw.append(raw_block)
                previous = block_hash
            generate_seconds = time.monotonic() - generate_started

            invalidated_hash = branch_hashes[0]
            if self.rpc("invalidateblock", [invalidated_hash], deadline=active_deadline) is not None:
                raise FixtureError("invalidateblock returned an unexpected result")
            restoration: dict[str, Any] = {}
            if explicit:
                held_raw, restoration = self._restore_invalidated_mempool(
                    fork_height, fork_hash, required, before_pool, old_block,
                    active_deadline,
                )
            else:
                held_raw = self._wait_invalidated_mempool(
                    fork_height, fork_hash, required, before_pool, old_block,
                    active_deadline,
                )
            held_txids = sorted(held_raw)
            reintroduced = sorted(set(held_txids) - set(before_pool))

            submit_started = time.monotonic()
            for index, (block_hash, raw_block) in enumerate(
                zip(replacement_hashes, replacement_raw), start=1
            ):
                if self.rpc("submitblock", [raw_block], deadline=active_deadline) is not None:
                    raise FixtureError("main node rejected a donor replacement block")
                expected_height = fork_height + index
                if self._required_hash(
                    self.rpc("getblockhash", [expected_height], deadline=active_deadline),
                    "main replacement hash",
                ) != block_hash:
                    raise FixtureError("main node committed a different replacement block")
                block_transactions = self._block_transactions(
                    self.rpc, block_hash, active_deadline
                )
                if set(block_transactions) & set(held_txids):
                    raise FixtureError("replacement block mined a held transaction")
                current_pool = self._mempool_raw(self.rpc, active_deadline)
                if current_pool != held_raw:
                    raise FixtureError("held mempool transactions changed during replacement")
            submit_seconds = time.monotonic() - submit_started

            after = self.wait_synced(deadline=active_deadline)
            if (
                after.get("height") != old_height + 1
                or after.get("hash") != replacement_hashes[-1]
            ):
                raise FixtureError("lightwalletd did not reach the exact replacement tip")
            self._held_transactions = held_raw
            self._explicit_reorg = explicit
            self._released_transactions = set()
            self._explicit_release_count = 0
            if explicit:
                self._explicit_reorg_count += 1
            self._reorg_state = "released" if explicit and not held_raw else "held"
            result = {
                "fork_height": fork_height,
                "old_tip_height": old_height,
                "old_tip_hash": old_hash,
                "invalidated_hash": invalidated_hash,
                "new_tip_height": old_height + 1,
                "new_tip_hash": replacement_hashes[-1],
                "replacement_hashes": replacement_hashes,
                "held_txids": held_txids,
                "reintroduced_txids": reintroduced,
            }
            if explicit:
                result["reintroduction"] = restoration
            proof = dict(result)
            if explicit:
                proof.update(
                    invalidated_branch_hashes=branch_hashes,
                    invalidated_branch_raw_sha256={
                        txid: hashlib.sha256(bytes.fromhex(raw)).hexdigest()
                        for txid, raw in old_block.items()
                    },
                )
            proof.update(
                donor=donor_identity,
                required_txids=required,
                held_raw_sha256={
                    txid: hashlib.sha256(bytes.fromhex(raw)).hexdigest()
                    for txid, raw in held_raw.items()
                },
                before_parity=before,
                after_parity=after,
                fork_tree=main_tree,
                timings={
                    "donor_ready_seconds": round(donor_ready_seconds, 6),
                    "seed_seconds": round(seed_seconds, 6),
                    "generate_seconds": round(generate_seconds, 6),
                    "submit_seconds": round(submit_seconds, 6),
                    "total_seconds": round(time.monotonic() - started, 6),
                },
            )
            proof_name = (
                f"reorg-hold-{self._explicit_reorg_count}.json" if explicit
                else "reorg-hold-proof.json"
            )
            self._write_json(proof_name, proof)
            return result
        except BaseException:
            self._reorg_state = "failed"
            raise

    def release_held_transactions(
        self,
        txids: list[str],
        *,
        deadline: float | None = None,
    ) -> dict[str, Any]:
        """Release the fixture scheduling gate for the exact held transaction set."""
        requested = self._validated_txids(txids, maximum=64 if self._explicit_reorg else 8)
        if (self._reorg_state not in ({"held", "released"} if self._explicit_reorg else {"held"})
            or self._held_transactions is None):
            raise FixtureError("no held reorg transactions are available for release")
        if self._explicit_reorg:
            if not set(requested) <= set(self._held_transactions):
                raise FixtureError("release must name a captured held subset")
        elif requested != sorted(self._held_transactions):
            raise FixtureError("release transaction set differs from the held set")
        active_deadline = (
            time.monotonic() + self.timeout if deadline is None else deadline
        )
        current = self._mempool_raw(self.rpc, active_deadline)
        expected = {
            txid: raw for txid, raw in self._held_transactions.items()
            if txid not in self._released_transactions
        }
        if (self._explicit_reorg and any(current.get(txid) != raw for txid, raw in expected.items())) or (
            not self._explicit_reorg and current != expected
        ):
            raise FixtureError("held transactions changed before release")
        parity = self.wait_synced(deadline=active_deadline)
        result = {
            "released_txids": requested,
            "tip_height": parity["height"],
            "tip_hash": parity["hash"],
        }
        newly_released = set(requested) - self._released_transactions
        if newly_released or not self._explicit_reorg:
            proof = dict(result, raw_transactions_preserved=True, parity=parity)
            if self._explicit_reorg:
                proof["newly_released_txids"] = sorted(newly_released)
            self._write_json(
                (f"reorg-release-{self._explicit_reorg_count}-{self._explicit_release_count + 1}.json"
                 if self._explicit_reorg else "reorg-release-proof.json"),
                proof,
            )
        self._released_transactions.update(requested)
        if newly_released:
            self._explicit_release_count += 1
        if self._released_transactions == set(self._held_transactions):
            self._reorg_state = "released"
        return result

    def _reset_owned_donor(self, deadline: float) -> None:
        donor_id = self._container_ids.get("zakura_donor")
        if donor_id is None:
            raise FixtureError("cannot reset donor without its owned identity")
        self._assert_owned("container", self.donor_name, donor_id, deadline)
        self._docker(["container", "rm", "--force", donor_id], deadline=deadline)
        self._ensure_resource_absent("container", self.donor_name, deadline)
        self._forget_resource("container", self.donor_name)
        self._write_json(
            f"reorg-donor-reset-{self._explicit_reorg_count}.json",
            {"name": self.donor_name, "id": donor_id, "removed": True},
        )

    def hold_pending_transactions(
        self,
        required_txids: list[str],
        *,
        expiry_height: int | None = None,
        deadline: float | None = None,
    ) -> dict[str, Any]:
        """Hold exact pending bytes while a peerless donor extends the same tip."""
        required = self._validated_txids(required_txids, maximum=64)
        if not self._started or self._closed or self._reorg_state != "ready":
            raise FixtureError("pending hold requires a fresh running fixture")
        active_deadline = time.monotonic() + self.timeout if deadline is None else deadline
        self._reorg_state = "running"
        try:
            before = self.wait_synced(deadline=active_deadline)
            height = self._integer(before.get("height"), "pending hold tip height")
            if not 1 <= height <= MAX_REORG_FORK_HEIGHT:
                raise FixtureError("pending hold tip must be bounded")
            if expiry_height is not None and (
                isinstance(expiry_height, bool) or not isinstance(expiry_height, int)
                or not height < expiry_height <= height + 10_000
            ):
                raise FixtureError("expiry height must be a bounded future height")
            if self.rpc("getpeerinfo", deadline=active_deadline) != []:
                raise FixtureError("pending hold requires a peerless main node")
            pool = self._wait_required_mempool(required, active_deadline)
            donor = self._ensure_donor(active_deadline)
            if self._donor_rpc("getpeerinfo", deadline=active_deadline) != [] or self._donor_rpc("getrawmempool", deadline=active_deadline) != []:
                raise FixtureError("pending hold donor must be empty and peerless")
            genesis = self._required_hash(self.rpc("getblockhash", [0], deadline=active_deadline), "main genesis hash")
            if self._required_hash(self._donor_rpc("getblockhash", [0], deadline=active_deadline), "donor genesis hash") != genesis:
                raise FixtureError("pending hold donor genesis differs")
            for current in range(1, height + 1):
                block_hash = self._required_hash(self.rpc("getblockhash", [current], deadline=active_deadline), "pending hold seed hash")
                raw = self._required_hex(self.rpc("getblock", [block_hash, 0], deadline=active_deadline), "pending hold seed block")
                if self._donor_rpc("submitblock", [raw], deadline=active_deadline) is not None:
                    raise FixtureError("pending hold donor rejected the main prefix")
            if self._required_hash(self._donor_rpc("getbestblockhash", deadline=active_deadline), "pending hold donor tip") != before["hash"]:
                raise FixtureError("pending hold donor did not reach the adopted main tip")
            if self._donor_rpc("z_gettreestate", [str(height)], deadline=active_deadline) != self.rpc("z_gettreestate", [str(height)], deadline=active_deadline):
                raise FixtureError("pending hold donor tree differs at adopted tip")
            if self._mempool_raw(self.rpc, active_deadline) != pool:
                raise FixtureError("pending transactions changed while seeding donor")
            self._held_transactions = {txid: pool[txid] for txid in required}
            self._explicit_reorg = True
            self._pending_hold = True
            self._held_expiry_height = expiry_height
            self._reorg_state = "held"
            result = {"initial_tip_height": height, "initial_tip_hash": before["hash"], "held_txids": required, "expiry_height": expiry_height}
            self._write_json("pending-hold-proof.json", dict(result, donor=donor, parity=before, held_raw_sha256={txid: hashlib.sha256(bytes.fromhex(pool[txid])).hexdigest() for txid in required}))
            return result
        except BaseException:
            self._reorg_state = "failed"
            raise

    def _require_held_bytes(self, pool: dict[str, str], excluded: dict[str, str], height: int) -> None:
        for txid, raw in excluded.items():
            if pool.get(txid) == raw:
                continue
            if txid not in pool and self._held_expiry_height is not None and height >= self._held_expiry_height:
                continue
            raise FixtureError("held raw transaction changed before its permitted expiry")

    def _mine_with_held_transactions(self, count: int) -> dict[str, Any]:
        if isinstance(count, bool) or not isinstance(count, int) or not 1 <= count <= 10_000:
            raise FixtureError("held-safe mine count must be in 1..10000")
        deadline = time.monotonic() + self.timeout
        before = self.wait_synced(deadline=deadline)
        self._ensure_donor(deadline)
        excluded = {
            txid: raw for txid, raw in (self._held_transactions or {}).items()
            if txid not in self._released_transactions
        }
        hashes: list[str] = []
        block_proofs = []
        try:
            for index in range(1, count + 1):
                if self.rpc("getpeerinfo", deadline=deadline) != [] or self._donor_rpc("getpeerinfo", deadline=deadline) != []:
                    raise FixtureError("held-safe mining requires peerless nodes")
                pool = self._mempool_raw(self.rpc, deadline)
                self._require_held_bytes(pool, excluded, before["height"] + index - 1)
                allowed = {txid: raw for txid, raw in pool.items() if txid not in excluded}
                pending = dict(allowed)
                while pending:
                    accepted_txids = []
                    for txid, raw in pending.items():
                        try:
                            accepted = self._donor_rpc("sendrawtransaction", [raw], deadline=deadline)
                        except FixtureError:
                            # Descendants can sort before their unconfirmed parents.
                            continue
                        if accepted != txid:
                            raise FixtureError("donor did not accept the exact released transaction")
                        accepted_txids.append(txid)
                    if not accepted_txids:
                        raise FixtureError("donor could not accept the released transaction dependencies")
                    for txid in accepted_txids:
                        pending.pop(txid)
                donor_pool = self._mempool_raw(self._donor_rpc, deadline)
                if donor_pool != allowed:
                    raise FixtureError("donor mempool differs from the allowed raw transactions")
                generated = self._donor_rpc("generate", [1], deadline=deadline)
                self._validate_hashes(generated, expected=1)
                block_hash = generated[0].lower()
                block = self._donor_rpc("getblock", [block_hash, 2], deadline=deadline)
                parent = hashes[-1] if hashes else before["hash"]
                if (not isinstance(block, dict) or block.get("hash") != block_hash
                    or block.get("height") != before["height"] + index
                    or block.get("previousblockhash") != parent):
                    raise FixtureError("held-safe donor block identity differs from the adopted tip")
                transactions = self._block_transactions(self._donor_rpc, block_hash, deadline)
                if set(transactions) & set(excluded) or any(transactions.get(txid) != raw for txid, raw in allowed.items()):
                    raise FixtureError("held-safe block included held or changed released transactions")
                block_entries = block.get("tx")
                if not isinstance(block_entries, list) or not block_entries or not isinstance(block_entries[0], dict):
                    raise FixtureError("held-safe block has no verified coinbase")
                coinbase = block_entries[0]
                coinbase_id = self._required_hash(coinbase.get("txid"), "held-safe coinbase ID")
                inputs = coinbase.get("vin")
                if (not isinstance(inputs, list) or len(inputs) != 1
                    or not isinstance(inputs[0], dict) or "coinbase" not in inputs[0]
                    or set(transactions) != set(allowed) | {coinbase_id}):
                    raise FixtureError("held-safe block contains transactions outside the exact allowed set")
                self._required_hex(inputs[0]["coinbase"], "held-safe coinbase input")
                raw_block = self._required_hex(self._donor_rpc("getblock", [block_hash, 0], deadline=deadline), "held-safe raw block")
                if self.rpc("submitblock", [raw_block], deadline=deadline) is not None:
                    raise FixtureError("main node rejected the held-safe donor block")
                parity = self.wait_synced(deadline=deadline)
                if parity.get("height") != before["height"] + index or parity.get("hash") != block_hash:
                    raise FixtureError("held-safe node/lightwalletd tip differs from donor")
                committed = self._block_transactions(self.rpc, block_hash, deadline)
                if committed != transactions:
                    raise FixtureError("held-safe main block differs from donor transaction bytes")
                remaining = self._mempool_raw(self.rpc, deadline)
                self._require_held_bytes(remaining, excluded, parity["height"])
                if self.rpc("getpeerinfo", deadline=deadline) != [] or self._donor_rpc("getpeerinfo", deadline=deadline) != []:
                    raise FixtureError("held-safe nodes gained peers while mining")
                hashes.append(block_hash)
                block_proofs.append({"hash": block_hash, "height": parity["height"], "included_txids": sorted(allowed), "excluded_txids": sorted(excluded), "parity": parity})
            result = {"hashes": hashes, "tip": parity}
            self._write_json(f"mine-{parity['height']}.json", dict(result, held_safe_blocks=block_proofs))
            return result
        except BaseException:
            self._reorg_state = "failed"
            raise

    def wait_synced(self, *, deadline: float | None = None) -> dict[str, Any]:
        """Wait for exact node/lightwalletd height, hash, time, and tree parity."""
        self._assert_not_retained()
        active_deadline = (
            time.monotonic() + self.timeout if deadline is None else deadline
        )
        last_error: BaseException | None = None
        while True:
            self._assert_containers_running(active_deadline)
            try:
                return self._parity_once(active_deadline)
            except (FixtureError, OSError, urllib.error.URLError) as error:
                last_error = error
            if time.monotonic() >= active_deadline:
                raise FixtureError(f"lightwalletd synchronization timed out: {last_error}")
            time.sleep(min(0.1, self._remaining(active_deadline)))

    def _assert_not_retained(self) -> None:
        if self._retained:
            raise FixtureError("fixture is retained; execution and automatic deletion are disabled")

    def retain(self) -> dict[str, Any]:
        """Terminally stop owned writers, retaining containers, state and port locks.

        The caller must first stop/join its wallet and control writers. This
        single-owner operation cannot resume the fixture or certify a scenario
        result; a failed stop stays failed, without deleting its evidence.
        """
        if self._closed:
            raise FixtureError("fixture is already closed")
        if self._retained:
            if self._retention_proof is None:
                raise FixtureError("fixture retention did not finish")
            return self._retention_proof

        self._retained = True
        self._started = False
        self._reorg_state = "failed"
        stopped: list[dict[str, str]] = []
        errors: list[str] = []
        try:
            self._capture_diagnostics("retain-before")
        except BaseException as error:
            errors.append(f"retention diagnostics: {error}")
        deadline = time.monotonic() + self.timeout
        for role, name in (("zakura_donor", self.donor_name),
                           ("lightwalletd", self.lwd_name), ("zakura", self.node_name)):
            try:
                expected_id = self._container_ids.get(role)
                if expected_id is None:
                    if ("container", name) not in self._attempted_resources:
                        continue
                    expected_id = self._owned_resource_id_if_present("container", name, deadline)
                    if expected_id is None:
                        continue
                    self._container_ids[role] = expected_id
                self._assert_owned("container", name, expected_id, deadline)
                self._docker(["stop", "--time", "5", expected_id], deadline=deadline)
                inspected = self._assert_owned("container", name, expected_id, deadline)
                state = inspected.get("State")
                if (not isinstance(state, dict)
                    or any(state.get(field) is not False for field in ("Running", "Paused", "Restarting"))
                    or type(state.get("Pid")) is not int or state["Pid"] != 0):
                    raise FixtureError("owned container stop was not proved")
                stopped.append({"role": role, "name": name, "id": expected_id})
            except BaseException as error:
                errors.append(f"container {name}: {error}")

        port_proofs = []
        for role, lease in self._port_leases.items():
            try:
                lease.handoff()
                if lease.descriptor < 0:
                    raise FixtureError("retained fixture lost its cooperative port lock")
                port_proofs.append({"role": role, "port": lease.port, "lock_retained": True})
            except BaseException as error:
                errors.append(f"port lease {role}: {error}")
        proof = {
            "schema_version": 1,
            "run_id": self.run_id,
            "mode": "stopped-retained-terminal",
            "stopped": stopped,
            "identity": {"network": self._network_id, "lightwalletd_volume": self._volume_name,
                         "containers": dict(self._container_ids)},
            "port_leases": port_proofs,
            "errors": errors,
            "complete": not errors,
        }
        try:
            self._write_json("retention-proof.json", proof)
        except BaseException as error:
            errors.append(f"retention proof: {error}")
            proof["complete"] = False
        self._retention_proof = proof
        return proof

    def close(self) -> dict[str, Any]:
        """Remove only resources whose IDs and ownership labels still match."""
        self._assert_not_retained()
        if self._closed:
            if self._cleanup_proof is not None:
                return self._cleanup_proof
            return {"schema_version": 1, "run_id": self.run_id, "removed": [], "errors": [], "complete": True}

        try:
            self._capture_diagnostics("close")
        except BaseException:
            pass
        removed: list[dict[str, str]] = []
        errors: list[str] = []
        deadline = time.monotonic() + self.timeout
        resources: list[tuple[str, str, str | None]] = [
            ("container", self.donor_name, self._container_ids.get("zakura_donor")),
            ("container", self.lwd_name, self._container_ids.get("lightwalletd")),
            ("container", self.node_name, self._container_ids.get("zakura")),
            ("volume", self.lwd_volume, self._volume_name),
            ("network", self.network_name, self._network_id),
        ]
        for kind, name, expected_id in resources:
            try:
                if expected_id is None:
                    if (kind, name) not in self._attempted_resources:
                        continue
                    expected_id = self._owned_resource_id_if_present(kind, name, deadline)
                    if expected_id is None:
                        self._attempted_resources.discard((kind, name))
                        continue
                self._assert_owned(kind, name, expected_id, deadline)
                command = [kind, "rm"]
                if kind == "container":
                    command.append("--force")
                command.append(expected_id if kind in {"container", "network"} else name)
                self._docker(command, deadline=deadline)
                self._ensure_resource_absent(kind, name, deadline)
                removed.append({"kind": kind, "name": name, "id": expected_id})
                self._forget_resource(kind, name)
            except BaseException as error:
                errors.append(f"{kind} {name}: {error}")

        port_proofs = []
        names = {"zakura": self.node_name, "lightwalletd": self.lwd_name,
                 "zakura_donor": self.donor_name}
        for role, lease in self._port_leases.items():
            try:
                lease.handoff()
                absent = (role not in self._container_ids
                          and ("container", names[role]) not in self._attempted_resources)
                if absent:
                    lease.close()
                port_proofs.append({"role": role, "port": lease.port,
                                    "lock_released": lease.descriptor < 0})
            except BaseException as error:
                errors.append(f"port lease {role}: {error}")

        proof = {
            "schema_version": 1,
            "run_id": self.run_id,
            "removed": removed,
            "errors": errors,
            "complete": not errors,
            "port_leases": port_proofs,
        }
        try:
            self._write_json("cleanup-proof.json", proof)
        except BaseException as error:
            errors.append(f"cleanup proof: {error}")
            proof["complete"] = False
        self._closed = bool(proof["complete"])
        self._cleanup_proof = proof
        return proof

    def _create_node(self, deadline: float) -> None:
        port = self._lease_loopback_port("zakura", deadline)
        mount = f"type=bind,src={self.config_path},dst=/config/zakurad.toml,readonly"
        self._attempted_resources.add(("container", self.node_name))
        self._port_leases["zakura"].handoff()
        completed = self._docker(
            [
                "create",
                "--name",
                self.node_name,
                *self._label_args(),
                "--network",
                self.network_name,
                "--network-alias",
                "zakura",
                "--publish",
                f"127.0.0.1:{port}:18232",
                "--mount",
                mount,
                "--env",
                "CONFIG_FILE_PATH=/config/zakurad.toml",
                ZAKURA_IMAGE,
                "zakurad",
                "start",
            ],
            deadline=deadline,
        )
        container_id = completed.stdout.strip()
        if not container_id:
            raise FixtureError("docker did not return the Zakura container ID")
        self._container_ids["zakura"] = container_id
        inspected = self._assert_owned("container", self.node_name, container_id, deadline)
        if inspected.get("Image") != ZAKURA_IMAGE_ID:
            raise FixtureError("Zakura container image identity does not match the pinned digest")

    def _ensure_donor(self, deadline: float) -> dict[str, str]:
        if self._donor_rpc_url is not None:
            donor_id = self._container_ids.get("zakura_donor")
            if donor_id is None:
                raise FixtureError("donor RPC exists without an owned container identity")
            self._assert_container_running(self.donor_name, donor_id, deadline)
            return {"name": self.donor_name, "id": donor_id}
        self._ensure_resource_absent("container", self.donor_name, deadline)
        port = self._lease_loopback_port("zakura_donor", deadline)
        mount = f"type=bind,src={self.config_path},dst=/config/zakurad.toml,readonly"
        self._attempted_resources.add(("container", self.donor_name))
        self._port_leases["zakura_donor"].handoff()
        completed = self._docker(
            [
                "create",
                "--name",
                self.donor_name,
                *self._label_args(),
                "--network",
                self.network_name,
                "--network-alias",
                "zakura-donor",
                "--publish",
                f"127.0.0.1:{port}:18232",
                "--mount",
                mount,
                "--env",
                "CONFIG_FILE_PATH=/config/zakurad.toml",
                ZAKURA_IMAGE,
                "zakurad",
                "start",
            ],
            deadline=deadline,
        )
        donor_id = completed.stdout.strip()
        if not donor_id:
            raise FixtureError("docker did not return the donor Zakura container ID")
        self._container_ids["zakura_donor"] = donor_id
        inspected = self._assert_owned(
            "container", self.donor_name, donor_id, deadline
        )
        if inspected.get("Image") != ZAKURA_IMAGE_ID:
            raise FixtureError("donor Zakura image identity does not match the pinned digest")
        self._docker(["start", self.donor_name], deadline=deadline)
        donor_port = self._published_port(self.donor_name, "18232/tcp", deadline)
        self._donor_rpc_url = f"http://127.0.0.1:{donor_port}"
        last_error: BaseException | None = None
        while True:
            self._assert_container_running(self.donor_name, donor_id, deadline)
            try:
                if self._donor_rpc("getblockcount", deadline=deadline) != 0:
                    raise FixtureError("donor node did not start at genesis")
                best_hash = self._required_hash(
                    self._donor_rpc("getbestblockhash", deadline=deadline),
                    "donor best hash",
                )
                return {"name": self.donor_name, "id": donor_id, "genesis_hash": best_hash}
            except (FixtureError, OSError, urllib.error.URLError) as error:
                last_error = error
            if time.monotonic() >= deadline:
                raise FixtureError(f"donor Zakura readiness timed out: {last_error}")
            time.sleep(min(0.1, self._remaining(deadline)))

    def _create_lightwalletd(self, deadline: float) -> None:
        port = self._lease_loopback_port("lightwalletd", deadline)
        self._attempted_resources.add(("container", self.lwd_name))
        self._port_leases["lightwalletd"].handoff()
        completed = self._docker(
            [
                "create",
                "--name",
                self.lwd_name,
                *self._label_args(),
                "--network",
                self.network_name,
                "--publish",
                f"127.0.0.1:{port}:9067",
                "--mount",
                f"type=volume,src={self.lwd_volume},dst=/var/lib/lightwalletd",
                "--user",
                "0:0",
                LIGHTWALLETD_IMAGE,
                "--no-tls-very-insecure",
                "--grpc-bind-addr",
                "0.0.0.0:9067",
                "--rpchost",
                "zakura",
                "--rpcport",
                "18232",
                "--rpcuser",
                "unused",
                "--rpcpassword",
                "unused",
                "--data-dir",
                "/var/lib/lightwalletd",
                "--log-file",
                "/dev/stdout",
            ],
            deadline=deadline,
        )
        container_id = completed.stdout.strip()
        if not container_id:
            raise FixtureError("docker did not return the lightwalletd container ID")
        self._container_ids["lightwalletd"] = container_id
        inspected = self._assert_owned("container", self.lwd_name, container_id, deadline)
        if inspected.get("Image") != LIGHTWALLETD_IMAGE_ID:
            raise FixtureError("lightwalletd container image identity does not match the pinned digest")

    def _wait_node(self, deadline: float) -> dict[str, Any]:
        last_error: BaseException | None = None
        while True:
            self._assert_container_running(self.node_name, self._container_ids["zakura"], deadline)
            try:
                blockchain = self.rpc("getblockchaininfo", deadline=deadline)
                mempool = self.rpc("getmempoolinfo", deadline=deadline)
                best_hash = self.rpc("getbestblockhash", deadline=deadline)
                if not isinstance(blockchain, dict) or not isinstance(mempool, dict):
                    raise FixtureError("Zakura readiness RPC returned invalid objects")
                if not isinstance(best_hash, str) or not _HEX_HASH.fullmatch(best_hash):
                    raise FixtureError("Zakura readiness RPC returned an invalid best hash")
                return {"blockchain": blockchain, "mempool": mempool, "best_hash": best_hash.lower()}
            except (FixtureError, OSError, urllib.error.URLError) as error:
                last_error = error
            if time.monotonic() >= deadline:
                raise FixtureError(f"Zakura readiness timed out: {last_error}")
            time.sleep(min(0.1, self._remaining(deadline)))

    def _parity_once(self, deadline: float) -> dict[str, Any]:
        blockchain = self.rpc("getblockchaininfo", deadline=deadline)
        if not isinstance(blockchain, dict):
            raise FixtureError("getblockchaininfo returned a non-object")
        height = self._integer(blockchain.get("blocks"), "node blocks")
        node_hash = self.rpc("getbestblockhash", deadline=deadline)
        if not isinstance(node_hash, str) or not _HEX_HASH.fullmatch(node_hash):
            raise FixtureError("getbestblockhash returned an invalid hash")
        node_hash = node_hash.lower()
        tree = self.rpc("z_gettreestate", [str(height)], deadline=deadline)
        if not isinstance(tree, dict):
            raise FixtureError("z_gettreestate returned a non-object")
        if self._integer(tree.get("height"), "node tree height") != height:
            raise FixtureError("Zakura tree height does not match its chain tip")
        if str(tree.get("hash", "")).lower() != node_hash:
            raise FixtureError("Zakura tree hash does not match its chain tip")

        info = self.grpc("GetLightdInfo", deadline=deadline)
        latest = self.grpc("GetLatestBlock", deadline=deadline)
        lwd_tree = self.grpc("GetTreeState", {"height": str(height)}, deadline=deadline)
        if self._integer(info.get("blockHeight"), "lightwalletd blockHeight") != height:
            raise FixtureError("lightwalletd info height has not reached the node tip")
        if self._integer(latest.get("height"), "lightwalletd latest height") != height:
            raise FixtureError("lightwalletd latest height has not reached the node tip")
        if self._integer(lwd_tree.get("height"), "lightwalletd tree height") != height:
            raise FixtureError("lightwalletd tree height has not reached the node tip")
        if str(lwd_tree.get("hash", "")).lower() != node_hash:
            raise FixtureError("lightwalletd TreeState hash does not match Zakura")

        latest_hash, orientation = self._decode_block_id_hash(latest.get("hash"), node_hash)
        node_time = self._integer(tree.get("time"), "node tree time")
        if self._integer(lwd_tree.get("time"), "lightwalletd tree time") != node_time:
            raise FixtureError("lightwalletd TreeState time does not match Zakura")
        tree_fields = {
            "sapling": "saplingTree",
            "orchard": "orchardTree",
        }
        if height >= self.nu6_3_activation_height:
            tree_fields["ironwood"] = "ironwoodTree"
        matched_trees: dict[str, str] = {}
        for pool, lwd_key in tree_fields.items():
            if pool not in tree or lwd_key not in lwd_tree:
                raise FixtureError(f"{pool} tree evidence is missing")
            pool_value = tree[pool]
            if not isinstance(pool_value, dict):
                raise FixtureError(f"Zakura {pool} tree is malformed")
            if "commitments" not in pool_value:
                raise FixtureError(f"Zakura {pool} commitments are missing")
            commitments = pool_value["commitments"]
            if not isinstance(commitments, dict):
                raise FixtureError(f"Zakura {pool} commitments are malformed")
            if "finalState" not in commitments:
                raise FixtureError(f"Zakura {pool} finalState is missing")
            node_raw = commitments["finalState"]
            lwd_raw = lwd_tree[lwd_key]
            if not isinstance(node_raw, str) or not isinstance(lwd_raw, str):
                raise FixtureError(f"{pool} tree evidence is not text")
            node_value = node_raw.lower()
            lwd_value = lwd_raw.lower()
            if node_value != lwd_value:
                raise FixtureError(f"lightwalletd {pool} tree does not match Zakura")
            matched_trees[pool] = node_value

        branch = str(info.get("consensusBranchId", "")).lower()
        expected_branch = (
            NU63_BRANCH_ID
            if height >= self.nu6_3_activation_height
            else NU62_BRANCH_ID
        )
        if branch != expected_branch:
            era = "NU6.3" if height >= self.nu6_3_activation_height else "NU6.2"
            raise FixtureError(f"lightwalletd consensus branch is not {era}")
        chain_name = info.get("chainName")
        tree_network = lwd_tree.get("network")
        if chain_name not in {"test", "regtest"} or tree_network not in {"test", "regtest"}:
            raise FixtureError("lightwalletd did not report a test/regtest chain")
        if chain_name != tree_network:
            raise FixtureError("lightwalletd chainName and TreeState network disagree")

        return {
            "height": height,
            "hash": node_hash,
            "time": node_time,
            "trees": matched_trees,
            "latest_block_hash": latest_hash,
            "latest_block_hash_orientation": orientation,
            "chain_name": chain_name,
            "consensus_branch_id": branch,
        }

    def _assert_containers_running(self, deadline: float) -> None:
        self._assert_container_running(self.node_name, self._container_ids.get("zakura"), deadline)
        self._assert_container_running(self.lwd_name, self._container_ids.get("lightwalletd"), deadline)

    def _assert_container_running(
        self, name: str, expected_id: str | None, deadline: float
    ) -> None:
        if expected_id is None:
            raise FixtureError(f"container {name} was not created")
        inspected = self._assert_owned("container", name, expected_id, deadline)
        state = inspected.get("State")
        if not isinstance(state, dict) or state.get("Running") is not True:
            raise FixtureError(f"owned container {name} is not running")

    @staticmethod
    def _validated_txids(value: Any, *, maximum: int = 8, minimum: int = 1) -> list[str]:
        if (
            not isinstance(value, list)
            or not minimum <= len(value) <= maximum
            or any(
                not isinstance(txid, str)
                or not re.fullmatch(r"[0-9a-f]{64}", txid)
                for txid in value
            )
            or len(set(value)) != len(value)
        ):
            raise FixtureError(
                f"transaction IDs must be {minimum}..{maximum} unique lowercase 64-byte hex IDs"
            )
        return sorted(value)

    @staticmethod
    def _required_hash(value: Any, label: str) -> str:
        if not isinstance(value, str) or not _HEX_HASH.fullmatch(value):
            raise FixtureError(f"{label} is not a block hash")
        return value.lower()

    @staticmethod
    def _required_hex(value: Any, label: str) -> str:
        if (
            not isinstance(value, str)
            or not value
            or len(value) % 2
            or any(character not in "0123456789abcdefABCDEF" for character in value)
        ):
            raise FixtureError(f"{label} is not hexadecimal bytes")
        return value.lower()

    def _mempool_raw(
        self,
        rpc_call: Callable[..., Any],
        deadline: float,
    ) -> dict[str, str]:
        txids = rpc_call("getrawmempool", deadline=deadline)
        if (
            not isinstance(txids, list)
            or len(txids) > 64
            or any(
                not isinstance(txid, str)
                or not re.fullmatch(r"[0-9a-f]{64}", txid)
                for txid in txids
            )
            or len(set(txids)) != len(txids)
        ):
            raise FixtureError("mempool transaction list is malformed")
        normalized = sorted(txids)
        raw: dict[str, str] = {}
        for txid in normalized:
            transaction = rpc_call(
                "getrawtransaction", [txid, 1], deadline=deadline
            )
            if not isinstance(transaction, dict) or transaction.get("txid") != txid:
                raise FixtureError("mempool transaction identity is malformed")
            raw[txid] = self._required_hex(
                transaction.get("hex"), "mempool raw transaction"
            )
        return raw

    def _block_transactions(
        self,
        rpc_call: Callable[..., Any],
        block_hash: str,
        deadline: float,
    ) -> dict[str, str]:
        block = rpc_call("getblock", [block_hash, 2], deadline=deadline)
        if not isinstance(block, dict) or not isinstance(block.get("tx"), list):
            raise FixtureError("verbose block transaction list is malformed")
        result: dict[str, str] = {}
        for transaction in block["tx"]:
            if not isinstance(transaction, dict):
                raise FixtureError("verbose block transaction is malformed")
            txid = self._required_hash(transaction.get("txid"), "block transaction ID")
            if txid in result:
                raise FixtureError("verbose block contains a duplicate transaction")
            result[txid] = self._required_hex(
                transaction.get("hex"), "block raw transaction"
            )
        return result

    def _validate_replacement_block(
        self,
        block: Any,
        *,
        expected_hash: str,
        expected_height: int,
        expected_parent: str,
    ) -> None:
        if not isinstance(block, dict):
            raise FixtureError("donor replacement block is malformed")
        if self._required_hash(
            block.get("hash"), "donor replacement block hash"
        ) != expected_hash:
            raise FixtureError("donor replacement block hash differs from generate")
        if self._integer(
            block.get("height"), "donor replacement block height"
        ) != expected_height:
            raise FixtureError("donor replacement block height is unexpected")
        if self._required_hash(
            block.get("previousblockhash"), "donor replacement parent hash"
        ) != expected_parent:
            raise FixtureError("donor replacement block is not linked to the fork")
        transactions = block.get("tx")
        if not isinstance(transactions, list) or len(transactions) != 1:
            raise FixtureError("donor replacement block is not coinbase-only")
        coinbase = transactions[0]
        if not isinstance(coinbase, dict):
            raise FixtureError("donor replacement coinbase transaction is malformed")
        self._required_hash(
            coinbase.get("txid"), "donor replacement coinbase transaction ID"
        )
        inputs = coinbase.get("vin")
        if not isinstance(inputs, list) or len(inputs) != 1:
            raise FixtureError("donor replacement coinbase input is malformed")
        coinbase_input = inputs[0]
        if not isinstance(coinbase_input, dict):
            raise FixtureError("donor replacement coinbase input is malformed")
        self._required_hex(
            coinbase_input.get("coinbase"), "donor replacement coinbase input"
        )

    def _restore_invalidated_mempool(
        self,
        fork_height: int,
        fork_hash: str,
        required: list[str],
        before_pool: dict[str, str],
        old_block: dict[str, str],
        deadline: float,
    ) -> tuple[dict[str, str], dict[str, Any]]:
        """Restore captured required bytes, not a natural reinsertion promise."""
        expected = {txid: before_pool.get(txid, old_block.get(txid))
                    for txid in set(required)}
        if any(raw is None for raw in expected.values()):
            raise FixtureError("required restoration bytes were not captured before reorg")
        if any(before_pool[txid] != old_block[txid]
               for txid in set(before_pool) & set(old_block)):
            raise FixtureError("captured branch and mempool raw bytes disagree")
        # invalidateblock is synchronous, but allow a bounded observation retry
        # for state-tip publication. Do not spend the case budget waiting for
        # the node's asynchronous orphan-transaction reinsertion path.
        observation_deadline = min(deadline, time.monotonic() + 5.0)
        while True:
            if (self._integer(self.rpc("getblockcount", deadline=observation_deadline), "invalidated tip height") == fork_height
                and self._required_hash(self.rpc("getbestblockhash", deadline=observation_deadline), "invalidated tip hash") == fork_hash):
                break
            if time.monotonic() >= observation_deadline:
                raise FixtureError("main node did not publish the exact invalidated fork parent")
            time.sleep(min(0.05, self._remaining(observation_deadline)))

        natural = self._mempool_raw(self.rpc, deadline)
        for txid, raw in natural.items():
            if raw != before_pool.get(txid, old_block.get(txid)):
                raise FixtureError("naturally reinserted raw transaction was not captured")
        missing = set(expected) - set(natural)
        # Canonical branch order puts mined parents before their descendants;
        # remaining pre-reorg pending transactions follow that restored branch.
        order = [txid for txid in old_block if txid in missing]
        order.extend(txid for txid in before_pool if txid in missing and txid not in order)
        resubmitted = []
        for txid in order:
            raw = self._required_hex(expected[txid], "captured restoration transaction")
            # An earlier parent submission or the node's own reinsertion may
            # already have restored this tx. Re-observe before the one RPC.
            observed = self._mempool_raw(self.rpc, deadline)
            if txid in observed:
                if observed[txid] != raw:
                    raise FixtureError("restoration changed captured transaction bytes")
                natural[txid] = raw
                continue
            accepted = self.rpc("sendrawtransaction", [raw], deadline=deadline)
            if accepted != txid:
                raise FixtureError("captured restoration submission returned a different txid")
            exact = self.rpc("getrawtransaction", [txid, 1], deadline=deadline)
            self._require_exact_pending_transaction(exact, txid, raw)
            resubmitted.append(txid)

        held = self._mempool_raw(self.rpc, deadline)
        self._validated_txids(list(held), maximum=64, minimum=0)
        if not set(expected) <= set(held):
            raise FixtureError("captured restoration transactions are absent from mempool")
        for txid, raw in held.items():
            if raw != before_pool.get(txid, old_block.get(txid)):
                raise FixtureError("restored mempool transaction bytes differ from capture")
            self._require_exact_pending_transaction(
                self.rpc("getrawtransaction", [txid, 1], deadline=deadline),
                txid, raw,
            )
        if (self.rpc("getblockcount", deadline=deadline) != fork_height
            or self.rpc("getbestblockhash", deadline=deadline) != fork_hash
            or self.rpc("getpeerinfo", deadline=deadline) != []):
            raise FixtureError("restoration changed the peerless fork tip")
        return held, {
            "mode": "captured-exact-raw-controlled-restoration",
            "natural_txids": sorted(set(held) - set(resubmitted) - set(before_pool)),
            "preserved_pending_txids": sorted(set(before_pool) & set(held)),
            "invalidated_pending_txids": sorted(set(before_pool) - set(held)),
            "invalidated_pending_raw_sha256": {
                txid: hashlib.sha256(bytes.fromhex(before_pool[txid])).hexdigest()
                for txid in sorted(set(before_pool) - set(held))
            },
            "resubmitted_txids": sorted(resubmitted),
            "resubmitted_raw_sha256": {
                txid: hashlib.sha256(bytes.fromhex(expected[txid])).hexdigest()
                for txid in resubmitted
            },
            "submission_attempts_per_txid": {txid: 1 for txid in resubmitted},
        }

    @staticmethod
    def _require_exact_pending_transaction(value: Any, txid: str, raw: str) -> None:
        if (not isinstance(value, dict) or value.get("txid") != txid
            or value.get("hex") != raw or value.get("blockhash")
            or any(type(value.get(field, 0)) is not int or value.get(field, 0) != 0
                   for field in ("confirmations", "height"))):
            raise FixtureError("restored transaction is changed or confirmed")

    def _wait_invalidated_mempool(
        self,
        fork_height: int,
        fork_hash: str,
        required: list[str],
        before_pool: dict[str, str],
        old_block: dict[str, str],
        deadline: float,
        *,
        maximum_transactions: int = 8,
    ) -> dict[str, str]:
        last_error: BaseException | None = None
        while True:
            try:
                height = self._integer(
                    self.rpc("getblockcount", deadline=deadline),
                    "post-invalidation height",
                )
                best_hash = self._required_hash(
                    self.rpc("getbestblockhash", deadline=deadline),
                    "post-invalidation tip hash",
                )
                if height != fork_height or best_hash != fork_hash:
                    raise FixtureError("main node has not reached the exact fork parent")
                held = self._mempool_raw(self.rpc, deadline)
                if not set(required) <= set(held):
                    raise FixtureError("required transactions were not reverified into mempool")
                if not set(before_pool) <= set(held):
                    raise FixtureError("a pre-invalidation mempool transaction was lost")
                self._validated_txids(list(held), maximum=maximum_transactions)
                for txid, raw in held.items():
                    expected = before_pool.get(txid, old_block.get(txid))
                    if expected is None or raw != expected:
                        raise FixtureError("reverified mempool raw transaction changed")
                return held
            except (FixtureError, OSError, urllib.error.URLError) as error:
                last_error = error
            if time.monotonic() >= deadline:
                raise FixtureError(
                    f"mempool revalidation after invalidate timed out: {last_error}"
                )
            time.sleep(min(0.05, self._remaining(deadline)))

    def _wait_required_mempool(
        self,
        required: list[str],
        deadline: float,
    ) -> dict[str, str]:
        last_pool: dict[str, str] = {}
        while True:
            last_pool = self._mempool_raw(self.rpc, deadline)
            if set(required) <= set(last_pool):
                return last_pool
            if time.monotonic() >= deadline:
                raise FixtureError(
                    "required transactions did not reach the main mempool: "
                    f"observed {sorted(last_pool)}"
                )
            time.sleep(min(0.05, self._remaining(deadline)))

    def _assert_owned(
        self, kind: str, name: str, expected_id: str, deadline: float
    ) -> dict[str, Any]:
        inspected = self._inspect(kind, name, deadline)
        actual_id = inspected.get("Id") if kind != "volume" else inspected.get("Name")
        if actual_id != expected_id:
            raise FixtureError(f"{kind} {name} identity changed")
        labels = inspected.get("Config", {}).get("Labels") if kind == "container" else inspected.get("Labels")
        if not isinstance(labels, dict) or any(labels.get(key) != value for key, value in self.labels.items()):
            raise FixtureError(f"{kind} {name} ownership labels changed")
        if kind == "volume" and inspected.get("Driver") != "local":
            raise FixtureError(f"volume {name} does not use the local driver")
        return inspected

    def _inspect(self, kind: str, name: str, deadline: float) -> dict[str, Any]:
        completed = self._docker([kind, "inspect", name], deadline=deadline)
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise FixtureError(f"docker {kind} inspect returned invalid JSON") from error
        if not isinstance(payload, list) or len(payload) != 1 or not isinstance(payload[0], dict):
            raise FixtureError(f"docker {kind} inspect returned an invalid result")
        return payload[0]

    def _ensure_resource_absent(self, kind: str, name: str, deadline: float) -> None:
        completed = self._docker([kind, "inspect", name], deadline=deadline, check=False)
        if completed.returncode == 0:
            raise FixtureError(f"refusing to reuse existing {kind} {name}")
        if not self._is_resource_absent(kind, name, completed):
            raise FixtureError(f"could not prove {kind} {name} is absent: {completed.stderr.strip()}")

    @staticmethod
    def _is_resource_absent(kind: str, name: str, completed: subprocess.CompletedProcess[str]) -> bool:
        """Recognize the exact supported CLI daemon response, not transport errors.

        Missing Docker sockets/credential helpers and another resource's error
        cannot establish absence of this resource. The installed Docker CLI
        emits an empty inspect array plus a kind/name-specific daemon error.
        """
        expected = {
            "container": f"Error response from daemon: No such container: {name}",
            "network": f"Error response from daemon: network {name} not found",
            "volume": f"Error response from daemon: get {name}: no such volume",
        }.get(kind)
        if completed.returncode != 1 or completed.stderr.strip() != expected:
            return False
        try:
            return json.loads(completed.stdout) == []
        except json.JSONDecodeError:
            return False

    def _owned_resource_id_if_present(
        self, kind: str, name: str, deadline: float
    ) -> str | None:
        completed = self._docker([kind, "inspect", name], deadline=deadline, check=False)
        if completed.returncode != 0:
            if self._is_resource_absent(kind, name, completed):
                return None
            raise FixtureError(
                f"could not inspect attempted {kind} {name}: {completed.stderr.strip()}"
            )
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise FixtureError(f"docker {kind} inspect returned invalid JSON") from error
        if not isinstance(payload, list) or len(payload) != 1 or not isinstance(payload[0], dict):
            raise FixtureError(f"docker {kind} inspect returned an invalid result")
        inspected = payload[0]
        labels = (
            inspected.get("Config", {}).get("Labels")
            if kind == "container"
            else inspected.get("Labels")
        )
        if not isinstance(labels, dict) or any(
            labels.get(key) != value for key, value in self.labels.items()
        ):
            raise FixtureError(f"attempted {kind} {name} is not owned by this run")
        resource_id = inspected.get("Name") if kind == "volume" else inspected.get("Id")
        if not isinstance(resource_id, str) or not resource_id:
            raise FixtureError(f"attempted {kind} {name} has no identity")
        if kind == "volume" and (
            resource_id != name or inspected.get("Driver") != "local"
        ):
            raise FixtureError(f"attempted volume {name} has an unexpected identity")
        return resource_id

    def _forget_resource(self, kind: str, name: str) -> None:
        self._attempted_resources.discard((kind, name))
        if kind == "network":
            self._network_id = None
        elif kind == "volume":
            self._volume_name = None
        elif name == self.node_name:
            self._container_ids.pop("zakura", None)
        elif name == self.donor_name:
            self._container_ids.pop("zakura_donor", None)
            self._donor_rpc_url = None
        elif name == self.lwd_name:
            self._container_ids.pop("lightwalletd", None)

    def _verify_image(self, image: str, expected_id: str, deadline: float) -> dict[str, str]:
        completed = self._docker(["image", "inspect", image], deadline=deadline)
        try:
            payload = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise FixtureError(f"docker image inspect returned invalid JSON for {image}") from error
        if not isinstance(payload, list) or len(payload) != 1 or not isinstance(payload[0], dict):
            raise FixtureError(f"docker image inspect returned an invalid result for {image}")
        image_id = payload[0].get("Id")
        if image_id != expected_id:
            raise FixtureError(f"local image identity does not match pinned digest: {image}")
        return {"reference": image, "id": image_id}

    def _published_port(self, container: str, port: str, deadline: float) -> int:
        output = self._docker(["port", container, port], deadline=deadline).stdout.strip()
        matches = re.findall(r"^127\.0\.0\.1:(\d+)$", output, flags=re.MULTILINE)
        if len(matches) != 1:
            raise FixtureError(f"container {container} has no unique localhost port for {port}")
        value = int(matches[0])
        if not 0 < value <= 65535:
            raise FixtureError(f"container {container} returned an invalid published port")
        role = {self.node_name: "zakura", self.lwd_name: "lightwalletd",
                self.donor_name: "zakura_donor"}.get(container)
        lease = self._port_leases.get(role)
        if lease is None or value != lease.port:
            raise FixtureError(f"container {container} published port differs from its owned lease")
        return value

    def _lease_loopback_port(self, role: str, deadline: float) -> int:
        self._remaining(deadline)
        if role in self._port_leases:
            return self._port_leases[role].port
        # Share the coordinator's per-UID cooperative port locks without a
        # reverse import from the standalone fixture into the wallet harness.
        root = Path(tempfile.gettempdir()) / f"vizor-wallet-native-e2e-{os.getuid()}"
        for directory in (root, root / "ports"):
            directory.mkdir(mode=0o700, exist_ok=True)
            details = directory.lstat()
            forbidden_mode = 0o022 if directory == root else 0o077
            if (not stat.S_ISDIR(details.st_mode) or directory.is_symlink()
                or details.st_uid != os.getuid() or stat.S_IMODE(details.st_mode) & forbidden_mode):
                raise FixtureError("native port lock directory is unsafe")
        for _ in range(100):
            self._remaining(deadline)
            reserved = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            descriptor = None
            try:
                reserved.bind(("127.0.0.1", 0))
                reserved.listen(1)
                port = reserved.getsockname()[1]
                descriptor = os.open(root / "ports" / f"{port}.lock",
                                     os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
                details = os.fstat(descriptor)
                if (not stat.S_ISREG(details.st_mode) or details.st_nlink != 1 or details.st_uid != os.getuid()
                    or stat.S_IMODE(details.st_mode) & 0o077):
                    raise FixtureError("native port lock file is unsafe")
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    os.close(descriptor)
                    descriptor = None
                    reserved.close()
                    continue
                os.ftruncate(descriptor, 0)
                os.write(descriptor, f"run_id={self.run_id}\nrole={role}\npid={os.getpid()}\n".encode())
                self._port_leases[role] = _LoopbackPortLease(port, reserved, descriptor)
                return port
            except BaseException:
                if descriptor is not None:
                    os.close(descriptor)
                reserved.close()
                raise
        raise FixtureError("could not reserve a cooperatively locked native port")

    def _write_config(self) -> None:
        activation_heights = (
            '"NU6.3" = 1'
            if self.profile == DIRECT_HEIGHT1_PROFILE
            else '"NU6.2" = 1\n"NU6.3" = 500'
        )
        config = f'''[network]
network = "Regtest"
listen_addr = "0.0.0.0:18233"
p2p_stack = "legacy"
cache_dir = false
initial_testnet_peers = []

[network.testnet_parameters.activation_heights]
{activation_heights}

[[network.testnet_parameters.lockbox_disbursements]]
address = "{LOCKBOX_ADDRESS}"
amount = 0

[rpc]
listen_addr = "0.0.0.0:18232"
enable_cookie_auth = false
parallel_cpu_threads = 1

[sync]
parallel_cpu_threads = 1

[state]
ephemeral = false
cache_dir = "{NODE_STATE_CACHE_DIR}"
should_backup_non_finalized_state = true

[mempool]
debug_enable_at_height = 0

[mining]
internal_miner = false
miner_address = "{self.miner_address}"

[tracing]
use_color = false
'''
        self._write_text(self.config_path.name, config)
        os.chmod(self.config_path, 0o644)

    def _decode_block_id_hash(self, encoded: Any, expected: str) -> tuple[str, str]:
        if not isinstance(encoded, str):
            raise FixtureError("lightwalletd latest block hash is not base64 text")
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (ValueError, TypeError) as error:
            raise FixtureError("lightwalletd latest block hash is invalid base64") from error
        if len(raw) != 32:
            raise FixtureError("lightwalletd latest block hash is not 32 bytes")
        direct = raw.hex()
        reversed_hash = raw[::-1].hex()
        if direct == expected:
            return direct, "display"
        if reversed_hash == expected:
            return reversed_hash, "wire-reversed"
        raise FixtureError("lightwalletd latest block hash does not match Zakura")

    @staticmethod
    def _integer(value: Any, field: str) -> int:
        if isinstance(value, bool):
            raise FixtureError(f"{field} is not an integer")
        if isinstance(value, int):
            result = value
        elif isinstance(value, str) and value.isdecimal():
            result = int(value)
        else:
            raise FixtureError(f"{field} is not an integer")
        if result < 0:
            raise FixtureError(f"{field} is negative")
        return result

    @staticmethod
    def _validate_hashes(value: Any, *, expected: int) -> None:
        if not isinstance(value, list) or len(value) != expected:
            raise FixtureError("generate returned an unexpected number of hashes")
        if any(not isinstance(item, str) or not _HEX_HASH.fullmatch(item) for item in value):
            raise FixtureError("generate returned an invalid block hash")

    def _label_args(self) -> list[str]:
        result: list[str] = []
        for key, value in self.labels.items():
            result.extend(["--label", f"{key}={value}"])
        return result

    def _docker(
        self,
        args: list[str],
        *,
        deadline: float,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return self._run(["docker", *args], timeout=self._remaining(deadline), check=check)

    @staticmethod
    def _run(
        command: list[str],
        *,
        timeout: float,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        try:
            completed = subprocess.run(
                command,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=max(0.001, timeout),
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise FixtureError(f"command failed: {command[0]}: {error}") from error
        if check and completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise FixtureError(f"command failed ({completed.returncode}): {' '.join(command[:3])}: {detail}")
        return completed

    @staticmethod
    def _remaining(deadline: float) -> float:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise FixtureError("fixture operation timed out")
        return remaining

    def _capture_diagnostics(self, label: str) -> None:
        deadline = time.monotonic() + min(self.timeout, 5.0)
        for role, name in (
            ("zakura", self.node_name),
            ("zakura_donor", self.donor_name),
            ("lightwalletd", self.lwd_name),
        ):
            expected_id = self._container_ids.get(role)
            if expected_id is None:
                continue
            try:
                inspected = self._assert_owned("container", name, expected_id, deadline)
                self._write_json(f"{label}-{role}-inspect.json", inspected)
                completed = self._docker(["logs", expected_id], deadline=deadline, check=False)
                self._write_text(f"{label}-{role}.log", completed.stdout + completed.stderr)
            except BaseException as error:
                try:
                    self._write_text(f"{label}-{role}-diagnostic-error.txt", str(error))
                except BaseException:
                    pass

    def _write_json(self, name: str, payload: Any) -> None:
        self._write_text(name, json.dumps(payload, indent=2, sort_keys=True) + "\n")

    def _write_text(self, name: str, text: str) -> None:
        target = self.artifacts / name
        if target.parent != self.artifacts or target.is_symlink():
            raise FixtureError("artifact target escaped the fixture directory")
        temporary = self.artifacts / f".{name}.{uuid.uuid4().hex}.tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                output.write(text)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, target)
        finally:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass


__all__ = ["FixtureError", "RegtestFixture"]
