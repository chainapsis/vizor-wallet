import Flutter
import Foundation
import XCTest

@testable import Runner

final class BackgroundMigrationOutboxTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_750_000_000)

  func testBroadcastCompleteIsAnnouncedOncePerRunAcrossRecordCleanup() throws {
    // Acknowledging receipts prunes the emptied batch record, which used to
    // take the "already notified" marker with it. A later wave then recreated
    // the record under the same id and announced the same run again.
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let first = makeBatch(batchId: "batch-a", account: "account-a", heights: [100])
    try snapshot.stage(first)
    try snapshot.armBatch(batchId: first.batchId, expectedDigests: digests(first), at: now)
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

    XCTAssertNotNil(
      snapshot.markBroadcastCompleteIfNeeded(batchId: first.batchId, at: now)
    )
    try snapshot.acknowledgeBroadcastCompleteNotification(
      batchId: first.batchId,
      at: now
    )
    snapshot.acknowledgeReceipts(Set(snapshot.receipts.map(\.receiptId)))
    XCTAssertTrue(snapshot.batches.isEmpty)

    // A later wave of the same run restages the record from scratch.
    var second = makeBatch(batchId: "batch-a", account: "account-a", heights: [300])
    second.items = [
      BackgroundMigrationOutboxItem(
        itemId: "item-late",
        partIndex: 9,
        txidHex: String(format: "%064x", 99),
        rawTransaction: Data([0x02, 0x09]),
        anchorBoundaryHeight: 144,
        scheduledHeight: 300,
        scheduleStartHeight: 299,
        expiryHeight: 69_120
      )
    ]
    try snapshot.stage(second)
    try snapshot.armBatch(batchId: second.batchId, expectedDigests: digests(second), at: now)
    let lateSelection = try XCTUnwrap(snapshot.selectDue(remoteHeight: 400, at: now))
    try snapshot.beginSubmission(
      itemId: lateSelection.item.itemId,
      attemptId: "attempt-late",
      at: now
    )
    try snapshot.recordAccepted(
      itemId: lateSelection.item.itemId,
      equivalent: false,
      remoteHeight: 400,
      responseCode: 0,
      responseMessage: "",
      at: now,
      random: &random
    )

    XCTAssertNil(
      snapshot.markBroadcastCompleteIfNeeded(batchId: second.batchId, at: now)
    )
  }

  func testSnapshotDecodesWithoutTheAnnouncedRunField() throws {
    let legacy = """
      {"version":1,"batches":[],"receipts":[]}
      """
    let snapshot = try JSONDecoder().decode(
      BackgroundMigrationOutboxSnapshot.self,
      from: Data(legacy.utf8)
    )

    XCTAssertTrue(snapshot.batches.isEmpty)
    XCTAssertNil(snapshot.announcedBroadcastCompleteBatchIds)
  }

  func testDiscardBatchRemovesAnIdleRecordButKeepsTheAccountScope() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(batchId: "batch-a", account: "account-a")
    let other = makeBatch(batchId: "batch-b", account: "account-a")
    try snapshot.stage(batch)
    try snapshot.stage(other)

    XCTAssertTrue(try snapshot.discardBatch(batchId: batch.batchId))

    XCTAssertEqual(snapshot.batches.map(\.batchId), [other.batchId])
    XCTAssertFalse(try snapshot.discardBatch(batchId: batch.batchId))
  }

  func testDiscardBatchRefusesAnInFlightSubmission() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(batchId: "batch-a", account: "account-a", heights: [100])
    try snapshot.stage(batch)
    try snapshot.armBatch(
      batchId: batch.batchId,
      expectedDigests: digests(batch),
      at: now
    )
    try snapshot.beginSubmission(
      itemId: batch.items[0].itemId,
      attemptId: "attempt",
      at: now
    )

    XCTAssertThrowsError(try snapshot.discardBatch(batchId: batch.batchId)) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .conflictingBatch)
    }
    XCTAssertEqual(snapshot.batches.count, 1)
  }

  func testDiscardBatchRefusesAnUncertainSubmission() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(batchId: "batch-a", account: "account-a", heights: [100])
    try snapshot.stage(batch)
    try snapshot.armBatch(
      batchId: batch.batchId,
      expectedDigests: digests(batch),
      at: now
    )
    try snapshot.beginSubmission(
      itemId: batch.items[0].itemId,
      attemptId: "attempt",
      at: now
    )
    try snapshot.recordUncertain(
      itemId: batch.items[0].itemId,
      error: "timeout",
      at: now
    )

    XCTAssertThrowsError(try snapshot.discardBatch(batchId: batch.batchId)) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .conflictingBatch)
    }
    XCTAssertEqual(snapshot.batches[0].items[0].attemptCount, 1)
    XCTAssertEqual(snapshot.batches[0].items[0].lastError, "timeout")
  }

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

  func testRecoverBatchArmsOnlyItemsFromTheExpectedRun() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(batchId: "batch-a", account: "account-a")
    try snapshot.stage(batch)

    let recovered = try snapshot.recoverBatch(
      batchId: batch.batchId,
      network: batch.network,
      accountUuid: batch.accountUuid,
      runId: batch.runId,
      expectedTxids: Set(batch.items.map(\.txidHex)),
      lightwalletdUrl: "https://updated.example:443",
      at: now
    )

    XCTAssertTrue(recovered)
    XCTAssertEqual(snapshot.batches[0].lightwalletdUrl, "https://updated.example:443")
    XCTAssertEqual(snapshot.batches[0].armedAt, now)
    XCTAssertTrue(snapshot.batches[0].items.allSatisfy { $0.status == .armed })
  }

  func testRecoverBatchRejectsAnUnknownPersistedTransaction() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(batchId: "batch-a", account: "account-a")
    try snapshot.stage(batch)

    XCTAssertThrowsError(
      try snapshot.recoverBatch(
        batchId: batch.batchId,
        network: batch.network,
        accountUuid: batch.accountUuid,
        runId: batch.runId,
        expectedTxids: [batch.items[0].txidHex],
        lightwalletdUrl: batch.lightwalletdUrl,
        at: now
      )
    ) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .conflictingBatch)
    }
  }

  func testHasBatchRequiresEveryScheduledTransaction() throws {
    var snapshot = BackgroundMigrationOutboxSnapshot()
    let batch = makeBatch(batchId: "batch-a", account: "account-a")
    try snapshot.stage(batch)
    let expectedTxids = Set(batch.items.map(\.txidHex))

    XCTAssertTrue(
      try snapshot.hasBatch(
        batchId: batch.batchId,
        network: batch.network,
        accountUuid: batch.accountUuid,
        runId: batch.runId,
        expectedTxids: expectedTxids,
        requiredTxids: [batch.items[0].txidHex]
      )
    )
    XCTAssertThrowsError(
      try snapshot.hasBatch(
        batchId: batch.batchId,
        network: batch.network,
        accountUuid: batch.accountUuid,
        runId: batch.runId,
        expectedTxids: expectedTxids.union(["missing-txid"]),
        requiredTxids: ["missing-txid"]
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

  func testRestagingUpdatesTimingCadenceOnAnIdleBatch() throws {
    let original = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    var replacement = original
    replacement.timingMeanBlocks = original.timingMeanBlocks / 2
    var snapshot = BackgroundMigrationOutboxSnapshot()

    try snapshot.stage(original)
    try snapshot.armBatch(
      batchId: original.batchId,
      expectedDigests: digests(original),
      at: now
    )
    try snapshot.stage(replacement)

    XCTAssertEqual(
      snapshot.batches.first?.timingMeanBlocks,
      replacement.timingMeanBlocks
    )
    XCTAssertEqual(
      snapshot.batches.first?.timingMaxBlocks,
      original.timingMaxBlocks
    )
  }

  func testRestagingCannotChangeTimingCadenceDuringAnInFlightSubmission() throws {
    let original = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    var replacement = original
    replacement.timingMeanBlocks = original.timingMeanBlocks / 2
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
    XCTAssertEqual(
      snapshot.batches.first?.timingMeanBlocks,
      original.timingMeanBlocks
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

  func testRedrawFitsEveryPeerThatValidationAccepts() throws {
    let activation = try testnetNu7ActivationHeight()
    // From NU7 each redrawn peer takes at least three blocks.
    let afterNu7 = activation + 1_000
    // Before NU7 a peer that expires first still leaves room for later ones.
    for (remoteHeight, expiryHeights) in [
      (afterNu7, [afterNu7 + 10, afterNu7 + 10, afterNu7 + 10]),
      (UInt64(200), [202, 210]),
    ] {
      var batch = makeBatch(
        batchId: "batch-a",
        account: "account-a",
        heights: Array(repeating: 100, count: expiryHeights.count + 1)
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
          expiryHeight: index == 0 ? remoteHeight + 100 : expiryHeights[index - 1]
        )
      }
      var snapshot = BackgroundMigrationOutboxSnapshot()
      try snapshot.stage(batch)
      try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
      let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: remoteHeight, at: now))
      XCTAssertEqual(selected.item.itemId, "item-0")
      try snapshot.validateReschedulingAfterAcceptance(
        itemId: selected.item.itemId,
        remoteHeight: remoteHeight
      )
      try snapshot.beginSubmission(itemId: selected.item.itemId, attemptId: "attempt", at: now)
      // Zero draws the longest delay each time.
      var random = SeededOutboxRandom(values: Array(repeating: 0, count: 16))

      try snapshot.recordAccepted(
        itemId: selected.item.itemId,
        equivalent: false,
        remoteHeight: remoteHeight,
        responseCode: 0,
        responseMessage: "",
        at: now,
        random: &random
      )

      let updates = snapshot.receipts[0].scheduleUpdates
      XCTAssertEqual(updates.count, expiryHeights.count)
      for update in updates {
        let item = try XCTUnwrap(
          snapshot.batches[0].items.first(where: { $0.itemId == update.itemId })
        )
        XCTAssertLessThan(update.scheduledHeight, item.expiryHeight)
      }
    }
  }

  func testValidationReservesThreeBlocksPerPeerAfterNu7() throws {
    let remoteHeight = try testnetNu7ActivationHeight() + 1_000
    var batch = makeBatch(batchId: "batch-a", account: "account-a", heights: [100, 100, 100])
    batch.items = batch.items.enumerated().map { index, item in
      BackgroundMigrationOutboxItem(
        itemId: item.itemId,
        partIndex: item.partIndex,
        txidHex: item.txidHex,
        rawTransaction: item.rawTransaction,
        anchorBoundaryHeight: item.anchorBoundaryHeight,
        scheduledHeight: item.scheduledHeight,
        scheduleStartHeight: item.scheduleStartHeight,
        expiryHeight: index == 0 ? remoteHeight + 100 : remoteHeight + 6
      )
    }
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)

    // Two peers three blocks apart need seven blocks before their expiry.
    XCTAssertThrowsError(
      try snapshot.validateReschedulingAfterAcceptance(
        itemId: "item-0",
        remoteHeight: remoteHeight
      )
    ) { error in
      XCTAssertEqual(error as? BackgroundMigrationOutboxError, .invalidSchedule)
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

    snapshot.expireItems(remoteHeight: 69_120, endpoint: batch.lightwalletdUrl, at: now)

    XCTAssertNil(snapshot.batches.first?.armedAt)
    XCTAssertNil(snapshot.selectDue(remoteHeight: 69_120, at: now))
    XCTAssertEqual(snapshot.receipts.count, 2)
    snapshot.acknowledgeReceipts(Set(snapshot.receipts.map(\.receiptId)))
    XCTAssertTrue(snapshot.batches.isEmpty)
  }

  func testNeedsResignAcknowledgementPreservesAnUnreconciledAcceptedReceipt() throws {
    var batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [34_559, 34_560]
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
        expiryHeight: 69_120
      )
    }
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    let selected = try XCTUnwrap(snapshot.selectDue(remoteHeight: 34_559, at: now))
    try snapshot.beginSubmission(itemId: selected.item.itemId, attemptId: "attempt", at: now)
    var random = SeededOutboxRandom(values: [0])
    try snapshot.recordAccepted(
      itemId: selected.item.itemId,
      equivalent: false,
      remoteHeight: 34_559,
      responseCode: 0,
      responseMessage: "",
      at: now,
      random: &random
    )
    snapshot.markDueItemsNeedingResign(
      remoteHeight: 34_560,
      endpoint: batch.lightwalletdUrl,
      at: now
    )

    let needsResignReceipt = try XCTUnwrap(
      snapshot.receipts.first(where: { $0.outcome == .needsResign })
    )
    snapshot.acknowledgeReceipts([needsResignReceipt.receiptId])

    XCTAssertEqual(snapshot.receipts.map(\.outcome), [.accepted])
    let retainedBatch = try XCTUnwrap(snapshot.batches.first)
    let acceptedItem = try XCTUnwrap(
      retainedBatch.items.first(where: { $0.itemId == selected.item.itemId })
    )
    XCTAssertEqual(acceptedItem.rawTransaction, selected.item.rawTransaction)
    XCTAssertEqual(acceptedItem.status, .acceptedAwaitingReconciliation)

    snapshot.acknowledgeReceipts(Set(snapshot.receipts.map(\.receiptId)))
    XCTAssertTrue(snapshot.batches.isEmpty)
    XCTAssertTrue(snapshot.receipts.isEmpty)
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

  func testCadenceUsesTwentyFiveSecondBlocksFromNu7() {
    // Blocks 101...109 take 75 seconds; 110...120 take 25.
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.estimatedSeconds(
        from: 100,
        to: 120,
        nu7ActivationHeight: 110
      ),
      9 * 75 + 11 * 25
    )
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: 120,
        nu7ActivationHeight: 110
      ),
      350
    )
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 200,
        nextScheduledHeight: 230,
        nu7ActivationHeight: 110
      ),
      150
    )
  }

  func testBroadcastsAreHeldAroundNu7ByTheirTargetHeight() throws {
    let activation = try testnetNu7ActivationHeight()
    func armedSnapshot(targetHeight: UInt64?) throws -> BackgroundMigrationOutboxSnapshot {
      let batch = try makeBatchBeforeNu7(targetHeight: targetHeight)
      var snapshot = BackgroundMigrationOutboxSnapshot()
      try snapshot.stage(batch)
      try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
      return snapshot
    }
    func due(_ targetHeight: UInt64?, at remoteHeight: UInt64) throws -> Bool {
      var snapshot = try armedSnapshot(targetHeight: targetHeight)
      return snapshot.selectDue(remoteHeight: remoteHeight, at: now) != nil
    }

    // Signed for the old branch: held from A - 11 and after activation.
    XCTAssertTrue(try due(activation - 100, at: activation - 12))
    XCTAssertFalse(try due(activation - 100, at: activation - 11))
    XCTAssertFalse(try due(activation - 100, at: activation - 1))
    XCTAssertFalse(try due(activation - 100, at: activation))
    // Signed for the new branch: nothing to hold.
    XCTAssertTrue(try due(activation, at: activation - 1))
    // A part saved by an older build is held by the tip until activation.
    XCTAssertFalse(try due(nil, at: activation - 11))
    XCTAssertFalse(try due(nil, at: activation - 1))
    XCTAssertTrue(try due(nil, at: activation))
  }

  func testRunnerReportsAPartHeldForTheUpgrade() throws {
    let activation = try testnetNu7ActivationHeight()
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = try makeBatchBeforeNu7(targetHeight: activation - 100)
    try stageAndArm(batch, in: harness.store)

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: BackgroundMigrationOutboxRunnerDependencies(
        latestBlockHeight: { _, _ in .success(activation - 5) },
        sendTransaction: { _, _, _ in
          XCTFail("A held part must not be sent")
          return .success(NativeLightwalletdSendResponse(errorCode: 0, errorMessage: ""))
        }
      )
    )

    XCTAssertEqual(outcome.heldForUpgradeTxids, [batch.items[0].txidHex])
    XCTAssertTrue(try harness.store.read().receipts.isEmpty)
  }

  func testUpgradeStopKeyNamesTheUpgradeOnceNoOldBranchBlockIsLeft() throws {
    let activation = try testnetNu7ActivationHeight()
    func key(
      _ targetHeight: UInt64?,
      at remoteHeight: UInt64,
      attempts: UInt32 = 0
    ) throws -> String? {
      let batch = try makeBatchBeforeNu7(targetHeight: targetHeight)
      var snapshot = BackgroundMigrationOutboxSnapshot()
      try snapshot.stage(batch)
      try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
      snapshot.batches[0].items[0].attemptCount = attempts
      return snapshot.upgradeStopKey(remoteHeight: remoteHeight, endpoint: batch.lightwalletdUrl)
    }

    // Block A - 1 can still take an old-branch part.
    XCTAssertNil(try key(activation - 100, at: activation - 2))
    XCTAssertEqual(try key(activation - 100, at: activation - 1), "test:\(activation)")
    XCTAssertEqual(try key(activation - 100, at: activation + 5), "test:\(activation)")
    XCTAssertEqual(try key(activation - 100, at: UInt64.max), "test:\(activation)")
    // Signed for the new branch, or saved by an older build with no target.
    XCTAssertNil(try key(activation, at: activation + 5))
    XCTAssertNil(try key(nil, at: activation + 5))
    // A part sent before with no recorded outcome may already be mined.
    XCTAssertNil(try key(activation - 100, at: activation + 5, attempts: 1))
  }

  func testUpgradeStopKeyNamesTheLatestCrossedUpgrade() throws {
    let activation = try testnetNu7ActivationHeight()
    let batch = try makeBatchBeforeNu7(targetHeight: activation - 100)
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(batch)
    try snapshot.armBatch(batchId: batch.batchId, expectedDigests: digests(batch), at: now)
    // A part an earlier upgrade stopped that the foreground never reconciled.
    var earlier = snapshot.batches[0].items[0]
    earlier.targetHeight = 1
    snapshot.batches[0].items.insert(earlier, at: 0)

    XCTAssertEqual(
      snapshot.upgradeStopKey(remoteHeight: activation, endpoint: batch.lightwalletdUrl),
      "test:\(activation)"
    )
  }

  func testStopAlertCoversOnlyUnsentPartsItsUpgradeStopped() throws {
    let activation = try testnetNu7ActivationHeight()
    let key = "test:\(activation)"
    let stopped = try makeBatchBeforeNu7(targetHeight: activation - 100)
    var snapshot = BackgroundMigrationOutboxSnapshot()
    try snapshot.stage(stopped)
    try snapshot.armBatch(batchId: stopped.batchId, expectedDigests: digests(stopped), at: now)
    // From A the part waits for a new signature and no longer counts as work.
    snapshot.batches[0].items[0].status = .needsResignAwaitingReconciliation
    XCTAssertTrue(snapshot.holdsPartsStopped(byUpgrade: key))
    // An alert for another upgrade or network does not cover it.
    XCTAssertFalse(snapshot.holdsPartsStopped(byUpgrade: "test:\(activation + 1)"))
    XCTAssertFalse(snapshot.holdsPartsStopped(byUpgrade: "main:\(activation)"))

    snapshot.batches[0].items[0].attemptCount = 1
    XCTAssertFalse(snapshot.holdsPartsStopped(byUpgrade: key))
    XCTAssertFalse(BackgroundMigrationOutboxSnapshot().holdsPartsStopped(byUpgrade: key))
  }

  func testRunnerReportsTheUpgradeThatStoppedAPart() throws {
    let activation = try testnetNu7ActivationHeight()
    func outcome(at remoteHeight: UInt64) throws -> BackgroundMigrationOutboxRunResult {
      let harness = try makeStoreHarness()
      defer { harness.cleanup() }
      try stageAndArm(try makeBatchBeforeNu7(targetHeight: activation - 100), in: harness.store)
      return BackgroundMigrationOutboxRunner.runOnce(
        store: harness.store,
        cancellation: BackgroundMigrationCancellation(),
        now: now,
        dependencies: BackgroundMigrationOutboxRunnerDependencies(
          latestBlockHeight: { _, _ in .success(remoteHeight) },
          sendTransaction: { _, _, _ in
            XCTFail("A part the upgrade stopped must not be sent")
            return .success(NativeLightwalletdSendResponse(errorCode: 0, errorMessage: ""))
          }
        )
      )
    }

    // Still held at A - 1.
    let held = try outcome(at: activation - 1)
    XCTAssertEqual(held.upgradeStopKey, "test:\(activation)")
    XCTAssertFalse(held.transport == .needsUserAction)
    // From A the part also crosses the ZIP 318 expiry bucket and needs a new
    // signature, which the stop alert covers.
    let crossed = try outcome(at: activation)
    XCTAssertEqual(crossed.transport, .needsUserAction)
    XCTAssertEqual(crossed.upgradeStopKey, "test:\(activation)")
  }

  func testUpgradeStopAlertGoesOutOncePerUpgrade() {
    XCTAssertEqual(
      backgroundMigrationUpgradeStopAlertKey("test:600", alreadyAlerted: nil),
      "test:600"
    )
    XCTAssertNil(backgroundMigrationUpgradeStopAlertKey("test:600", alreadyAlerted: "test:600"))
    XCTAssertEqual(
      backgroundMigrationUpgradeStopAlertKey("main:700", alreadyAlerted: "test:600"),
      "main:700"
    )
    XCTAssertNil(backgroundMigrationUpgradeStopAlertKey(nil, alreadyAlerted: nil))
  }

  func testZip318DurationsFollowRust() {
    // Mainnet NU7 activates at 3,543,405: the expiry modulus becomes 103,680.
    XCTAssertEqual(
      BackgroundMigrationOutboxSnapshot.canonicalExpiryHeight(for: 3_543_404, network: "main"),
      3_594_240
    )
    XCTAssertEqual(
      BackgroundMigrationOutboxSnapshot.canonicalExpiryHeight(for: 3_543_405, network: "main"),
      3_732_480
    )
    XCTAssertNil(BackgroundMigrationOutboxSnapshot.canonicalExpiryHeight(for: 100, network: "nope"))
    XCTAssertEqual(
      BackgroundMigrationOutboxSchedule.blocksPerReferenceBlock(at: 3_543_404, network: "main"),
      1
    )
    XCTAssertEqual(
      BackgroundMigrationOutboxSchedule.blocksPerReferenceBlock(at: 3_543_405, network: "main"),
      3
    )
  }

  func testCadenceChecksAheadOfDueHeightAndCapsPolling() {
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: 101,
        nu7ActivationHeight: nil
      ),
      60
    )
    XCTAssertEqual(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: 244,
        nu7ActivationHeight: nil
      ),
      600
    )
    XCTAssertNil(
      BackgroundMigrationOutboxCadence.nextCheckDelay(
        remoteHeight: 100,
        nextScheduledHeight: nil,
        nu7ActivationHeight: nil
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
    let receipt = try XCTUnwrap(
      BackgroundMigrationOutboxChannel.listReceipts(store: harness.store).first
    )
    XCTAssertEqual(
      (receipt["rawTransaction"] as? FlutterStandardTypedData)?.data,
      batch.items[0].rawTransaction
    )
  }

  func testStopInspectionReportsOnlyTransactionsWithAStartedAttempt() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100, 101]
    )
    try stageAndArm(batch, in: harness.store)
    _ = try harness.store.update { snapshot in
      try snapshot.beginSubmission(
        itemId: batch.items[0].itemId,
        attemptId: "attempt",
        at: now
      )
    }

    let attempted = try BackgroundMigrationOutboxChannel.listAttemptedTxids(
      arguments: [
        "network": batch.network,
        "accountUuid": batch.accountUuid,
        "runId": batch.runId,
      ],
      store: harness.store
    )

    XCTAssertEqual(attempted, [batch.items[0].txidHex])
  }

  func testCancellationBeforeSubmissionDoesNotCreateAnAttempt() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100]
    )
    try stageAndArm(batch, in: harness.store)
    _ = try harness.store.update { snapshot in
      try snapshot.beginSubmission(
        itemId: batch.items[0].itemId,
        attemptId: "attempt",
        at: now
      )
      try snapshot.recordCancelledBeforeSubmission(
        itemId: batch.items[0].itemId,
        error: "cancelled before transport"
      )
    }

    let attempted = try BackgroundMigrationOutboxChannel.listAttemptedTxids(
      arguments: [
        "network": batch.network,
        "accountUuid": batch.accountUuid,
        "runId": batch.runId,
      ],
      store: harness.store
    )
    let item = try XCTUnwrap(harness.store.read().batches.first?.items.first)

    XCTAssertTrue(attempted.isEmpty)
    XCTAssertEqual(item.status, .armed)
    XCTAssertEqual(item.attemptCount, 0)
  }

  func testRunnerReportsBroadcastCompleteAfterLastAcceptedEquivalentItem() throws {
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
      sendTransaction: { _, _, _ in
        .success(
          NativeLightwalletdSendResponse(
            errorCode: 1,
            errorMessage: "already in mempool"
          )
        )
      }
    )

    let result = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )

    XCTAssertEqual(
      result.broadcastComplete,
      BackgroundMigrationBroadcastCompleteMetadata(batchId: batch.batchId)
    )
    XCTAssertEqual(try harness.store.read().receipts.first?.outcome, .acceptedEquivalent)
  }

  func testRunnerDoesNotReportBroadcastCompleteWhileBatchHasMoreWork() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "batch-a",
      account: "account-a",
      heights: [100, 300]
    )
    try stageAndArm(batch, in: harness.store)
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(200) },
      sendTransaction: { _, _, _ in
        .success(
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

    XCTAssertNil(result.broadcastComplete)
  }

  func testRunnerRetriesBroadcastCompleteUntilNotificationIsAcknowledged() throws {
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
      sendTransaction: { _, _, _ in
        .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let first = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      dependencies: dependencies
    )
    let receiptIds = Set(try harness.store.read().receipts.map(\.receiptId))
    _ = try harness.store.update { snapshot in
      snapshot.acknowledgeReceipts(receiptIds)
    }
    let second = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(60),
      dependencies: dependencies
    )
    _ = try harness.store.update { snapshot in
      try snapshot.acknowledgeBroadcastCompleteNotification(
        batchId: batch.batchId,
        at: now.addingTimeInterval(61)
      )
    }
    let third = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(120),
      dependencies: dependencies
    )

    let expected = BackgroundMigrationBroadcastCompleteMetadata(
      batchId: batch.batchId
    )
    XCTAssertEqual(first.broadcastComplete, expected)
    XCTAssertEqual(second.broadcastComplete, expected)
    XCTAssertNil(third.broadcastComplete)
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
    XCTAssertNil(result.broadcastComplete)
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
    XCTAssertEqual(outcome.transportAccountUuid, "account-a")
    XCTAssertNil(outcome.proofReady)
  }

  func testRunnerRequiresFreshSignatureWhenWakeCrossesExpiryBucket() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    var batch = makeBatch(
      batchId: "boundary-batch",
      account: "account-a",
      heights: [34_559]
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
        expiryHeight: 69_120
      )
    }
    try stageAndArm(batch, in: harness.store)
    var sendCount = 0
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(34_560) },
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
    XCTAssertEqual(outcome.transport, .needsUserAction)
    XCTAssertEqual(outcome.transportAccountUuid, "account-a")
    let snapshot = try harness.store.read()
    XCTAssertNil(snapshot.batches.first?.armedAt)
    XCTAssertEqual(
      snapshot.batches.first?.items.first?.status,
      .needsResignAwaitingReconciliation
    )
    XCTAssertEqual(snapshot.receipts.first?.outcome, .needsResign)
    XCTAssertEqual(snapshot.receipts.first?.remoteHeight, 34_560)
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

  func testRunnerDoesNotArmProofNotificationBeforePreparationVerification() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)
    let dependencies = BackgroundMigrationOutboxRunnerDependencies(
      latestBlockHeight: { _, _ in .success(288) },
      sendTransaction: { _, _, _ in
        XCTFail("A proof watch must not submit a transaction")
        return .success(
          NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
        )
      }
    )

    let candidate = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now,
      requiresPreparationProofVerification: true,
      dependencies: dependencies
    )
    XCTAssertEqual(
      candidate.proofReady,
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 288
      )
    )
    XCTAssertNil(
      try harness.store.read().batches.first?.proofReadyNotificationPendingAt
    )

    _ = try harness.store.update { snapshot in
      XCTAssertTrue(
        snapshot.recordVerifiedProofReadiness(
          network: batch.network,
          accountUuid: batch.accountUuid,
          runId: batch.runId,
          at: now.addingTimeInterval(1)
        )
      )
    }
    let verified = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(2),
      requiresPreparationProofVerification: true,
      dependencies: dependencies
    )
    XCTAssertEqual(verified.proofReady, candidate.proofReady)
    XCTAssertEqual(
      try harness.store.read().batches.first?.proofReadyNotificationPendingAt,
      now.addingTimeInterval(1)
    )
  }

  func testForegroundChannelDoesNotVerifyProofReadinessFromHeightAlone() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)

    _ = BackgroundMigrationOutboxChannel.runOnceNow(
      store: harness.store,
      dependencies: BackgroundMigrationOutboxRunnerDependencies(
        latestBlockHeight: { _, _ in .success(288) },
        sendTransaction: { _, _, _ in
          XCTFail("A proof watch must not submit a transaction")
          return .success(
            NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
          )
        }
      )
    )

    XCTAssertNil(
      try harness.store.read().batches.first?.proofReadyNotificationPendingAt
    )
  }

  func testForegroundChannelRecordsVerifiedProofReadiness() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)

    XCTAssertTrue(
      try BackgroundMigrationOutboxChannel.recordVerifiedProofReadiness(
        arguments: [
          "network": batch.network,
          "accountUuid": batch.accountUuid,
          "runId": batch.runId,
          "observedHeight": 288,
        ],
        store: harness.store
      )
    )
    XCTAssertEqual(
      try harness.store.read().pendingProofReadyNotification(),
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 288
      )
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
    for message in [
      "transaction was committed to the best chain",
      "already in mempool",
      "already have transaction",
      "transaction already in block chain",
      "transaction is already in state",
      "transaction already exists",
      "txn-already-known",
      "txn-already-in-mempool",
      "already known",
    ] {
      XCTAssertTrue(
        BackgroundMigrationOutboxRunner.isAcceptedEquivalent(message),
        message
      )
    }
    XCTAssertFalse(
      BackgroundMigrationOutboxRunner.isAcceptedEquivalent(
        "transaction rejected by consensus"
      )
    )
  }

  func testUnverifiedProofReadyNoticeKeepsTheVerifiedAnnouncementAvailable() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)

    var notice: BackgroundMigrationProofReadyMetadata?
    _ = try harness.store.update { snapshot in
      notice = snapshot.markUnverifiedProofReadyNoticeIfNeeded(
        batchId: batch.batchId,
        at: now
      )
    }
    XCTAssertEqual(
      notice,
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 288,
        verified: false
      )
    )
    // A pending nudge is reported back so a failed post is retried.
    XCTAssertEqual(
      try harness.store.read().pendingUnverifiedProofReadyNotice(),
      notice
    )

    _ = try harness.store.update { snapshot in
      try snapshot.acknowledgeUnverifiedProofReadyNotice(
        batchId: batch.batchId,
        at: now.addingTimeInterval(1)
      )
    }

    let acknowledged = try harness.store.read()
    // The nudge is unverified, so it must not retire the batch: the real
    // announcement is still owed once readiness can actually be observed.
    XCTAssertNil(acknowledged.batches.first?.proofReadyNotifiedAt)
    XCTAssertEqual(
      acknowledged.batches.first?.proofReadyHeightNoticedAt,
      now.addingTimeInterval(1)
    )
    XCTAssertNil(acknowledged.batches.first?.proofReadyHeightNoticePendingAt)
    XCTAssertNil(
      acknowledged.proofReadinessCandidate(
        remoteHeight: 288,
        endpoint: batch.lightwalletdUrl
      )
    )

    // It also must not repeat, and must stop pinning the wake cadence to the
    // proof height, which would re-run a chain sync every minute.
    var repeated: BackgroundMigrationProofReadyMetadata?
    _ = try harness.store.update { snapshot in
      repeated = snapshot.markUnverifiedProofReadyNoticeIfNeeded(
        batchId: batch.batchId,
        at: now.addingTimeInterval(2)
      )
    }
    XCTAssertNil(repeated)
    XCTAssertNil(acknowledged.pendingUnverifiedProofReadyNotice())
    XCTAssertNil(acknowledged.nextActionHeight(endpoint: batch.lightwalletdUrl))

    _ = try harness.store.update { snapshot in
      XCTAssertTrue(
        snapshot.recordVerifiedProofReadiness(
          network: batch.network,
          accountUuid: batch.accountUuid,
          runId: batch.runId,
          at: now.addingTimeInterval(3)
        )
      )
    }
    XCTAssertEqual(
      try harness.store.read().pendingProofReadyNotification(),
      BackgroundMigrationProofReadyMetadata(batchId: batch.batchId, observedHeight: 288)
    )
  }

  func testProofCandidateSkipsAnAcknowledgedHeightOnlyNotice() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let first = makeBatch(
      batchId: "watch-first",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    let second = makeBatch(
      batchId: "watch-second",
      account: "account-b",
      heights: [],
      nextProofHeight: 289
    )
    try stageAndArm(first, in: harness.store)
    try stageAndArm(second, in: harness.store)
    _ = try harness.store.update { snapshot in
      _ = snapshot.markUnverifiedProofReadyNoticeIfNeeded(
        batchId: first.batchId,
        at: now
      )
      try snapshot.acknowledgeUnverifiedProofReadyNotice(
        batchId: first.batchId,
        at: now.addingTimeInterval(1)
      )
    }

    let candidate = try harness.store.read().proofReadinessCandidate(
      remoteHeight: 289,
      endpoint: first.lightwalletdUrl
    )

    XCTAssertEqual(
      candidate,
      BackgroundMigrationProofReadyMetadata(
        batchId: second.batchId,
        observedHeight: 289
      )
    )
  }

  func testAVerifiedProofReadyNotificationQueuedByAnOlderBuildStillDrains() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)
    // What a build that verified readiness in the wake left behind.
    _ = try harness.store.update { snapshot in
      _ = snapshot.recordVerifiedProofReadiness(
        network: batch.network,
        accountUuid: batch.accountUuid,
        runId: batch.runId,
        at: now
      )
    }

    let snapshot = try harness.store.read()
    // Still reported, so the wake can deliver and acknowledge it.
    XCTAssertEqual(
      snapshot.pendingProofReadyNotification(),
      BackgroundMigrationProofReadyMetadata(batchId: batch.batchId, observedHeight: 288)
    )
    // And it cannot be re-marked as a nudge, which is why the wake has to
    // recognise it instead of overwriting it.
    var renotice: BackgroundMigrationProofReadyMetadata?
    _ = try harness.store.update { mutable in
      renotice = mutable.markUnverifiedProofReadyNoticeIfNeeded(
        batchId: batch.batchId,
        at: now.addingTimeInterval(1)
      )
    }
    XCTAssertNil(renotice)
  }

  func testRunnerRetriesAnUndeliveredUnverifiedProofReadyNotice() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)
    _ = try harness.store.update { snapshot in
      _ = snapshot.markUnverifiedProofReadyNoticeIfNeeded(
        batchId: batch.batchId,
        at: now
      )
    }

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(60),
      requiresPreparationProofVerification: true,
      dependencies: BackgroundMigrationOutboxRunnerDependencies(
        latestBlockHeight: { _, _ in .success(288) },
        sendTransaction: { _, _, _ in
          XCTFail("a proof watch must not submit a transaction")
          return .success(
            NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
          )
        }
      )
    )

    XCTAssertEqual(
      outcome.proofReady,
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 288,
        verified: false
      )
    )
  }

  func testRunnerDeliversVerifiedReadinessAfterAcknowledgedHeightNotice() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let batch = makeBatch(
      batchId: "watch-only",
      account: "account-a",
      heights: [],
      nextProofHeight: 288
    )
    try stageAndArm(batch, in: harness.store)
    _ = try harness.store.update { snapshot in
      _ = snapshot.markUnverifiedProofReadyNoticeIfNeeded(
        batchId: batch.batchId,
        at: now
      )
      try snapshot.acknowledgeUnverifiedProofReadyNotice(
        batchId: batch.batchId,
        at: now.addingTimeInterval(1)
      )
      XCTAssertTrue(
        snapshot.recordVerifiedProofReadiness(
          network: batch.network,
          accountUuid: batch.accountUuid,
          runId: batch.runId,
          at: now.addingTimeInterval(2)
        )
      )
    }

    let outcome = BackgroundMigrationOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundMigrationCancellation(),
      now: now.addingTimeInterval(3),
      requiresPreparationProofVerification: true,
      dependencies: BackgroundMigrationOutboxRunnerDependencies(
        latestBlockHeight: { _, _ in .success(288) },
        sendTransaction: { _, _, _ in
          XCTFail("a proof watch must not submit a transaction")
          return .success(
            NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
          )
        }
      )
    )

    XCTAssertEqual(
      outcome.proofReady,
      BackgroundMigrationProofReadyMetadata(
        batchId: batch.batchId,
        observedHeight: 288
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
          expiryHeight: 69_120
        )
      }
    )
  }

  private func testnetNu7ActivationHeight() throws -> UInt64 {
    try XCTUnwrap(BackgroundMigrationOutboxCadence.nu7ActivationHeight(network: "test"))
  }

  /// One part due 12 blocks before testnet NU7, signed for `targetHeight`.
  private func makeBatchBeforeNu7(targetHeight: UInt64?) throws -> BackgroundMigrationOutboxBatch {
    let scheduledHeight = try testnetNu7ActivationHeight() - 12
    let expiryHeight = try XCTUnwrap(
      BackgroundMigrationOutboxSnapshot.canonicalExpiryHeight(for: scheduledHeight, network: "test")
    )
    var batch = makeBatch(batchId: "batch-a", account: "account-a", heights: [scheduledHeight])
    batch.items = batch.items.map { item in
      BackgroundMigrationOutboxItem(
        itemId: item.itemId,
        partIndex: item.partIndex,
        txidHex: item.txidHex,
        rawTransaction: item.rawTransaction,
        anchorBoundaryHeight: item.anchorBoundaryHeight,
        scheduledHeight: scheduledHeight,
        scheduleStartHeight: scheduledHeight - 1,
        expiryHeight: expiryHeight,
        targetHeight: targetHeight
      )
    }
    return batch
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
