#!/usr/bin/env python3
"""Run shared Apple Ledger handler tests without launching the wallet app.

Uses the FVM Flutter framework and the project's pinned Ledger BLE revision.
The temporary Swift package imports real Flutter/BLE modules; only devices are
faked by LedgerMobileHandlerTests. It does not access wallet storage.
"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
pins = json.loads((root / 'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins']
ledger = next(pin for pin in pins if pin['identity'] == 'hw-transport-ios-ble')
with tempfile.TemporaryDirectory(prefix='vizor-ledger-native-') as directory:
    package = Path(directory)
    probe = package / 'sdk.dart'
    probe.write_text("import 'dart:io'; void main() { print(Platform.resolvedExecutable); }")
    dart = Path(subprocess.check_output(['fvm', 'dart', str(probe)], cwd=root, text=True).strip().splitlines()[-1])
    framework = dart.parents[2] / 'artifacts/engine/darwin-x64/FlutterMacOS.xcframework'
    if not framework.exists():
        raise SystemExit('Run fvm flutter precache --macos first.')
    (package / 'Sources/Runner').mkdir(parents=True)
    (package / 'Tests/RunnerTests').mkdir(parents=True)
    shutil.copy(root / 'ios/Runner/LedgerMobileHandler.swift', package / 'Sources/Runner')
    shutil.copy(root / 'ios/RunnerTests/LedgerMobileHandlerTests.swift', package / 'Tests/RunnerTests')
    (package / 'FlutterMacOS.xcframework').symlink_to(framework.resolve())
    (package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LedgerNativeTests", platforms: [.macOS(.v13)], dependencies: [
  .package(url: %s, revision: %s)
], targets: [
  .binaryTarget(name: "FlutterMacOS", path: "FlutterMacOS.xcframework"),
  .target(name: "Runner", dependencies: ["FlutterMacOS", .product(name: "BleTransport", package: "hw-transport-ios-ble")]),
  .testTarget(name: "RunnerTests", dependencies: ["Runner", "FlutterMacOS", .product(name: "BleTransport", package: "hw-transport-ios-ble")])
])
''' % (json.dumps(ledger['location']), json.dumps(ledger['state']['revision'])))
    subprocess.run(['swift', 'test', '--package-path', str(package)], check=True)
