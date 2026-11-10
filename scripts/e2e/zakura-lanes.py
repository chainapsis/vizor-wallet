#!/usr/bin/env python3
"""Run direct Zakura regtest scenarios as concurrent lanes.

  python3 scripts/e2e/zakura-lanes.py rust flutter
  python3 scripts/e2e/zakura-lanes.py flutter.macos --single-macos

See zakura_lanes.py for what each lane runs. The working tree must be clean.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import signal
import sys
import threading

if sys.version_info < (3, 11):
    sys.exit("zakura-lanes.py needs Python 3.11 or newer")

sys.path.insert(0, str(Path(__file__).resolve().parent))
import zakura_lanes as lanes  # noqa: E402
import zakura_sequential as sequential  # noqa: E402


def _console(text):
    print(text, file=sys.stderr, flush=True)


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="Run direct Zakura regtest scenarios as concurrent lanes.")
    parser.add_argument("scenarios", nargs="+",
        help="scenario IDs, or dotted prefixes such as `rust` or `flutter.ios`")
    parser.add_argument("--flutter", type=Path, help="Flutter executable (default: the fvm-pinned SDK)")
    parser.add_argument("--grpcurl", type=Path, help="grpcurl executable (default: from PATH)")
    parser.add_argument("--proto-dir", type=Path, default=root / "protos",
        help="lightwalletd protos (default: protos/)")
    parser.add_argument("--build-jobs", type=int, default=4, help="Cargo build jobs, 1 through 8")
    parser.add_argument("--keep-failed", action="store_true",
        help="keep the regtest chain and wallet files of failed scenarios")
    parser.add_argument("--ios-runtime", help="simulator runtime for iOS scenarios (default: the newest installed)")
    parser.add_argument("--single-macos", action="store_true",
        help="run every macOS scenario in the fixed lane instead of starting a second macOS app")
    parser.add_argument("--dart-define", action="append", default=[], metavar="NAME=VALUE",
        help="add a define to every Flutter phase")
    args = parser.parse_args(argv)
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
    if not 1 <= args.build_jobs <= 8:
        parser.error("--build-jobs must be 1 through 8")
    grpcurl = args.grpcurl or (Path(found) if (found := shutil.which("grpcurl")) else None)
    if grpcurl is None:
        parser.error("grpcurl was not found; install it or pass --grpcurl")
    flutter = args.flutter or sequential.flutter_cases.pinned_flutter(root)
    if flutter is None:
        parser.error("the Flutter SDK could not be resolved through fvm; pass --flutter")

    cancel = threading.Event()

    def interrupt(_signum, _frame):
        cancel.set()

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGHUP, interrupt)
    try:
        report, path = lanes.run_lanes(root, scenarios, flutter=flutter, grpcurl=grpcurl,
            proto_dir=args.proto_dir, build_jobs=args.build_jobs, keep_failed=args.keep_failed,
            ios_runtime=args.ios_runtime, dart_defines=tuple(defines),
            second_macos=not args.single_macos, cancel_event=cancel, out=_console)
    except ValueError as error:
        _console(f"zakura-lanes: {error}")
        return 2
    passed = total = 0
    complete = report["error"] is None
    for name, lane in report["lanes"].items():
        total += len(lane["scenarios"])
        passed += sum(result["status"] == "passed" for result in lane["results"])
        complete = complete and lane["returncode"] in (0, 1) and len(lane["results"]) == len(lane["scenarios"])
        for result in lane["results"]:
            if result["status"] != "passed":
                _console(f"{result['status'].upper()} [{name}] {result['scenario_id']} "
                         f"({result.get('failed_phase')}): {result['error']}")
                _console(f"    evidence: {result.get('evidence')}")
        if len(lane["results"]) != len(lane["scenarios"]):
            _console(f"[{name}] ran {len(lane['results'])} of {len(lane['scenarios'])} scenario(s); "
                     f"see {path.parent / (name + '.log')}")
    _console(f"{passed}/{total} passed in {report['duration_seconds']:.0f}s; report: {path}")
    return 0 if complete and passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
