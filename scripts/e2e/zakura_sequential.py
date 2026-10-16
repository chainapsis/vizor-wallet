"""Run Zakura regtest cases one at a time, each on its own chain.

Every case owns a fresh Zakura node and lightwalletd, the lightwalletd
shim in front of them and an HTTP control. The offline signer and the Rust test
executables are built once per run from the committed `rust/` tree and shared
read-only. Cases never share chain state, wallets or evidence. Rust cases lease
free ports; Flutter cases use the app's default regtest ports, one case at a
time.
"""
from __future__ import annotations

import dataclasses
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import uuid

import content_memo
import e2e_runtime as runtime
from funder_build import build_regtest_funder
from native_case_lifecycle import NativeCaseLifecycle
import native_owned_tree as tree
from native_ports import lease_fixed_ports, lease_native_ports
from native_rust_case_storage import RustCaseStorage
from native_workspace import prepare_native_case_workspace
from native_zakura_backend import prepare_native_zakura_backend
from native_zakura_control import prepare_native_zakura_control
from native_zakura_front import prepare_native_zakura_front
import zakura_flutter as flutter_cases
from zakura_flutter import Derived
from zakura_batch_funding import fund_zakura_batch, migration_note_batches
import zakura_diagnostics as diagnostics
from zakura_funding import fund_zakura
from zakura_genesis import create_zakura_genesis_proof
from zakura_regtest import ensure_pinned_images
from zakura_simulator import RunSimulator, newest_runtime, uninstall_app


# The coinbase of every chain pays the signer's public test-only key.
MINER_ADDRESS = "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX"
# Ironwood (NU6.3) is active from height 1 unless a scenario funds Orchard
# before a controlled activation.
DEFAULT_ACTIVATION = 1
MIGRATION_ACTIVATION = 500
# Coinbase spends need 100 confirmations, so every chain starts mature.
INITIAL_BLOCKS = 100
# The Gift Card tracking tests print each capture they save in the app sandbox.
CAPTURE_MARKER = "[gift-card-tracking-screenshot] "
CAPTURE_DIRECTORY = "gift_card_tracking_e2e_screenshots"


@dataclasses.dataclass(frozen=True)
class RustScenario:
    id: str
    target: str
    test: str
    activation_height: int = DEFAULT_ACTIVATION
    timeout_seconds: int = 600


RUST_SCENARIOS = (
    RustScenario("rust.send.basic", "regtest_send", "funded_wallet_can_send_to_second_wallet"),
    RustScenario("rust.send.second-account", "regtest_send",
                 "imported_second_account_can_send_using_its_own_seed"),
    RustScenario("rust.receive.sync", "regtest_receive_sync", "create_wallet_receives_funds_and_syncs_balance"),
    RustScenario("rust.receive.direct-zakura", "regtest_direct_zakura_receive",
                 "empty_wallet_receives_exact_ironwood_funding_from_direct_zakura", timeout_seconds=180),
    RustScenario("rust.import.direct-zakura", "regtest_direct_zakura_import",
                 "historical_bip39_passphrase_import_recovers_exact_ironwood_funding_from_direct_zakura",
                 timeout_seconds=180),
    RustScenario("rust.import.bip39-passphrase", "regtest_import",
                 "bip39_passphrase_import_recovers_funds_sent_to_independently_derived_address"),
    RustScenario("rust.import.historical-birthday", "regtest_import",
                 "import_wallet_with_historical_birthday_recovers_existing_funds"),
    RustScenario("rust.import.future-birthday", "regtest_import",
                 "import_wallet_with_future_birthday_does_not_rescan_old_receive"),
    RustScenario("rust.import.receive-after-sync", "regtest_import",
                 "import_wallet_then_receive_new_funds_after_sync_updates_correctly"),
    RustScenario("rust.import.deterministic-reimport", "regtest_import",
                 "same_mnemonic_imported_into_fresh_db_matches_original_ua_and_balance"),
    RustScenario("rust.multi-account.orphaned-range", "regtest_multi_account",
                 "sync_start_rescues_wallet_stuck_by_orphaned_historical_scan_range"),
    RustScenario("rust.multi-account.deleted-range", "regtest_multi_account",
                 "sync_completes_when_deleted_account_left_scanned_range_below_birthday"),
    RustScenario("rust.multi-account.late-add-history-future", "regtest_multi_account",
                 "adding_second_account_after_tip_sync_recovers_historical_and_future_funds"),
    RustScenario("rust.multi-account.tip-birthday-history", "regtest_multi_account",
                 "late_added_account_with_tip_birthday_still_recovers_historical_funds"),
    RustScenario("rust.multi-account.two-before-sync", "regtest_multi_account",
                 "two_new_accounts_added_before_single_sync_are_both_recovered"),
    RustScenario("rust.multi-account.preserve-history", "regtest_multi_account",
                 "existing_account_history_is_unchanged_when_new_account_is_added"),
    RustScenario("rust.multi-account.isolated-balances", "regtest_multi_account",
                 "multi_account_sync_keeps_balances_isolated_per_account"),
    RustScenario("rust.multi-account.idempotent-sync", "regtest_multi_account",
                 "repeated_sync_is_idempotent_for_multi_account_wallet"),
    RustScenario("rust.gift-card.tracking-multiple", "regtest_gift_card_tracking",
                 "observer_scans_multiple_view_only_accounts_and_retires_only_used_card"),
    RustScenario("rust.gift-card.empty-db-reuse", "regtest_gift_card_tracking",
                 "observer_reuses_empty_db_without_scanning_idle_gap"),
    RustScenario("rust.gift-card.competition", "regtest_payment_link_competition",
                 "one_card_two_claimants_preserve_and_resolve_losing_transaction"),
    RustScenario("rust.ironwood.migration", "ironwood_regtest_migration",
                 "orchard_funds_migrate_after_controlled_nu6_3_activation",
                 activation_height=MIGRATION_ACTIVATION, timeout_seconds=1200),
    RustScenario("rust.ironwood.gift-card-claim", "ironwood_regtest_gift_card_claim",
                 "gift_card_claims_at_two_confirmations_and_discards_the_card_ovk",
                 activation_height=MIGRATION_ACTIVATION, timeout_seconds=1200),
)
ALL_SCENARIOS = RUST_SCENARIOS + flutter_cases.FLUTTER_SCENARIOS
SCENARIOS = {scenario.id: scenario for scenario in ALL_SCENARIOS}


def select_scenarios(names):
    """Exact IDs, or every scenario whose ID starts with a dotted prefix."""
    selected = []
    for name in names:
        matches = [s for s in ALL_SCENARIOS if s.id == name or s.id.startswith(name.rstrip(".") + ".")]
        if not matches:
            raise ValueError(f"unknown scenario or prefix: {name}")
        selected.extend(s for s in matches if s not in selected)
    return selected


def verify_test_output(lines, test):
    """Exit 0 with zero tests, an ignored test or a different test is not a pass."""
    output = "".join(lines)
    if (len(re.findall(r"^running 1 test$", output, re.MULTILINE)) != 1
        or len(re.findall(r"^test " + re.escape(test) + r" \.\.\. ok$", output, re.MULTILINE)) != 1
        or len(re.findall(r"^test result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; [0-9]+ filtered out; "
                          r"finished in [0-9.]+s$", output, re.MULTILINE)) != 1):
        raise runtime.RunnerError("the Rust test binary did not report the selected test as passed")


def _check(cancel_event):
    if cancel_event.is_set():
        raise runtime.Cancelled()


SESSION_LOCKED = ("the macOS session is locked, which stops the Flutter app's keychain and platform calls; "
                  "unlock the Mac and rerun the remaining scenarios")


def _require_unlocked_session():
    if diagnostics.session_locked():
        raise runtime.RunnerError(SESSION_LOCKED)


class SequentialCase:
    """One case's ports, workspace, chain, front and control.

    Finalize with close() after a pass, or retain() to keep the chain and
    wallet files of a failed case for inspection.
    """

    def __init__(self, run_root, *, run_id, case_index, scenario_id, platform, activation_height,
                 ports=None):
        if ports is None:
            self.lease = lease_native_ports(0, run_id)
        else:
            _require_unbound(flutter_cases.UNAVAILABLE_PORT)
            self.lease = lease_fixed_ports(run_id, dict(ports))
        try:
            # Screenshot and voting ports stay leased for their services, outside the chain's.
            workspace = prepare_native_case_workspace(run_root, platform=platform,
                scenario_id=scenario_id, run_id=run_id, worker_id=0, case_index=case_index,
                ports={name: self.lease.ports[name] for name in ("rpc", "lwd", "proxy")},
                activation_height=activation_height)
            self.case = NativeCaseLifecycle(workspace)
            self.storage = RustCaseStorage(self.case) if platform == "rust" else None
        except BaseException:
            self.lease.close()
            raise
        self.backend = self.front = self.control = None
        self.derived = {}
        self._voting_env = None
        self._finished = False

    def start(self, *, grpcurl, proto_dir, dart, source_root, artifact, cancel_event,
              initial_blocks=INITIAL_BLOCKS, funding=(), orchard_notes=None, derive=()):
        """Start the chain, mature its coinbase and fund it, then put the shim and control in front.

        The addresses in `derive` are derived first; funding and Flutter
        defines use them.
        """
        self.backend = prepare_native_zakura_backend(self.case, grpcurl=grpcurl,
            proto_dir=proto_dir, miner_address=MINER_ADDRESS, timeout=120)
        self.backend.start()
        _check(cancel_event)
        self.backend.mine(initial_blocks)
        _check(cancel_event)
        for value in derive:
            self.derived[value] = self.wallet_addresses(artifact, value.mnemonic,
                cancel_event=cancel_event)[value.field]
        for payment in funding:
            address = self.derived[payment.address] if isinstance(payment.address, Derived) else payment.address
            fund_zakura(self.case, self.backend, artifact, recipient_address=address,
                amount_zatoshi=payment.zatoshi, recipient_pool=payment.pool,
                source_height=payment.source_height, confirmations=10, timeout=120,
                cancel_event=cancel_event)
            _check(cancel_event)
        if orchard_notes is not None:
            addresses = self.wallet_addresses(artifact, flutter_cases.DESKTOP_MNEMONIC,
                orchard_notes.note_count, cancel_event=cancel_event)["unifiedAddresses"]
            batches = migration_note_batches(addresses, total_zatoshi=orchard_notes.total_zatoshi,
                tx_count=len(orchard_notes.sources))
            for payments, sources in zip(batches, orchard_notes.sources):
                fund_zakura_batch(self.case, self.backend, artifact, payments=payments,
                    source_heights=sources, recipient_pool="orchard", confirmations=10,
                    timeout=180, cancel_event=cancel_event)
                _check(cancel_event)
        genesis = create_zakura_genesis_proof(self.case, self.backend, timeout=30,
            cancel_event=cancel_event)
        self.front = prepare_native_zakura_front(self.case, self.backend, genesis,
            dart=dart, source_root=source_root, timeout=30)
        # The shim and control bind the leased ports themselves.
        self.lease.release_sockets()
        self.front.start(cancel_event=cancel_event)
        self.control = prepare_native_zakura_control(self.case, self.backend, self.front,
            artifact=artifact)

    def wallet_addresses(self, artifact, mnemonic, count=1, *, cancel_event):
        """The wallet address tool's record for a test mnemonic's first `count` addresses."""
        result = self.case.run_command([str(artifact.wallet_addresses_binary()), mnemonic, str(count)],
            env=os.environ.copy(), timeout=60, cancel_event=cancel_event,
            max_output_bytes=2 * 1024 * 1024)
        if result.returncode:
            raise runtime.RunnerError("the wallet address tool failed", result.returncode)
        records = [json.loads(line) for line in result.lines if line.lstrip().startswith("{")]
        if len(records) != 1 or len(records[0].get("unifiedAddresses", ())) != count:
            raise runtime.RunnerError("the wallet address tool did not print the requested addresses")
        return records[0]

    def run_rust(self, artifact, scenario, *, cancel_event):
        """Run one exact ignored test while serving its control requests."""
        if self.storage is None or self.control is None:
            raise runtime.RunnerError("a Rust case needs its wallet storage and a started control")
        binary = artifact.test_binary(scenario.target)
        deadline = time.monotonic() + scenario.timeout_seconds
        _check(cancel_event)
        lines = []
        process = self.case.start_process([str(binary), scenario.test, "--exact", "--ignored",
            "--show-output", "--test-threads=1", "--color", "never"],
            env={**os.environ, "VIZOR_E2E_RUST_TEMP_ROOT": str(self.storage.path)},
            raw_lines=lines, max_output_bytes=8 * 1024 * 1024)
        while process.process.poll() is None:
            _check(cancel_event)
            if time.monotonic() >= deadline:
                raise runtime.RunnerError("the Rust test did not finish before its deadline", 124)
            self.storage.verify_owned()
            self.front.assert_running()
            self.control.pump(deadline=deadline, cancel_event=cancel_event)
        code = self.case.wait_process(process, timeout=max(0.001, deadline - time.monotonic()),
            cancel_event=cancel_event)
        if code != 0:
            raise runtime.RunnerError("the Rust test failed", code)
        verify_test_output(lines, scenario.test)
        artifact.verify_unchanged()
        self.front.assert_running()

    def run_flutter(self, scenario, *, flutter, device, source_root, cancel_event, dart_defines=()):
        """Run each phase's `flutter test`, with `dart_defines` added, while serving its control requests."""
        if self.control is None:
            raise runtime.RunnerError("a Flutter case needs a started control")
        deadline = time.monotonic() + scenario.timeout_seconds
        env = {**os.environ, **dict(scenario.env)}
        if scenario.screenshots:
            self._start_screenshot_driver(source_root, device, cancel_event)
        voting_defines = ()
        for index, phase in enumerate(scenario.phases):
            _check(cancel_event)
            if index == 1 and scenario.voting:
                voting_defines = self._start_voting(scenario.voting, source_root, device,
                    deadline, cancel_event)
            if phase.mine_before:
                self.backend.mine(phase.mine_before)
            if phase.reinstall:
                uninstall_app(device, source_root / "build/ios/iphonesimulator/Runner.app")
            lines = []
            on_macos = flutter_cases.phase_platform(scenario, phase) == "macos"
            process = self.case.start_process(flutter_cases.flutter_command(scenario, phase,
                flutter=flutter, device="macos" if on_macos else device, source_root=source_root,
                derived=self.derived, extra_defines=(*voting_defines, *dart_defines)),
                env=env, raw_lines=lines, max_output_bytes=16 * 1024 * 1024)
            app_platform = "macos" if on_macos else "ios"
            stacks = diagnostics.StallRecorder(self.case.workspace.root / "stacks",
                lambda: diagnostics.app_pids(app_platform, source_root=source_root, device=device),
                label=f"phase-{index + 1}")
            try:
                while process.process.poll() is None:
                    _check(cancel_event)
                    stacks.observe(len(lines))
                    if time.monotonic() >= deadline:
                        raise runtime.RunnerError("the Flutter test did not finish before its deadline", 124)
                    self.front.assert_running()
                    self.control.pump(deadline=deadline, cancel_event=cancel_event)
            except runtime.RunnerError as error:
                if error.exit_code == 124:
                    stacks.record_now("deadline")
                raise
            finally:
                stacks.join()
            code = self.case.wait_process(process, timeout=max(0.001, deadline - time.monotonic()),
                cancel_event=cancel_event)
            self._collect_captures(lines)
            if code != 0:
                raise runtime.RunnerError(f"{phase.test} failed", code)
            flutter_cases.verify_flutter_output(lines)
        if scenario.voting:
            self._check_voting(source_root, deadline, cancel_event)
        self.front.assert_running()

    def _collect_captures(self, lines):
        """Copy the PNGs the phase saved in the app sandbox into this case's evidence."""
        for line in "".join(lines).splitlines():
            source = Path(line.partition(CAPTURE_MARKER)[2].strip())
            if source.parent.name == CAPTURE_DIRECTORY and source.suffix == ".png" and source.is_file():
                captures = self.case.workspace.root / "captures"
                captures.mkdir(mode=0o700, exist_ok=True)
                shutil.copy2(source, captures / source.name)

    def _voting_command(self, source_root, mode):
        script = Path(source_root) / "scripts/e2e/voting-services.sh"
        return ["bash", str(script), mode, str(self.case.workspace.root / "voting" / "ready.json")]

    def _start_voting(self, voting, source_root, device, deadline, cancel_event):
        """Start the voting services against this chain; return their defines.

        The services run until the case stops them on close.
        """
        ready = self.case.workspace.root / "voting" / "ready.json"
        self._voting_env = {**os.environ, "VOTING_DEVICE": device,
            "ZCASH_E2E_DRIVER_URL": f"http://127.0.0.1:{flutter_cases.CONTROL_PORT}",
            "VOTING_LIGHTWALLETD": f"127.0.0.1:{flutter_cases.LIGHTWALLETD_PORT}",
            "E2E_SLOW_HELPER_MODE": "1" if voting.slow_helper else "0",
            "E2E_VOTING_DISCOVERY_TRANSITION": "1" if voting.discovery_transition else "0",
            "E2E_FINAL_TALLY": "1" if voting.final_tally else "0",
            "E2E_LEDGER_VOTING": "1" if voting.ledger else "0"}
        if voting.final_tally:
            # The round finalizes only after its vote window closes; slower
            # hosts can lengthen it with E2E_VOTE_WINDOW_SECS.
            self._voting_env.setdefault("E2E_VOTE_WINDOW_SECS", "300")
        services = self.case.start_process(self._voting_command(source_root, "start"),
            env=self._voting_env, max_output_bytes=8 * 1024 * 1024)
        while not ready.exists():
            _check(cancel_event)
            if services.process.poll() is not None:
                raise runtime.RunnerError("the voting services stopped before they were ready")
            if time.monotonic() >= deadline:
                raise runtime.RunnerError("the voting services were not ready before the deadline", 124)
            self.control.pump(deadline=deadline, cancel_event=cancel_event)
        return tuple(json.loads(ready.read_text(encoding="utf-8"))["defines"].items())

    def _check_voting(self, source_root, deadline, cancel_event):
        """The gateway must have served discovery, and the round must have votes.

        A final-tally check waits up to 15 minutes for the round to finalize.
        """
        result = self.case.run_command(self._voting_command(source_root, "check"),
            env=self._voting_env, timeout=max(1.0, deadline - time.monotonic()),
            cancel_event=cancel_event, max_output_bytes=1024 * 1024)
        if result.returncode:
            raise runtime.RunnerError("the voting services did not record the votes", result.returncode)

    def _start_screenshot_driver(self, source_root, device, cancel_event):
        """Capture the simulator into this case's evidence; the case stops it on close."""
        driver = self.case.start_process([sys.executable, "-u",
            str(Path(source_root) / "scripts/e2e/screenshot-driver.py"), "--udid", device,
            "--out-dir", str(self.case.workspace.root / "screenshots"),
            "--port", str(flutter_cases.SCREENSHOT_PORT)],
            env=os.environ.copy(), max_output_bytes=1024 * 1024)
        health = f"http://127.0.0.1:{flutter_cases.SCREENSHOT_PORT}/health"
        deadline = time.monotonic() + 10
        while True:
            _check(cancel_event)
            try:
                with urllib.request.urlopen(health, timeout=1) as response:
                    if response.status == 200:
                        return
            except OSError:
                pass
            if driver.process.poll() is not None or time.monotonic() >= deadline:
                raise runtime.RunnerError("the screenshot driver did not start")
            time.sleep(0.1)

    def close(self, *, timeout=60.0):
        """Stop every case process, then remove the chain, wallet files and port locks."""
        if self._finished:
            raise runtime.RunnerError("case already finalized")
        self._finished = True
        if self.control is not None:
            self.control.close()
        self.case.close(timeout=timeout)
        if self.control is not None:
            self.control.release_clipboard_after_writers()
        if self.backend is not None:
            self.backend.close()
        if self.storage is not None:
            self.storage.close(timeout=timeout)
        self.lease.close()

    def retain(self):
        """Stop every case process; keep the chain, wallet files and evidence."""
        self._finished = True
        errors = []
        steps = [lambda: self.control.close() if self.control is not None else None,
                 lambda: self.storage.retain() if self.storage is not None else self.case.close(),
                 lambda: self.control.release_clipboard_after_writers() if self.control is not None else None,
                 lambda: self.backend.retain() if self.backend is not None else None]
        for step in steps:
            try:
                step()
            except BaseException as error:
                errors.append(error)
        # Keep the port locks while a writer may still be alive.
        if not errors:
            self.lease.close()
        if errors:
            raise errors[0]

    def retained_resources(self):
        return {"evidence": str(self.case.workspace.root),
                "docker": self.backend.retained_resources() if self.backend is not None else None,
                "wallet_files": str(self.storage.path) if self.storage is not None else None}


def _require_unbound(port):
    """The Unavailable endpoint preset must refuse connections."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.settimeout(1.0)
        if probe.connect_ex(("127.0.0.1", port)) == 0:
            raise runtime.RunnerError(f"something listens on port {port}, which must stay unavailable")


def run_case(cases_root, run_id, case_index, scenario, *, artifact, grpcurl, proto_dir, dart,
             source_root, keep_failed, cancel_event, flutter=None, device=None, dart_defines=()):
    """Run one scenario on its own chain and return its report entry."""
    started = time.monotonic()
    is_flutter = isinstance(scenario, flutter_cases.FlutterScenario)
    result = {"scenario_id": scenario.id, "activation_height": scenario.activation_height,
              "status": "failed", "returncode": 1, "error": None, "cleanup_error": None}
    if is_flutter:
        result["tests"] = [phase.test for phase in scenario.phases]
    else:
        result.update(target=scenario.target, test=scenario.test)
    phases = {}
    current = {"name": None, "start": started}

    def begin(name):
        now = time.monotonic()
        if current["name"] is not None:
            phases[current["name"]] = round(now - current["start"], 3)
        current.update(name=name, start=now)

    session = None
    stopped = False
    try:
        begin("prepare")
        session = SequentialCase(cases_root, run_id=run_id, case_index=case_index,
            scenario_id=scenario.id, platform=scenario.platform if is_flutter else "rust",
            activation_height=scenario.activation_height,
            ports=flutter_cases.fixed_ports(scenario) if is_flutter else None)
        result["evidence"] = str(session.case.workspace.root)
        begin("chain")
        session.start(grpcurl=grpcurl, proto_dir=proto_dir, dart=dart, source_root=source_root,
            artifact=artifact, cancel_event=cancel_event,
            initial_blocks=scenario.initial_blocks if is_flutter else INITIAL_BLOCKS,
            funding=scenario.funding if is_flutter else (),
            orchard_notes=scenario.orchard_notes if is_flutter else None,
            derive=flutter_cases.derived_addresses(scenario) if is_flutter else ())
        begin("execute")
        if is_flutter:
            session.run_flutter(scenario, flutter=flutter, device=device, source_root=source_root,
                cancel_event=cancel_event, dart_defines=dart_defines)
        else:
            session.run_rust(artifact, scenario, cancel_event=cancel_event)
        begin("close")
        session.close()
        stopped = True
        result.update(status="passed", returncode=0)
    except BaseException as error:
        result["failed_phase"] = current["name"]
        result.update(error=str(error), returncode=getattr(error, "exit_code", 1))
        if result["returncode"] == 130:
            result["status"] = "cancelled"
        elif result["returncode"] == 124:
            result["status"] = "timed_out"
        if session is not None and not session._finished:
            try:
                if keep_failed:
                    session.retain()
                    result["retained"] = session.retained_resources()
                else:
                    session.close()
                stopped = True
            except BaseException as cleanup:
                result["cleanup_error"] = str(cleanup)
                try:
                    session.retain()
                except BaseException:
                    pass
                result["retained"] = session.retained_resources()
        if not isinstance(error, Exception):
            raise
    finally:
        begin(None)
        if stopped and is_flutter and scenario.voting:
            # Each voting case regenerates several GB of PIR data and chain state.
            result["voting_prune"] = tree.prune_voting_data(Path(result["evidence"]))
        result["duration_seconds"] = round(time.monotonic() - started, 3)
        result["phase_seconds"] = phases
    return result


def committed_source(source_root):
    """The signer and test executables are built from HEAD's `rust/` tree only."""
    root = Path(source_root).resolve(strict=True)
    commit = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
        check=True, capture_output=True, text=True).stdout.strip()
    changed = subprocess.run(["git", "-C", str(root), "status", "--porcelain", "--", "rust"],
        check=True, capture_output=True, text=True).stdout
    if changed:
        raise ValueError("commit the changes under rust/ first; the test executables are built from HEAD")
    return root, commit


def resolve_dart(flutter, source_root):
    """The shim runs on the SDK's Dart with the checkout's resolved packages."""
    dart = (Path(flutter).resolve(strict=True).parent / "cache/dart-sdk/bin/dart").resolve(strict=True)
    if not (Path(source_root) / ".dart_tool/package_config.json").is_file():
        raise ValueError("run `fvm flutter pub get` first; the lightwalletd shim needs the resolved packages")
    return dart


def run_sequence(source_root, scenarios, *, flutter, grpcurl, proto_dir, build_jobs=4,
                 keep_failed=False, cancel_event=None, out=print, ios_runtime=None, dart_defines=()):
    """Build once, then run each scenario on its own chain; return the report.

    iOS scenarios run on a simulator the run creates after the build and
    deletes at the end, unless it is kept beside failed chains.
    """
    cancel = cancel_event if cancel_event is not None else threading.Event()
    root, commit = committed_source(source_root)
    dart = resolve_dart(flutter, root)
    grpcurl = Path(grpcurl).resolve(strict=True)
    proto_dir = Path(proto_dir).resolve(strict=True)
    needs_simulator = any(getattr(s, "platform", None) == "ios" for s in scenarios)
    runs_flutter = any(isinstance(s, flutter_cases.FlutterScenario) for s in scenarios)
    run_id = uuid.uuid4().hex[:10]
    logs = root / ".regtest-logs"
    logs.mkdir(mode=0o700, exist_ok=True)
    evidence = logs / f"zakura-{run_id}"
    evidence.mkdir(mode=0o700)
    report = {"schema_version": 1, "run_id": run_id, "source_commit": commit,
              "scenarios": [s.id for s in scenarios], "results": [], "error": None,
              "dart_defines": [f"{name}={value}" for name, value in dart_defines]}
    report_path = evidence / "report.json"

    def write_report():
        temporary = evidence / "report.json.tmp"
        temporary.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        temporary.replace(report_path)

    started = time.monotonic()
    builds = builds_id = simulator = None
    try:
        with content_memo.run_scope():
            if runs_flutter:
                _require_unlocked_session()
            report["pinned_images"] = ensure_pinned_images(evidence, cancel_event=cancel, out=out)
            # Every run asks for the same signer: every catalog Rust target and the
            # address tool. Any selection then reuses one build cache entry.
            targets = tuple(dict.fromkeys(s.target for s in RUST_SCENARIOS))
            selected = tuple(dict.fromkeys(s.target for s in scenarios if isinstance(s, RustScenario)))
            out(f"Building the signer and {len(targets)} Rust test target(s), unless cached; logs: {evidence}")
            builds = evidence / "builds"
            builds.mkdir(mode=0o700)
            builds_id = tree.identity(builds.lstat())
            producer = NativeCaseLifecycle(prepare_native_case_workspace(builds, platform="rust",
                scenario_id="rust.signer-build", run_id=run_id, worker_id=0, case_index=0,
                # A build case never listens; its manifest only needs distinct ports.
                ports={"rpc": 28232, "lwd": 29067, "proxy": 29068}, activation_height=1))
            cache = logs / "build-cache"
            cache.mkdir(mode=0o700, exist_ok=True)
            artifact = build_regtest_funder(producer, source_root=root, source_commit=commit,
                jobs=build_jobs, timeout=1200, cancel_event=cancel, test_targets=targets,
                wallet_addresses=True, cache_root=cache / "funder-v1")
            built = artifact.identity()
            report["builds"] = {"signer_cache_hit": built["cache_hit"], "signer_cache_key": built.get("cache_key"),
                                "rust_built_test_targets": list(targets), "rust_test_targets": list(selected)}
            out("Reused the cached signer" if built["cache_hit"] else "Built the signer and cached it")
            if any(getattr(s, "voting", None) for s in scenarios):
                out("Building the pinned voting services")
                built = runtime.run_logged_command(
                    ["bash", str(root / "scripts/e2e/voting-services.sh"), "build"], cwd=root,
                    env=os.environ.copy(), log_path=evidence / "voting-build.log", timeout=3600,
                    cancel_event=cancel)
                if built.returncode:
                    raise runtime.RunnerError("the voting services did not build; see voting-build.log",
                        built.returncode)
            if needs_simulator:
                simulator = RunSimulator(run_id, ios_runtime or newest_runtime())
                report["ios_simulator"] = simulator.describe()
                out(f"Booted {simulator.name} ({simulator.udid}, {simulator.runtime})")
            cases = evidence / "cases"
            cases.mkdir(mode=0o700)
            for index, scenario in enumerate(scenarios, start=1):
                _check(cancel)
                is_flutter = isinstance(scenario, flutter_cases.FlutterScenario)
                if is_flutter:
                    _require_unlocked_session()
                out(f"[{index}/{len(scenarios)}] {scenario.id}")
                result = run_case(cases, run_id, index, scenario, artifact=artifact, grpcurl=grpcurl,
                    proto_dir=proto_dir, dart=dart, source_root=root, keep_failed=keep_failed,
                    cancel_event=cancel, flutter=flutter, dart_defines=dart_defines,
                    device=simulator.udid if getattr(scenario, "platform", None) == "ios" else "macos")
                if is_flutter and result["status"] != "passed" and diagnostics.session_locked():
                    result["error"] = f"{result['error']} (the macOS session was locked)"
                report["results"].append(result)
                write_report()
                out(f"    {result['status']} in {result['duration_seconds']:.0f}s"
                    + (f": {result['error']}" if result["error"] else ""))
                if result["status"] == "cancelled":
                    break
    except BaseException as error:
        report["error"] = str(error)
        if not isinstance(error, Exception):
            raise
    finally:
        failed = report["error"] is not None or any(r["status"] != "passed" for r in report["results"])
        if simulator is not None:
            if keep_failed and failed:
                report["ios_simulator"]["kept"] = True
                out(f"Kept {simulator.name} ({simulator.udid})")
            else:
                try:
                    simulator.delete()
                except runtime.RunnerError as error:
                    report["ios_simulator"]["cleanup_error"] = str(error)
                    out(f"Could not delete {simulator.name} ({simulator.udid}): {error}")
        if builds_id is not None:
            # Each run builds into a fresh target directory (several GB). Kept
            # chains do not need it; logs and markers stay.
            report["build_prune"] = tree.prune_build_outputs(builds, expected=builds_id)
            out(f"Removed {tree.size_text(report['build_prune']['bytes'])} of build output"
                + (f"; {len(report['build_prune']['errors'])} error(s)" if report["build_prune"]["errors"] else ""))
        report["duration_seconds"] = round(time.monotonic() - started, 3)
        write_report()
    return report, report_path
