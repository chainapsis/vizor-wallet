import Foundation
import XCTest
#if canImport(Runner)
@testable import Runner
#endif

final class BackgroundMigrationOutboxExecutionGateTests: XCTestCase {
  func testIdlePauseBlocksAdmissionUntilResume() {
    let gate = BackgroundMigrationOutboxExecutionGate()
    gate.pause(leaseId: "a")
    gate.waitUntilIdle()
    XCTAssertFalse(gate.tryBeginRun())
    XCTAssertTrue(gate.resume(leaseId: "a"))
    XCTAssertTrue(gate.tryBeginRun())
    gate.finishRun()
  }

  func testOverlappingAndRepeatedLeasesCannotResumeAnotherMutation() {
    let gate = BackgroundMigrationOutboxExecutionGate()
    gate.pause(leaseId: "a")
    gate.pause(leaseId: "a") // lost quiesce response, same retry
    gate.pause(leaseId: "b")
    XCTAssertFalse(gate.resume(leaseId: "a"))
    XCTAssertFalse(gate.resume(leaseId: "a")) // lost resume response
    XCTAssertFalse(gate.tryBeginRun())
    XCTAssertTrue(gate.resume(leaseId: "b"))
    XCTAssertTrue(gate.tryBeginRun())
    gate.finishRun()
  }

  func testAccountRemovalRetiresOnlyItsFailedStopLeases() {
    let gate = BackgroundMigrationOutboxExecutionGate()
    gate.pause(leaseId: "stop:test:a:run-a")
    gate.pause(leaseId: "stop:test:b:run-b")
    gate.pause(leaseId: "remove-a")
    gate.discardStopLeases(network: "test", accountUuid: "a")
    XCTAssertFalse(gate.resume(leaseId: "remove-a"))
    XCTAssertFalse(gate.tryBeginRun())
    XCTAssertTrue(gate.resume(leaseId: "stop:test:b:run-b"))
  }

  func testWalletResetPreservesOtherLiveMutationLeases() {
    let gate = BackgroundMigrationOutboxExecutionGate()
    gate.pause(leaseId: "stop:test:a:run-a")
    gate.pause(leaseId: "reset")
    gate.discardStopLeases()
    XCTAssertFalse(gate.tryBeginRun())
    XCTAssertTrue(gate.resume(leaseId: "reset"))
  }

  func testDrainWaitsForSuccessfulBroadcastAndReceipt() throws {
    try verifyDrain(accepted: true)
  }

  func testDrainWaitsForUncertainBroadcastAndAttemptRecord() throws {
    try verifyDrain(accepted: false)
  }

  private func verifyDrain(accepted: Bool) throws {
    let gate = BackgroundMigrationOutboxExecutionGate.shared
    let leaseId = "stop:test:a:" + UUID().uuidString
    let sendStarted = DispatchSemaphore(value: 0)
    let releaseSend = DispatchSemaphore(value: 0)
    let drained = DispatchSemaphore(value: 0)
    let runnerDone = DispatchSemaphore(value: 0)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = BackgroundMigrationOutboxStore(
      fileURL: directory.appendingPathComponent("outbox.bin"),
      keyProvider: { Data(repeating: 0xCD, count: 32) }
    )
    defer {
      releaseSend.signal()
      gate.resume(leaseId: leaseId)
      try? FileManager.default.removeItem(at: directory)
    }
    let item = BackgroundMigrationOutboxItem(
      itemId: "item-a", partIndex: 0, txidHex: String(repeating: "a", count: 64),
      rawTransaction: Data([1, 2]), anchorBoundaryHeight: 0,
      scheduledHeight: 100, scheduleStartHeight: 99, expiryHeight: 69_120
    )
    let batch = BackgroundMigrationOutboxBatch(
      batchId: "batch-a", network: "test", accountUuid: "a", runId: "run-a",
      lightwalletdUrl: "https://example.invalid", timingMeanBlocks: 144,
      timingMaxBlocks: 576, createdAt: Date(), armedAt: nil,
      nextProofHeight: nil, proofReadyNotificationPendingAt: nil,
      proofReadyNotifiedAt: nil, items: [item]
    )
    _ = try store.update {
      try $0.stage(batch)
      try $0.armBatch(batchId: batch.batchId,
        expectedDigests: [item.itemId: item.payloadDigestHex], at: Date())
    }
    // Foreground recovery for any account enters this same wallet-wide runner.
    DispatchQueue.global().async {
      _ = BackgroundMigrationOutboxRunner.runOnce(
        store: store, cancellation: BackgroundMigrationCancellation(),
        dependencies: BackgroundMigrationOutboxRunnerDependencies(
          latestBlockHeight: { _, _ in .success(100) },
          sendTransaction: { _, _, cancellation in
            sendStarted.signal()
            guard releaseSend.wait(timeout: .now() + 5) == .success else {
              XCTFail("Test did not release the broadcast")
              return .failure(.timedOut)
            }
            XCTAssertFalse(cancellation.isCancelled)
            return accepted
              ? .success(NativeLightwalletdSendResponse(errorCode: 0, errorMessage: ""))
              : .failure(.timedOut)
          }
        )
      )
      runnerDone.signal()
    }
    XCTAssertEqual(sendStarted.wait(timeout: .now() + 5), .success)
    gate.pause(leaseId: leaseId)
    DispatchQueue.global().async {
      gate.waitUntilIdle()
      drained.signal()
    }
    XCTAssertEqual(drained.wait(timeout: .now() + 0.05), .timedOut)
    let blocked = BackgroundMigrationOutboxRunner.runOnce(
      store: store, cancellation: BackgroundMigrationCancellation(),
      dependencies: BackgroundMigrationOutboxRunnerDependencies(
        latestBlockHeight: { _, _ in XCTFail("A paused runner contacted the network"); return .success(100) },
        sendTransaction: { _, _, _ in XCTFail("A paused runner broadcast"); return .failure(.timedOut) }
      )
    )
    XCTAssertEqual(blocked.transport, .temporarilyUnavailable)
    releaseSend.signal()
    XCTAssertEqual(drained.wait(timeout: .now() + 5), .success)
    XCTAssertEqual(runnerDone.wait(timeout: .now() + 5), .success)
    let snapshot = try store.read()
    XCTAssertEqual(snapshot.batches.first?.items.first?.attemptCount, accepted ? 0 : 1)
    if accepted {
      XCTAssertEqual(snapshot.receipts.count, 1)
      XCTAssertEqual(snapshot.receipts.first?.outcome, .accepted)
    } else {
      // A timeout is not evidence that no submission happened. Rust stop must
      // reconcile this attempt rather than treating the input as unspent.
      XCTAssertEqual(snapshot.batches.first?.items.first?.status, .armed)
    }
    XCTAssertFalse(gate.tryBeginRun())
    gate.resume(leaseId: leaseId)
    XCTAssertTrue(gate.tryBeginRun())
    gate.finishRun()
  }
}
