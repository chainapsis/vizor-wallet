#!/usr/bin/env python3
"""Inventory an extracted AppDir and enforce its host-library boundary."""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


# Vizor policy, not linuxdeploy's default list.
HOST_LIBRARIES = tuple(
    line.strip() for line in Path(__file__).with_name("host-libraries.txt").read_text().splitlines()
    if line.strip() and not line.lstrip().startswith("#")
)


def host_library(name: str) -> bool:
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in HOST_LIBRARIES)


def inspect_bundle(appdir: Path, output: Path) -> dict:
    failures = []
    libraries = []
    paths = sorted(appdir.rglob("*"))
    env = dict(os.environ, LD_LIBRARY_PATH=f"{appdir}/usr/bin/lib:{appdir}/usr/lib")
    for path in paths:
        relative = str(path.relative_to(appdir))
        if host_library(path.name):
            failures.append(f"Bundled host library: {relative}")
        if not path.is_file() or path.is_symlink():
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        dynamic = subprocess.run(
            ["readelf", "--wide", "--dynamic", str(path)],
            capture_output=True, text=True, timeout=15, check=True,
        ).stdout
        soname = re.search(r"\(SONAME\).*?\[(.*?)\]", dynamic)
        if soname and host_library(soname[1]) and not host_library(path.name):
            failures.append(f"Bundled host SONAME: {relative} ({soname[1]})")
        needed = re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic)
        resolved = ""
        if needed:
            linked = subprocess.run(
                ["ldd", str(path)], env=env, capture_output=True, text=True, timeout=20,
            )
            resolved = linked.stdout + linked.stderr
            if linked.returncode or "not found" in resolved or "no version information available" in resolved:
                failures.append(f"Unresolved dependencies: {relative}")
        libraries.append({"path": relative, "needed": needed, "ldd": resolved})
    report = {"status": "failed" if failures else "passed", "failures": failures, "elfs": libraries}
    (output / "bundle.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appdir", type=Path, required=True)
    args = parser.parse_args()
    if not (args.appdir / "AppRun").is_file():
        parser.error("--appdir must contain AppRun")
    with tempfile.TemporaryDirectory(prefix="vizor-bundle-preflight-") as temporary:
        report = inspect_bundle(args.appdir.resolve(), Path(temporary))
    for failure in report["failures"]:
        print(failure)
    print(f"Bundle preflight: {report['status']} ({len(report['elfs'])} ELF files)")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
