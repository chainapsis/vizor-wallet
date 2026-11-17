#!/usr/bin/env python3
"""Check or refresh native tab SVG copies from assets/icons (the source).

Run with --apply after changing a tab icon. The default and --check are read-only.
See docs/ios-native-tab-bar.md for the native icon contract.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parent.parent
ICONS = ("home", "swap_arrows", "history", "cog")
CATALOG = ROOT / "ios/Runner/Assets.xcassets"


def contents(name: str) -> dict:
    return {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {
            "template-rendering-intent": "template",
            "preserves-vector-representation": True,
        },
    }


def synchronize(apply: bool) -> list[str]:
    errors = []
    for name in ICONS:
        source = ROOT / f"assets/icons/{name}.svg"
        imageset = CATALOG / f"VizorTab_{name}.imageset"
        target = imageset / source.name
        metadata = imageset / "Contents.json"
        expected = contents(name)
        if not source.is_file():
            errors.append(f"Missing source: {source.relative_to(ROOT)}")
            continue
        if apply:
            imageset.mkdir(parents=True, exist_ok=True)
            if not target.is_file() or target.read_bytes() != source.read_bytes():
                target.write_bytes(source.read_bytes())
            text = json.dumps(expected, indent=2) + "\n"
            if not metadata.is_file() or metadata.read_text() != text:
                metadata.write_text(text)
        if not target.is_file() or target.read_bytes() != source.read_bytes():
            errors.append(f"Stale or missing SVG: {target.relative_to(ROOT)}")
        try:
            actual = json.loads(metadata.read_text())
        except (OSError, ValueError):
            actual = None
        if actual != expected:
            errors.append(f"Stale or missing metadata: {metadata.relative_to(ROOT)}")
    expected_sets = {f"VizorTab_{name}.imageset" for name in ICONS}
    for imageset in sorted(CATALOG.glob("VizorTab_*.imageset")):
        if imageset.name not in expected_sets:
            errors.append(f"Unmapped native tab imageset: {imageset.relative_to(ROOT)}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Refresh native copies")
    mode.add_argument("--check", action="store_true", help="Check without writing (default)")
    args = parser.parse_args()
    errors = synchronize(args.apply)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print("Run scripts/sync-ios-native-tab-icons.py --apply to refresh copies.", file=sys.stderr)
        return 1
    print(f"Native tab icons match all {len(ICONS)} source SVGs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
