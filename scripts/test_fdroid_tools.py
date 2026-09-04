#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parent.parent
GENERATOR_PATH = ROOT / "scripts" / "generate-fdroid-metadata.py"
RUST_WRAPPER_PATH = ROOT / "scripts" / "run-with-android-reproducible-rust.sh"
REPRODUCIBLE_BUILD_PATH = ROOT / "scripts" / "build-android-reproducible.sh"
SPEC = importlib.util.spec_from_file_location("generate_fdroid_metadata", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


def release_metadata() -> dict:
    base = 350999
    return {
        "schemaVersion": 2,
        "channel": "direct",
        "packageName": "com.keplr.vizor",
        "versionName": "0.0.35",
        "assetVersion": "0.0.35",
        "versionCodeBase": base,
        "versionCode": base + 2000,
        "sourceTag": "mobile/v0.0.35",
        "sourceSha": "a" * 40,
        "signingCertificateSha256": GENERATOR.SIGNING_SHA256.upper(),
        "primaryAbi": "arm64-v8a",
        "artifacts": [
            {
                "file": "Vizor-android.apk",
                "abi": "arm64-v8a",
                "versionCode": base + 2000,
                "sha256": "1" * 64,
                "primary": True,
            },
            {
                "file": "Vizor-android-armeabi-v7a.apk",
                "abi": "armeabi-v7a",
                "versionCode": base + 1000,
                "sha256": "2" * 64,
                "primary": False,
            },
            {
                "file": "Vizor-android-x86_64.apk",
                "abi": "x86_64",
                "versionCode": base + 4000,
                "sha256": "3" * 64,
                "primary": False,
            },
        ],
    }


class FdroidMetadataTest(unittest.TestCase):
    def test_renders_three_reproducible_builds(self) -> None:
        metadata = release_metadata()
        GENERATOR.validate_release(metadata)
        rendered = GENERATOR.render(metadata)

        self.assertEqual(rendered.count("  - versionName: 0.0.35"), 3)
        for code in (351999, 352999, 354999):
            self.assertIn(f"    versionCode: {code}", rendered)
        for filename in (
            "Vizor-android-armeabi-v7a.apk",
            "Vizor-android.apk",
            "Vizor-android-x86_64.apk",
        ):
            self.assertIn(f"/{filename}", rendered)
        self.assertIn(f"AllowedAPKSigningKeys: {GENERATOR.SIGNING_SHA256}", rendered)
        self.assertIn("AutoUpdateMode: Version mobile/v%v", rendered)
        self.assertIn(
            "git -C $$flutter$$ checkout -f "
            "db50e20168db8fee486b9abf32fc912de3bc5b6a",
            rendered,
        )
        self.assertEqual(
            rendered.count("cargo fetch --locked --manifest-path rust/Cargo.toml"),
            3,
        )
        self.assertEqual(
            rendered.count(
                f"--default-toolchain {GENERATOR.RELEASE_RUST_TOOLCHAIN}"
            ),
            3,
        )
        self.assertEqual(rendered.count(f"flutter@{GENERATOR.FLUTTER_VERSION}"), 3)
        self.assertNotIn("flutter@stable", rendered)
        self.assertEqual(
            rendered.count(
                'echo "deb https://deb.debian.org/debian bookworm main" > '
                "/etc/apt/sources.list.d/bookworm.list"
            ),
            3,
        )
        self.assertEqual(
            rendered.count(
                "apt-get install -y -t bookworm build-essential openjdk-17-jdk-headless"
            ),
            3,
        )
        self.assertEqual(
            rendered.count(
                "update-java-alternatives -s java-1.17.0-openjdk-amd64"
            ),
            3,
        )
        self.assertEqual(
            rendered.count("export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64"),
            6,
        )
        self.assertEqual(
            rendered.count(
                "export PUB_CACHE=/tmp/vizor-android-reproducible/pub-cache"
            ),
            6,
        )
        self.assertEqual(
            rendered.count(
                "export CARGO_HOME=/tmp/vizor-android-reproducible/cargo-home"
            ),
            6,
        )

    def test_rejects_unexpected_signing_key(self) -> None:
        metadata = release_metadata()
        metadata["signingCertificateSha256"] = "f" * 64
        with self.assertRaisesRegex(ValueError, "signing certificate"):
            GENERATOR.validate_release(metadata)

    def test_rejects_version_code_base_unrelated_to_version(self) -> None:
        metadata = release_metadata()
        metadata["versionCodeBase"] = 360999
        for artifact in metadata["artifacts"]:
            offset = {"armeabi-v7a": 1000, "arm64-v8a": 2000, "x86_64": 4000}[
                artifact["abi"]
            ]
            artifact["versionCode"] = metadata["versionCodeBase"] + offset
        metadata["versionCode"] = metadata["versionCodeBase"] + 2000

        with self.assertRaisesRegex(ValueError, "versionCodeBase must be 350999"):
            GENERATOR.validate_release(metadata)

    def test_cli_writes_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            temp = pathlib.Path(directory)
            source = temp / "release.json"
            output = temp / "com.keplr.vizor.yml"
            source.write_text(json.dumps(release_metadata()), encoding="utf-8")
            subprocess.run(
                [
                    "python3",
                    str(GENERATOR_PATH),
                    "--release-metadata",
                    str(source),
                    "--output",
                    str(output),
                    "--skip-source-ref-check",
                ],
                check=True,
                cwd=ROOT,
            )
            self.assertIn("CurrentVersion: 0.0.35", output.read_text(encoding="utf-8"))


class FdroidBuildScriptTest(unittest.TestCase):
    def test_dry_run_matches_stable_version_code_contract(self) -> None:
        result = subprocess.run(
            [
                str(ROOT / "scripts" / "build-android-fdroid.sh"),
                "--version",
                "0.0.35",
                "--expected-abi",
                "arm64-v8a",
                "--expected-version-code",
                "352999",
                "--dry-run",
            ],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        command_output = result.stdout.replace("\\", "")
        self.assertIn("baseVersionCode=350999", command_output)
        self.assertIn("rust=1.98.0", command_output)
        self.assertIn("--target-platform android-arm64,android-arm,android-x64", command_output)
        self.assertIn("--dart-define=VIZOR_FORM_FACTOR=mobile", command_output)
        self.assertIn(
            "--dart-define=VIZOR_COINGECKO_PRICE_BASE_URL=https://functions.vizor.cash/api/v3",
            command_output,
        )
        self.assertIn(
            "--dart-define=VIZOR_WALLET_LINK_BACKEND_URL=https://functions.vizor.cash",
            command_output,
        )
        self.assertIn(
            "Canonical source: /tmp/vizor-android-reproducible/source",
            command_output,
        )
        self.assertIn("signing=unsigned", command_output)
        self.assertIn("offline=true", command_output)

    def test_dry_run_rejects_wrong_abi_version_code(self) -> None:
        result = subprocess.run(
            [
                str(ROOT / "scripts" / "build-android-fdroid.sh"),
                "--version",
                "0.0.35",
                "--expected-abi",
                "x86_64",
                "--expected-version-code",
                "352999",
                "--dry-run",
            ],
            check=False,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Version code mismatch", result.stderr)


class AndroidReproducibleBuildScriptTest(unittest.TestCase):
    def test_dry_run_centralizes_release_inputs(self) -> None:
        result = subprocess.run(
            [
                str(REPRODUCIBLE_BUILD_PATH),
                "--build-name",
                "0.0.35",
                "--build-number",
                "350999",
                "--release-version",
                "0.0.35-internal.2",
                "--signing",
                "required",
                "--dry-run",
            ],
            check=True,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        command_output = result.stdout.replace("\\", "")
        self.assertIn("signing=required", command_output)
        self.assertIn("offline=false", command_output)
        self.assertIn("--build-name 0.0.35", command_output)
        self.assertIn("--build-number 350999", command_output)
        self.assertIn(
            "--dart-define=VIZOR_RELEASE_VERSION=0.0.35-internal.2",
            command_output,
        )
        self.assertIn(
            "--dart-define=VIZOR_COINGECKO_PRICE_BASE_URL=https://functions.vizor.cash/api/v3",
            command_output,
        )

    def test_rejects_relative_flutter_binary(self) -> None:
        environment = os.environ.copy()
        environment["FLUTTER_BIN"] = "flutter"
        result = subprocess.run(
            [
                str(REPRODUCIBLE_BUILD_PATH),
                "--build-name",
                "0.0.35",
                "--build-number",
                "350999",
                "--release-version",
                "0.0.35",
                "--signing",
                "unsigned",
                "--dry-run",
            ],
            check=False,
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("FLUTTER_BIN must be an absolute path", result.stderr)

class AndroidReproducibleRustWrapperTest(unittest.TestCase):
    def _run_with_fake_rustup(self, *, installed: bool) -> tuple[subprocess.CompletedProcess, pathlib.Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        temp = pathlib.Path(temporary.name)
        install_log = temp / "install.log"
        installed_output = "1.98.0-test-host (default)" if installed else "stable-test-host (default)"
        fake_rustup = temp / "rustup"
        fake_rustup.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "case \"${1:-} ${2:-}\" in\n"
            f"  'toolchain list') printf '%s\\n' '{installed_output}' ;;\n"
            f"  'toolchain install') printf '%s\\n' \"$*\" > '{install_log}' ;;\n"
            "  'run 1.98.0') printf '%s\\n' 'rustc 1.98.0 (test)' ;;\n"
            "  *) exit 64 ;;\n"
            "esac\n",
            encoding="utf-8",
        )
        fake_rustup.chmod(0o755)
        environment = os.environ.copy()
        environment["PATH"] = f"{temp}{os.pathsep}{environment['PATH']}"
        result = subprocess.run(
            [
                str(RUST_WRAPPER_PATH),
                sys.executable,
                "-c",
                "import os; print(os.environ['VIZOR_RUST_TOOLCHAIN'])",
            ],
            check=True,
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        return result, install_log

    def test_reuses_installed_toolchain_without_installing(self) -> None:
        result, install_log = self._run_with_fake_rustup(installed=True)

        self.assertEqual(result.stdout.strip(), "1.98.0")
        self.assertFalse(install_log.exists())

    def test_installs_missing_toolchain_before_running_command(self) -> None:
        result, install_log = self._run_with_fake_rustup(installed=False)

        self.assertEqual(result.stdout.strip(), "1.98.0")
        self.assertEqual(
            install_log.read_text(encoding="utf-8").strip(),
            "toolchain install 1.98.0 --profile minimal",
        )


if __name__ == "__main__":
    unittest.main()
