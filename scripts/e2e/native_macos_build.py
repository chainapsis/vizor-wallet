"""Build one trusted macOS cohort/helper for in-process reuse in a selected run.

The caller supplies a fresh original case and keeps the signing capture. An
immutable cache hit creates private copies, never shared app storage.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import platform
import shutil
import sys
import threading
import time

import e2e_runtime as runtime
from native_case_lifecycle import NativeCaseLifecycle
from native_mac_cleanup import _inspect_signed_app, capture_mac_cleanup_helper
from native_zakura_front import _capture
import native_build_cache as cache


class NativeMacosBuildError(runtime.RunnerError):
    """Trusted build/signing or original build writer completion failed."""


def build_native_macos_cohort(case, *, source_root, flutter, timeout=1200.0, cancel_event=None,
                            tex_address=None, cache_root=None):
    """Build exactly once before workers, retaining all compiler/artifact evidence."""
    if not isinstance(case, NativeCaseLifecycle) or not case.accepting_launches or case.launched_process_count:
        raise NativeMacosBuildError("native build requires a fresh dedicated original case")
    runtime._positive_timeout(timeout)
    root = Path(source_root)
    tool = Path(flutter).resolve(strict=True)
    if not root.is_absolute() or root.resolve(strict=True) != root or not os.access(tool, os.X_OK):
        raise NativeMacosBuildError("native source/Flutter must be explicit and canonical")
    cancel = cancel_event if cancel_event is not None else threading.Event()
    if tex_address is not None and (not isinstance(tex_address, str)
        or not tex_address.startswith("texregtest1") or not 20 <= len(tex_address) <= 100
        or not tex_address.isascii() or not tex_address.isalnum()):
        raise NativeMacosBuildError("TEX fixture must be a derived regtest address")
    deadline = time.monotonic() + timeout
    environment = os.environ.copy()
    environment.pop("_", None)
    lease = None

    def command(arguments, *, in_source=False):
        if cancel.is_set():
            raise runtime.Cancelled()
        if in_source:
            arguments = [sys.executable,"-c",
                "import os,sys; os.chdir(sys.argv[1]); os.execvp(sys.argv[2],sys.argv[2:])",
                str(root), *arguments]
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise NativeMacosBuildError("original native build deadline expired", 124)
        result = case.run_command(arguments, env=environment, timeout=remaining,
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
            "scripts/e2e/native-cleanup", "third_party", "pubspec.yaml", "pubspec.lock", ".fvmrc"]))
        paths = [root / name for name in members.rstrip("\n\0").split("\0")
                 if name and name != "macos/Podfile.lock"]
        paths.extend([root/".dart_tool/package_config.json", tool])
        if cache_root is not None:
            paths.extend([Path(__file__).resolve(strict=True), Path(cache.__file__).resolve(strict=True)])
        source = {path:_capture(path) for path in paths}
        build_arguments = [str(tool),"build","macos","--debug","--no-pub",
            "--target","integration_test/regtest_desktop_cohort_test.dart",
            "--dart-define=ZCASH_DEFAULT_NETWORK=regtest",
            "--dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT=1",
            "--dart-define=VIZOR_E2E_MACOS_COHORT=true",
            "--dart-define=VIZOR_PAYMENT_LINK_REGTEST_ENABLED=true",
            "--dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true",
            *(["--dart-define=ZCASH_E2E_TEX_ADDRESS="+tex_address] if tex_address is not None else []),
            "--dart-define=VIZOR_E2E_HIDDEN_WINDOW=true"]
        inputs = None
        def current_inputs():
            return cache.collect_native_cache_inputs(root, {path:_capture(path) for path in source}, tool,
                platform="macos", architecture=platform.machine(), command=command,
                environment=environment, cancel=cancel, tex_address=tex_address)
        if cache_root is not None:
            command([*build_arguments, "--config-only"], in_source=True)
            if not (root/"macos/Pods").is_dir():
                raise NativeMacosBuildError("prepared macOS Pod sandbox is missing")
            cache.prepare_native_rust_targets(root, platform="macos", architecture=platform.machine(),
                environment=environment, command=command)
            changed = cache.native_source_changes(root, source, "macos")
            if changed:
                raise NativeMacosBuildError("native preparation changed source/tool: " + ", ".join(changed[:8]))
            inputs = current_inputs()
            lease = cache.NativeCohortCacheLease(cache_root, inputs,
                timeout=max(0.001, deadline-time.monotonic()), cancel_event=cancel)
            lease.__enter__()
            cached = lease.load()
            if cached is not None:
                copies = lease.materialize(case, cached)
                captured = capture_mac_cleanup_helper(copies["helper"], cohort_app=copies["cohort"])
                if current_inputs() != inputs:
                    raise NativeMacosBuildError("native inputs changed during cache publication")
                receipt = case.close()
                captured.verify_unchanged()
                return captured, {"app_build_count":0, "helper_build_count":0,
                    "cache_hit":True, "cache_key":lease.key, "team":captured.team,
                    "joined_build_processes":case.launched_process_count, "exit_codes":receipt.exit_codes,
                    "persistent_cache_attestation":True, "wallet_or_catalog_pass":False}
        command(build_arguments,in_source=True)
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
        # CocoaPods rewrites the project even when its bytes are unchanged.
        # Still reject changed project contents; other inputs retain strict
        # identity and byte continuity, including the executable Flutter tool.
        changed = cache.native_source_changes(root, source, "macos")
        if changed:
            raise NativeMacosBuildError("native source/tool changed while its build ran: " + ", ".join(changed[:8]))
        if inputs is not None and current_inputs() != inputs:
            raise NativeMacosBuildError("native cache inputs changed during original build")
        receipt = case.close()
        captured.verify_unchanged()
        if lease is not None:
            lease.publish(cache.ProducedNativeCohort(case, captured, inputs, cache._TOKEN))
        proof = {"app_build_count":1,"helper_build_count":1,"team":captured.team,
            "cache_hit":False, "cache_key":lease.key if lease is not None else None,
            "joined_build_processes":case.launched_process_count,"exit_codes":receipt.exit_codes,
            "checked_source_files_sha256":hashlib.sha256(json.dumps({str(path.relative_to(root)) if path.is_relative_to(root)
                else str(path):record[1] for path,record in source.items()},sort_keys=True).encode()).hexdigest(),
            "persistent_cache_attestation":lease is not None,"wallet_or_catalog_pass":False}
        return captured, proof
    except BaseException as primary:
        try:
            case.close()
        except BaseException as cleanup:
            raise primary from cleanup
        raise
    finally:
        if lease is not None:
            lease.__exit__()
