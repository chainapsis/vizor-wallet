#!/usr/bin/env python3
"""Convert illustration PNGs to pixel-exact lossless WebP files.

Usage:
  scripts/convert-illustrations-to-webp.py          # dry-run and report
  scripts/convert-illustrations-to-webp.py --apply  # apply the verified plan

Requires `cwebp` and ImageMagick's `magick` on PATH. The conversion preserves
the decoded 8-bit RGBA pixels, including RGB values hidden by fully transparent
alpha, and asks cwebp to copy every WebP-supported metadata type. PNG-only
chunks such as pHYs, tEXt, tIME, and bKGD have no guaranteed WebP equivalent.
The script rejects APNG, non-8-bit input, embedded ICC profiles, and non-sRGB
gamma or chromaticity declarations rather than silently changing color.
RGBA equality is verified with ImageMagick. Native renderers may still round
alpha premultiplication differently between their PNG and WebP decoders.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
ASSET_ROOT = REPOSITORY_ROOT / "assets" / "illustrations"
REFERENCE_ROOTS = ("lib", "test", "integration_test")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SRGB_GAMMA = 45_455
SRGB_CHROMATICITIES = (
    31_270,
    32_900,
    64_000,
    33_000,
    30_000,
    60_000,
    15_000,
    6_000,
)
DART_STRING = re.compile(
    r"(?P<prefix>[rR]?)(?P<quote>['\"])(?P<body>(?:\\.|(?!(?P=quote))[^\r\n])*)(?P=quote)"
)


class ConversionError(RuntimeError):
    pass


@dataclass(frozen=True)
class PngInfo:
    width: int
    height: int


@dataclass(frozen=True)
class ReferenceEdit:
    path: Path
    before: bytes
    after: bytes
    replacements: int


@dataclass(frozen=True)
class Conversion:
    source: Path
    target: Path
    staged: Path
    backup: Path
    source_sha256: str
    source_size: int
    target_size: int


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise ConversionError(f"required command is not on PATH: {name}")
    return path


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def inspect_png(path: Path) -> PngInfo:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ConversionError(f"not a PNG file: {path}")

    offset = len(PNG_SIGNATURE)
    info: PngInfo | None = None
    saw_end = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            raise ConversionError(f"truncated PNG chunk in {path}")
        chunk_type = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : end])[0]
        actual_crc = binascii.crc32(chunk_type + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ConversionError(f"invalid {chunk_type!r} CRC in {path}")

        if chunk_type == b"IHDR":
            if info is not None or length != 13:
                raise ConversionError(f"invalid IHDR in {path}")
            width, height, bit_depth, color_type = struct.unpack(">IIBB", payload[:10])
            if bit_depth != 8:
                raise ConversionError(
                    f"{path} is {bit_depth}-bit; lossless WebP input must be 8-bit"
                )
            if color_type not in (0, 2, 3, 4, 6):
                raise ConversionError(f"unsupported PNG color type {color_type} in {path}")
            info = PngInfo(width, height)
        elif chunk_type == b"acTL":
            raise ConversionError(f"APNG is not supported: {path}")
        elif chunk_type == b"iCCP":
            raise ConversionError(
                f"embedded ICC profile requires explicit color handling: {path}"
            )
        elif chunk_type == b"gAMA":
            if length != 4 or struct.unpack(">I", payload)[0] != SRGB_GAMMA:
                raise ConversionError(f"non-sRGB gAMA chunk in {path}")
        elif chunk_type == b"cHRM":
            if length != 32 or struct.unpack(">8I", payload) != SRGB_CHROMATICITIES:
                raise ConversionError(f"non-sRGB cHRM chunk in {path}")
        elif chunk_type == b"IEND":
            saw_end = True
            break
        offset = end

    if info is None or not saw_end:
        raise ConversionError(f"incomplete PNG structure: {path}")
    return info


def run(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(command, check=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode("utf-8", errors="replace").strip()
        raise ConversionError(f"command failed: {' '.join(command)}\n{detail}") from error


def image_dimensions(magick: str, path: Path) -> tuple[int, int]:
    result = run([magick, "identify", "-format", "%w %h", str(path)])
    try:
        width, height = result.stdout.decode("ascii").split()
        return int(width), int(height)
    except ValueError as error:
        raise ConversionError(f"cannot read image dimensions from {path}") from error


def rgba_sha256(magick: str, path: Path, info: PngInfo) -> str:
    result = run([magick, str(path), "-alpha", "on", "-depth", "8", "RGBA:-"])
    expected_size = info.width * info.height * 4
    if len(result.stdout) != expected_size:
        raise ConversionError(
            f"decoded RGBA size mismatch for {path}: "
            f"{len(result.stdout)} != {expected_size}"
        )
    return hashlib.sha256(result.stdout).hexdigest()


def rewrite_dart(text: str, full_names: dict[str, str], short_names: dict[str, str]) -> tuple[str, int]:
    replacements = 0

    def replace_string(match: re.Match[str]) -> str:
        nonlocal replacements
        body = match.group("body")
        replacement = full_names.get(body) or short_names.get(body)
        if replacement is None and body.startswith("assets/illustrations/"):
            if "$" in body and body.endswith(".png"):
                replacement = body[:-4] + ".webp"
        if replacement is None:
            return match.group(0)
        replacements += 1
        return f'{match.group("prefix")}{match.group("quote")}{replacement}{match.group("quote")}'

    return DART_STRING.sub(replace_string, text), replacements


def plan_reference_edits(pngs: list[Path]) -> list[ReferenceEdit]:
    relative_names = [path.relative_to(ASSET_ROOT).as_posix() for path in pngs]
    if len({Path(name).name for name in relative_names}) != len(relative_names):
        raise ConversionError("illustration PNG basenames must be unique")

    full_names = {
        f"assets/illustrations/{name}": f"assets/illustrations/{Path(name).with_suffix('.webp').as_posix()}"
        for name in relative_names
    }
    short_names: dict[str, str] = {}
    for name in relative_names:
        new_name = Path(name).with_suffix(".webp").as_posix()
        short_names[name] = new_name
        short_names[Path(name).name] = Path(new_name).name

    edits: list[ReferenceEdit] = []
    for root_name in REFERENCE_ROOTS:
        root = REPOSITORY_ROOT / root_name
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.dart")):
            before = path.read_bytes()
            try:
                text = before.decode("utf-8")
            except UnicodeDecodeError as error:
                raise ConversionError(f"Dart source is not UTF-8: {path}") from error
            rewritten, replacements = rewrite_dart(text, full_names, short_names)
            if replacements:
                edits.append(
                    ReferenceEdit(path, before, rewritten.encode("utf-8"), replacements)
                )
    return edits


def atomic_copy(source: Path, target: Path, mode: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output, source.open("rb") as input_stream:
            shutil.copyfileobj(input_stream, output)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_write(path: Path, contents: bytes) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(contents)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, stat.S_IMODE(path.stat().st_mode))
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def stage_conversions(
    pngs: list[Path], temporary_root: Path, cwebp: str, magick: str
) -> list[Conversion]:
    infos = {path: inspect_png(path) for path in pngs}
    conversions: list[Conversion] = []
    for index, source in enumerate(pngs, start=1):
        relative = source.relative_to(ASSET_ROOT)
        target = source.with_suffix(".webp")
        staged = temporary_root / "converted" / relative.with_suffix(".webp")
        backup = temporary_root / "original" / relative
        staged.parent.mkdir(parents=True, exist_ok=True)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, backup)
        source_hash = file_sha256(source)
        source_pixels = rgba_sha256(magick, source, infos[source])
        run(
            [
                cwebp,
                "-quiet",
                "-lossless",
                "-exact",
                "-m",
                "6",
                "-metadata",
                "all",
                str(source),
                "-o",
                str(staged),
            ]
        )
        if image_dimensions(magick, staged) != (infos[source].width, infos[source].height):
            raise ConversionError(f"converted dimensions changed: {source}")
        if rgba_sha256(magick, staged, infos[source]) != source_pixels:
            raise ConversionError(f"converted RGBA pixels changed: {source}")
        conversions.append(
            Conversion(
                source,
                target,
                staged,
                backup,
                source_hash,
                source.stat().st_size,
                staged.stat().st_size,
            )
        )
        print(f"[{index:02d}/{len(pngs)}] verified {relative}")
    return conversions


def apply_plan(conversions: list[Conversion], edits: list[ReferenceEdit]) -> None:
    for conversion in conversions:
        if conversion.target.exists():
            raise ConversionError(f"target appeared during staging: {conversion.target}")
        if file_sha256(conversion.source) != conversion.source_sha256:
            raise ConversionError(f"source changed during staging: {conversion.source}")
    for edit in edits:
        if edit.path.read_bytes() != edit.before:
            raise ConversionError(f"reference changed during staging: {edit.path}")

    installed: list[Conversion] = []
    changed_edits: list[ReferenceEdit] = []
    deleted: list[Conversion] = []
    try:
        for conversion in conversions:
            mode = stat.S_IMODE(conversion.source.stat().st_mode)
            atomic_copy(conversion.staged, conversion.target, mode)
            installed.append(conversion)
        for edit in edits:
            atomic_write(edit.path, edit.after)
            changed_edits.append(edit)
        for conversion in conversions:
            conversion.source.unlink()
            deleted.append(conversion)
    except BaseException:
        for conversion in reversed(deleted):
            atomic_copy(
                conversion.backup,
                conversion.source,
                stat.S_IMODE(conversion.backup.stat().st_mode),
            )
        for edit in reversed(changed_edits):
            atomic_write(edit.path, edit.before)
        for conversion in reversed(installed):
            conversion.target.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--apply",
        action="store_true",
        help="install verified WebP files, update Dart references, and delete source PNGs",
    )
    args = parser.parse_args()
    try:
        pngs = sorted(path for path in ASSET_ROOT.rglob("*.png") if path.is_file())
        if not pngs:
            print(f"no PNG illustrations to convert under {ASSET_ROOT}")
            return 0
        cwebp = require_tool("cwebp")
        magick = require_tool("magick")
        collisions = [path.with_suffix(".webp") for path in pngs if path.with_suffix(".webp").exists()]
        if collisions:
            raise ConversionError(f"refusing to overwrite existing target: {collisions[0]}")

        edits = plan_reference_edits(pngs)
        with tempfile.TemporaryDirectory(prefix="vizor-lossless-webp-") as directory:
            conversions = stage_conversions(pngs, Path(directory), cwebp, magick)
            source_bytes = sum(item.source_size for item in conversions)
            target_bytes = sum(item.target_size for item in conversions)
            saved_bytes = source_bytes - target_bytes
            percent = saved_bytes * 100 / source_bytes
            print(
                f"verified {len(conversions)} files: {source_bytes:,} -> {target_bytes:,} bytes "
                f"({saved_bytes:,} bytes, {percent:.1f}% smaller)"
            )
            print(
                f"planned {sum(edit.replacements for edit in edits)} reference replacements "
                f"across {len(edits)} Dart files"
            )
            if args.apply:
                apply_plan(conversions, edits)
                print("applied verified lossless WebP conversion")
            else:
                print("dry-run only; pass --apply to write the verified plan")
        return 0
    except (ConversionError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
