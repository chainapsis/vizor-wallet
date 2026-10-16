#!/usr/bin/env python3
"""Run direct Zakura regtest scenarios one at a time.

  python3 scripts/e2e/zakura-run.py --list
  python3 scripts/e2e/zakura-run.py rust
  python3 scripts/e2e/zakura-run.py rust.import rust.send.basic
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading

if sys.version_info < (3, 11):
    sys.exit("zakura-run.py needs Python 3.11 or newer")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_sequential as sequential  # noqa: E402


def pinned_flutter(root):
    """The checkout's fvm-pinned Flutter executable, or None."""
    fvm = shutil.which("fvm")
    if fvm is None:
        return None
    completed = subprocess.run([fvm, "flutter", "--version", "--machine"], cwd=root,
        capture_output=True, text=True, timeout=300)
    if completed.returncode or "{" not in completed.stdout:
        return None
    info = json.loads(completed.stdout[completed.stdout.index("{"):])
    return Path(info["flutterRoot"]) / "bin" / "flutter"


def _console(text):
    print(text, file=sys.stderr, flush=True)


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="Run direct Zakura regtest scenarios one at a time.")
    parser.add_argument("scenarios", nargs="*",
        help="scenario IDs, or dotted prefixes such as `rust` or `rust.import`")
    parser.add_argument("--list", action="store_true", help="print every scenario ID and exit")
    parser.add_argument("--flutter", type=Path, help="Flutter executable (default: the fvm-pinned SDK)")
    parser.add_argument("--grpcurl", type=Path, help="grpcurl executable (default: from PATH)")
    parser.add_argument("--proto-dir", type=Path, default=root / "protos",
        help="lightwalletd protos (default: protos/)")
    parser.add_argument("--build-jobs", type=int, default=4, help="Cargo build jobs, 1 through 8")
    parser.add_argument("--keep-failed", action="store_true",
        help="keep the regtest chain and wallet files of failed scenarios")
    parser.add_argument("--ios-runtime",
        help="simulator runtime for iOS scenarios, such as com.apple.CoreSimulator.SimRuntime.iOS-26-3 "
             "(default: the newest installed)")
    parser.add_argument("--dart-define", action="append", default=[], metavar="NAME=VALUE",
        help="add a define to every Flutter phase, such as GIFT_CARD_E2E_AMOUNT_MODE=usd")
    args = parser.parse_args(argv)
    if args.list:
        for scenario in sequential.ALL_SCENARIOS:
            print(scenario.id)
        return 0
    if not args.scenarios:
        parser.error("select scenarios, or `rust` for all of them; see --list")
    try:
        scenarios = sequential.select_scenarios(args.scenarios)
    except ValueError as error:
        parser.error(str(error))
    defines = []
    for text in args.dart_define:
        name, separator, value = text.partition("=")
        if not name or not separator:
            parser.error(f"--dart-define takes NAME=VALUE, not {text!r}")
        defines.append((name, value))
    if defines and any(not isinstance(s, sequential.flutter_cases.FlutterScenario) for s in scenarios):
        parser.error("--dart-define applies only to Flutter scenarios")
    if not 1 <= args.build_jobs <= 8:
        parser.error("--build-jobs must be 1 through 8")
    grpcurl = args.grpcurl or (Path(found) if (found := shutil.which("grpcurl")) else None)
    if grpcurl is None:
        parser.error("grpcurl was not found; install it or pass --grpcurl")
    flutter = args.flutter or pinned_flutter(root)
    if flutter is None:
        parser.error("the Flutter SDK could not be resolved through fvm; pass --flutter")

    cancel = threading.Event()

    def interrupt(_signum, _frame):
        cancel.set()

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    try:
        report, path = sequential.run_sequence(root, scenarios, flutter=flutter, grpcurl=grpcurl,
            proto_dir=args.proto_dir, build_jobs=args.build_jobs, keep_failed=args.keep_failed,
            cancel_event=cancel, out=_console, ios_runtime=args.ios_runtime, dart_defines=tuple(defines))
    except ValueError as error:
        _console(f"zakura-run: {error}")
        return 2
    results = report["results"]
    passed = [result for result in results if result["status"] == "passed"]
    for result in results:
        if result["status"] != "passed":
            _console(f"{result['status'].upper()} {result['scenario_id']} "
                     f"({result.get('failed_phase')}): {result['error']}")
            _console(f"    evidence: {result.get('evidence')}")
            if result.get("retained"):
                _console(f"    kept: {json.dumps(result['retained'])}")
    if report["error"]:
        _console(f"run stopped: {report['error']}")
    _console(f"{len(passed)}/{len(scenarios)} passed; report: {path}")
    return 0 if len(passed) == len(scenarios) and report["error"] is None else 1


if __name__ == "__main__":
    sys.exit(main())
