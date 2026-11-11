#!/usr/bin/env python3
"""Reproducible language font subsets. Upstream files stay in .dart_tool.

The normal localization generator calls this automatically. --check is offline,
needs only Python's standard library, and detects stale or modified artifacts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "tool/l10n/ui_fonts.manifest.json"
LOCK = "tool/l10n/ui_fonts.lock.json"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_output(root, relative):
    path = root
    for part in Path(relative).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f"Refusing to write through symbolic link: {path}")
    return path


def write_if_changed(path, data):
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def additional_characters(root, font):
    characters = set()
    for start, end in font.get("include_unicode_ranges", []):
        characters.update(range(int(start, 16), int(end, 16) + 1))
    if "include_character_file" in font:
        path = root / font["include_character_file"]
        data = path.read_bytes()
        if digest(data) != font["include_character_file_sha256"]:
            raise ValueError(f"Character-set checksum mismatch: {path}")
        for line in data.decode("utf-8").splitlines():
            if not line.startswith("#"):
                characters.update(ord(c) for c in line if not c.isspace())
    return characters


def inputs(root):
    lock = json.loads((root / LOCK).read_text(encoding="utf-8"))
    names = re.findall(
        r"nativeName:\s*'([^']+)'",
        (root / "lib/src/core/l10n/app_language.dart").read_text(encoding="utf-8"),
    )
    character_sets = {}
    formatting = json.loads((root / "tool/l10n/ui_font_characters.json").read_text(encoding="utf-8"))
    intl_version = re.search(
        r'\n  intl:\n[\s\S]*?\n    version: "([^"]+)"',
        (root / "pubspec.lock").read_text(encoding="utf-8"),
    ).group(1)
    if formatting["intl_version"] != intl_version:
        raise ValueError("intl changed; run fvm dart run tool/l10n/generate.dart")
    for font in lock["fonts"]:
        arb = json.loads((root / font["arb"]).read_text(encoding="utf-8"))
        text = "".join(
            value for key, value in sorted(arb.items())
            if not key.startswith("@") and isinstance(value, str)
        )
        # Both names occur in every language picker. Keep the Korean word
        # joiner too, even though translators edit the source without it.
        text += "".join(names) + "\u200c\u200d\u00a0"
        text += formatting["locales"][font["locale"]]
        character_sets[font["locale"]] = sorted(
            {ord(c) for c in text if ord(c) >= 32}
            | set(range(32, 127))
            | additional_characters(root, font)
        )
    signature = digest(json.dumps({
        "lock": lock,
        "generator": digest((root / "tool/l10n/ui_fonts.py").read_bytes()),
        "formatting_generator": digest((root / "tool/l10n/ui_font_characters.dart").read_bytes()),
        "characters": character_sets,
    }, sort_keys=True).encode())
    return lock, character_sets, signature


def is_current(root):
    lock, _, signature = inputs(root)
    path = root / MANIFEST
    if not path.exists():
        return False
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("input_sha256") != signature:
        return False
    expected_paths = {font["output"] for font in lock["fonts"]}
    if set(manifest.get("fonts", {})) != expected_paths:
        return False
    for relative, font in manifest["fonts"].items():
        path = safe_output(root, relative)
        if not path.is_file() or digest(path.read_bytes()) != font["sha256"]:
            return False
    return True


def fetch_source(root, font):
    path = safe_output(root, ".dart_tool/ui_fonts/sources/" + font["sha256"] + ".ttf")
    if not path.exists() or digest(path.read_bytes()) != font["sha256"]:
        print(f"Downloading pinned {font['upstream']}…", flush=True)
        with urllib.request.urlopen(font["url"], timeout=120) as response:
            data = response.read()
        if digest(data) != font["sha256"]:
            raise ValueError(f"Source checksum mismatch: {font['upstream']}")
        write_if_changed(path, data)
    return path


def build(root, force=False):
    from fontTools import subset
    from fontTools.ttLib import TTFont
    from io import BytesIO

    lock, characters, signature = inputs(root)
    manifest = {"input_sha256": signature, "fonts": {}}
    previous_path = root / MANIFEST
    previous = json.loads(previous_path.read_text(encoding="utf-8")) if previous_path.exists() else {}
    for config in lock["fonts"]:
        font_signature = digest(json.dumps({
            "config": config,
            "characters": characters[config["locale"]],
            "fonttools_version": lock["fonttools_version"],
            "generator": digest((root / "tool/l10n/ui_fonts.py").read_bytes()),
            "formatting_generator": digest((root / "tool/l10n/ui_font_characters.dart").read_bytes()),
        }, sort_keys=True).encode())
        path = safe_output(root, config["output"])
        old_font = previous.get("fonts", {}).get(config["output"], {})
        if (not force and old_font.get("input_sha256") == font_signature
                and path.exists() and digest(path.read_bytes()) == old_font.get("sha256")):
            manifest["fonts"][config["output"]] = old_font
            print(f"{config['output']}: unchanged", flush=True)
            continue
        font = TTFont(fetch_source(root, config), recalcTimestamp=False)
        original_cmap = font.getBestCmap()
        requested = set(characters[config["locale"]])
        # Keep only characters the upstream font actually supports. In
        # particular, Pretendard's unsupported conjoining/archaic jamo stay
        # on system fallback. The other bundled font covers picker names.
        available = requested.intersection(original_cmap)
        options = subset.Options()
        options.layout_features = ["*"]
        sub = subset.Subsetter(options=options)
        sub.populate(unicodes=available)
        sub.subset(font)
        # Pretendard has a Reserved Font Name. Give both modified subsets
        # their own names; preserve upstream copyright/license name records.
        family = config["family"]
        postscript = family.replace(" ", "")
        renamed = {1: family, 3: postscript + "-UI", 4: family,
                   6: postscript, 16: family, 25: postscript}
        for instance in font["fvar"].instances:
            name_id = instance.postscriptNameID
            if name_id != 0xFFFF and name_id not in renamed:
                old_name = font["name"].getDebugName(name_id)
                renamed[name_id] = postscript + "-" + old_name.rsplit("-", 1)[-1]
        for record in font["name"].names:
            if record.nameID in renamed:
                record.string = renamed[record.nameID].encode(record.getEncoding())
        output = BytesIO()
        font.save(output, reorderTables=True)
        data = output.getvalue()
        path = safe_output(root, config["output"])
        write_if_changed(path, data)
        manifest["fonts"][config["output"]] = {
            "input_sha256": font_signature,
            "family": family,
            "upstream": config["upstream"],
            "source_sha256": config["sha256"],
            "sha256": digest(data),
            "bytes": len(data),
            "codepoints": sorted(font.getBestCmap()),
            "axes": {a.axisTag: [a.minValue, a.maxValue]
                     for a in font["fvar"].axes},
        }
        print(f"{config['output']}: {len(data):,} bytes", flush=True)
    target = safe_output(root, MANIFEST)
    write_if_changed(target, (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode())


def generator_python(root, version):
    # No font tooling, network, or full font files are needed for an up-to-date
    # checkout. Bootstrap the pinned pure-Python tool only when glyphs change.
    environment = safe_output(root, ".dart_tool/ui_fonts/venv")
    python = environment / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    ready = environment / "fonttools-version"
    if not python.exists():
        subprocess.run([sys.executable, "-m", "venv", str(environment)], check=True)
    if not ready.exists() or ready.read_text(encoding="utf-8") != version:
        subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                        "fonttools==" + version], check=True)
        ready.write_text(version, encoding="utf-8")
    return python


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--rebuild", action="store_true", help="Regenerate even when current")
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        build(ROOT, force=args.rebuild)
    elif is_current(ROOT) and not args.rebuild:
        print("UI font subsets are current.")
    elif args.check:
        sys.exit("UI font subsets are stale. Run fvm dart run tool/l10n/generate.dart.")
    else:
        lock, _, _ = inputs(ROOT)
        python = generator_python(ROOT, lock["fonttools_version"])
        subprocess.run([str(python), str(Path(__file__).resolve()), "--worker",
                        *(["--rebuild"] if args.rebuild else [])], check=True)


if __name__ == "__main__":
    main()
