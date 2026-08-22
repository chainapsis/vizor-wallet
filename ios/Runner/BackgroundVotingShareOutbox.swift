import CryptoKit
import Foundation

// The voting share outbox may only GET share-status and POST exact staged
// payloads to helper servers; it never reads wallet or sidecar state and never
// calls into Dart or Rust.
//
// The foreground stages the exact HTTP payload bytes and the metadata needed to
// time them; the background lane confirms or resubmits those bytes verbatim and
// records receipts for foreground reconciliation. Nothing in this lane can
// construct, alter, or re-derive a share.

enum BackgroundVotingShareOutboxError: Error, Equatable {
  case invalidRound
  case conflictingRound
  case roundNotFound
  case shareNotFound
  case invalidArmRequest
  case invalidTransition
}

enum BackgroundVotingShareStatus: String, Codable, Equatable {
  case staged
  case armed
  case submitting
  case confirmedAwaitingReconciliation
  case expiredAwaitingReconciliation
}

enum BackgroundVotingShareReceiptOutcome: String, Codable, Equatable {
  case confirmed
  case resubmitted
  case expired
}

/// Timing policy for voting share confirmation and resubmission.
///
/// Mirror of the Rust crate `zcash_voting::share_policy` — keep the constants
/// and formulas in lockstep with that crate; the foreground submission path
/// runs the Rust original and this lane must reach the same decisions.
enum BackgroundVotingSharePolicy {
  /// SHARE_STATUS_CHECK_GRACE_SECONDS.
  static let statusCheckGraceSeconds: UInt64 = 10
  /// SHARE_MIN_OVERDUE_THRESHOLD_SECONDS.
  static let minOverdueThresholdSeconds: UInt64 = 30
  /// SHARE_MAX_OVERDUE_THRESHOLD_SECONDS.
  static let maxOverdueThresholdSeconds: UInt64 = 3600
  /// SHARE_RESUBMIT_CUTOFF_SECONDS.
  static let resubmitCutoffSeconds: UInt64 = 10

  /// Rolling re-poll interval once every policy trigger for a share is in the
  /// past but the vote has not ended. This is scheduling policy of the iOS
  /// lane (BGTask wakes are coarse), not part of the Rust crate.
  static let statusRepollInterval: TimeInterval = 10 * 60

  static func submissionBaseSeconds(
    submitAtSeconds: UInt64,
    createdAtSeconds: UInt64
  ) -> UInt64 {
    submitAtSeconds > 0 ? submitAtSeconds : createdAtSeconds
  }

  static func statusCheckAtSeconds(baseSeconds: UInt64) -> UInt64 {
    baseSeconds.votingSaturatingAdd(statusCheckGraceSeconds)
  }

  static func overdueThresholdSeconds(
    baseSeconds: UInt64,
    voteEndSeconds: UInt64
  ) -> UInt64 {
    let window = voteEndSeconds > baseSeconds ? (voteEndSeconds - baseSeconds) / 4 : 0
    return min(max(window, minOverdueThresholdSeconds), maxOverdueThresholdSeconds)
  }

  static func overdueAtSeconds(
    baseSeconds: UInt64,
    voteEndSeconds: UInt64
  ) -> UInt64 {
    baseSeconds.votingSaturatingAdd(
      overdueThresholdSeconds(baseSeconds: baseSeconds, voteEndSeconds: voteEndSeconds)
    )
  }

  static func allowsResubmission(
    voteEndSeconds: UInt64,
    nowSeconds: UInt64
  ) -> Bool {
    voteEndSeconds > nowSeconds.votingSaturatingAdd(resubmitCutoffSeconds)
  }

  /// Mirror of `resubmission_server_order`: shuffled not-yet-sent helpers
  /// first, then shuffled already-sent helpers. Only configured helpers are
  /// candidates; stale entries in `sentToUrls` never become targets.
  static func resubmissionServerOrder(
    helperUrls: [String],
    sentToUrls: [String],
    random: inout some RandomNumberGenerator
  ) -> [String] {
    var seen = Set<String>()
    let candidates = helperUrls.filter { seen.insert($0).inserted }
    let sent = Set(sentToUrls)
    var unsent = candidates.filter { !sent.contains($0) }
    var alreadySent = candidates.filter { sent.contains($0) }
    unsent.shuffle(using: &random)
    alreadySent.shuffle(using: &random)
    return unsent + alreadySent
  }

  /// Retry cadence after a resubmission pass fails against every helper.
  /// Same ladder as the Ironwood migration outbox.
  static func retryDelay(attemptCount: UInt32) -> TimeInterval {
    switch attemptCount {
    case 0, 1: return 60
    case 2: return 5 * 60
    case 3: return 15 * 60
    default: return 60 * 60
    }
  }
}

struct BackgroundVotingShare: Codable, Equatable {
  let bundleIndex: UInt32
  let proposalId: UInt32
  let shareIndex: UInt32
  let shareIdHex: String
  let submitAtSeconds: UInt64
  let createdAtSeconds: UInt64
  /// The exact POST body, pre-rendered by Dart. Transmitted verbatim.
  let recoveryBodyJson: Data
  let payloadDigestHex: String
  var sentToUrls: [String]
  var status: BackgroundVotingShareStatus
  var attemptCount: UInt32
  var nextAttemptAt: Date?
  var lastError: String?

  var shareKey: String { "\(bundleIndex):\(proposalId):\(shareIndex)" }

  var submissionBaseSeconds: UInt64 {
    BackgroundVotingSharePolicy.submissionBaseSeconds(
      submitAtSeconds: submitAtSeconds,
      createdAtSeconds: createdAtSeconds
    )
  }

  var statusCheckAt: Date {
    Date(
      timeIntervalSince1970: TimeInterval(
        BackgroundVotingSharePolicy.statusCheckAtSeconds(
          baseSeconds: submissionBaseSeconds
        )
      )
    )
  }

  func overdueAt(voteEndSeconds: UInt64) -> Date {
    Date(
      timeIntervalSince1970: TimeInterval(
        BackgroundVotingSharePolicy.overdueAtSeconds(
          baseSeconds: submissionBaseSeconds,
          voteEndSeconds: voteEndSeconds
        )
      )
    )
  }

  init(
    bundleIndex: UInt32,
    proposalId: UInt32,
    shareIndex: UInt32,
    shareIdHex: String,
    submitAtSeconds: UInt64,
    createdAtSeconds: UInt64,
    recoveryBodyJson: Data,
    sentToUrls: [String]
  ) {
    self.bundleIndex = bundleIndex
    self.proposalId = proposalId
    self.shareIndex = shareIndex
    self.shareIdHex = shareIdHex.lowercased()
    self.submitAtSeconds = submitAtSeconds
    self.createdAtSeconds = createdAtSeconds
    self.recoveryBodyJson = recoveryBodyJson
    payloadDigestHex = Self.digestHex(recoveryBodyJson)
    self.sentToUrls = sentToUrls
    status = .staged
    attemptCount = 0
    nextAttemptAt = nil
    lastError = nil
  }

  static func digestHex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct BackgroundVotingShareRound: Codable, Equatable {
  let network: String
  let accountUuid: String
  /// Normalized lowercase hex; the manifest binding half of `roundKey`.
  let roundId: String
  var voteEndSeconds: UInt64
  /// Configured helper base URLs at staging time.
  var helperUrls: [String]
  let createdAt: Date
  var armedAt: Date?
  var shares: [BackgroundVotingShare]

  var roundKey: String { "\(network):\(accountUuid):\(roundId)" }

  init(
    network: String,
    accountUuid: String,
    roundId: String,
    voteEndSeconds: UInt64,
    helperUrls: [String],
    createdAt: Date,
    shares: [BackgroundVotingShare]
  ) {
    self.network = network
    self.accountUuid = accountUuid
    self.roundId = roundId.lowercased()
    self.voteEndSeconds = voteEndSeconds
    self.helperUrls = helperUrls
    self.createdAt = createdAt
    armedAt = nil
    self.shares = shares
  }
}

struct BackgroundVotingShareReceipt: Codable, Equatable {
  let receiptId: String
  let roundKey: String
  // The round scope is carried explicitly (not only inside roundKey) because
  // the Dart reconciler addresses sidecar writes by these fields.
  let network: String
  let accountUuid: String
  let roundId: String
  let bundleIndex: UInt32
  let proposalId: UInt32
  let shareIndex: UInt32
  let shareIdHex: String
  let outcome: BackgroundVotingShareReceiptOutcome
  /// The helper that confirmed the share or accepted the resubmission.
  let url: String?
  let recordedAt: Date
}

/// One due share the runner should act on, with the round context needed to
/// poll and resubmit it. The embedded share is the state observed at selection
/// time; the runner re-reads before acting.
struct BackgroundVotingShareWorkItem: Equatable {
  let roundKey: String
  let shareKey: String
  let roundId: String
  let voteEndSeconds: UInt64
  let helperUrls: [String]
  let share: BackgroundVotingShare
}

enum BackgroundVotingShareTransportOutcome: Equatable {
  case noWork
  case processed(confirmed: Int, resubmitted: Int, expired: Int, failed: Int)
  case temporarilyUnavailable
  case cancelled
  case failed(String)
}

struct BackgroundVotingShareOutboxRunResult: Equatable {
  let transport: BackgroundVotingShareTransportOutcome
  /// Earliest moment any remaining armed share needs attention; the manager
  /// re-arms the BGTask no earlier than this (and no earlier than its floor).
  let nextActionableDate: Date?
  let hasArmedUnconfirmedWork: Bool
}

struct BackgroundVotingShareOutboxSnapshot: Codable, Equatable {
  static let currentVersion = 1

  var version = currentVersion
  var rounds: [BackgroundVotingShareRound] = []
  var receipts: [BackgroundVotingShareReceipt] = []

  var hasArmedUnconfirmedWork: Bool {
    rounds.contains { round in
      round.armedAt != nil
        && round.shares.contains {
          $0.status == .armed || $0.status == .submitting
        }
    }
  }

  /// Idempotent merge keyed by `roundKey`/`shareKey`.
  ///
  /// A conflicting stage — the same share key with a different payload digest,
  /// share id, or timing base — is rejected, mirroring the Ironwood outbox's
  /// conflicting-batch handling. With `prune`, shares absent from the incoming
  /// list are removed; surviving shares keep their runner-side progress and
  /// union their `sentToUrls`. A share currently `submitting` is never
  /// changed: pruning it away or restaging it with different identity fails,
  /// and a matching restage leaves it untouched.
  mutating func stage(_ round: BackgroundVotingShareRound, prune: Bool) throws {
    guard !round.network.isEmpty,
      !round.accountUuid.isEmpty,
      Self.isLowercaseHex(round.roundId),
      round.voteEndSeconds > 0,
      !round.helperUrls.isEmpty,
      round.helperUrls.allSatisfy({ !$0.isEmpty }),
      !round.shares.isEmpty,
      round.armedAt == nil,
      Set(round.shares.map(\.shareKey)).count == round.shares.count,
      Set(round.shares.map(\.shareIdHex)).count == round.shares.count,
      round.shares.allSatisfy({
        Self.isLowercaseHex($0.shareIdHex)
          && !$0.recoveryBodyJson.isEmpty
          && $0.payloadDigestHex == BackgroundVotingShare.digestHex($0.recoveryBodyJson)
          && $0.createdAtSeconds > 0
          && $0.status == .staged
          && $0.attemptCount == 0
          && $0.nextAttemptAt == nil
      })
    else {
      throw BackgroundVotingShareOutboxError.invalidRound
    }

    guard let roundIndex = rounds.firstIndex(where: { $0.roundKey == round.roundKey })
    else {
      rounds.append(round)
      return
    }

    let existing = rounds[roundIndex]
    let hasSubmittingShare = existing.shares.contains { $0.status == .submitting }
    if existing.voteEndSeconds != round.voteEndSeconds
      || existing.helperUrls != round.helperUrls
    {
      // Round-level config is staging policy, not identity, but changing it
      // under an in-flight resubmission would change which helpers that
      // attempt is judged against.
      guard !hasSubmittingShare else {
        throw BackgroundVotingShareOutboxError.conflictingRound
      }
      rounds[roundIndex].voteEndSeconds = round.voteEndSeconds
      rounds[roundIndex].helperUrls = round.helperUrls
    }

    let incomingKeys = Set(round.shares.map(\.shareKey))
    if prune {
      guard
        !existing.shares.contains(where: {
          $0.status == .submitting && !incomingKeys.contains($0.shareKey)
        })
      else {
        throw BackgroundVotingShareOutboxError.conflictingRound
      }
      rounds[roundIndex].shares.removeAll { !incomingKeys.contains($0.shareKey) }
    }

    for incoming in round.shares {
      if let existingIndex = rounds[roundIndex].shares.firstIndex(where: {
        $0.shareKey == incoming.shareKey
      }) {
        let existingShare = rounds[roundIndex].shares[existingIndex]
        guard existingShare.shareIdHex == incoming.shareIdHex,
          existingShare.payloadDigestHex == incoming.payloadDigestHex,
          existingShare.submitAtSeconds == incoming.submitAtSeconds,
          existingShare.createdAtSeconds == incoming.createdAtSeconds
        else {
          throw BackgroundVotingShareOutboxError.conflictingRound
        }
        // A submitting share is mid-attempt; even a sentToUrls union would
        // race with the outcome the runner is about to record.
        guard existingShare.status != .submitting else { continue }
        for url in incoming.sentToUrls
        where !rounds[roundIndex].shares[existingIndex].sentToUrls.contains(url) {
          rounds[roundIndex].shares[existingIndex].sentToUrls.append(url)
        }
        continue
      }
      if rounds[roundIndex].shares.contains(where: {
        $0.shareIdHex == incoming.shareIdHex
      }) {
        throw BackgroundVotingShareOutboxError.conflictingRound
      }
      rounds[roundIndex].shares.append(incoming)
    }
  }

  /// Stage-to-arm handshake: every expected digest must match the stored share
  /// before anything is armed, so the background lane only ever transmits the
  /// exact bytes the caller believes it staged.
  mutating func armRound(
    roundKey: String,
    expectedDigests: [String: String],
    at date: Date
  ) throws {
    guard let roundIndex = rounds.firstIndex(where: { $0.roundKey == roundKey }) else {
      throw BackgroundVotingShareOutboxError.roundNotFound
    }
    guard !expectedDigests.isEmpty,
      expectedDigests.allSatisfy({ entry in
        rounds[roundIndex].shares.contains(where: {
          $0.shareKey == entry.key && $0.payloadDigestHex == entry.value
        })
      })
    else {
      throw BackgroundVotingShareOutboxError.invalidArmRequest
    }
    if rounds[roundIndex].armedAt == nil { rounds[roundIndex].armedAt = date }
    for shareIndex in rounds[roundIndex].shares.indices {
      if expectedDigests[rounds[roundIndex].shares[shareIndex].shareKey] != nil,
        rounds[roundIndex].shares[shareIndex].status == .staged
      {
        rounds[roundIndex].shares[shareIndex].status = .armed
      }
    }
  }

  /// Whether the round exists and holds every expected share. A round that
  /// exists but is missing shares answers false rather than throwing: staging
  /// is an idempotent merge, so the caller's recovery is simply to restage.
  func hasRound(roundKey: String, expectedShareKeys: Set<String>) throws -> Bool {
    guard !expectedShareKeys.isEmpty else {
      throw BackgroundVotingShareOutboxError.invalidArmRequest
    }
    guard let round = rounds.first(where: { $0.roundKey == roundKey }) else {
      return false
    }
    return expectedShareKeys.isSubset(of: Set(round.shares.map(\.shareKey)))
  }

  /// Returns interrupted `submitting` shares to `armed` with retry backoff.
  /// The interrupted POST's outcome is unknown, so the attempt is counted.
  mutating func recoverInterruptedSubmissions(at date: Date) {
    for roundIndex in rounds.indices {
      for shareIndex in rounds[roundIndex].shares.indices
      where rounds[roundIndex].shares[shareIndex].status == .submitting {
        var share = rounds[roundIndex].shares[shareIndex]
        share.status = .armed
        share.attemptCount += 1
        share.nextAttemptAt = date.addingTimeInterval(
          BackgroundVotingSharePolicy.retryDelay(attemptCount: share.attemptCount)
        )
        share.lastError = "The previous resubmission outcome is unknown."
        rounds[roundIndex].shares[shareIndex] = share
      }
    }
  }

  /// Moves every unconfirmed share of an ended round to
  /// `expiredAwaitingReconciliation`, records `expired` receipts, and disarms
  /// the round. Returns how many shares expired.
  mutating func expireEndedRounds(at date: Date) -> Int {
    let nowSeconds = UInt64(max(0, date.timeIntervalSince1970))
    var expiredCount = 0
    for roundIndex in rounds.indices {
      guard nowSeconds >= rounds[roundIndex].voteEndSeconds else { continue }
      for shareIndex in rounds[roundIndex].shares.indices {
        let share = rounds[roundIndex].shares[shareIndex]
        switch share.status {
        case .staged, .armed, .submitting:
          rounds[roundIndex].shares[shareIndex].status = .expiredAwaitingReconciliation
          rounds[roundIndex].shares[shareIndex].nextAttemptAt = nil
          expiredCount += 1
          upsertReceipt(
            makeReceipt(
              round: rounds[roundIndex],
              share: rounds[roundIndex].shares[shareIndex],
              outcome: .expired,
              url: nil,
              at: date
            )
          )
        case .confirmedAwaitingReconciliation, .expiredAwaitingReconciliation:
          continue
        }
      }
      rounds[roundIndex].armedAt = nil
    }
    return expiredCount
  }

  /// Every armed share whose status poll or resubmission is due, in due order.
  func dueShareWorkItems(at date: Date) -> [BackgroundVotingShareWorkItem] {
    let nowSeconds = UInt64(max(0, date.timeIntervalSince1970))
    var items: [BackgroundVotingShareWorkItem] = []
    for round in rounds where round.armedAt != nil && nowSeconds < round.voteEndSeconds {
      for share in round.shares where share.status == .armed {
        let pollDue = date >= share.statusCheckAt && !share.sentToUrls.isEmpty
        let resubmitDue =
          date >= share.overdueAt(voteEndSeconds: round.voteEndSeconds)
          && (share.nextAttemptAt == nil || date >= share.nextAttemptAt!)
          && BackgroundVotingSharePolicy.allowsResubmission(
            voteEndSeconds: round.voteEndSeconds,
            nowSeconds: nowSeconds
          )
        guard pollDue || resubmitDue else { continue }
        items.append(
          BackgroundVotingShareWorkItem(
            roundKey: round.roundKey,
            shareKey: share.shareKey,
            roundId: round.roundId,
            voteEndSeconds: round.voteEndSeconds,
            helperUrls: round.helperUrls,
            share: share
          )
        )
      }
    }
    return items.sorted {
      ($0.share.submissionBaseSeconds, $0.roundKey, $0.shareKey)
        < ($1.share.submissionBaseSeconds, $1.roundKey, $1.shareKey)
    }
  }

  mutating func beginSubmission(
    roundKey: String,
    shareKey: String,
    at date: Date
  ) throws {
    let location = try shareLocation(roundKey: roundKey, shareKey: shareKey)
    guard rounds[location.round].shares[location.share].status == .armed else {
      throw BackgroundVotingShareOutboxError.invalidTransition
    }
    rounds[location.round].shares[location.share].status = .submitting
  }

  mutating func recordConfirmed(
    roundKey: String,
    shareKey: String,
    url: String,
    at date: Date
  ) throws {
    let location = try shareLocation(roundKey: roundKey, shareKey: shareKey)
    guard rounds[location.round].shares[location.share].status == .armed else {
      throw BackgroundVotingShareOutboxError.invalidTransition
    }
    rounds[location.round].shares[location.share].status =
      .confirmedAwaitingReconciliation
    rounds[location.round].shares[location.share].nextAttemptAt = nil
    rounds[location.round].shares[location.share].lastError = nil
    upsertReceipt(
      makeReceipt(
        round: rounds[location.round],
        share: rounds[location.round].shares[location.share],
        outcome: .confirmed,
        url: url,
        at: date
      )
    )
  }

  /// An accepted resubmission goes back to `armed`, not confirmed —
  /// confirmation still comes from the status poll. The accepting helper joins
  /// `sentToUrls` so the next poll asks it, and the retry state resets.
  mutating func recordResubmitted(
    roundKey: String,
    shareKey: String,
    url: String,
    at date: Date
  ) throws {
    let location = try shareLocation(roundKey: roundKey, shareKey: shareKey)
    guard rounds[location.round].shares[location.share].status == .submitting else {
      throw BackgroundVotingShareOutboxError.invalidTransition
    }
    rounds[location.round].shares[location.share].status = .armed
    rounds[location.round].shares[location.share].attemptCount = 0
    rounds[location.round].shares[location.share].nextAttemptAt = nil
    rounds[location.round].shares[location.share].lastError = nil
    if !rounds[location.round].shares[location.share].sentToUrls.contains(url) {
      rounds[location.round].shares[location.share].sentToUrls.append(url)
    }
    upsertReceipt(
      makeReceipt(
        round: rounds[location.round],
        share: rounds[location.round].shares[location.share],
        outcome: .resubmitted,
        url: url,
        at: date
      )
    )
  }

  mutating func recordResubmitFailure(
    roundKey: String,
    shareKey: String,
    error: String,
    at date: Date
  ) throws {
    let location = try shareLocation(roundKey: roundKey, shareKey: shareKey)
    guard rounds[location.round].shares[location.share].status == .submitting else {
      throw BackgroundVotingShareOutboxError.invalidTransition
    }
    var share = rounds[location.round].shares[location.share]
    share.status = .armed
    share.attemptCount += 1
    share.nextAttemptAt = date.addingTimeInterval(
      BackgroundVotingSharePolicy.retryDelay(attemptCount: share.attemptCount)
    )
    share.lastError = error
    rounds[location.round].shares[location.share] = share
  }

  /// Restores a share when cancellation was observed before any POST began.
  /// A definite non-attempt takes no retry penalty.
  mutating func recordCancelledBeforeSubmission(
    roundKey: String,
    shareKey: String,
    error: String
  ) throws {
    let location = try shareLocation(roundKey: roundKey, shareKey: shareKey)
    guard rounds[location.round].shares[location.share].status == .submitting else {
      throw BackgroundVotingShareOutboxError.invalidTransition
    }
    rounds[location.round].shares[location.share].status = .armed
    rounds[location.round].shares[location.share].nextAttemptAt = nil
    rounds[location.round].shares[location.share].lastError = error
  }

  /// Prunes acknowledged receipts. A confirmed or expired receipt also retires
  /// its reconciled share; rounds emptied by that are dropped. Acknowledging a
  /// `resubmitted` receipt removes only the receipt — the share is still live.
  mutating func acknowledgeReceipts(_ receiptIds: Set<String>) {
    let acknowledged = receipts.filter { receiptIds.contains($0.receiptId) }
    receipts.removeAll { receiptIds.contains($0.receiptId) }
    let terminalKeys = Set(
      acknowledged
        .filter { $0.outcome == .confirmed || $0.outcome == .expired }
        .map { "\($0.roundKey):\($0.bundleIndex):\($0.proposalId):\($0.shareIndex)" }
    )
    for roundIndex in rounds.indices {
      let roundKey = rounds[roundIndex].roundKey
      rounds[roundIndex].shares.removeAll { share in
        (share.status == .confirmedAwaitingReconciliation
          || share.status == .expiredAwaitingReconciliation)
          && terminalKeys.contains("\(roundKey):\(share.shareKey)")
      }
    }
    rounds.removeAll { $0.shares.isEmpty }
  }

  mutating func revoke(network: String, accountUuid: String) {
    let scopePrefix = "\(network):\(accountUuid):"
    rounds.removeAll { $0.network == network && $0.accountUuid == accountUuid }
    receipts.removeAll { $0.roundKey.hasPrefix(scopePrefix) }
  }

  /// The earliest moment any armed share needs attention: the minimum of its
  /// future status check, overdue point, and retry gate, capped at the round's
  /// vote end (where the expiry pass takes over). A share past every trigger
  /// re-polls on the rolling interval.
  func nextActionableDate(at date: Date) -> Date? {
    let nowSeconds = UInt64(max(0, date.timeIntervalSince1970))
    var earliest: Date?
    for round in rounds where round.armedAt != nil {
      let voteEndDate = Date(
        timeIntervalSince1970: TimeInterval(round.voteEndSeconds)
      )
      for share in round.shares
      where share.status == .armed || share.status == .submitting {
        var candidates: [Date] = []
        if share.statusCheckAt > date { candidates.append(share.statusCheckAt) }
        if BackgroundVotingSharePolicy.allowsResubmission(
          voteEndSeconds: round.voteEndSeconds,
          nowSeconds: nowSeconds
        ) {
          let overdueAt = share.overdueAt(voteEndSeconds: round.voteEndSeconds)
          if overdueAt > date { candidates.append(overdueAt) }
          if let nextAttemptAt = share.nextAttemptAt, nextAttemptAt > date {
            candidates.append(nextAttemptAt)
          }
        }
        let candidate =
          candidates.min()
          ?? date.addingTimeInterval(BackgroundVotingSharePolicy.statusRepollInterval)
        let capped = min(candidate, voteEndDate)
        earliest = earliest.map { min($0, capped) } ?? capped
      }
    }
    return earliest
  }

  private func shareLocation(
    roundKey: String,
    shareKey: String
  ) throws -> (round: Int, share: Int) {
    guard let roundIndex = rounds.firstIndex(where: { $0.roundKey == roundKey }) else {
      throw BackgroundVotingShareOutboxError.roundNotFound
    }
    guard
      let shareIndex = rounds[roundIndex].shares.firstIndex(where: {
        $0.shareKey == shareKey
      })
    else {
      throw BackgroundVotingShareOutboxError.shareNotFound
    }
    return (roundIndex, shareIndex)
  }

  /// Receipt ids are `roundKey:shareKey:outcome`, so a repeated outcome (a
  /// second resubmission of the same share) replaces the standing receipt
  /// rather than duplicating its id.
  private mutating func upsertReceipt(_ receipt: BackgroundVotingShareReceipt) {
    if let index = receipts.firstIndex(where: { $0.receiptId == receipt.receiptId }) {
      receipts[index] = receipt
    } else {
      receipts.append(receipt)
    }
  }

  private func makeReceipt(
    round: BackgroundVotingShareRound,
    share: BackgroundVotingShare,
    outcome: BackgroundVotingShareReceiptOutcome,
    url: String?,
    at date: Date
  ) -> BackgroundVotingShareReceipt {
    BackgroundVotingShareReceipt(
      receiptId: "\(round.roundKey):\(share.shareKey):\(outcome.rawValue)",
      roundKey: round.roundKey,
      network: round.network,
      accountUuid: round.accountUuid,
      roundId: round.roundId,
      bundleIndex: share.bundleIndex,
      proposalId: share.proposalId,
      shareIndex: share.shareIndex,
      shareIdHex: share.shareIdHex,
      outcome: outcome,
      url: url,
      recordedAt: date
    )
  }

  private static func isLowercaseHex(_ value: String) -> Bool {
    !value.isEmpty
      && value.allSatisfy { character in
        character.isHexDigit && (!character.isLetter || character.isLowercase)
      }
  }
}

extension UInt64 {
  fileprivate func votingSaturatingAdd(_ other: UInt64) -> UInt64 {
    let (result, overflow) = addingReportingOverflow(other)
    return overflow ? UInt64.max : result
  }
}
