import Foundation
import XCTest

@testable import Runner

final class BackgroundMigrationOutboxTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_750_000_000)

  func testStageAndArmAreIdempotentButConflictsFailClosed() throws {
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    var snapshot = BackgroundMigrationOutboxSnapshot()

    try snapshot.stage(batch)
    try snapshot.stage(batch)
    try snapshot.armBatch(
      batchId: batch.batchId,
      expectedDigests: digests(batch),
      at: now
    )
    try snapshot.armBatch(
      batchId: batch.batchId,
      expectedDigests: digests(batch),
      at: now
    )

    XCTAssertEqual(snapshot.batches.count, 1)
    XCTAssertTrue(snapshot.batches[0].items.allSatisfy { $0.status == .armed })
    XCTAssertThrowsError(
      try snapshot.armBatch(
        batchId: batch.batchId,
        expectedDigests: ["item-0": "different"],
        at: now
      )
    )
  }

  func testRestagingMovesAnIdleBatchToTheCurrentEndpoint() throws {
    let original = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    var replacement = original
    replacement.lightwalletdUrl = "https://replacement.example:443"
    var snapshot = BackgroundMigrationOutboxSnapshot()

    try snapshot.stage(original)
    try snapshot.armBatch(
      batchId: original.batchId,
      expectedDigests: digests(original),
      at: now
    )
    try snapshot.stage(replacement)

    XCTAssertEqual(
      snapshot.batches.first?.lightwalletdUrl,
      replacement.lightwalletdUrl
    )
  }

  func testRestagingCannotMoveAnInFlightSubmissionToAnotherEndpoint() throws {
    let original = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    var replacement = original
    replacement.lightwalletdUrl = "https://replacement.example:443"
    var snapshot = BackgroundMigrationOutboxSnapshot()

    try snapshot.stage(original)
    try snapshot.armBatch(
      batchId: original.batchId,
      expectedDigests: digests(original),
      at: now
    )
    try snapshot.beginSubmission(
      itemId: original.items[0].itemId,
      attemptId: "attempt",
      at: now
    )

    XCTAssertThrowsError(try snapshot.stage(replacement)) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .conflictingBatch)
    }
  }

  func testWatchOnlyBatchIsValidButEmptyBatchWithoutWatchIsRejected() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let watchOnly = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )

    try snapshot.stage(watchOnly)
    try snapshot.armBatch(
      batchId: watchOnly.batchId,
      expectedDigests: [:],
      at: now
    )

    XCTAssertEqual(snapshot.batches.first?.armedAt, now)
    XCTAssertTrue(snapshot.batches.first?.items.isEmpty == true)
    XCTAssertThrowsError(
      try snapshot.stage(
        makeBatch(
          batchId: "empty",
          account: "account-b",
          heights: [],
          nextProofHeight: nil
        )
      )
    ) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .invalidBatch)
    }
  }

  func testEndpointInspectionIncludesWatchOnlyBatchAndUsesEarliestHeight() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [500],
      nextProofHeight: 288
    )
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)

    XCTAssertEqual(snapshot.nextEndpointForInspection(), batch.lightwalletdUrl)
    XCTAssertEqual(snapshot.nextActionHeight(endpoint: batch.lightwalletdUrl), 288)
  }

  func testSelectDueSendsOneItemAndRotatesAccounts() throws {
    let first = makeBatch(batchId: "batch-a", account: "account-a")
    let second = makeBatch(batchId: "batch-b", account: "account-b")
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(first)
    try snapshot.stage(second)
    try snapshot.armBatch(batchId: first.batchId, expectedDigests: digests(first), at: now)
    try snapshot.armBatch(batchId: second.batchId, expectedDigests: digests(second), at: now)

    let selectionA = snapshot.selectDue(remoteHeight: 200, at: now)
    let selectionB = snapshot.selectDue(remoteHeight: 200, at: now)

    XCTAssertEqual(selectionA?.scopeKey, "test:account-a")
    XCTAssertEqual(selectionB?.scopeKey, "test:account-b")
    XCTAssertEqual(selectionA?.item.itemId, "item-0")
  }

  func testAcceptedItemCreatesReceiptAndReschedulesOnlyOverduePeers() throws {
    let batch = makeBatch(batchId: "batch-a", account: "account-a", heights: [100, 101, 500])
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: 200, at: now))
    try snapshot.beginSubmission(itemId: selected.item.itemId, attemptId: "attempt", at: now)
    var random = SeededOutboxRandom(values: [1, UInt64.max / 2, UInt64.max / 2])

    try snapshot.recordAccepted(
      itemId: selected.item.itemId,
      equivalent: false,
      remoteHeight: 200,
      responseCode: 0,
      responseMessage: "",
      at: now,
      random: &random
    )

    XCTAssertEqual(snapshot.receipts.count, 1)
    XCTAssertEqual(snapshot.receipts[0].outcome, .accepted)
    XCTAssertEqual(snapshot.receipts[0].scheduleUpdates.count, 1)
    let rescheduled = try XCTUnwrap(
      snapshot.batches[0].items.first(where: { $0.itemId == "item-1" })
    )
    let future = try XCTUnwrap(
      snapshot.batches[0].items.first(where: { $0.itemId == "item-2" })
    )
    XCTAssertGreaterThan(rescheduled.scheduledHeight, 200)
    XCTAssertEqual(rescheduled.scheduleStartHeight, 200)
    XCTAssertEqual(future.scheduledHeight, 500)
  }

  func testOverduePeersAreRescheduledBeforeTheirExpiry() throws {
    var batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100, 101, 102]
    )
    batch.items = batch.items.enumerated().map { index, item in
      BackgroundMigrationOutboxItem(
        itemId: item.itemId,
        partIndex: item.partIndex,
        txidHex: item.txidHex,
        rawTransaction: item.rawTransaction,
        anchorBoundaryHeight: item.anchorBoundaryHeight,
        scheduledHeight: item.scheduledHeight,
        scheduleStartHeight: item.scheduleStartHeight,
        expiryHeight: UInt64(204 + index)
      )
    }
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: 200, at: now))
    try snapshot.validateReschedulingAfterAcceptance(
      itemId: selected.item.itemId,
      remoteHeight: 200
    )
    try snapshot.beginSubmission(itemId: selected.item.itemId, attemptId: "attempt", at: now)
    var random = SeededOutboxRandom(values: [0, 0])

    try snapshot.recordAccepted(
      itemId: selected.item.itemId,
      equivalent: false,
      remoteHeight: 200,
      responseCode: 0,
      responseMessage: "",
      at: now,
      random: &random
    )

    for update in snapshot.receipts[0].scheduleUpdates {
      let item = try XCTUnwrap(
        snapshot.batches[0].items.first(where: { $0.itemId == update.itemId })
      )
      XCTAssertLessThan(update.scheduledHeight, item.expiryHeight)
    }
  }

  func testSubmissionIsRejectedBeforeBroadcastWhenPeersCannotFitBeforeExpiry() throws {
    var batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100, 101]
    )
    batch.items = batch.items.map { item in
      BackgroundMigrationOutboxItem(
        itemId: item.itemId,
        partIndex: item.partIndex,
        txidHex: item.txidHex,
        rawTransaction: item.rawTransaction,
        anchorBoundaryHeight: item.anchorBoundaryHeight,
        scheduledHeight: item.scheduledHeight,
        scheduleStartHeight: item.scheduleStartHeight,
        expiryHeight: 201
      )
    }
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: 200, at: now))

    XCTAssertThrowsError(
      try snapshot.validateReschedulingAfterAcceptance(
        itemId: selected.item.itemId,
        remoteHeight: 200
      )
    ) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .invalidSchedule)
    }
  }

  func testUncertainSubmissionRetainsExactBytesAndBacksOff() throws {
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: 200, at: now))
    try snapshot.beginSubmission(itemId: selected.item.itemId, attemptId: "attempt", at: now)
    try snapshot.recordUncertain(itemId: selected.item.itemId, error: "timeout", at: now)

    let retried = snapshot.batches[0].items[0]
    XCTAssertEqual(retried.rawTransaction, selected.item.rawTransaction)
    XCTAssertEqual(retried.payloadDigestHex, selected.item.payloadDigestHex)
    XCTAssertEqual(retried.status, .armed)
    XCTAssertEqual(retried.attemptCount, 1)
    XCTAssertEqual(retried.nextAttemptAt, now.addingTimeInterval(60))
    XCTAssertNil(snapshot.selectDue(remoteHeight: 200, at: now.addingTimeInterval(59)))
    XCTAssertNotNil(snapshot.selectDue(remoteHeight: 200, at: now.addingTimeInterval(60)))
  }

  func testRejectedItemPausesTheWholeBatchUntilForegroundAcknowledges() throws {
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100, 101],
      nextProofHeight: 288
    )
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: 200, at: now))
    try snapshot.beginSubmission(itemId: selected.item.itemId, attemptId: "attempt", at: now)

    try snapshot.recordRejected(
      itemId: selected.item.itemId,
      remoteHeight: 200,
      responseCode: -22,
      responseMessage: "rejected",
      at: now
    )

    XCTAssertNil(snapshot.batches.first?.armedAt)
    XCTAssertNil(snapshot.batches.first?.nextProofHeight)
    XCTAssertNil(snapshot.selectDue(remoteHeight: 200, at: now))
    snapshot.acknowledgeReceipts(Set(snapshot.receipts.map(\.receiptId)))
    XCTAssertTrue(snapshot.batches.isEmpty)
  }

  func testExpiredItemPausesAndTerminalAcknowledgementRemovesTheBatch() throws {
    let batch = makeBatch(batchId: "batch-a", account: "account-a", heights: [100, 101])
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)

    snapshot.expireItems(remoteHeight: 10_000, endpoint: batch.lightwalletdUrl, at: now)

    XCTAssertNil(snapshot.batches.first?.armedAt)
    XCTAssertNil(snapshot.selectDue(remoteHeight: 10_000, at: now))
    XCTAssertEqual(snapshot.receipts.count, 2)
    snapshot.acknowledgeReceipts(Set(snapshot.receipts.map(\.receiptId)))
    XCTAssertTrue(snapshot.batches.isEmpty)
  }

  func testEncryptedStoreRoundTripsWithoutPlaintextAndRejectsTampering() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileURL = directory.appendingPathComponent("outbox.bin")
    let key = Data(repeating: 0xAB, count: 32)
    let store = BackgroundMigrationOutboxStore(fileURL: fileURL, keyProvider: { key })
    defer { try? FileManager.default.removeItem(at: directory) }
    let batch = makeBatch(batchId: "private-batch-marker", account: "account-a")

    _ = try store.update { snapshot in try snapshot.stage(batch) }
    XCTAssertEqual(try store.read().batches, [batch])
    let ciphertext = try Data(contentsOf: fileURL)
    XCTAssertNil(String(data: ciphertext, encoding: .utf8)?.range(of: "private-batch-marker"))

    var tampered = ciphertext
    tampered[tampered.startIndex] ^= 0x01
    try tampered.write(to: fileURL, options: .atomic)
    XCTAssertThrowsError(try store.read()) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxStoreError, .invalidCiphertext)
    }
  }

  func testCadenceChecksAheadOfDueHeightAndCapsPolling() {
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: 101
      ),
      60
    )
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: 244
      ),
      600
    )
    XCTAssertNil(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: nil
      )
    )
  }

  func testRunnerQueriesTipAndSubmitsOnlyOneDueTransaction() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100, 101]
    )
    try stageAndArm(batch, in: harness.store)
    var sentPayloads: [Data] = []
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(200) },
      sendTransaction: { _, payload, _ in
        sentPayloads.append(payload)
        return .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )

    XCTAssertEqual(sentPayloads, [batch.items[0].rawTransaction])
    guard case .accepted(_, let observedHeight, _) = outcome.transport else {
      return XCTFail("Expected an accepted background submission, got \(outcome)")
    }
    XCTAssertEqual(observedHeight, 200)
    XCTAssertNil(outcome.proofReady)
    XCTAssertEqual(try harness.store.read().receipts.count, 1)
  }

  func testRunnerBroadcastsDueTransactionAndReturnsProofReadyInSameWake() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100],
      nextProofHeight: 200
    )
    try stageAndArm(batch, in: harness.store)
    var tipQueryCount = 0
    var sendCount = 0
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in
        tipQueryCount += 1
        return .success(200)
      },
      sendTransaction: { _, payload, _ in
        sendCount += 1
        XCTAssertEqual(payload, batch.items[0].rawTransaction)
        return .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let result = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )

    XCTAssertEqual(tipQueryCount, 1)
    XCTAssertEqual(sendCount, 1)
    guard case .accepted(_, let observedHeight, _) = result.transport else {
      return XCTFail("Expected an accepted background submission, got \(result)")
    }
    XCTAssertEqual(observedHeight, 200)
    XCTAssertEqual(
      result.proofReady,
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 200
      )
    )
  }

  func testRunnerDoesNotSubmitBeforeScheduledHeight() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [300]
    )
    try stageAndArm(batch, in: harness.store)
    var sendCount = 0
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(200) },
      sendTransaction: { _, _, _ in
        sendCount += 1
        return .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )

    XCTAssertEqual(sendCount, 0)
    XCTAssertEqual(
      outcome.transport,
      .waiting(nextHeight: 300, observedHeight: 200, delay: 600)
    )
    XCTAssertNil(outcome.proofReady)
  }

  func testRunnerReturnsStableProofReadyUntilNotificationIsAcknowledged() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)
    var sendCount = 0
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(288) },
      sendTransaction: { _, _, _ in
        sendCount += 1
        return .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let firstOutcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )
    let secondOutcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(60),
      dependencies: dependencies
    )
    _ = try harness.store.update { snapshot in
      try snapshot.acknowledgeProofReadyNotification(
        batchId: batch.batchId,
        at: now.addingTimeInterval(61)
      )
    }
    let thirdOutcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(120),
      dependencies: dependencies
    )

    XCTAssertEqual(
      firstOutcome,
      BackgroundMigrationOutboxRunResult(
        transport: .noWork,
        proofReady: BackgroundMigrationProofReadyMetadata(
          batchId: batch.batchId,
          observedHeight: 288
        )
      )
    )
    XCTAssertEqual(secondOutcome, firstOutcome)
    XCTAssertEqual(
      thirdOutcome,
      BackgroundMigrationOutboxRunResult(
        transport: .noWork,
        proofReady: nil
      )
    )
    XCTAssertEqual(sendCount, 0)
    XCTAssertEqual(
      try harness.store.read().batches.first?.proofReadyNotifiedAt,
      now.addingTimeInterval(61)
    )
    XCTAssertNil(
      try harness.store.read().batches.first?.proofReadyNotificationPendingAt
    )
  }

  func testRunnerWaitsForFutureProofHeightWithoutFinalizedTransactions() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 300
    )
    try stageAndArm(batch, in: harness.store)
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(200) },
      sendTransaction: { _, _, _ in
        XCTFail("A proof watch must not submit a transaction")
        return .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )

    XCTAssertEqual(
      outcome.transport,
      .waiting(nextHeight: 300, observedHeight: 200, delay: 600)
    )
    XCTAssertNil(outcome.proofReady)
  }

  func testRestagingSameProofHeightDoesNotRearmNotification() throws {
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: [:], at: now)
    XCTAssertEqual(
      snapshot.markProofReadyIfNeeded(
        remoteHeight: 288,
        endpoint: batch.lightwalletdUrl,
        at: now
      ),
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 288
      )
    )

    try snapshot.stage(batch)

    XCTAssertEqual(snapshot.batches.first?.proofReadyNotificationPendingAt, now)
    try snapshot.acknowledgeProofReadyNotification(
      batchId: batch.batchId,
      at: now.addingTimeInterval(60)
    )
    try snapshot.stage(batch)
    XCTAssertEqual(
      snapshot.batches.first?.proofReadyNotifiedAt,
      now.addingTimeInterval(60)
    )
    XCTAssertNil(
      snapshot.markProofReadyIfNeeded(
        remoteHeight: 288,
        endpoint: batch.lightwalletdUrl,
        at: now.addingTimeInterval(60)
      )
    )
  }

  func testRunnerKeepsExactTransactionAfterTransportFailure() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    try stageAndArm(batch, in: harness.store)
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(200) },
      sendTransaction: { _, _, _ in .failure(.timedOut) }
    )

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )

    XCTAssertEqual(outcome.transport, .temporarilyUnavailable)
    XCTAssertNil(outcome.proofReady)
    let item = try XCTUnwrap(try harness.store.read().batches.first?.items.first)
    XCTAssertEqual(item.rawTransaction, batch.items[0].rawTransaction)
    XCTAssertEqual(item.payloadDigestHex, batch.items[0].payloadDigestHex)
    XCTAssertEqual(item.status, .armed)
    XCTAssertEqual(item.nextAttemptAt, now.addingTimeInterval(60))
  }

  func testDuplicateResponseIsAcceptedEquivalent() {
    XCTAssertTrue(
      BackgroundMigrationOutboxRunner.isAcceptedEquivalent(
        "transaction already exists in mempool"
      )
    )
    XCTAssertFalse(
      BackgroundMigrationOutboxRunner.isAcceptedEquivalent(
        "transaction rejected by consensus"
      )
    )
  }

  private func makeBatch(
    batchId: String,
    account: String,
    heights: [UInt64] = [100, 101, 102],
    nextProofHeight: UInt64? = nil
  ) -> BackgroundMigrationOutboxBatch {
    BackgroundMigrationOutboxBatch(
      batchId: batchId,
      network: "test",
      accountUuid: account,
      runId: "run-\(account)",
      lightwalletdUrl: "https://testnet.zec.rocks:443",
      timingMeanBlocks: 144,
      timingMaxBlocks: 576,
      createdAt: now,
      armedAt: nil,
      nextProofHeight: nextProofHeight,
      proofReadyNotificationPendingAt: nil,
      proofReadyNotifiedAt: nil,
      items: heights.enumerated().map { index, height in
        BackgroundMigrationOutboxItem(
          itemId: "item-\(index)",
          partIndex: UInt32(index),
          txidHex: String(format: "%064x", index + 1),
          rawTransaction: Data([0x01, UInt8(index)]),
          anchorBoundaryHeight: 144,
          scheduledHeight: height,
          scheduleStartHeight: 99,
          expiryHeight: 10_000
        )
      }
    )
  }

  private func digests(_ batch: BackgroundMigrationOutboxBatch) -> [String: String] {
    Dictionary(uniqueKeysWithValues: batch.items.map { ($0.itemId, $0.payloadDigestHex) })
  }

  private func makeStoreHarness() throws -> OutboxStoreHarness {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = BackgroundMigrationOutboxStore(
      fileURL: directory.appendingPathComponent("outbox.bin"),
      keyProvider: { Data(repeating: 0xCD, count: 32) }
    )
    return OutboxStoreHarness(directory: directory, store: store)
  }

  private func stageAndArm(
    _ batch: BackgroundMigrationOutboxBatch,
    in store: BackgroundMigrationOutboxStore
  ) throws {
    _ = try store.update { snapshot in
      try snapshot.stage(batch)
      try snapshot.armBatch(
        batchId: batch.batchId,
        expectedDigests: digests(batch),
        at: now
      )
    }
  }
}

private struct OutboxStoreHarness {
  let directory: URL
  let store: BackgroundMigrationOutboxStore

  func cleanup() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct SeededOutboxRandom: RandomNumberGenerator {
  var values: [UInt64]

  mutating func next() -> UInt64 {
    values.isEmpty ? UInt64.max / 2 : values.removeFirst()
  }
}
