"""Build one trusted macOS cohort/helper for in-process reuse in a selected run.

This is not a persistent cache loader. The caller supplies a fresh dedicated
original case, keeps the produced signing capture, and never shares app storage.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys
import threading
import time

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
from native_mac_cleanup import _inspect_signed_app, capture_mac_cleanup_helper
from native_zakura_front import _capture


class NativeMacosBuildError(runtime.RunnerError):
    """Trusted build/signing or original build writer completion failed."""


def build_native_macos_cohort(case, *, source_root, flutter, timeout=1200.0, cancel_event=None):
    """Build exactly once before workers, retaining all compiler/artifact evidence."""
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches or case.launched_process_count:
        raise NativeMacosBuildError("native build requires a fresh dedicated original case")
    runtime._positive_timeout(timeout)
    root = Path(source_root)
    tool = Path(flutter).resolve(strict=True)
    if not root.is_absolute() or root.resolve(strict=True) != root or not os.access(tool, os.X_OK):
        raise NativeMacosBuildError("native source/Flutter must be explicit and canonical")
    cancel = cancel_event if cancel_event is not None else threading.Event()
    deadline = time.monotonic() + timeout

    def command(arguments, *, in_source=False):
        if cancel.is_set():
            raise runtime.Cancelled()
        if in_source:
            arguments = [sys.executable,"-c",
                "import os,sys; os.chdir(sys.argv[1]); os.execv(sys.argv[2],sys.argv[2:])",
                str(root), *arguments]
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NativeMacosBuildError("original native build deadline expired", 124)
        result = case.run_command(arguments, env=os.environ.copy(), timeout=remaining,
            cancel_event=cancel, max_output_bytes=8*1024*1024)
        if result.returncode:
            raise NativeMacosBuildError("owned native build/signing failed; retain original logs", result.returncode)
        return result.lines

    try:
        # Git excludes generated build trees while including current untracked
        # sources. This is checked-source continuity, not hermetic provenance.
        members = "".join(command(["/usr/bin/git", "-C", str(root), "ls-files",
            "--cached", "--others", "--exclude-standard", "-z", "--", "lib",
            "integration_test", "rust", "rust_builder", "macos", "assets",
            "scripts/e2e/native-cleanup", "pubspec.yaml", "pubspec.lock"]))
        paths = [root / name for name in members.rstrip("\n\0").split("\0")
                 if name and name != "macos/Podfile.lock"]
        paths.extend([root/".dart_tool/package_config.json", tool])
        source = {path:_capture(path) for path in paths}
        command([str(tool),"build","macos","--debug","--no-pub",
            "--target","integration_test/regtest_desktop_cohort_test.dart",
            "--dart-define=ZCASH_DEFAULT_NETWORK=regtest",
            "--dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=1",
            "--dart-define=VIZOR_E2E_MACOS_COHORT=true",
            "--dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true",
            "--dart-define=VIZOR_E2E_HIDDEN_WINDOW=true"],in_source=True)
        app = root/"build/macos/Build/Products/Debug/Vizor.app"
        cohort = _inspect_signed_app(app)
        metadata = command(["/usr/bin/codesign","--display","--verbose=4",str(app)])
        authorities = [line.strip().removeprefix("Authority=") for line in metadata if line.startswith("Authority=")]
        if not authorities:
            raise NativeMacosBuildError("actual cohort has no signing authority")
        target = case.workspace.root/"swift-target"
        command(["/usr/bin/xcrun","swift","build","--package-path",str(root/"scripts/e2e/native-cleanup"),
            "--scratch-path",str(target),"--product","vizor-native-cleanup","-c","debug","-j","2"])
        helper = case.workspace.root/"Helper.app"
        (helper/"Contents/MacOS").mkdir(parents=True,mode=0o700)
        shutil.copy2(target/"debug/vizor-native-cleanup",helper/"Contents/MacOS/vizor-native-cleanup")
        shutil.copy2(app/"Contents/embedded.provisionprofile",helper/"Contents/embedded.provisionprofile")
        with (helper/"Contents/Info.plist").open("xb") as output:
            plistlib.dump({"CFBundleExecutable":"vizor-native-cleanup","CFBundleIdentifier":"com.keplr.vizor",
                "CFBundleName":"Vizor owned cleanup","CFBundlePackageType":"APPL","CFBundleVersion":"1",
                "LSBackgroundOnly":True},output)
        entitlements = case.workspace.root/"helper-entitlements.plist"
        with entitlements.open("xb") as output:
            plistlib.dump({"com.apple.security.app-sandbox":True,"com.apple.application-identifier":cohort.team+".com.keplr.vizor",
                "com.apple.developer.team-identifier":cohort.team},output)
        command(["/usr/bin/codesign","--force","--sign",authorities[0],"--entitlements",str(entitlements),
            "--timestamp=none",str(helper)])
        captured = capture_mac_cleanup_helper(helper,cohort_app=app)
        observed = {path:_capture(path) for path in source}
        changed = [str(path.relative_to(root)) if path.is_relative_to(root) else str(path)
                   for path in source if observed[path] != source[path]]
        if changed:
            raise NativeMacosBuildError("native source/tool changed while its build ran: " + ", ".join(changed[:8]))
        receipt = case.close()
        captured.verify_unchanged()
        proof = {"app_build_count":1,"helper_build_count":1,"team":captured.team,
            "joined_build_processes":case.launched_process_count,"exit_codes":receipt.exit_codes,
            "checked_source_files_sha256":hashlib.sha256(json.dumps({str(path.relative_to(root)) if path.is_relative_to(root)
                else str(path):record[1] for path,record in source.items()},sort_keys=True).encode()).hexdigest(),
            "persistent_cache_attestation":False,"wallet_or_catalog_pass":False}
        return captured, proof
    except BaseException as primary:
        try:
            case.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
