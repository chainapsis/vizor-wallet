#!/usr/bin/env python3
"""Count production Cargo packages without counting dev dependencies.

Normal dependencies exclude proc-macro subtrees. The build graph includes
normal dependencies, build dependencies, and proc macros. These are package
graph counts, not a claim that every package contributes linked machine code.
"""

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def packages(manifest, target, edges):
    command = [
        "cargo", "tree", "--locked", "--offline", "--manifest-path",
        str(manifest), "--target", target, "--edges", edges,
        "--prefix", "none", "--format", "{p}",
    ]
    output = subprocess.check_output(command, text=True)
    # Preserve version and source identity, but omit Cargo's display markers.
    result = set()
    for line in output.splitlines()[1:]:
        line = re.sub(r" \((?:\*|proc-macro)\)", "", line)
        result.add(line)
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest-path", type=Path,
                        default=Path(__file__).resolve().parents[1] / "rust/Cargo.toml")
    parser.add_argument("--target", help="Cargo target triple (defaults to host)")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    if args.baseline and args.baseline.resolve() == args.output.resolve():
        parser.error("output must not overwrite the comparison baseline")
    rustc = subprocess.check_output(["rustc", "-vV"], text=True)
    host = next(line[6:] for line in rustc.splitlines()
                if line.startswith("host: "))
    target = args.target or host
    runtime = packages(args.manifest_path, target, "normal,no-proc-macro")
    total = packages(args.manifest_path, target, "normal,build")
    build_only = sorted(set(total) - set(runtime))
    report = {
        "schema_version": 1,
        "host": host,
        "target": target,
        "rustc": rustc,
        "manifest_sha256": hashlib.sha256(args.manifest_path.read_bytes()).hexdigest(),
        "lockfile_sha256": hashlib.sha256(
            args.manifest_path.with_name("Cargo.lock").read_bytes()).hexdigest(),
        "runtime_definition": "normal edges, excluding proc-macro subtrees",
        "build_definition": "normal and build edges, including proc macros",
        "runtime_packages": runtime,
        "build_only_packages": build_only,
        "total_packages": total,
        "counts": {"runtime": len(runtime), "build_only": len(build_only),
                   "total": len(total)},
    }
    if args.baseline:
        baseline = json.loads(args.baseline.read_text())
        if baseline["target"] != target or baseline.get("host", host) != host:
            parser.error("baseline and candidate must use the same host and target")
        report["comparison"] = {}
        for key, field in [("runtime", "runtime_packages"),
                           ("build_only", "build_only_packages"),
                           ("total", "total_packages")]:
            before, after = set(baseline[field]), set(report[field])
            report["comparison"][key] = {
                "removed": sorted(before - after),
                "added": sorted(after - before),
                "reduction_percent": 100 * (len(before) - len(after)) / len(before)
                if before else None,
            }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"target": target, **report["counts"]}))
    if "comparison" in report:
        print(json.dumps(report["comparison"], indent=2))


if __name__ == "__main__":
    main()
