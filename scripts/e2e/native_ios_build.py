"""Build one actual Simulator cohort/helper before isolated wallet workers.

Only original build-process completion publishes the captured pair. This is
per-invocation build sharing, not a persistent artifact cache.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import threading
import time

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
from native_ios_cleanup import _inspect_app, capture_ios_cleanup_helper
from native_zakura_front import _capture


class NativeIosBuildError(runtime.RunnerError):
    """Original Simulator build, signature or input continuity failed."""


def build_native_ios_cohort(case, *, source_root, flutter, timeout=1800.0,
                           cancel_event=None):
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches or case.launched_process_count:
        raise NativeIosBuildError("iOS build requires a fresh dedicated original case")
    runtime._positive_timeout(timeout)
    root = Path(source_root)
    tool = Path(flutter).resolve(strict=True)
    architecture = platform.machine()
    if (not root.is_absolute() or root.resolve(strict=True) != root
        or not os.access(tool, os.X_OK) or architecture not in {"arm64", "x86_64"}):
        raise NativeIosBuildError("iOS source/Flutter/host architecture must be explicit and supported")
    cancel = cancel_event if cancel_event is not None else threading.Event()
    deadline = time.monotonic() + timeout

    def command(arguments, *, in_source=False):
        if cancel.is_set():
            raise runtime.Cancelled()
        if in_source:
            arguments = [sys.executable, "-c",
                "import os,sys; os.chdir(sys.argv[1]); os.execv(sys.argv[2],sys.argv[2:])",
                str(root), *arguments]
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NativeIosBuildError("original iOS build deadline expired", 124)
        result = case.run_command(arguments, env=os.environ.copy(), timeout=remaining,
            cancel_event=cancel, max_output_bytes=8*1024*1024)
        if result.returncode:
            raise NativeIosBuildError("original iOS build failed; retain logs", result.returncode)
        return result.lines

    try:
        members = "".join(command(["/usr/bin/git", "-C", str(root), "ls-files",
            "--cached", "--others", "--exclude-standard", "-z", "--", "lib",
            "integration_test", "rust", "rust_builder", "ios", "assets",
            "scripts/e2e/native-cleanup", "scripts/e2e/stamp-ios-runtime-profile.swift",
            "pubspec.yaml", "pubspec.lock"]))
        paths = [root/name for name in members.rstrip("\n\0").split("\0")
                 if name and name != "ios/Podfile.lock"]
        paths.extend([root/".dart_tool/package_config.json", tool])
        source = {path:_capture(path) for path in paths}
        # Configure Flutter once, then build a thin, signed Simulator app into
        # this original producer's private derived-data directory.
        command([str(tool), "build", "ios", "--simulator", "--debug", "--no-pub", "--config-only",
            "--target", "integration_test/regtest_mobile_cohort_test.dart",
            "--dart-define=VIZOR_FORM_FACTOR=mobile",
            "--dart-define=ZCASH_DEFAULT_NETWORK=regtest",
            "--dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=1",
            "--dart-define=VIZOR_E2E_IOS_COHORT=true",
            "--dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true",
            "--dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true"], in_source=True)
        derived = case.workspace.root/"ios-build"
        command(["/usr/bin/xcodebuild", "-workspace", str(root/"ios/Runner.xcworkspace"),
            "-scheme", "Runner", "-configuration", "Debug", "-sdk", "iphonesimulator",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(derived),
            "ARCHS="+architecture, "ONLY_ACTIVE_ARCH=YES", "ENABLE_DEBUG_DYLIB=NO", "build"], in_source=True)
        app = derived/"Build/Products/Debug-iphonesimulator/Runner.app"
        cohort = _inspect_app(app, helper=False)
        helper_derived = case.workspace.root/"ios-helper-build"
        command(["/usr/bin/xcodebuild", "-project",
            str(root/"scripts/e2e/native-cleanup/SimulatorHelper/NativeCleanup.xcodeproj"),
            "-scheme", "VizorIosCleanup", "-configuration", "Debug", "-sdk", "iphonesimulator",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(helper_derived),
            "DEVELOPMENT_TEAM="+cohort.application_identifier[:10],
            "ARCHS="+architecture, "build"])
        helper_app = helper_derived/"Build/Products/Debug-iphonesimulator/VizorIosCleanup.app"
        captured = capture_ios_cleanup_helper(helper_app, cohort_app=app)
        observed = {path:_capture(path) for path in source}
        project = root/"ios/Runner.xcodeproj/project.pbxproj"
        changed = [str(path.relative_to(root)) if path.is_relative_to(root) else str(path)
            for path in source if (observed[path][1] != source[path][1]
                if path == project else observed[path] != source[path])]
        if changed:
            raise NativeIosBuildError("iOS build source/tool changed: " + ", ".join(changed[:8]))
        receipt = case.close()
        captured.verify_unchanged()
        return captured, {"ios_app_build_count":1, "ios_helper_build_count":1,
            "architecture":captured.architecture, "team":captured.team,
            "joined_build_processes":case.launched_process_count, "exit_codes":receipt.exit_codes,
            "checked_source_files_sha256":hashlib.sha256(json.dumps({
                str(path.relative_to(root)) if path.is_relative_to(root) else str(path):record[1]
                for path,record in source.items()}, sort_keys=True).encode()).hexdigest(),
            "persistent_cache_attestation":False, "wallet_or_catalog_pass":False}
    except BaseException as primary:
        try:
            case.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
