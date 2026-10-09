"""Case-owned pinned voting services; no shared Compose or wallet lifecycle."""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from e2e_runtime import (
    Cancelled, RunnerError,
)
from native_voting_build import ProducedVotingArtifacts
from native_ports import lease_native_ports
from native_worker_lifecycle import NativeWorkerCase


def write_json(path, value):
    with path.open("x", encoding="utf-8") as output:
        json.dump(value, output, indent=2)
        output.write("\n")

VOTE_SDK_REV = "36f5d828fc5be42d9a80baa38d1145c5541b229e"
PIR_REV = "20356d14f61a825ef28726f38270c37d604cc268"
MANAGER_KEY = "0" * 63 + "1"
RUNTIME_KEYS = frozenset({
    "ZCASH_E2E_VOTING_GATEWAY_URL", "ZCASH_E2E_VOTING_STATIC_CONFIG_URL",
    "ZCASH_E2E_VOTE_ROUND_ID", "ZCASH_E2E_VOTE_CHAIN_ID",
    "ZCASH_E2E_VOTE_VALIDATOR_HASH", "ZCASH_E2E_REUSE_MIGRATED_WALLET",
})
PORT_NAMES = ("pir", "api", "rpc", "gateway", "p2p", "grpc", "pprof")


def _sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _loopback_endpoint(value: str) -> str:
    parsed = urllib.parse.urlsplit(value)
    try:
        port = parsed.port
    except ValueError as error:
        raise RunnerError("invalid voting lightwalletd port") from error
    if (parsed.scheme != "http" or parsed.hostname != "127.0.0.1"
            or port is None or not 1 <= port <= 65535 or parsed.path not in ("", "/")
            or parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise RunnerError("voting requires an exact owned loopback lightwalletd URL")
    return f"127.0.0.1:{port}"


def patch_toml(text: str, updates: dict[tuple[str, str], object]) -> str:
    """Patch existing generated keys using TOML's JSON-compatible scalar subset.

    All other bytes remain SDK-generated. The actual pinned service parses the
    complete TOML at startup; no new Python-version or package requirement.
    """
    section = ""
    found: set[tuple[str, str]] = set()
    lines = []
    for line in text.splitlines(keepends=True):
        heading = re.fullmatch(r"\s*\[([^\[\]]+)\]\s*(?:#.*)?\n?", line)
        if heading:
            section = heading[1]
        key = re.match(r"\s*([\w-]+)\s*=", line)
        pair = (section, key[1]) if key else None
        if pair in updates:
            if pair in found:
                raise RunnerError(f"duplicate generated voting TOML key: {pair}")
            found.add(pair)
            line = f"{pair[1]} = {json.dumps(updates[pair])}\n"
        lines.append(line)
    if found != set(updates):
        raise RunnerError(f"missing generated voting TOML keys: {set(updates) - found}")
    result = "".join(lines)
    parsed = patched_bindings(result, set(updates))
    for (section, key), expected in updates.items():
        if parsed[(section, key)] != expected:
            raise RunnerError("generated voting TOML did not preserve isolated bindings")
    return result


def patched_bindings(text: str, keys: set[tuple[str, str]]) -> dict:
    """Read only the exact rewritten scalar keys, not arbitrary TOML."""
    section = ""
    found = {}
    for line in text.splitlines():
        heading = re.fullmatch(r"\s*\[([^\[\]]+)\]\s*(?:#.*)?", line)
        if heading:
            section = heading[1]
        item = re.fullmatch(r"\s*([\w-]+)\s*=\s*(.+)", line)
        pair = (section, item[1]) if item else None
        if pair in keys:
            if pair in found:
                raise RunnerError(f"duplicate rewritten voting binding: {pair}")
            found[pair] = json.loads(item[2])
    if set(found) != keys:
        raise RunnerError("missing rewritten voting binding")
    return found


def verify_participation(metrics: dict, tree: dict, *, slow_helper: bool) -> None:
    required = ["discovery_successes", "config_requests", "round_list_requests"]
    if slow_helper:
        required.append("slow_share_requests")
    if any(type(metrics.get(key)) is not int or metrics[key] <= 0 for key in required):
        raise RunnerError("real signed voting discovery/share submission was not exercised")
    if slow_helper and (type(metrics.get("slow_share_max_inflight")) is not int
                        or metrics["slow_share_max_inflight"] <= 1):
        raise RunnerError("slow voting helper did not observe concurrent share submission")
    index = tree.get("tree", {}).get("next_index")
    # Cosmos protobuf JSON encodes uint64 as a decimal string.
    if not ((type(index) is int and index > 0)
            or (isinstance(index, str) and re.fullmatch(r"[1-9][0-9]*", index))):
        raise RunnerError("real voting commitment tree remained empty")


class NativeVotingServices:
    def __init__(self, session, artifact, root, grpcurl, cancel_event):
        if (not isinstance(session, NativeWorkerCase) or session._finished
            or session._front is None or not isinstance(artifact, ProducedVotingArtifacts)):
            raise RunnerError("voting requires this original native case and producer")
        session.verify_owned()
        artifact.verify_unchanged()
        self.session, self.artifact = session, artifact
        self.root = Path(root).resolve(strict=True)
        self.sdk = artifact.sdk
        if (self.sdk / ".env").exists() or (self.sdk / ".env").is_symlink():
            raise RunnerError("pinned voting source must not load local .env overrides")
        self.grpcurl = Path(grpcurl).resolve(strict=True)
        self.cancel_event = cancel_event
        self.state = session.case.workspace.root / "voting"
        self.log_dir = self.state / "logs"
        self.config = self.state / "config"
        self.pir_data = self.state / "pir-data"
        self.vote_home = self.state / "vote-home"
        self.shims = self.state / "shims"
        self.temp = self.state / "tmp"
        self.binaries = artifact.binaries
        self.processes = []
        self.lease = None
        self.ports = {}
        self.runtime = {}
        self.deadline_ns = 0
        self.started = False
        self.closed = False
        self.slow_helper = False
        self._failed = False

    def _remaining(self) -> float:
        if self.cancel_event.is_set():
            raise Cancelled()
        remaining = (self.deadline_ns - time.monotonic_ns()) / 1e9
        if remaining <= 0:
            raise RunnerError("owned voting case deadline expired", 124)
        return remaining

    def _env(self) -> dict[str, str]:
        # Do not inherit global voting keys, paths, chain IDs or production URLs.
        env = {key: value for key, value in os.environ.items()
               if not key.startswith(("SVOTE", "ZASHI_", "VM_", "VAL_", "HELPER_"))
               and key not in {"CHAIN_ID", "MONIKER", "SENTRY_DSN", "CARGO_TARGET_DIR"}}
        env.update({"PATH": f"{self.shims}:{self.binaries['svoted'].parent}:" + env.get("PATH", ""),
                    "VM_PRIVKEYS": MANAGER_KEY,
                    "TMPDIR": str(self.temp),
                    "SVOTED_HOME": str(self.vote_home), "SVOTE_HOME": str(self.vote_home),
                    "SVOTE_ADMIN_DISABLE": "true", "SVOTE_HELPER_EXPOSE_QUEUE_STATUS": "true",
                    "SVOTE_HELPER_SENTRY_DSN": "", "SVOTE_PIR_CONFIG_URL": "",
                    "SVOTE_PIR_PRECOMPUTED_BASE_URL": "", "CHAIN_ID": "svote-1"})
        return env

    def _run(self, name, command, *, cwd=None, extra_env=None):
        self.session.verify_owned()
        arguments = [sys.executable, "-c",
            "import os,sys; os.chdir(sys.argv[1]); os.execvp(sys.argv[2],sys.argv[2:])",
            str(cwd or self.state), *command]
        result = self.session.case.run_command(arguments,
            env=dict(self._env(), **(extra_env or {})), timeout=self._remaining(),
            cancel_event=self.cancel_event, max_output_bytes=8*1024*1024)
        if result.returncode:
            raise RunnerError("original voting " + name + " failed; retain original process log",
                              result.returncode)
        return "".join(result.lines)

    def _check_processes(self) -> None:
        self._remaining()
        self.session.verify_owned()
        self.session._front.assert_running()
        for managed in self.processes:
            if managed.process.poll() is not None:
                raise RunnerError(f"owned voting service exited; see {managed.log_path}")

    def _spawn(self, name, command, ports):
        self._check_processes()
        managed = self.session.case.start_process(command, env=self._env(),
                                                  max_output_bytes=8*1024*1024)
        self.processes.append(managed)
        write_json(self.state / (name + "-owner.json"),
                   {"pid": managed.process.pid, "command": command})

    def _get(self, url: str) -> dict:
        self._check_processes()
        try:
            with urllib.request.urlopen(url, timeout=min(5, self._remaining())) as response:
                raw = response.read(4 * 1024 * 1024 + 1)
        except urllib.error.HTTPError as error:
            # urlopen raises this response before the context manager is entered.
            error.close()
            raise
        if len(raw) > 4 * 1024 * 1024:
            raise RunnerError("voting service response exceeded bounded size")
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise RunnerError("voting service returned non-object JSON")
        return value

    def _ready(self, url: str) -> None:
        while True:
            self._check_processes()
            try:
                self._get(url)
                return
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
                self.cancel_event.wait(min(0.1, self._remaining()))

    def _url(self, name: str) -> str:
        return f"http://127.0.0.1:{self.ports[name]}"

    def start(self, snapshot_height: int, lightwalletd_url: str, deadline_ns: int,
              slow_helper: bool = False, *, vote_window_seconds: int = 7200) -> dict[str, str]:
        if self.started or self.closed or self.state.exists():
            raise RunnerError("voting service state is single-use and must initially be absent")
        if type(snapshot_height) is not int or snapshot_height < 500:
            raise RunnerError("voting snapshot must follow actual Ironwood migration")
        if type(deadline_ns) is not int or type(slow_helper) is not bool:
            raise RunnerError("invalid voting service deadline or helper mode")
        if type(vote_window_seconds) is not int or not 1 <= vote_window_seconds <= 86400:
            raise RunnerError("voting window must be bounded positive seconds")
        endpoint = _loopback_endpoint(lightwalletd_url)
        self.deadline_ns = deadline_ns
        self.slow_helper = slow_helper
        self._remaining()
        self.state.mkdir(mode=0o700)
        for directory in (self.log_dir, self.config, self.pir_data, self.shims, self.temp):
            directory.mkdir(mode=0o700)
        try:
            self.artifact.verify_unchanged()
            manifest = json.loads(self.session.case.workspace.launch_environment()["VIZOR_E2E_CASE_MANIFEST"])
            self.lease = lease_native_ports(manifest["worker_id"], manifest["run_id"],
                                           port_names=PORT_NAMES)
            self.ports = dict(self.lease.ports)
            self.lease.release_sockets()
            write_json(self.state / "ports.json", self.ports)
            self._run("nullifier-export", [sys.executable, str(self.root / "scripts/e2e/export-regtest-ironwood-nullifiers.py"),
                "--grpcurl", str(self.grpcurl), "--proto-dir", str(self.root / "protos"), "--endpoint", endpoint,
                "--activation-height", "500", "--snapshot-height", str(snapshot_height),
                "--output", str(self.pir_data / "nullifiers.bin")])
            nullifiers = self.pir_data / "nullifiers.bin"
            if nullifiers.stat().st_size == 0 or nullifiers.stat().st_size % 32:
                raise RunnerError("actual migrated voting snapshot has no valid Ironwood nullifiers")
            write_json(self.pir_data / "nullifiers.dataset.json", {"zcash_network": "test", "nullifier_pool": "ironwood", "dataset_version": 2})
            (self.pir_data / "nullifiers.checkpoint").write_bytes(struct.pack("<QQ", snapshot_height, nullifiers.stat().st_size))
            self._run("pir-export", [str(self.binaries["pir-export"]), "--nullifiers", str(nullifiers),
                "--checkpoint", str(self.pir_data / "nullifiers.checkpoint"), "--output-dir", str(self.pir_data)])
            self._spawn("pir-server", [str(self.binaries["nf-server"]), "serve", "--zcash-network", "test",
                "--port", str(self.ports["pir"]), "--pir-data-dir", str(self.pir_data), "--lwd-url", lightwalletd_url,
                "--stale-threshold-secs", "0"], ("pir",))
            self._ready(self._url("pir") + "/ready")
            pir_root = self._get(self._url("pir") + "/root")
            if (pir_root.get("height") != snapshot_height or pir_root.get("nullifier_pool") != "ironwood"
                    or pir_root.get("dataset_version") != 2):
                raise RunnerError("PIR server did not serve the exact real migration snapshot")
            write_json(self.state / "pir-root.json", pir_root)
            self._run("vote-init", ["bash", str(self.sdk / "scripts/init.sh")], cwd=self.sdk)
            self._patch_bindings()
            self._spawn("vote-server", [str(self.binaries["svoted"]), "start", "--home", str(self.vote_home),
                "--rpc.laddr", "tcp://" + self._url("rpc").removeprefix("http://"),
                "--api.address", "tcp://" + self._url("api").removeprefix("http://")],
                ("api", "rpc", "p2p", "grpc", "pprof"))
            self._ready(self._url("api") + "/shielded-vote/v1/rounds")
            self._ready(self._url("api") + "/shielded-vote/v1/readiness")
            shim = self.shims / "grpcurl"
            shim.write_text("#!/bin/sh\nexec " + shlex.quote(str(self.grpcurl)) + " -plaintext -import-path "
                + shlex.quote(str(self.root / "protos")) + ' -proto service.proto "$@"\n')
            shim.chmod(0o700)
            self._run("create-round", [str(self.binaries["create-round"]),
                "--exact", "create_round_for_zashi", "--ignored", "--nocapture"],
                cwd=self.sdk, extra_env={"SVOTE_API_URL": self._url("api"), "SVOTE_NODE_URL": "tcp://" + self._url("rpc").removeprefix("http://"),
                    "SVOTE_CHAIN_ID": "svote-1", "SVOTE_PALLAS_PK_PATH": str(self.vote_home / "pallas.pk"),
                    "ZASHI_LIGHTWALLETD": endpoint, "ZASHI_PIR_URL": self._url("pir"),
                    "ZASHI_SNAPSHOT_HEIGHT": str(snapshot_height), "ZASHI_VOTE_WINDOW_SECS": str(vote_window_seconds)})
            round_data = self._get(self._url("api") + "/shielded-vote/v1/rounds/active")["round"]
            round_id = base64.b64decode(round_data["vote_round_id"], validate=True).hex()
            if not re.fullmatch(r"[0-9a-f]{64}", round_id):
                raise RunnerError("active real voting round has invalid ID")
            self._signed_config(round_id, round_data["ea_pk"])
            self._spawn("gateway", [sys.executable, str(self.root / "scripts/e2e/voting-regtest-gateway.py"),
                "--port", str(self.ports["gateway"]), "--config-dir", str(self.config),
                "--pir-target", self._url("pir"), "--vote-target", self._url("api"),
                "--rpc-target", self._url("rpc"), "--slow-helper-delay", "2.0"], ("gateway",))
            self._ready(self._url("gateway") + "/health")
            header = self._get(self._url("rpc") + "/commit")["result"]["signed_header"]["header"]
            if header.get("chain_id") != "svote-1" or not re.fullmatch(r"[0-9A-Fa-f]{64}", header.get("validators_hash", "")):
                raise RunnerError("fresh voting chain trust anchor is invalid")
            self.runtime = {
                "ZCASH_E2E_VOTING_GATEWAY_URL": self._url("gateway"),
                "ZCASH_E2E_VOTING_STATIC_CONFIG_URL": "https://config.vizor-vote.invalid/static-voting-config.json?checksum=sha256:" + _sha(self.config / "static-voting-config.json"),
                "ZCASH_E2E_VOTE_ROUND_ID": round_id,
                "ZCASH_E2E_VOTE_CHAIN_ID": header["chain_id"],
                "ZCASH_E2E_VOTE_VALIDATOR_HASH": header["validators_hash"],
                "ZCASH_E2E_REUSE_MIGRATED_WALLET": "true",
            }
            write_json(self.state / "runtime.json", self.runtime)
            self.started = True
            return self.environment()
        except BaseException as primary:
            try:
                self.close()
            except BaseException as cleanup:
                raise primary from cleanup
            raise

    def _patch_bindings(self) -> None:
        app = self.vote_home / "config/app.toml"
        app_text = app.read_text()
        grpc_web = patched_bindings(app_text, {("grpc-web", "enable")})
        if grpc_web.get(("grpc-web", "enable")) is not True:
            raise RunnerError("pinned generated grpc-web.enable must already be true")
        updates = {
            ("api", "address"): "tcp://127.0.0.1:" + str(self.ports["api"]),
            ("grpc", "address"): "127.0.0.1:" + str(self.ports["grpc"]),
            # Pinned Cosmos SDK serves gRPC-Web on the API listener; its
            # generated schema has only enable, not a separate address.
            ("grpc-web", "enable"): True,
            ("helper", "chain_api_port"): self.ports["api"],
            ("helper", "db_path"): str(self.vote_home / "helper.db"),
            ("vote", "comet_rpc"): self._url("rpc"),
            ("admin", "disable"): True,
        }
        app.write_text(patch_toml(app_text, updates))
        config = self.vote_home / "config/config.toml"
        config.write_text(patch_toml(config.read_text(), {
            ("rpc", "laddr"): "tcp://127.0.0.1:" + str(self.ports["rpc"]),
            ("rpc", "pprof_laddr"): "127.0.0.1:" + str(self.ports["pprof"]),
            ("p2p", "laddr"): "tcp://127.0.0.1:" + str(self.ports["p2p"]),
            ("p2p", "seeds"): "", ("p2p", "persistent_peers"): "",
            ("instrumentation", "prometheus"): False,
        }))

    def _signed_config(self, round_id: str, ea_pk: str) -> None:
        binary = str(self.binaries["voting-config"])
        output = self._run("config-keygen", [binary, "keygen", "--signer-id", "vizor-regtest-e2e", "--out", str(self.config / "signing.seed"), "--force"])
        entries = [line.removeprefix("trusted_keys_entry: ") for line in output.splitlines() if line.startswith("trusted_keys_entry: ")]
        if len(entries) != 1 or not isinstance(trusted := json.loads(entries[0]), dict):
            raise RunnerError("pinned voting keygen did not emit exactly one trusted signing key")
        write_json(self.config / "static-voting-config.json", {"static_config_version": 1,
            "dynamic_config_url": "https://config.vizor-vote.invalid/dynamic-voting-config.json", "trusted_keys": [trusted]})
        servers = [{"url": "https://vote.vizor-vote.invalid", "label": "healthy regtest helper"}]
        if self.slow_helper:
            servers.insert(0, {"url": "https://slow.vizor-vote.invalid", "label": "delayed regtest helper"})
        dynamic = self.config / "dynamic-voting-config.json"
        write_json(dynamic, {"config_version": 1, "vote_servers": servers,
            "pir_endpoints": [{"url": "https://pir.vizor-vote.invalid", "label": "regtest PIR"}],
            "pir_layout": {"pir_depth": 19, "tier0_layers": 12, "tier1_layers": 7, "poly_len": 4096},
            "supported_versions": {"pir": ["v0"], "vote_protocol": "v0", "tally": "v0", "vote_server": "v1"}, "rounds": {}})
        self._run("config-sign", [binary, "sign", "--round-id", round_id, "--ea-pk", ea_pk,
            "--signer-id", "vizor-regtest-e2e", "--privkey-file", str(self.config / "signing.seed"),
            "--pir-depth", "19", "--tier0-layers", "12", "--tier1-layers", "7", "--poly-len", "4096", "--merge", str(dynamic)])
        self._run("config-verify", [binary, "verify", "--config", str(dynamic), "--static-config", str(self.config / "static-voting-config.json")])

    def environment(self) -> dict[str, str]:
        if not self.started or self.closed or set(self.runtime) != RUNTIME_KEYS:
            raise RunnerError("voting runtime is not ready or no longer owned")
        self._check_processes()
        return dict(self.runtime)

    def verify(self) -> dict:
        runtime = self.environment()
        metrics = self._get(self._url("gateway") + "/metrics")
        tree = self._get(self._url("api") + "/shielded-vote/v1/commitment-tree/" + runtime["ZCASH_E2E_VOTE_ROUND_ID"] + "/latest")
        verify_participation(metrics, tree, slow_helper=self.slow_helper)
        evidence = {"round_id": runtime["ZCASH_E2E_VOTE_ROUND_ID"], "metrics": metrics, "commitment_tree": tree, "slow_helper": self.slow_helper}
        write_json(self.state / "participation-proof.json", evidence)
        return evidence

    def close(self):
        if self.closed:
            return
        failures = []
        for managed in reversed(self.processes):
            try:
                self.session.case.stop_process(managed, timeout=5)
                if not managed.cleanup_completed:
                    raise RunnerError("original voting service group/output join is unproven")
            except BaseException as error:
                failures.append(error)
        if failures or self._failed:
            self._failed = True
            raise RunnerError("voting cleanup unproven; retain state and port locks") from (failures[0] if failures else None)
        # Never release these cooperative locks while an original service survives.
        if self.lease is not None:
            self.lease.close()
        self.artifact.verify_unchanged()
        self.closed = True
