#!/usr/bin/env bash
# Run the production Swift outbox/gate/store with injected transport on macOS.
# No simulator, wallet DB, Keychain reads, or network access is needed.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/vizor-outbox-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
cat > "$test_dir/TransportStub.swift" <<'SWIFT'
import Foundation
final class BackgroundMigrationCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
enum NativeLightwalletdError: Error, Equatable { case cancelled, timedOut }
struct NativeLightwalletdSendResponse { let errorCode: Int32; let errorMessage: String }
enum NativeLightwalletdClient {
  static func latestBlockHeight(endpoint: String, cancellation: BackgroundMigrationCancellation) -> Result<UInt64, NativeLightwalletdError> { fatalError("Inject transport in tests") }
  static func sendTransaction(endpoint: String, rawTransaction: Data, cancellation: BackgroundMigrationCancellation) -> Result<NativeLightwalletdSendResponse, NativeLightwalletdError> { fatalError("Inject transport in tests") }
}
SWIFT
cat > "$test_dir/main.swift" <<'SWIFT'
import XCTest
import Darwin
let suite = BackgroundMigrationOutboxExecutionGateTests.defaultTestSuite
suite.run()
exit(suite.testRun?.hasSucceeded == true && suite.testCaseCount == 6 ? 0 : 1)
SWIFT
test_frameworks="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
test_libraries="$(xcrun --show-sdk-platform-path)/Developer/usr/lib"
test_private_frameworks="$(xcrun --show-sdk-platform-path)/Developer/Library/PrivateFrameworks"
xcrun swiftc -swift-version 5 -Xlinker -rpath -Xlinker "$test_private_frameworks" -I "$test_libraries" -L "$test_libraries" -Xlinker -rpath -Xlinker "$test_libraries" -F "$test_frameworks" -Xlinker -rpath -Xlinker "$test_frameworks" \
  ios/Runner/BackgroundMigrationOutboxExecutionGate.swift \
  ios/Runner/BackgroundMigrationOutbox.swift \
  ios/Runner/BackgroundMigrationOutboxStore.swift \
  ios/Runner/BackgroundMigrationOutboxRunner.swift \
  "$test_dir/TransportStub.swift" \
  ios/RunnerTests/BackgroundMigrationOutboxExecutionGateTests.swift \
  "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests"
