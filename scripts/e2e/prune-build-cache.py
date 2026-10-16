#!/usr/bin/env python3
"""List the E2E build cache, and with --apply remove all but each kind's newest entries."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_cache  # noqa: E402


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--keep", type=int, default=build_cache.DEFAULT_KEEP,
                        help=f"newest entries to keep of each kind (default {build_cache.DEFAULT_KEEP})")
    parser.add_argument("--apply", action="store_true", help="remove the entries the listing marks delete")
    args = parser.parse_args(argv)
    if args.keep < 1:
        parser.error("--keep must be one or more")
    checkout = Path(__file__).resolve().parents[2]
    return build_cache.prune(checkout / ".regtest-logs" / "build-cache", keep=args.keep, apply=args.apply)


if __name__ == "__main__":
    sys.exit(main())
