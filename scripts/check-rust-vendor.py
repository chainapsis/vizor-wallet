#!/usr/bin/env python3
"""Check vendored source against its pinned provenance and reviewed patches."""

import argparse
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--vendor-root", type=Path,
        default=Path(__file__).resolve().parents[1] / "rust/vendor",
    )
    root = parser.parse_args().vendor_root
    failures = []
    records = sorted(root.glob("*/UPSTREAM.json"))
    if not records:
        parser.error(f"no vendored provenance found in {root}")
    for record in records:
        package = record.parent
        metadata = json.loads(record.read_text())
        expected = {
            **metadata["upstream_files_sha256"],
            **metadata["patched_files_sha256"],
            **metadata["added_file_sha256"],
        }
        for relative, digest in expected.items():
            path = package / relative
            if not path.is_file():
                failures.append(f"{package.name}/{relative}: missing")
            elif hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                failures.append(f"{package.name}/{relative}: content changed")
        rust_sources = {
            str(path.relative_to(package)) for path in package.rglob("*.rs")
            if "target" not in path.relative_to(package).parts
        }
        unexpected = rust_sources - expected.keys()
        for relative in sorted(unexpected):
            failures.append(f"{package.name}/{relative}: unrecorded Rust source")
        print(f"{package.name}: checked {len(expected)} pinned files")
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
