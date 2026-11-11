"""Run Zakura regtest scenarios as up to three concurrent sequential runs.

Each lane is one `zakura-run.py` process:

  fixed   the default ports and this checkout: every scenario that needs the
          default ports, such as the endpoint, proxy, screenshot and voting ones
  macos   leased ports and a second checkout whose macOS app has its own bundle
          identifier, so its sandbox, preferences and keychain are separate
  ios     leased ports and the second checkout: the Rust and iOS scenarios

Two runs cannot build in one checkout for the same platform, and only one
macOS app per bundle identifier can run. The second checkout is a clone of
HEAD under `.regtest-logs/lanes/checkout`; it is kept between runs for its
build outputs.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid

import zakura_flutter as flutter_cases
import zakura_sequential as sequential

FIXED, MACOS, IOS = "fixed", "macos", "ios"
# The second macOS app's bundle identifier; the default one stays with the fixed lane.
SECOND_BUNDLE_ID = "com.keplr.vizor.e2eb"
FLAVOR_OVERRIDES = Path("macos/Runner/Configs/FlavorOverrides.xcconfig")


def plan_lanes(scenarios, *, second_macos=True):
    """Split the scenarios into lanes, keeping their order; empty lanes are omitted."""
    lanes = {FIXED: [], MACOS: [], IOS: []}
    for scenario in scenarios:
        if not isinstance(scenario, flutter_cases.FlutterScenario):
            lanes[IOS].append(scenario)
        elif not flutter_cases.leasable(scenario):
            lanes[FIXED].append(scenario)
        elif scenario.platform == "macos":
            lanes[MACOS if second_macos else FIXED].append(scenario)
        else:
            lanes[IOS].append(scenario)
    return {name: selected for name, selected in lanes.items() if selected}


def _git(root, *args):
    return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True,
        text=True).stdout.strip()


def require_clean(root):
    """The second checkout is a clone of HEAD, so every lane must run HEAD."""
    if _git(root, "status", "--porcelain"):
        raise ValueError("commit or stash the changes first; the second checkout runs HEAD")
    return _git(root, "rev-parse", "HEAD")


def prepare_checkout(root, commit, *, flutter, out=print):
    """Clone or update the second checkout at `commit` and resolve its packages."""
    checkout = Path(root) / ".regtest-logs" / "lanes" / "checkout"
    if not (checkout / ".git").exists():
        if checkout.exists():
            raise ValueError(f"{checkout} exists but is not a checkout; remove it")
        checkout.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        out(f"Cloning the second checkout into {checkout}")
        subprocess.run(["git", "clone", "--quiet", "--no-checkout", str(root), str(checkout)], check=True)
    _git(checkout, "fetch", "--quiet", str(root), commit)
    _git(checkout, "checkout", "--quiet", "--detach", "--force", commit)
    (checkout / FLAVOR_OVERRIDES).write_text(f"PRODUCT_BUNDLE_IDENTIFIER = {SECOND_BUNDLE_ID}\n",
        encoding="utf-8")
    resolved = subprocess.run([str(flutter), "pub", "get"], cwd=checkout, capture_output=True, text=True)
    if resolved.returncode:
        raise ValueError(f"`flutter pub get` failed in {checkout}: {resolved.stderr.strip()[-400:]}")
    return checkout


def share_build_cache(root, checkout):
    """Copy the signer builds the second checkout lacks, so its lanes do not rebuild them."""
    source = Path(root) / ".regtest-logs" / "build-cache"
    target = Path(checkout) / ".regtest-logs" / "build-cache"
    for entry in sorted(source.glob("*/*")):
        copy = target / entry.relative_to(source)
        if entry.is_dir() and not copy.exists():
            copy.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            shutil.copytree(entry, copy)


def lane_command(checkout, scenarios, *, leased, flutter, grpcurl, proto_dir, build_jobs, keep_failed,
                 ios_runtime, dart_defines):
    command = [sys.executable, str(Path(checkout) / "scripts/e2e/zakura-run.py"),
               *(scenario.id for scenario in scenarios), "--flutter", str(flutter),
               "--grpcurl", str(grpcurl), "--build-jobs", str(build_jobs)]
    if proto_dir is not None:
        command += ["--proto-dir", str(proto_dir)]
    if leased:
        command.append("--lease-ports")
    if keep_failed:
        command.append("--keep-failed")
    if ios_runtime:
        command += ["--ios-runtime", ios_runtime]
    for name, value in dart_defines:
        command += ["--dart-define", f"{name}={value}"]
    return command


def _report_path(lines):
    for line in reversed(lines):
        if "; report: " in line:
            return Path(line.rsplit("; report: ", 1)[1].strip())
    return None


def run_lanes(root, scenarios, *, flutter, grpcurl, proto_dir=None, build_jobs=4, keep_failed=False,
              ios_runtime=None, dart_defines=(), second_macos=True, cancel_event=None, out=print):
    """Run the scenarios as concurrent lanes; return the merged report and its path."""
    root = Path(root).resolve(strict=True)
    cancel = cancel_event if cancel_event is not None else threading.Event()
    lanes = plan_lanes(scenarios, second_macos=second_macos)
    if dart_defines and any(not isinstance(s, flutter_cases.FlutterScenario) for s in scenarios):
        raise ValueError("--dart-define applies only to Flutter scenarios")
    commit = require_clean(root)
    run_id = uuid.uuid4().hex[:10]
    evidence = root / ".regtest-logs" / f"lanes-{run_id}"
    evidence.mkdir(mode=0o700, parents=True)
    started = time.monotonic()
    report = {"schema_version": 1, "run_id": run_id, "source_commit": commit, "lanes": {}, "error": None}
    checkouts = {FIXED: root}
    if MACOS in lanes or IOS in lanes:
        # One build of the signer serves every lane.
        built, _ = sequential.run_sequence(root, [], flutter=flutter, grpcurl=grpcurl,
            proto_dir=proto_dir if proto_dir is not None else root / "protos",
            build_jobs=build_jobs, cancel_event=cancel, out=out)
        if built["error"]:
            raise ValueError(f"the signer did not build: {built['error']}")
        checkout = prepare_checkout(root, commit, flutter=flutter, out=out)
        share_build_cache(root, checkout)
        checkouts.update({MACOS: checkout, IOS: checkout})

    processes = {}
    outputs = {name: [] for name in lanes}

    def follow(name, process):
        for line in process.stdout:
            outputs[name].append(line)
            out(f"[{name}] {line.rstrip()}")

    threads = []
    interrupted = False

    def stop():
        for process in processes.values():
            if process.poll() is None:
                # Each lane leads its own process group; its runner cleans up on SIGINT.
                os.killpg(process.pid, signal.SIGINT)

    try:
        for name, selected in lanes.items():
            command = lane_command(checkouts[name], selected, leased=name != FIXED, flutter=flutter,
                grpcurl=grpcurl, proto_dir=proto_dir, build_jobs=build_jobs, keep_failed=keep_failed,
                ios_runtime=ios_runtime, dart_defines=dart_defines)
            out(f"[{name}] {len(selected)} scenario(s) in {checkouts[name]}")
            process = subprocess.Popen(command, cwd=checkouts[name], stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, start_new_session=True)
            processes[name] = process
            thread = threading.Thread(target=follow, args=(name, process), daemon=True)
            thread.start()
            threads.append(thread)
        while any(process.poll() is None for process in processes.values()):
            if cancel.is_set() and not interrupted:
                interrupted = True
                stop()
            time.sleep(0.2)
    finally:
        # An error here must not leave lanes running without their parent.
        stop()
        for process in processes.values():
            process.wait()
    for thread in threads:
        thread.join(timeout=5)
    for name, selected in lanes.items():
        path = _report_path(outputs[name])
        lane = {"scenarios": [s.id for s in selected], "checkout": str(checkouts[name]),
                "returncode": processes[name].returncode, "report": str(path) if path else None,
                "results": [], "duration_seconds": None}
        if path is not None and path.is_file():
            data = json.loads(path.read_text(encoding="utf-8"))
            lane.update(results=data["results"], duration_seconds=data["duration_seconds"],
                error=data["error"])
        (evidence / f"{name}.log").write_text("".join(outputs[name]), encoding="utf-8")
        report["lanes"][name] = lane
    if interrupted:
        report["error"] = "cancelled"
    report["duration_seconds"] = round(time.monotonic() - started, 3)
    path = evidence / "report.json"
    path.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return report, path
