import Foundation
import XCTest

@testable import Runner

final class BackgroundVotingShareOutboxTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_750_000_000)
  private var nowSeconds: UInt64 { UInt64(now.timeIntervalSince1970) }

  // MARK: - Timing policy

  func testTimingPolicyMirrorsTheRustShareCrate() {
    // Pinned to zcash_voting::share_policy; a drift here is a protocol bug,
    // not a tuning choice.
    XCTAssertEqual(BackgroundVotingSharePolicy.statusCheckGraceSeconds, 10)
    XCTAssertEqual(BackgroundVotingSharePolicy.minOverdueThresholdSeconds, 30)
    XCTAssertEqual(BackgroundVotingSharePolicy.maxOverdueThresholdSeconds, 3600)
    XCTAssertEqual(BackgroundVotingSharePolicy.resubmitCutoffSeconds, 10)

    // base falls back to createdAt when submitAt is unset.
    XCTAssertEqual(
      BackgroundVotingSharePolicy.submissionBaseSeconds(
        submitAtSeconds: 0,
        createdAtSeconds: 500
      ),
      500
    )
    XCTAssertEqual(
      BackgroundVotingSharePolicy.submissionBaseSeconds(
        submitAtSeconds: 700,
        createdAtSeconds: 500
      ),
      700
    )
    XCTAssertEqual(
      BackgroundVotingSharePolicy.statusCheckAtSeconds(baseSeconds: 1000),
      1010
    )

    // Quarter-window overdue threshold with clamping.
    XCTAssertEqual(
      BackgroundVotingSharePolicy.overdueThresholdSeconds(
        baseSeconds: 1000,
        voteEndSeconds: 1400
      ),
      100
    )
    XCTAssertEqual(
      BackgroundVotingSharePolicy.overdueThresholdSeconds(
        baseSeconds: 1000,
        voteEndSeconds: 1040
      ),
      30
    )
    XCTAssertEqual(
      BackgroundVotingSharePolicy.overdueThresholdSeconds(
        baseSeconds: 1000,
        voteEndSeconds: 21000
      ),
      3600
    )
    // A vote end at or before the base still yields the minimum threshold.
    XCTAssertEqual(
      BackgroundVotingSharePolicy.overdueThresholdSeconds(
        baseSeconds: 1000,
        voteEndSeconds: 900
      ),
      30
    )

    XCTAssertTrue(
      BackgroundVotingSharePolicy.allowsResubmission(
        voteEndSeconds: 1011,
        nowSeconds: 1000
      )
    )
    XCTAssertFalse(
      BackgroundVotingSharePolicy.allowsResubmission(
        voteEndSeconds: 1010,
        nowSeconds: 1000
      )
    )
  }

  func testRetryLadderMatchesTheOutboxCadence() {
    XCTAssertEqual(BackgroundVotingSharePolicy.retryDelay(attemptCount: 1), 60)
    XCTAssertEqual(BackgroundVotingSharePolicy.retryDelay(attemptCount: 2), 5 * 60)
    XCTAssertEqual(BackgroundVotingSharePolicy.retryDelay(attemptCount: 3), 15 * 60)
    XCTAssertEqual(BackgroundVotingSharePolicy.retryDelay(attemptCount: 4), 60 * 60)
    XCTAssertEqual(BackgroundVotingSharePolicy.retryDelay(attemptCount: 9), 60 * 60)
  }

  func testResubmissionOrderPrefersUnsentHelpers() {
    let helpers = ["https://h1", "https://h2", "https://h3", "https://h4"]
    var random = SeededVotingRandom(values: [3, 1, 4, 1, 5, 9, 2, 6])
    let order = BackgroundVotingSharePolicy.resubmissionServerOrder(
      helperUrls: helpers,
      sentToUrls: ["https://h2", "https://stale.example"],
      random: &random
    )

    XCTAssertEqual(order.count, 4)
    XCTAssertEqual(
      Set(order.prefix(3)),
      Set(["https://h1", "https://h3", "https://h4"])
    )
    XCTAssertEqual(order.last, "https://h2")
    // A stale sent URL that is no longer a configured helper is not a target.
    XCTAssertFalse(order.contains("https://stale.example"))
  }

  // MARK: - Staging

  func testStageIsIdempotentAndUnionsSentUrls() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let round = makeRound(shares: [makeShare(sentToUrls: ["https://h1"])])
    try snapshot.stage(round, prune: false)
    var restaged = round
    restaged.shares[0].sentToUrls = ["https://h1", "https://h2"]
    try snapshot.stage(restaged, prune: false)

    XCTAssertEqual(snapshot.rounds.count, 1)
    XCTAssertEqual(snapshot.rounds[0].shares.count, 1)
    XCTAssertEqual(
      snapshot.rounds[0].shares[0].sentToUrls,
      ["https://h1", "https://h2"]
    )
  }

  func testStageRejectsAConflictingShare() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    try snapshot.stage(makeRound(shares: [makeShare()]), prune: false)

    var differentBody = makeRound(
      shares: [makeShare(body: #"{"share":"different"}"#)]
    )
    XCTAssertThrowsError(try snapshot.stage(differentBody, prune: false)) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxError,
        .conflictingRound
      )
    }

    differentBody = makeRound(shares: [makeShare(shareIdHex: "beef")])
    XCTAssertThrowsError(try snapshot.stage(differentBody, prune: false)) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxError,
        .conflictingRound
      )
    }
  }

  func testPruneReplacesTheShareSetButPreservesProgress() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let shareA = makeShare(shareIndex: 0, shareIdHex: "aa01")
    let shareB = makeShare(shareIndex: 1, shareIdHex: "bb01")
    let round = makeRound(shares: [shareA, shareB])
    try snapshot.stage(round, prune: false)
    try snapshot.armRound(
      roundKey: round.roundKey,
      expectedDigests: digests(round),
      at: now
    )
    // Give share A runner-side progress.
    try snapshot.beginSubmission(
      roundKey: round.roundKey,
      shareKey: shareA.shareKey,
      at: now
    )
    try snapshot.recordResubmitFailure(
      roundKey: round.roundKey,
      shareKey: shareA.shareKey,
      error: "helper refused",
      at: now
    )

    let shareC = makeShare(shareIndex: 2, shareIdHex: "cc01")
    let restaged = makeRound(shares: [shareA, shareC])
    try snapshot.stage(restaged, prune: true)

    let keys = snapshot.rounds[0].shares.map(\.shareKey)
    XCTAssertEqual(keys, [shareA.shareKey, shareC.shareKey])
    let survivor = snapshot.rounds[0].shares[0]
    XCTAssertEqual(survivor.status, .armed)
    XCTAssertEqual(survivor.attemptCount, 1)
    XCTAssertNotNil(survivor.nextAttemptAt)
    XCTAssertEqual(snapshot.rounds[0].shares[1].status, .staged)
  }

  func testStageRefusesToChangeASubmittingShare() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let share = makeShare()
    let round = makeRound(shares: [share])
    try snapshot.stage(round, prune: false)
    try snapshot.armRound(
      roundKey: round.roundKey,
      expectedDigests: digests(round),
      at: now
    )
    try snapshot.beginSubmission(
      roundKey: round.roundKey,
      shareKey: share.shareKey,
      at: now
    )

    // Pruning the submitting share away is refused.
    let withoutShare = makeRound(
      shares: [makeShare(shareIndex: 5, shareIdHex: "ee01")]
    )
    XCTAssertThrowsError(try snapshot.stage(withoutShare, prune: true)) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxError,
        .conflictingRound
      )
    }

    // Round config changes under an in-flight resubmission are refused.
    var newConfig = makeRound(shares: [share])
    newConfig.voteEndSeconds += 100
    XCTAssertThrowsError(try snapshot.stage(newConfig, prune: false)) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxError,
        .conflictingRound
      )
    }

    // A matching restage passes but leaves the submitting share untouched.
    var matching = makeRound(shares: [share])
    matching.shares[0].sentToUrls = ["https://late-union.example"]
    try snapshot.stage(matching, prune: false)
    XCTAssertEqual(snapshot.rounds[0].shares[0].status, .submitting)
    XCTAssertFalse(
      snapshot.rounds[0].shares[0].sentToUrls.contains("https://late-union.example")
    )
  }

  func testArmHandshakeRejectsADigestMismatch() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let round = makeRound(shares: [makeShare()])
    try snapshot.stage(round, prune: false)

    XCTAssertThrowsError(
      try snapshot.armRound(
        roundKey: round.roundKey,
        expectedDigests: [round.shares[0].shareKey: "different"],
        at: now
      )
    ) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxError,
        .invalidArmRequest
      )
    }
    XCTAssertNil(snapshot.rounds[0].armedAt)

    try snapshot.armRound(
      roundKey: round.roundKey,
      expectedDigests: digests(round),
      at: now
    )
    XCTAssertEqual(snapshot.rounds[0].armedAt, now)
    XCTAssertTrue(snapshot.rounds[0].shares.allSatisfy { $0.status == .armed })
  }

  func testHasRoundAnswersFalseForMissingShares() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let round = makeRound(shares: [makeShare()])
    try snapshot.stage(round, prune: false)

    XCTAssertTrue(
      try snapshot.hasRound(
        roundKey: round.roundKey,
        expectedShareKeys: [round.shares[0].shareKey]
      )
    )
    XCTAssertFalse(
      try snapshot.hasRound(
        roundKey: round.roundKey,
        expectedShareKeys: [round.shares[0].shareKey, "9:9:9"]
      )
    )
    XCTAssertFalse(
      try snapshot.hasRound(
        roundKey: "test:other:abcd",
        expectedShareKeys: ["0:7:0"]
      )
    )
  }

  // MARK: - Expiry

  func testExpiryAtVoteEndRecordsReceiptsAndDisarms() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let round = makeRound(
      voteEndSeconds: nowSeconds + 100,
      shares: [makeShare(sentToUrls: ["https://h1"])]
    )
    try stageAndArm(round, in: harness.store)

    let afterEnd = now.addingTimeInterval(101)
    let outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { afterEnd },
      dependencies: makeDependencies(
        status: { _, _, _ in
          XCTFail("an ended round must not be polled")
          return .failure(.malformedResponse)
        },
        post: { _, _ in
          XCTFail("an ended round must not be resubmitted")
          return .failure(.malformedResponse)
        }
      )
    )

    XCTAssertEqual(
      outcome.transport,
      .processed(confirmed: 0, resubmitted: 0, expired: 1, failed: 0)
    )
    XCTAssertFalse(outcome.hasArmedUnconfirmedWork)
    let snapshot = try harness.store.read()
    XCTAssertNil(snapshot.rounds[0].armedAt)
    XCTAssertEqual(
      snapshot.rounds[0].shares[0].status,
      .expiredAwaitingReconciliation
    )
    XCTAssertEqual(snapshot.receipts.count, 1)
    XCTAssertEqual(snapshot.receipts[0].outcome, .expired)
    XCTAssertNil(snapshot.receipts[0].url)
  }

  // MARK: - Status polling

  func testStatusPollConfirmationRecordsAReceipt() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let share = makeShare(sentToUrls: ["https://h1", "https://h2"])
    let round = makeRound(shares: [share])
    try stageAndArm(round, in: harness.store)

    var polled: [String] = []
    let afterGrace = now.addingTimeInterval(20)
    let outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { afterGrace },
      dependencies: makeDependencies(
        status: { url, roundId, shareIdHex in
          XCTAssertEqual(roundId, round.roundId)
          XCTAssertEqual(shareIdHex, share.shareIdHex)
          polled.append(url)
          return .success(
            VotingShareStatusResponse(
              status: url == "https://h2" ? "confirmed" : "pending"
            )
          )
        },
        post: { _, _ in
          XCTFail("a confirmed share must not be resubmitted")
          return .failure(.malformedResponse)
        }
      )
    )

    XCTAssertEqual(polled, ["https://h1", "https://h2"])
    XCTAssertEqual(
      outcome.transport,
      .processed(confirmed: 1, resubmitted: 0, expired: 0, failed: 0)
    )
    XCTAssertFalse(outcome.hasArmedUnconfirmedWork)
    let snapshot = try harness.store.read()
    XCTAssertEqual(
      snapshot.rounds[0].shares[0].status,
      .confirmedAwaitingReconciliation
    )
    XCTAssertEqual(snapshot.receipts.count, 1)
    XCTAssertEqual(snapshot.receipts[0].outcome, .confirmed)
    XCTAssertEqual(snapshot.receipts[0].url, "https://h2")
  }

  // MARK: - Resubmission

  func testOverdueResubmitUnionsSentUrlsAndStaysUnconfirmed() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    // base = nowSeconds, vote end = base + 400 -> overdue threshold 100.
    let share = makeShare(sentToUrls: ["https://h1"])
    let round = makeRound(voteEndSeconds: nowSeconds + 400, shares: [share])
    try stageAndArm(round, in: harness.store)

    var posted: [String] = []
    let overdue = now.addingTimeInterval(150)
    let outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { overdue },
      dependencies: makeDependencies(
        status: { _, _, _ in
          .success(VotingShareStatusResponse(status: "pending"))
        },
        post: { url, body in
          XCTAssertEqual(body, share.recoveryBodyJson)
          posted.append(url)
          return .success(())
        }
      )
    )

    // Unsent helpers are tried first; the first acceptance ends the pass.
    XCTAssertEqual(posted.count, 1)
    XCTAssertTrue(["https://h2", "https://h3"].contains(posted[0]))
    XCTAssertEqual(
      outcome.transport,
      .processed(confirmed: 0, resubmitted: 1, expired: 0, failed: 0)
    )
    let snapshot = try harness.store.read()
    let updated = snapshot.rounds[0].shares[0]
    // Accepted resubmission is NOT confirmation: the share stays armed and the
    // accepting helper joins the status-poll set.
    XCTAssertEqual(updated.status, .armed)
    XCTAssertEqual(updated.attemptCount, 0)
    XCTAssertNil(updated.nextAttemptAt)
    XCTAssertEqual(updated.sentToUrls, ["https://h1", posted[0]])
    XCTAssertEqual(snapshot.receipts.count, 1)
    XCTAssertEqual(snapshot.receipts[0].outcome, .resubmitted)
    XCTAssertEqual(snapshot.receipts[0].url, posted[0])
    XCTAssertTrue(outcome.hasArmedUnconfirmedWork)
  }

  func testRetryLadderAppliesOnTotalResubmitFailure() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let share = makeShare()
    let round = makeRound(voteEndSeconds: nowSeconds + 400, shares: [share])
    try stageAndArm(round, in: harness.store)

    let failingDependencies = makeDependencies(
      status: { _, _, _ in .success(VotingShareStatusResponse(status: "pending")) },
      post: { _, _ in .failure(.invalidHTTPStatus(503)) }
    )

    let overdue = now.addingTimeInterval(150)
    var outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { overdue },
      dependencies: failingDependencies
    )
    XCTAssertEqual(
      outcome.transport,
      .processed(confirmed: 0, resubmitted: 0, expired: 0, failed: 1)
    )
    var updated = try harness.store.read().rounds[0].shares[0]
    XCTAssertEqual(updated.status, .armed)
    XCTAssertEqual(updated.attemptCount, 1)
    XCTAssertEqual(updated.nextAttemptAt, overdue.addingTimeInterval(60))
    XCTAssertNotNil(updated.lastError)

    // Inside the retry gate nothing is attempted.
    outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { overdue.addingTimeInterval(30) },
      dependencies: makeDependencies(
        status: { _, _, _ in .success(VotingShareStatusResponse(status: "pending")) },
        post: { _, _ in
          XCTFail("the retry gate must block this attempt")
          return .failure(.malformedResponse)
        }
      )
    )
    XCTAssertEqual(
      outcome.transport,
      .processed(confirmed: 0, resubmitted: 0, expired: 0, failed: 0)
    )

    // Past the gate the second failure climbs the ladder to five minutes.
    let secondAttempt = overdue.addingTimeInterval(61)
    outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { secondAttempt },
      dependencies: failingDependencies
    )
    updated = try harness.store.read().rounds[0].shares[0]
    XCTAssertEqual(updated.attemptCount, 2)
    XCTAssertEqual(updated.nextAttemptAt, secondAttempt.addingTimeInterval(5 * 60))
  }

  func testResubmitCutoffBlocksLateResubmission() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let share = makeShare()
    let round = makeRound(voteEndSeconds: nowSeconds + 400, shares: [share])
    try stageAndArm(round, in: harness.store)

    // Five seconds before the vote end is inside the ten-second cutoff.
    let nearEnd = now.addingTimeInterval(395)
    let outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: harness.store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { nearEnd },
      dependencies: makeDependencies(
        status: { _, _, _ in .success(VotingShareStatusResponse(status: "pending")) },
        post: { _, _ in
          XCTFail("the resubmit cutoff must block this attempt")
          return .failure(.malformedResponse)
        }
      )
    )

    XCTAssertEqual(
      outcome.transport,
      .processed(confirmed: 0, resubmitted: 0, expired: 0, failed: 0)
    )
    XCTAssertEqual(try harness.store.read().rounds[0].shares[0].status, .armed)
  }

  // MARK: - Recovery and receipts

  func testInterruptedSubmittingRecoversWithBackoff() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let share = makeShare()
    let round = makeRound(shares: [share])
    try snapshot.stage(round, prune: false)
    try snapshot.armRound(
      roundKey: round.roundKey,
      expectedDigests: digests(round),
      at: now
    )
    try snapshot.beginSubmission(
      roundKey: round.roundKey,
      shareKey: share.shareKey,
      at: now
    )

    snapshot.recoverInterruptedSubmissions(at: now)

    let recovered = snapshot.rounds[0].shares[0]
    XCTAssertEqual(recovered.status, .armed)
    XCTAssertEqual(recovered.attemptCount, 1)
    XCTAssertEqual(recovered.nextAttemptAt, now.addingTimeInterval(60))
    XCTAssertEqual(
      recovered.lastError,
      "The previous resubmission outcome is unknown."
    )
  }

  func testReceiptAckPrunesSharesAndDropsEmptyRounds() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let share = makeShare(sentToUrls: ["https://h1"])
    let round = makeRound(shares: [share])
    try snapshot.stage(round, prune: false)
    try snapshot.armRound(
      roundKey: round.roundKey,
      expectedDigests: digests(round),
      at: now
    )
    // A resubmitted receipt first: acknowledging it must not touch the share.
    try snapshot.beginSubmission(
      roundKey: round.roundKey,
      shareKey: share.shareKey,
      at: now
    )
    try snapshot.recordResubmitted(
      roundKey: round.roundKey,
      shareKey: share.shareKey,
      url: "https://h2",
      at: now
    )
    let resubmittedReceiptId = snapshot.receipts[0].receiptId
    snapshot.acknowledgeReceipts([resubmittedReceiptId])
    XCTAssertEqual(snapshot.rounds.count, 1)
    XCTAssertEqual(snapshot.rounds[0].shares[0].status, .armed)
    XCTAssertTrue(snapshot.receipts.isEmpty)

    try snapshot.recordConfirmed(
      roundKey: round.roundKey,
      shareKey: share.shareKey,
      url: "https://h2",
      at: now
    )
    let confirmedReceiptId = snapshot.receipts[0].receiptId
    snapshot.acknowledgeReceipts([confirmedReceiptId])

    XCTAssertTrue(snapshot.receipts.isEmpty)
    XCTAssertTrue(snapshot.rounds.isEmpty)
  }

  func testRevokeAccountScopesToTheAccount() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let mine = makeRound(account: "account-a", shares: [makeShare()])
    let other = makeRound(account: "account-b", shares: [makeShare()])
    try snapshot.stage(mine, prune: false)
    try snapshot.stage(other, prune: false)

    // Give both rounds a receipt via expiry after the vote end.
    for round in [mine, other] {
      try snapshot.armRound(
        roundKey: round.roundKey,
        expectedDigests: digests(round),
        at: now
      )
    }
    _ = snapshot.expireEndedRounds(
      at: Date(timeIntervalSince1970: TimeInterval(mine.voteEndSeconds + 1))
    )
    XCTAssertEqual(snapshot.receipts.count, 2)

    snapshot.revoke(network: "test", accountUuid: "account-a")

    XCTAssertEqual(snapshot.rounds.map(\.accountUuid), ["account-b"])
    XCTAssertEqual(snapshot.receipts.count, 1)
    XCTAssertTrue(snapshot.receipts[0].roundKey.hasPrefix("test:account-b:"))
  }

  func testStoreRemoveAllClearsEveryRound() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    try stageAndArm(makeRound(shares: [makeShare()]), in: harness.store)

    try harness.store.removeAll()

    let snapshot = try harness.store.read()
    XCTAssertTrue(snapshot.rounds.isEmpty)
    XCTAssertTrue(snapshot.receipts.isEmpty)
  }

  // MARK: - Store

  func testUnsupportedSnapshotVersionFailsClosed() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let future = Data(#"{"version":2,"rounds":[],"receipts":[]}"#.utf8)
    let sealed = try BackgroundVotingShareOutboxCipher.seal(
      future,
      keyData: harness.keyData
    )
    try FileManager.default.createDirectory(
      at: harness.directory,
      withIntermediateDirectories: true
    )
    try sealed.write(to: harness.fileURL)

    XCTAssertThrowsError(try harness.store.read()) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxStoreError,
        .unsupportedVersion
      )
    }
  }

  func testTemporarilyUnavailableKeychainSurfacesDistinctly() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = BackgroundVotingShareOutboxStore(
      fileURL: directory.appendingPathComponent("share-outbox.bin"),
      keyProvider: {
        throw BackgroundVotingShareOutboxStoreError.temporarilyUnavailable
      }
    )

    XCTAssertThrowsError(
      try store.update { snapshot in
        try snapshot.stage(self.makeRound(shares: [self.makeShare()]), prune: false)
      }
    ) { error in
      XCTAssertEqual(
        error as? BackgroundVotingShareOutboxStoreError,
        .temporarilyUnavailable
      )
    }

    let outcome = BackgroundVotingShareOutboxRunner.runOnce(
      store: store,
      cancellation: BackgroundVotingShareCancellation(),
      clock: { self.now },
      dependencies: makeDependencies(
        status: { _, _, _ in .failure(.malformedResponse) },
        post: { _, _ in .failure(.malformedResponse) }
      )
    )
    XCTAssertEqual(outcome.transport, .temporarilyUnavailable)
  }

  // MARK: - Scheduling

  func testNextActionableDateComputation() throws {
    var snapshot = BackgroundVotingShareOutboxSnapshot()
    let voteEnd = nowSeconds + 400
    let round = makeRound(voteEndSeconds: voteEnd, shares: [makeShare()])
    try snapshot.stage(round, prune: false)
    try snapshot.armRound(
      roundKey: round.roundKey,
      expectedDigests: digests(round),
      at: now
    )

    // Before the grace period: the status check is the next action.
    XCTAssertEqual(
      snapshot.nextActionableDate(at: now.addingTimeInterval(2)),
      now.addingTimeInterval(10)
    )
    // After the status check but before overdue (threshold 100): overdue next.
    XCTAssertEqual(
      snapshot.nextActionableDate(at: now.addingTimeInterval(20)),
      now.addingTimeInterval(100)
    )
    // A pending retry gate wins once overdue has passed.
    try snapshot.beginSubmission(
      roundKey: round.roundKey,
      shareKey: round.shares[0].shareKey,
      at: now.addingTimeInterval(150)
    )
    try snapshot.recordResubmitFailure(
      roundKey: round.roundKey,
      shareKey: round.shares[0].shareKey,
      error: "helper refused",
      at: now.addingTimeInterval(150)
    )
    XCTAssertEqual(
      snapshot.nextActionableDate(at: now.addingTimeInterval(151)),
      now.addingTimeInterval(150 + 60)
    )
    // Past every trigger the rolling re-poll applies, capped at the vote end.
    let nearEnd = now.addingTimeInterval(395)
    XCTAssertEqual(
      snapshot.nextActionableDate(at: nearEnd),
      Date(timeIntervalSince1970: TimeInterval(voteEnd))
    )
    // No armed work, no next action.
    snapshot.revoke(network: "test", accountUuid: "account-a")
    XCTAssertNil(snapshot.nextActionableDate(at: now))
  }

  // MARK: - Channel decoding

  func testChannelStageComputesDigestsNatively() throws {
    let harness = try makeStoreHarness()
    defer { harness.cleanup() }
    let body = #"{"share":"payload-0"}"#
    let arguments: [String: Any] = [
      "network": "test",
      "accountUuid": "account-a",
      "roundId": "ABCD12",
      "voteEndSeconds": NSNumber(value: nowSeconds + 400),
      "helperUrls": ["https://h1", "https://h2"],
      "prune": false,
      "shares": [
        [
          "bundleIndex": NSNumber(value: 0),
          "proposalId": NSNumber(value: 7),
          "shareIndex": NSNumber(value: 0),
          "shareIdHex": "AA01",
          "submitAtSeconds": NSNumber(value: nowSeconds),
          "createdAtSeconds": NSNumber(value: nowSeconds),
          "recoveryBodyJson": body,
          "sentToUrls": ["https://h1"],
        ]
      ],
    ]

    let digestsByShareKey = try BackgroundVotingShareChannel.stageShareRound(
      arguments: arguments,
      store: harness.store
    )

    XCTAssertEqual(
      digestsByShareKey,
      ["0:7:0": BackgroundVotingShare.digestHex(Data(body.utf8))]
    )
    let snapshot = try harness.store.read()
    // Identifiers are normalized to lowercase hex on the way in.
    XCTAssertEqual(snapshot.rounds[0].roundId, "abcd12")
    XCTAssertEqual(snapshot.rounds[0].shares[0].shareIdHex, "aa01")
    XCTAssertEqual(snapshot.rounds[0].roundKey, "test:account-a:abcd12")

    try BackgroundVotingShareChannel.armShareRound(
      arguments: [
        "roundKey": "test:account-a:abcd12",
        "expectedDigests": digestsByShareKey,
      ],
      store: harness.store
    )
    XCTAssertTrue(
      try BackgroundVotingShareChannel.hasShareRound(
        arguments: [
          "roundKey": "test:account-a:abcd12",
          "expectedShareKeys": ["0:7:0"],
        ],
        store: harness.store
      )
    )
    let receipts = try BackgroundVotingShareChannel.listShareReceipts(
      store: harness.store
    )
    XCTAssertTrue(receipts.isEmpty)
  }

  // MARK: - Helpers

  private func makeShare(
    bundleIndex: UInt32 = 0,
    proposalId: UInt32 = 7,
    shareIndex: UInt32 = 0,
    shareIdHex: String? = nil,
    submitAtSeconds: UInt64? = nil,
    createdAtSeconds: UInt64? = nil,
    body: String? = nil,
    sentToUrls: [String] = ["https://h1"]
  ) -> BackgroundVotingShare {
    BackgroundVotingShare(
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      shareIdHex: shareIdHex ?? String(format: "ab%02x", shareIndex),
      submitAtSeconds: submitAtSeconds ?? nowSeconds,
      createdAtSeconds: createdAtSeconds ?? nowSeconds,
      recoveryBodyJson: Data((body ?? #"{"share":"payload-\#(shareIndex)"}"#).utf8),
      sentToUrls: sentToUrls
    )
  }

  private func makeRound(
    account: String = "account-a",
    roundId: String = "abcd12",
    voteEndSeconds: UInt64? = nil,
    shares: [BackgroundVotingShare]
  ) -> BackgroundVotingShareRound {
    BackgroundVotingShareRound(
      network: "test",
      accountUuid: account,
      roundId: roundId,
      voteEndSeconds: voteEndSeconds ?? (nowSeconds + 400),
      helperUrls: ["https://h1", "https://h2", "https://h3"],
      createdAt: now,
      shares: shares
    )
  }

  private func digests(_ round: BackgroundVotingShareRound) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: round.shares.map { ($0.shareKey, $0.payloadDigestHex) }
    )
  }

  private func makeDependencies(
    status: @escaping (String, String, String) -> Result<
      VotingShareStatusResponse, VotingShareHelperClientError
    >,
    post: @escaping (String, Data) -> Result<Void, VotingShareHelperClientError>
  ) -> BackgroundVotingShareOutboxRunnerDependencies {
    BackgroundVotingShareOutboxRunnerDependencies(
      getShareStatus: { url, roundId, shareIdHex, _ in status(url, roundId, shareIdHex) },
      postShare: { url, body, _ in post(url, body) }
    )
  }

  private func makeStoreHarness() throws -> VotingShareStoreHarness {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let keyData = Data(repeating: 0xCD, count: 32)
    let fileURL = directory.appendingPathComponent("share-outbox.bin")
    let store = BackgroundVotingShareOutboxStore(
      fileURL: fileURL,
      keyProvider: { keyData }
    )
    return VotingShareStoreHarness(
      directory: directory,
      fileURL: fileURL,
      keyData: keyData,
      store: store
    )
  }

  private func stageAndArm(
    _ round: BackgroundVotingShareRound,
    in store: BackgroundVotingShareOutboxStore
  ) throws {
    _ = try store.update { snapshot in
      try snapshot.stage(round, prune: false)
      try snapshot.armRound(
        roundKey: round.roundKey,
        expectedDigests: digests(round),
        at: now
      )
    }
  }
}

private struct VotingShareStoreHarness {
  let directory: URL
  let fileURL: URL
  let keyData: Data
  let store: BackgroundVotingShareOutboxStore

  func cleanup() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct SeededVotingRandom: RandomNumberGenerator {
  var values: [UInt64]

  mutating func next() -> UInt64 {
    values.isEmpty ? UInt64.max / 2 : values.removeFirst()
  }
}
