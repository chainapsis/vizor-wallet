"""Build once, then run selected Rust/macOS cases with independent original owners.

Each repetition has its own schema-2 report, so failed-from selection stays
unambiguous. Signed artifacts and the offline signer are shared read-only;
wallets, chain state, ports, controllers and evidence are never shared.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time
import uuid

import e2e_runtime as runtime
from funder_build import build_regtest_funder
from native_case_lifecycle import NativeCaseLifecycle
from native_macos_build import build_native_macos_cohort
from native_macos_execution import execute_native_macos_case
from native_rust_execution import RUST_CASES, RUST_PROFILES, execute_native_rust_case
from native_worker_lifecycle import prepare_native_worker_lifecycle
from native_workspace import prepare_native_case_workspace
from zakura_funding import fund_zakura


SUPPORTED_SCENARIOS = frozenset({
    "flutter.macos.import-sync",
    "flutter.macos.fallback-endpoint",
    "flutter.macos.custom-endpoint-no-fallback",
    "flutter.macos.slow-height-fallback",
    "flutter.macos.sync-startup-stall-recovery",
    "flutter.macos.shield-transparent",
    "flutter.macos.shield-transparent-retry",
    "flutter.macos.multi-account-send",
    "flutter.macos.tex-send",
    "flutter.macos.payment-uri-send",
    "flutter.macos.payment-uri-locked-send",
    "flutter.macos.payment-request-round-trip",
    "flutter.macos.mempool-receive-history",
    "flutter.macos.mempool-during-sync",
    "flutter.macos.mempool-expiry",
    "flutter.macos.payment-link-round-trip",
    "flutter.macos.payment-link-restart",
    "flutter.macos.payment-link-recovery",
}) | frozenset(RUST_CASES)
_MINER = "tmLomwDqZSUb1Mvsfpjtmt4cLBA7c9tGssX"
_IMPORT_UA = "uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn"
_IMPORT_TRANSPARENT = "tmPTcChwqcza88W1mydzwkZ25C9qQm3ugiM"
_DESKTOP_UA = "uregtest1nu0qx0nca0ncpshm5x47ldc90835m2fy3gjuh3empp5js9qanzjwxppsw7x07a2ec3z52ute7d7f0z68ez90qlagx5ankjm4eyd6l90p"
_DESKTOP_MNEMONIC = "winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used"
_RECEIVER_MNEMONIC = "return try reason flat civil wolf dwarf announce toddler uphold equip range neck proof gauge east rifle swim tray twin venue fossil will version"


def scenario_funding(scenario_id, *, desktop_transparent=None):
    """Prefund only the balances asserted by each unchanged wallet scenario."""
    if scenario_id == "flutter.macos.import-sync":
        return ((_IMPORT_UA,125000000,"ironwood",1),
                (_IMPORT_TRANSPARENT,75000000,"transparent",2))
    if scenario_id in {"flutter.macos.fallback-endpoint", "flutter.macos.slow-height-fallback"}:
        return ((_DESKTOP_UA,125000000,"ironwood",1),)
    if scenario_id == "flutter.macos.multi-account-send":
        if not isinstance(desktop_transparent, str) or not desktop_transparent.startswith("tm"):
            raise ValueError("multi-account funding needs the independently derived transparent address")
        return ((_DESKTOP_UA,125000000,"ironwood",1),
                (desktop_transparent,75000000,"transparent",2))
    if scenario_id in {"flutter.macos.tex-send", "flutter.macos.payment-uri-send",
                       "flutter.macos.payment-uri-locked-send", "flutter.macos.payment-request-round-trip",
                       "flutter.macos.payment-link-round-trip", "flutter.macos.payment-link-restart",
                       "flutter.macos.payment-link-recovery"}:
        return ((_DESKTOP_UA,125000000,"ironwood",1),)
    if scenario_id in {"flutter.macos.shield-transparent", "flutter.macos.shield-transparent-retry"}:
        return ()  # Each new random wallet receives external proved funding in its scenario.
    if scenario_id in {"flutter.macos.custom-endpoint-no-fallback", "flutter.macos.sync-startup-stall-recovery"}:
        return ()
    if scenario_id in {"flutter.macos.mempool-receive-history", "flutter.macos.mempool-during-sync",
                       "flutter.macos.mempool-expiry"}:
        return ()  # External funding must remain unmined until the app observes it.
    raise ValueError("unsupported native funding scenario")


def derive_payment_addresses(case, artifact, *, cancel):
    """Use the existing public SDK example, never reimplement address encodings."""
    addresses = []
    try:
        for mnemonic in (_DESKTOP_MNEMONIC, _RECEIVER_MNEMONIC):
            binary = artifact.wallet_addresses_binary()
            result = case.run_command([str(binary), mnemonic], env=os.environ.copy(),
                timeout=60, cancel_event=cancel, max_output_bytes=64*1024)
            if result.returncode:
                raise runtime.RunnerError("owned wallet address derivation failed", result.returncode)
            records = [json.loads(line) for line in result.lines if line.lstrip().startswith("{")]
            if len(records) != 1:
                raise runtime.RunnerError("wallet address tool did not produce one result")
            record = records[0]
            for field, prefix in (("transparentAddress", "tm"), ("texAddress", "texregtest1")):
                value = record.get(field)
                if (not isinstance(value, str) or not value.startswith(prefix)
                    or not value.isascii() or not value.isalnum() or not 20 <= len(value) <= 100):
                    raise runtime.RunnerError("wallet address tool returned an invalid regtest fixture")
            addresses.append(record)
            artifact.verify_unchanged()
        return {"desktop_transparent": addresses[0]["transparentAddress"],
                "receiver_tex": addresses[1]["texAddress"],
                "receiver_transparent": addresses[1]["transparentAddress"]}
    finally:
        case.close()


def validate_options(args, scenarios):
    """Reject unsupported/invalid execution before creating any run resources."""
    if sys.platform != "darwin":
        raise ValueError("native macOS execution requires macOS")
    if not scenarios or any(s.id not in SUPPORTED_SCENARIOS for s in scenarios):
        raise ValueError("this executor implements only migrated Rust/macOS scenarios")
    for scenario in scenarios:
        if scenario.id in RUST_CASES and (scenario.engine != "rust"
            or scenario.profile != RUST_PROFILES[scenario.id]
            or (scenario.target, scenario.test) != RUST_CASES[scenario.id]):
            raise ValueError("selected Rust identity/profile does not match its executor")
    for field in ("workers", "repeat"):
        value = getattr(args, field)
        if type(value) is not int or not 1 <= value <= 16:
            raise ValueError(field + " must be an integer from 1 to 16")
    if type(args.build_jobs) is not int or not 1 <= args.build_jobs <= 8:
        raise ValueError("build_jobs must be an integer from 1 to 8")
    for field in ("flutter", "zakura_cache", "grpcurl", "proto_dir"):
        value = getattr(args, field)
        if value is None or not value.is_absolute():
            raise ValueError("--" + field.replace("_", "-") + " requires an absolute path")
        value.resolve(strict=True)
    for field in ("flutter", "grpcurl"):
        if not os.access(getattr(args, field), os.X_OK):
            raise ValueError(field + " must be executable")


def _write_report(path, report):
    with path.open("x", encoding="utf-8") as output:
        json.dump(report, output, indent=2, allow_nan=False)
        output.write("\n")


def execute_case(root, run_id, worker_id, scenario, *, helper, artifact, source_root,
                 dart, args, cancel, desktop_transparent=None):
    """The worker thread creates, drives and finalizes its own mutable handles."""
    started = time.monotonic()
    result = {"scenario_id":scenario.id, "profile":scenario.profile,
        "target":scenario.target, "test":scenario.test, "worker_id":worker_id,
        "attempt":1, "status":"failed", "failure_kind":None, "returncode":1,
        "duration_seconds":0.0, "error":None, "cleanup_errors":[]}
    worker = session = None
    try:
        if cancel.is_set():
            raise runtime.Cancelled()
        worker = prepare_native_worker_lifecycle(root, run_id=run_id, worker_id=worker_id)
        is_rust = scenario.id in RUST_CASES
        activation = 500 if is_rust and RUST_PROFILES[scenario.id] == "zakura-direct-activation500" else 1
        session = worker.prepare_case(platform="rust" if is_rust else "macos", scenario_id=scenario.id,
            case_index=1, activation_height=activation, helper=None if is_rust else helper, timeout=60, cancel_event=cancel)
        result["log"] = str(session.case.workspace.root)
        session.prepare_zakura_backend(tooling_root=args.zakura_cache,
            grpcurl=args.grpcurl.resolve(strict=True), proto_dir=args.proto_dir,
            miner_address=_MINER, timeout=120)
        if cancel.is_set():
            raise runtime.Cancelled()
        session.backend.mine(750 if scenario.id == "flutter.macos.mempool-during-sync" else 100)
        result["payments"] = []
        for address, amount, pool, source in (() if is_rust else scenario_funding(
                scenario.id, desktop_transparent=desktop_transparent)):
            result["payments"].append(fund_zakura(session.case, session.backend, artifact,
                recipient_address=address, amount_zatoshi=amount, recipient_pool=pool,
                source_height=source, confirmations=10, timeout=120, cancel_event=cancel))
        session.prepare_zakura_front(dart=dart, source_root=source_root, cancel_event=cancel)
        session.prepare_zakura_control(artifact=artifact)
        if is_rust:
            result["observation"] = execute_native_rust_case(session, artifact=artifact,
                scenario=scenario, cancel_event=cancel)
        else:
            result["observation"] = execute_native_macos_case(session, dart=dart,
                source_root=source_root, timeout=scenario.timeout_seconds, cancel_event=cancel)
        # No external PASS/cleanup boolean is accepted. The original owners
        # must complete their internal native/backend/process/port finalization.
        session.close(timeout=60)
        worker.close()
        result.update(status="passed", returncode=0, native_cleanup_proved=True,
                      backend_closed=session.backend.closed)
    except BaseException as error:
        result.update(error=str(error), returncode=getattr(error,"exit_code",1),
            failure_kind="process", native_cleanup_proved=False)
        if result["returncode"] == 130:
            result.update(status="cancelled", failure_kind="cancelled")
        elif result["returncode"] == 124:
            result.update(status="timed_out", failure_kind="timeout")
        if worker is not None:
            try:
                worker.retain(timeout=60)
            except BaseException as cleanup:
                result["cleanup_errors"].append(str(cleanup))
    result["duration_seconds"] = round(time.monotonic()-started,3)
    return result


def run_native_suite(args, catalog, scenarios, selection, *, source_root):
    validate_options(args, scenarios)
    root = Path(source_root).resolve(strict=True)
    commit = subprocess.run(["git","-C",str(root),"rev-parse","HEAD"],
        check=True, capture_output=True, text=True).stdout.strip()
    dirty = bool(subprocess.run(["git","-C",str(root),"status","--porcelain"],
        check=True, capture_output=True, text=True).stdout)
    # The signer uses committed Rust inputs; never mix them with a dirty wallet.
    rust_diff = subprocess.run(["git","-C",str(root),"diff","--exit-code","HEAD","--","rust"],
        stdout=subprocess.DEVNULL)
    if rust_diff.returncode:
        raise ValueError("commit the Rust inputs before building the shared signer")
    untracked = subprocess.run(["git","-C",str(root),"ls-files","--others",
        "--exclude-standard","--","rust"],check=True,capture_output=True,text=True).stdout
    if untracked:
        raise ValueError("commit the Rust inputs before building the shared signer")
    run_id = uuid.uuid4().hex[:10]
    logs = root/".regtest-logs"
    logs.mkdir(mode=0o700,exist_ok=True)
    if logs.resolve(strict=True) != logs:
        raise ValueError("the private E2E log directory must not be a symlink")
    evidence = logs/("native-suite-"+run_id)
    evidence.mkdir(mode=0o700)
    builds = evidence/"builds"
    builds.mkdir(mode=0o700)
    cancel = threading.Event()
    previous = {number:signal.getsignal(number) for number in (signal.SIGINT,signal.SIGTERM)}
    for number in previous:
        signal.signal(number, lambda *_:cancel.set())
    started = time.monotonic()

    def build_case(index, scenario, platform="macos"):
        return NativeCaseLifecycle(prepare_native_case_workspace(builds, platform=platform,
            scenario_id=scenario, run_id=run_id, worker_id=0, case_index=index,
            ports={"rpc":28232,"lwd":29067,"proxy":29068},activation_height=1))

    report = {"schema_version":2,"catalog_sha256":catalog.fingerprint,"selection":selection,
        "source_commit":commit,"working_tree_dirty":dirty,"run_id":run_id,
        "workers":args.workers,"repeat":args.repeat,"repetition_reports":[],
        "builds":{},"error":None}
    try:
        print("Building selected native artifacts once; logs: "+str(evidence),file=sys.stderr,flush=True)
        targets = tuple(dict.fromkeys(s.target for s in scenarios if s.engine == "rust"))
        needs_addresses = any(s.id in {"flutter.macos.multi-account-send", "flutter.macos.tex-send"}
                              for s in scenarios)
        producer = build_case(1, "rust.signer-build", "rust") if targets else build_case(1,"flutter.macos.signer-build")
        artifact = build_regtest_funder(producer,
            source_root=root, source_commit=commit, jobs=args.build_jobs, timeout=1200,
            cancel_event=cancel, test_targets=targets, wallet_addresses=needs_addresses)
        report["builds"]["signer_build_count"] = 1
        if targets:
            report["builds"].update(rust_build_count=1, rust_test_targets=list(targets))
        payment_addresses = {}
        if needs_addresses:
            payment_addresses = derive_payment_addresses(build_case(2,"rust.wallet-addresses", "rust"),
                artifact, cancel=cancel)
            report["builds"]["payment_addresses"] = payment_addresses
        helper = None
        if any(s.engine == "flutter-macos" for s in scenarios):
            helper, build_proof = build_native_macos_cohort(build_case(0,"flutter.macos.native-build"),
                source_root=root, flutter=args.flutter, cancel_event=cancel,
                tex_address=payment_addresses.get("receiver_tex"))
            report["builds"].update(build_proof)
        dart = (args.flutter.resolve(strict=True).parent/"cache/dart-sdk/bin/dart").resolve(strict=True)
        repetitions = []
        jobs = []
        for repetition in range(args.repeat):
            repeated = evidence/("repetition-"+str(repetition))
            repeated.mkdir(mode=0o700)
            repeated_id = uuid.uuid4().hex[:10]
            repetitions.append((repeated, repeated_id))
            jobs.extend((repetition, index, scenario) for index,scenario in enumerate(scenarios))
        results = [[] for _ in repetitions]
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            submitted = [(repetition,pool.submit(execute_case,*repetitions[repetition],index,scenario,
                helper=helper,artifact=artifact,source_root=root,dart=dart,args=args,cancel=cancel,
                desktop_transparent=payment_addresses.get("desktop_transparent")))
                for repetition,index,scenario in jobs]
            for repetition, future in submitted:
                results[repetition].append(future.result())
        for index,((repeated,repeated_id),items) in enumerate(zip(repetitions,results)):
            path = repeated/"run.json"
            _write_report(path,{"schema_version":2,"catalog_sha256":catalog.fingerprint,
                "selection":selection,"source_commit":commit,"working_tree_dirty":dirty,
                "run_id":repeated_id,"results":items})
            report["repetition_reports"].append({"repetition":index,"report":str(path),
                "passed":sum(item["status"] == "passed" for item in items),
                "failed":sum(item["status"] != "passed" for item in items)})
    except BaseException as error:
        report["error"] = str(error)
    finally:
        for number, handler in previous.items():
            signal.signal(number, handler)
    report["duration_seconds"] = round(time.monotonic()-started,3)
    _write_report(evidence/"summary.json",report)
    print(json.dumps(report,indent=2,allow_nan=False))
    return 0 if report["error"] is None and all(item["failed"] == 0 for item in report["repetition_reports"]) else 1
