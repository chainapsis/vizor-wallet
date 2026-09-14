#!/usr/bin/env python3
"""Build an isolated app and deliver cold/warm payment URLs through macOS.

Run from any directory: python3 scripts/e2e/flutter-macos-cross-chain-payment-request.py
No regtest node, funded wallet, default URL-handler changes, or payment is needed.
"""

import http.server
import json
import os
from pathlib import Path
import plistlib
import secrets
import signal
import subprocess
import threading


ROOT = Path(__file__).resolve().parents[2]
COLD_URI = (
    "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh?amount=0.00123456"
)
WARM_URI = (
    "ethereum:0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913@8453/transfer"
    "?address=0x52908400098527886E0F7030069857D2E4169EE7&uint256=25000000"
)


def main():
    run_id = secrets.token_hex(6)
    bundle_id = f"com.keplr.vizor.payment-e2e.r{run_id}"
    product = f"Vizor Payment E2E {run_id}"
    artifacts = ROOT / "build" / "payment-request-native-e2e" / run_id
    artifacts.mkdir(parents=True)
    app = ROOT / "build/macos/Build/Products/Debug" / f"{product}.app"
    results = {"bundle_id": bundle_id, "cold_uri": COLD_URI, "milestones": []}
    done = threading.Event()
    app_pid = None

    def open_uri(uri, *, cold=False):
        # Explicit app targeting leaves the user's default handler untouched.
        args = ["/usr/bin/open", "-g"]
        if cold:
            app_log = artifacts / "app.log"
            app_log.touch()
            args.extend(["-n", "--stdout", str(app_log), "--stderr", str(app_log)])
        subprocess.run([*args, "-a", str(app), uri], check=True, timeout=15)

    class Driver(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            nonlocal app_pid
            if not self.path.startswith(f"/{run_id}/"):
                self.send_error(404)
                return
            action = self.path.rsplit("/", 1)[1]
            try:
                data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if action == "ready":
                    app_pid = int(data["pid"])
                    results["pid"] = app_pid
                    print(f"Native test started (PID {app_pid})", flush=True)
                elif action == "open" and data.get("uri") == WARM_URI:
                    open_uri(WARM_URI)
                elif action == "milestone":
                    results["milestones"].append(data["name"])
                    print(data["name"], flush=True)
                elif action == "result":
                    results.update(data)
                    (artifacts / "result.json").write_text(json.dumps(results, indent=2) + "\n")
                    done.set()
                else:
                    raise ValueError("Unexpected driver request")
                self.send_response(200)
                self.end_headers()
            except Exception as error:
                results["driver_error"] = str(error)
                print(f"Driver failure: {error}", flush=True)
                self.send_error(500, str(error))
                done.set()

        def log_message(self, *_args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Driver)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    driver_url = f"http://127.0.0.1:{server.server_port}/{run_id}"
    flavor = ROOT / "macos/Runner/Configs/FlavorOverrides.xcconfig"
    previous_flavor = flavor.read_bytes() if flavor.exists() else None
    entitlements = plistlib.loads((ROOT / "macos/Runner/DebugProfile.entitlements").read_bytes())
    # This isolated test app can report to the loopback driver and is never
    # shipped. Ad-hoc signing avoids machine-specific provisioning profiles.
    entitlements["com.apple.security.app-sandbox"] = False
    entitlements.pop("com.apple.application-identifier", None)
    entitlements.pop("com.apple.developer.team-identifier", None)
    entitlements.pop("com.apple.security.temporary-exception.mach-lookup.global-name", None)
    entitlement_path = artifacts / "PaymentE2E.entitlements"
    entitlement_path.write_bytes(plistlib.dumps(entitlements))
    own_flavor = (
        f"PRODUCT_NAME = {product}\n"
        f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id}\n"
    ).encode()

    try:
        flavor.write_bytes(own_flavor)
        print(f"Building {bundle_id}; artifacts: {artifacts}", flush=True)
        with (artifacts / "build.log").open("w") as log:
            subprocess.run(
                [
                    "fvm", "flutter", "build", "macos", "--debug",
                    "--target=integration_test/cross_chain_payment_request_native_app.dart",
                    "--dart-define=VIZOR_E2E_HIDDEN_WINDOW=true",
                    "--dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false",
                    f"--dart-define=VIZOR_PAYMENT_E2E_DRIVER_URL={driver_url}",
                    f"--dart-define=VIZOR_PAYMENT_E2E_BUNDLE_ID={bundle_id}",
                ], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                env={**os.environ, "FLUTTER_XCODE_CODE_SIGNING_ALLOWED": "NO"},
                check=True, timeout=1200,
            )
        subprocess.run([
            "/usr/bin/codesign", "--force", "--deep", "--sign", "-",
            "--entitlements", str(entitlement_path), str(app),
        ], check=True, timeout=60)
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != bundle_id:
            raise RuntimeError("Refusing to launch a non-isolated app")
        schemes = {
            scheme for entry in info.get("CFBundleURLTypes", [])
            for scheme in entry.get("CFBundleURLSchemes", [])
        }
        if not {"bitcoin", "ethereum"} <= schemes:
            raise RuntimeError("Packaged app is missing payment URL registrations")
        print("Cold-launching the isolated app with a Bitcoin URL", flush=True)
        open_uri(COLD_URI, cold=True)
        if not done.wait(300):
            raise TimeoutError("Native test did not report completion within five minutes")
        if not results.get("passed"):
            raise RuntimeError(f"Native E2E failed; see {artifacts / 'result.json'}")
        print(f"PASS: {artifacts / 'result.json'}", flush=True)
    finally:
        # The test normally exits itself. Terminate only this runner's exact
        # executable if a failed/timed-out test leaves its process alive.
        for line in subprocess.check_output(["ps", "-axo", "pid=,command="], text=True).splitlines():
            process_id, command = line.strip().split(None, 1)
            if command.startswith(str(app / "Contents/MacOS") + "/"):
                try:
                    os.kill(int(process_id), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        server.shutdown()
        server.server_close()
        if flavor.exists() and flavor.read_bytes() == own_flavor:
            if previous_flavor is None:
                flavor.unlink()
            else:
                flavor.write_bytes(previous_flavor)
        if app.exists():
            subprocess.run([
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                "-u", str(app),
            ], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if not (artifacts / "result.json").exists():
            (artifacts / "result.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
