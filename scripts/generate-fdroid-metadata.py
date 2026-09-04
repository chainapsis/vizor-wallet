#!/usr/bin/env python3
"""Generate the fdroiddata metadata for a published Vizor Direct Release."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
from typing import Any


PACKAGE_NAME = "com.keplr.vizor"
SIGNING_SHA256 = "07a32dd9f58a0e3beaf0c30db08138b606e661235d0a6c790c597b5d99b0ffc7"
SOURCE_REPOSITORY = "https://github.com/chainapsis/vizor-wallet.git"
BINARY_BASE = (
    "https://github.com/chainapsis/vizor-wallet-mobile-releases/"
    "releases/download/v%v"
)
ABI_CONFIG = (
    ("armeabi-v7a", 1000, "app-armeabi-v7a-release.apk", "Vizor-android-armeabi-v7a.apk"),
    ("arm64-v8a", 2000, "app-arm64-v8a-release.apk", "Vizor-android.apk"),
    ("x86_64", 4000, "app-x86_64-release.apk", "Vizor-android-x86_64.apk"),
)
REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parent.parent
FLUTTER_VERSION = json.loads(
    (REPOSITORY_ROOT / ".fvmrc").read_text(encoding="utf-8")
)["flutter"]
if re.fullmatch(r"\d+\.\d+\.\d+", FLUTTER_VERSION) is None:
    raise RuntimeError(".fvmrc must pin Flutter to an exact X.Y.Z version.")
RELEASE_RUST_TOOLCHAIN = (
    REPOSITORY_ROOT
    / "scripts"
    / "release-config"
    / "android-reproducible-rust-version.txt"
).read_text(encoding="utf-8").strip()
if re.fullmatch(r"\d+\.\d+\.\d+", RELEASE_RUST_TOOLCHAIN) is None:
    raise RuntimeError(
        "scripts/release-config/android-reproducible-rust-version.txt must "
        "contain an exact X.Y.Z version."
    )


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _load_release(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"Cannot read Direct Release metadata: {error}") from error
    _require(isinstance(value, dict), "Direct Release metadata must be a JSON object.")
    return value


def validate_release(metadata: dict[str, Any]) -> None:
    _require(metadata.get("schemaVersion") == 2, "Expected metadata schemaVersion 2.")
    _require(metadata.get("channel") == "direct", "Expected direct release channel.")
    _require(metadata.get("packageName") == PACKAGE_NAME, "Unexpected Android package name.")

    version = metadata.get("versionName")
    version_match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", str(version))
    _require(version_match is not None,
             "F-Droid metadata can only be generated from a stable X.Y.Z release.")
    _require(metadata.get("assetVersion") == version, "assetVersion must equal versionName.")
    _require(metadata.get("sourceTag") == f"mobile/v{version}", "Unexpected stable source tag.")
    source_sha = metadata.get("sourceSha")
    _require(isinstance(source_sha, str) and re.fullmatch(r"[0-9a-f]{40}", source_sha) is not None,
             "sourceSha must be a lowercase full Git commit SHA.")

    signing_sha = str(metadata.get("signingCertificateSha256", "")).lower()
    _require(signing_sha == SIGNING_SHA256, "Unexpected Direct signing certificate.")

    base = metadata.get("versionCodeBase")
    _require(isinstance(base, int) and base > 0, "versionCodeBase must be a positive integer.")
    assert version_match is not None
    major, minor, patch = (int(component) for component in version_match.groups())
    expected_base = major * 100_000_000 + minor * 1_000_000 + patch * 10_000 + 999
    _require(base == expected_base,
             f"versionCodeBase must be {expected_base} for version {version}.")
    artifacts = metadata.get("artifacts")
    _require(isinstance(artifacts, list) and len(artifacts) == 3,
             "Exactly three ABI artifacts are required.")
    by_abi = {item.get("abi"): item for item in artifacts if isinstance(item, dict)}
    _require(len(by_abi) == 3, "ABI artifacts must be unique objects.")
    for abi, offset, _, release_name in ABI_CONFIG:
        artifact = by_abi.get(abi)
        _require(artifact is not None, f"Missing {abi} artifact.")
        _require(artifact.get("file") == release_name, f"Unexpected {abi} filename.")
        _require(artifact.get("versionCode") == base + offset,
                 f"Unexpected {abi} versionCode.")
        _require(re.fullmatch(r"[0-9a-f]{64}", str(artifact.get("sha256", ""))) is not None,
                 f"Invalid {abi} SHA-256.")
    _require(metadata.get("primaryAbi") == "arm64-v8a", "arm64-v8a must be the primary ABI.")
    _require(metadata.get("versionCode") == base + 2000, "Primary versionCode must be arm64-v8a.")


def verify_source_ref(metadata: dict[str, Any], repository: pathlib.Path) -> None:
    tag = metadata["sourceTag"]
    expected = metadata["sourceSha"]
    result = subprocess.run(
        ["git", "rev-parse", f"refs/tags/{tag}^{{commit}}"],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
    )
    _require(result.returncode == 0, f"Source tag is not available locally: {tag}")
    actual = result.stdout.strip()
    _require(actual == expected, f"{tag} resolves to {actual}, expected {expected}.")


def render(metadata: dict[str, Any]) -> str:
    version = metadata["versionName"]
    base = metadata["versionCodeBase"]
    source_sha = metadata["sourceSha"]
    lines = [
        "AntiFeatures:",
        "  NonFreeNet:",
        "    en-US: Optional price, swap, and wallet-link features use third-party or Vizor-operated network services.",
        "Categories:",
        "  - Wallet",
        "License: Apache-2.0",
        "AuthorName: Chainapsis Inc.",
        "WebSite: https://vizor.cash",
        "SourceCode: https://github.com/chainapsis/vizor-wallet",
        "IssueTracker: https://github.com/chainapsis/vizor-wallet/issues",
        "Changelog: https://github.com/chainapsis/vizor-wallet-mobile-releases/releases",
        "",
        "AutoName: Vizor",
        "",
        "RepoType: git",
        f"Repo: {SOURCE_REPOSITORY}",
        "",
        "Builds:",
    ]
    for abi, offset, output_name, release_name in ABI_CONFIG:
        version_code = base + offset
        lines.extend([
            f"  - versionName: {version}",
            f"    versionCode: {version_code}",
            f"    commit: {source_sha}",
            f"    output: build/app/outputs/flutter-apk/{output_name}",
            f"    binary: {BINARY_BASE}/{release_name}",
            "    sudo:",
            '      - echo "deb https://deb.debian.org/debian bookworm main" > /etc/apt/sources.list.d/bookworm.list',
            "      - apt-get update",
            "      - apt-get install -y build-essential",
            "      - apt-get install -y -t bookworm openjdk-17-jdk-headless",
            "      - update-java-alternatives -s java-1.17.0-openjdk-amd64",
            "    srclibs:",
            f"      - flutter@{FLUTTER_VERSION}",
            "      - rustup@1.28.2",
            "    rm:",
            "      - ios",
            "      - linux",
            "      - macos",
            "      - windows",
            "    prebuild:",
            "      - git -C $$flutter$$ checkout -f db50e20168db8fee486b9abf32fc912de3bc5b6a",
            "      - export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64",
            "      - export PUB_CACHE=/tmp/vizor-android-reproducible/pub-cache",
            "      - export CARGO_HOME=/tmp/vizor-android-reproducible/cargo-home",
            "      - export GRADLE_USER_HOME=/tmp/vizor-android-reproducible/gradle-home",
            "      - install -d -m 700 /tmp/vizor-android-reproducible $PUB_CACHE $CARGO_HOME $GRADLE_USER_HOME",
            "      - $$flutter$$/bin/flutter config --no-analytics",
            "      - $$flutter$$/bin/flutter pub get --enforce-lockfile",
            f"      - $$rustup$$/rustup-init.sh -y --profile minimal --default-toolchain {RELEASE_RUST_TOOLCHAIN}",
            "        --target armv7-linux-androideabi --target aarch64-linux-android",
            "        --target x86_64-linux-android",
            "      - source $CARGO_HOME/env",
            "      - cargo fetch --locked --manifest-path rust/Cargo.toml",
            "    build:",
            "      - export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64",
            "      - export PUB_CACHE=/tmp/vizor-android-reproducible/pub-cache",
            "      - export CARGO_HOME=/tmp/vizor-android-reproducible/cargo-home",
            "      - export GRADLE_USER_HOME=/tmp/vizor-android-reproducible/gradle-home",
            "      - source $CARGO_HOME/env",
            f"      - FLUTTER_BIN=$$flutter$$/bin/flutter ./scripts/build-android-fdroid.sh --version $$VERSION$$ --expected-abi {abi}",
            "        --expected-version-code $$VERCODE$$",
            "    ndk: 28.2.13676358",
            "",
        ])
    lines.extend([
        f"AllowedAPKSigningKeys: {SIGNING_SHA256}",
        "",
        "AutoUpdateMode: Version mobile/v%v",
        "UpdateCheckMode: HTTP",
        "UpdateCheckData: https://github.com/chainapsis/vizor-wallet-mobile-releases/releases/latest/download/Vizor-android-metadata.json|\"versionCodeBase\":\\s*([0-9]+)|.|\"versionName\":\\s*\"([^\"]+)\"",
        "VercodeOperation:",
        "  - '%c + 1000'",
        "  - '%c + 2000'",
        "  - '%c + 4000'",
        f"CurrentVersion: {version}",
        f"CurrentVersionCode: {base + 4000}",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-metadata", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--source-repository", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--skip-source-ref-check", action="store_true")
    args = parser.parse_args()

    try:
        metadata = _load_release(args.release_metadata)
        validate_release(metadata)
        if not args.skip_source_ref_check:
            verify_source_ref(metadata, args.source_repository)
        rendered = render(metadata)
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if args.output is None:
        print(rendered, end="")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
