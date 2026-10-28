import CryptoKit
import Foundation

enum BackgroundMigrationOutboxError: Error, Equatable {
  case invalidBatch
  case conflictingBatch
  case batchNotFound
  case itemNotFound
  case invalidArmRequest
  case invalidTransition
  case invalidSchedule
}

enum BackgroundMigrationOutboxItemStatus: String, Codable, Equatable {
  case staged
  case armed
  case submitting
  case acceptedAwaitingReconciliation
  case rejectedAwaitingReconciliation
  case expiredAwaitingReconciliation
  case needsResignAwaitingReconciliation
}

enum BackgroundMigrationOutboxReceiptOutcome: String, Codable, Equatable {
  case accepted
  case acceptedEquivalent
  case rejected
  case expired
  case needsResign
}

struct BackgroundMigrationOutboxItem: Codable, Equatable {
  let itemId: String
  let partIndex: UInt32
  let txidHex: String
  let rawTransaction: Data
  let payloadDigestHex: String
  let anchorBoundaryHeight: UInt64
  let scheduledHeight: UInt64
  let scheduleStartHeight: UInt64
  let expiryHeight: UInt64
  /// Height the part was signed for; nil for a part saved by an older build.
  var targetHeight: UInt64?
  var status: BackgroundMigrationOutboxItemStatus
  var attemptCount: UInt32
  var attemptId: String?
  var attemptStartedAt: Date?
  var nextAttemptAt: Date?
  var lastError: String?

  init(
    itemId: String,
    partIndex: UInt32,
    txidHex: String,
    rawTransaction: Data,
    anchorBoundaryHeight: UInt64,
    scheduledHeight: UInt64,
    scheduleStartHeight: UInt64,
    expiryHeight: UInt64,
    targetHeight: UInt64? = nil
  ) {
    self.itemId = itemId
    self.partIndex = partIndex
    self.txidHex = txidHex.lowercased()
    self.rawTransaction = rawTransaction
    payloadDigestHex = Self.digestHex(rawTransaction)
    self.anchorBoundaryHeight = anchorBoundaryHeight
    self.scheduledHeight = scheduledHeight
    self.scheduleStartHeight = scheduleStartHeight
    self.expiryHeight = expiryHeight
    self.targetHeight = targetHeight
    status = .staged
    attemptCount = 0
    attemptId = nil
    attemptStartedAt = nil
    nextAttemptAt = nil
    lastError = nil
  }

  static func digestHex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

struct BackgroundMigrationOutboxBatch: Codable, Equatable {
  let batchId: String
  let network: String
  let accountUuid: String
  let runId: String
  var lightwalletdUrl: String
  var timingMeanBlocks: UInt64
  var timingMaxBlocks: UInt64
  let createdAt: Date
  var armedAt: Date?
  var nextProofHeight: UInt64?
  var proofReadyNotificationPendingAt: Date?
  var proofReadyNotifiedAt: Date?
  // The "chain reached the proof height, come back to Vizor" nudge used where
  // background preparation is unavailable. It is tracked apart from
  // `proofReadyNotifiedAt` on purpose: closing the batch out on an unverified
  // announcement is what suppressed the announcement the user is owed once
  // readiness actually holds. Absent in snapshots written before this field
  // existed, which decodes to nil and reads as "not nudged yet".
  var proofReadyHeightNoticePendingAt: Date? = nil
  var proofReadyHeightNoticedAt: Date? = nil
  var broadcastCompleteNotificationPendingAt: Date? = nil
  var broadcastCompleteNotifiedAt: Date? = nil
  var items: [BackgroundMigrationOutboxItem]

  var scopeKey: String { "\(network):\(accountUuid)" }

  /// Whether this batch still owes the user a proof-ready announcement.
  ///
  /// A delivered height-only nudge normally counts as answered even though it
  /// leaves `proofReadyNotifiedAt` nil. A subsequently verified notification
  /// remains outstanding until delivery so endpoint selection can drain it.
  /// Otherwise an acknowledged nudge would strand the verified notification.
  var awaitsProofReadyAnnouncement: Bool {
    proofReadyNotifiedAt == nil
      && (proofReadyNotificationPendingAt != nil
        || proofReadyHeightNoticedAt == nil
        || proofReadyHeightNoticePendingAt != nil)
  }
}

struct BackgroundMigrationOutboxScheduleUpdate: Codable, Equatable {
  let itemId: String
  let scheduledHeight: UInt64
  let scheduleStartHeight: UInt64
}

struct BackgroundMigrationOutboxReceipt: Codable, Equatable {
  let receiptId: String
  let batchId: String
  let itemId: String
  let network: String
  let accountUuid: String
  let runId: String
  let txidHex: String
  let outcome: BackgroundMigrationOutboxReceiptOutcome
  let remoteHeight: UInt64
  let responseCode: Int32?
  let responseMessage: String?
  let recordedAt: Date
  let scheduleUpdates: [BackgroundMigrationOutboxScheduleUpdate]
}

struct BackgroundMigrationOutboxSelection: Equatable {
  let batchId: String
  let accountUuid: String
  let scopeKey: String
  let lightwalletdUrl: String
  let item: BackgroundMigrationOutboxItem
}

struct BackgroundMigrationProofReadyMetadata: Equatable {
  let batchId: String
  let observedHeight: UInt64
  /// False for the height-only nudge delivered where readiness cannot be
  /// verified in the background. Decides which acknowledgement the delivery
  /// records, so an unverified nudge does not retire the batch.
  var verified: Bool = true
}

struct BackgroundMigrationBroadcastCompleteMetadata: Equatable {
  let batchId: String
}

enum BackgroundMigrationTransportOutcome: Equatable {
  case noWork
  case waiting(nextHeight: UInt64?, observedHeight: UInt64, delay: TimeInterval?)
  case accepted(nextHeight: UInt64?, observedHeight: UInt64, delay: TimeInterval?)
  case needsUserAction
  case temporarilyUnavailable
  case cancelled
}

/// The upgrade-stop key to alert for, or nil once that upgrade was alerted:
/// one alert per upgrade, however many batches or accounts it stopped.
func backgroundMigrationUpgradeStopAlertKey(
  _ key: String?,
  alreadyAlerted: String?
) -> String? {
  guard let key, key != alreadyAlerted else { return nil }
  return key
}

struct BackgroundMigrationOutboxRunResult: Equatable {
  let transport: BackgroundMigrationTransportOutcome
  let proofReady: BackgroundMigrationProofReadyMetadata?
  let broadcastComplete: BackgroundMigrationBroadcastCompleteMetadata?
  let transportAccountUuid: String?
  /// Due parts that wait for the network upgrade rather than a retry.
  var heldForUpgradeTxids: [String] = []
  /// The upgrade, as "network:activation height", that left a part unsendable.
  var upgradeStopKey: String?

  init(
    transport: BackgroundMigrationTransportOutcome,
    proofReady: BackgroundMigrationProofReadyMetadata?,
    broadcastComplete: BackgroundMigrationBroadcastCompleteMetadata? = nil,
    transportAccountUuid: String? = nil
  ) {
    self.transport = transport
    self.proofReady = proofReady
    self.broadcastComplete = broadcastComplete
    self.transportAccountUuid = transportAccountUuid
  }
}

struct BackgroundMigrationOutboxSnapshot: Codable, Equatable {
  static let currentVersion = 1

  var version = currentVersion
  var batches: [BackgroundMigrationOutboxBatch] = []
  var receipts: [BackgroundMigrationOutboxReceipt] = []
  var lastAttemptedScopeKey: String?
  var lastInspectedEndpoint: String?
  /// Batch ids whose "transfers sent" notification has already been delivered.
  ///
  /// The per-batch marker cannot carry this on its own: acknowledging receipts
  /// prunes an emptied record, and a later wave of the same run restages it
  /// under the same id with no history, so the run would be announced again.
  /// The id encodes network, account, and run, so revocation can drop a scope's
  /// entries and a rebuilt run starts clean. Optional so snapshots written
  /// before this field decode unchanged.
  var announcedBroadcastCompleteBatchIds: [String]?

  mutating func stage(_ batch: BackgroundMigrationOutboxBatch) throws {
    guard !batch.batchId.isEmpty,
      !batch.network.isEmpty,
      !batch.accountUuid.isEmpty,
      !batch.runId.isEmpty,
      !batch.lightwalletdUrl.isEmpty,
      batch.timingMeanBlocks > 0,
      batch.timingMaxBlocks > 0,
      batch.timingMeanBlocks <= batch.timingMaxBlocks,
      !batch.items.isEmpty || batch.nextProofHeight != nil,
      batch.proofReadyNotificationPendingAt == nil,
      batch.proofReadyNotifiedAt == nil,
      batch.proofReadyHeightNoticePendingAt == nil,
      batch.proofReadyHeightNoticedAt == nil,
      batch.broadcastCompleteNotificationPendingAt == nil,
      batch.broadcastCompleteNotifiedAt == nil,
      Set(batch.items.map(\.itemId)).count == batch.items.count,
      Set(batch.items.map(\.txidHex)).count == batch.items.count,
      batch.items.allSatisfy({
        !$0.itemId.isEmpty && !$0.txidHex.isEmpty && !$0.rawTransaction.isEmpty
          && $0.payloadDigestHex == BackgroundMigrationOutboxItem.digestHex($0.rawTransaction)
          && $0.scheduledHeight < $0.expiryHeight
          && $0.status == .staged
      })
    else {
      throw BackgroundMigrationOutboxError.invalidBatch
    }

    if let batchIndex = batches.firstIndex(where: { $0.batchId == batch.batchId }) {
      let existing = batches[batchIndex]
      guard existing.network == batch.network,
        existing.accountUuid == batch.accountUuid,
        existing.runId == batch.runId
      else {
        throw BackgroundMigrationOutboxError.conflictingBatch
      }
      if existing.lightwalletdUrl != batch.lightwalletdUrl {
        guard !existing.items.contains(where: { $0.status == .submitting }) else {
          throw BackgroundMigrationOutboxError.conflictingBatch
        }
        batches[batchIndex].lightwalletdUrl = batch.lightwalletdUrl
      }
      // The timing cadence is scheduling policy, not batch identity: a newer
      // app build may legitimately recompute it for the same run (e.g. the
      // dense-plan mean halving), and rejecting the restage would strand a run
      // that already has broadcast progress and therefore cannot be discarded.
      // Delivery evidence (item statuses, receipts) is untouched; only future
      // rescheduling reads these values.
      if existing.timingMeanBlocks != batch.timingMeanBlocks
        || existing.timingMaxBlocks != batch.timingMaxBlocks
      {
        guard !existing.items.contains(where: { $0.status == .submitting }) else {
          throw BackgroundMigrationOutboxError.conflictingBatch
        }
        batches[batchIndex].timingMeanBlocks = batch.timingMeanBlocks
        batches[batchIndex].timingMaxBlocks = batch.timingMaxBlocks
      }
      var addedItem = false
      for incoming in batch.items {
        if let existingIndex = existing.items.firstIndex(where: { $0.itemId == incoming.itemId }) {
          let existingItem = existing.items[existingIndex]
          guard existingItem.partIndex == incoming.partIndex,
            existingItem.txidHex == incoming.txidHex,
            existingItem.payloadDigestHex == incoming.payloadDigestHex,
            existingItem.anchorBoundaryHeight == incoming.anchorBoundaryHeight,
            existingItem.expiryHeight == incoming.expiryHeight
          else {
            throw BackgroundMigrationOutboxError.conflictingBatch
          }
          if existingItem.targetHeight == nil {
            batches[batchIndex].items[existingIndex].targetHeight = incoming.targetHeight
          }
          continue
        }
        if existing.items.contains(where: {
          $0.txidHex == incoming.txidHex || $0.partIndex == incoming.partIndex
        }) {
          throw BackgroundMigrationOutboxError.conflictingBatch
        }
        batches[batchIndex].items.append(incoming)
        addedItem = true
      }
      if existing.nextProofHeight != batch.nextProofHeight {
        batches[batchIndex].nextProofHeight = batch.nextProofHeight
        batches[batchIndex].proofReadyNotificationPendingAt = nil
        batches[batchIndex].proofReadyNotifiedAt = nil
        batches[batchIndex].proofReadyHeightNoticePendingAt = nil
        batches[batchIndex].proofReadyHeightNoticedAt = nil
      }
      if addedItem || existing.nextProofHeight != batch.nextProofHeight {
        batches[batchIndex].broadcastCompleteNotificationPendingAt = nil
        batches[batchIndex].broadcastCompleteNotifiedAt = nil
      }
      return
    }
    batches.append(batch)
  }

  mutating func armBatch(
    batchId: String,
    expectedDigests: [String: String],
    at date: Date
  ) throws {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      throw BackgroundMigrationOutboxError.batchNotFound
    }
    let hasProofWatch = batches[batchIndex].nextProofHeight != nil
    guard !expectedDigests.isEmpty || hasProofWatch,
      expectedDigests.allSatisfy({ entry in
        batches[batchIndex].items.contains(where: {
          $0.itemId == entry.key && $0.payloadDigestHex == entry.value
        })
      })
    else {
      throw BackgroundMigrationOutboxError.invalidArmRequest
    }
    if batches[batchIndex].armedAt == nil { batches[batchIndex].armedAt = date }
    for itemIndex in batches[batchIndex].items.indices {
      if expectedDigests[batches[batchIndex].items[itemIndex].itemId] != nil,
        batches[batchIndex].items[itemIndex].status == .staged
      {
        batches[batchIndex].items[itemIndex].status = .armed
      }
    }
  }

  mutating func recoverBatch(
    batchId: String,
    network: String,
    accountUuid: String,
    runId: String,
    expectedTxids: Set<String>,
    lightwalletdUrl: String,
    at date: Date
  ) throws -> Bool {
    guard !expectedTxids.isEmpty, !lightwalletdUrl.isEmpty else {
      throw BackgroundMigrationOutboxError.invalidArmRequest
    }
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      return false
    }

    let normalizedExpectedTxids = Set(expectedTxids.map { $0.lowercased() })
    let batch = batches[batchIndex]
    guard batch.network == network,
      batch.accountUuid == accountUuid,
      batch.runId == runId,
      !batch.items.isEmpty,
      batch.items.allSatisfy({ normalizedExpectedTxids.contains($0.txidHex) })
    else {
      throw BackgroundMigrationOutboxError.conflictingBatch
    }

    for itemIndex in batches[batchIndex].items.indices {
      var item = batches[batchIndex].items[itemIndex]
      if item.status == .submitting {
        item.status = .armed
        item.attemptCount += 1
        item.nextAttemptAt = date.addingTimeInterval(
          BackgroundMigrationOutboxCadence.retryDelay(attemptCount: item.attemptCount)
        )
        item.lastError = "The previous submission outcome is unknown."
        item.attemptId = nil
        item.attemptStartedAt = nil
      } else if item.status == .staged {
        item.status = .armed
      }
      batches[batchIndex].items[itemIndex] = item
    }
    batches[batchIndex].lightwalletdUrl = lightwalletdUrl
    if batches[batchIndex].items.contains(where: { $0.status == .armed }) {
      batches[batchIndex].armedAt = batches[batchIndex].armedAt ?? date
    }
    return true
  }

  func hasBatch(
    batchId: String,
    network: String,
    accountUuid: String,
    runId: String,
    expectedTxids: Set<String>,
    requiredTxids: Set<String>
  ) throws -> Bool {
    guard !expectedTxids.isEmpty, !requiredTxids.isEmpty else {
      throw BackgroundMigrationOutboxError.invalidArmRequest
    }
    guard let batch = batches.first(where: { $0.batchId == batchId }) else {
      return false
    }
    let normalizedExpectedTxids = Set(expectedTxids.map { $0.lowercased() })
    let normalizedRequiredTxids = Set(requiredTxids.map { $0.lowercased() })
    let batchTxids = Set(batch.items.map(\.txidHex))
    guard batch.network == network,
      batch.accountUuid == accountUuid,
      batch.runId == runId,
      !batch.items.isEmpty,
      batchTxids.isSubset(of: normalizedExpectedTxids),
      normalizedRequiredTxids.isSubset(of: batchTxids)
    else {
      throw BackgroundMigrationOutboxError.conflictingBatch
    }
    return true
  }

  mutating func recoverInterruptedSubmissions(at date: Date) {
    for batchIndex in batches.indices {
      for itemIndex in batches[batchIndex].items.indices
      where batches[batchIndex].items[itemIndex].status == .submitting {
        var item = batches[batchIndex].items[itemIndex]
        item.status = .armed
        item.attemptCount += 1
        item.nextAttemptAt = date.addingTimeInterval(
          BackgroundMigrationOutboxCadence.retryDelay(attemptCount: item.attemptCount)
        )
        item.lastError = "The previous submission outcome is unknown."
        item.attemptId = nil
        item.attemptStartedAt = nil
        batches[batchIndex].items[itemIndex] = item
      }
    }
  }

  mutating func nextEndpointForInspection() -> String? {
    let endpoints = Set(
      batches.filter { batch in
        batch.armedAt != nil
          && (batch.items.contains(where: { $0.status == .armed })
            || (batch.nextProofHeight != nil && batch.awaitsProofReadyAnnouncement))
      }.map(\.lightwalletdUrl)
    ).sorted()
    guard !endpoints.isEmpty else { return nil }
    let selected: String
    if let lastInspectedEndpoint,
      let lastIndex = endpoints.firstIndex(of: lastInspectedEndpoint)
    {
      selected = endpoints[(lastIndex + 1) % endpoints.count]
    } else {
      selected = endpoints[0]
    }
    lastInspectedEndpoint = selected
    return selected
  }

  func network(endpoint: String) -> String? {
    batches.first { $0.lightwalletdUrl == endpoint }?.network
  }

  func nextActionHeight(endpoint: String) -> UInt64? {
    let transactionHeight = batches.filter { $0.lightwalletdUrl == endpoint }.flatMap(\.items)
      .filter { $0.status == .armed }
      .map(\.scheduledHeight)
      .min()
    let proofHeight = batches.filter {
      $0.lightwalletdUrl == endpoint
        && $0.armedAt != nil
        && $0.awaitsProofReadyAnnouncement
        && $0.proofReadyNotificationPendingAt == nil
    }.compactMap(\.nextProofHeight).min()
    return [transactionHeight, proofHeight].compactMap { $0 }.min()
  }

  func nextActionAccountUuid(endpoint: String, height: UInt64) -> String? {
    return batches
      .filter { batch in
        guard batch.lightwalletdUrl == endpoint else { return false }
        let hasTransaction = batch.items.contains {
          $0.status == .armed && $0.scheduledHeight == height
        }
        let hasProof =
          batch.armedAt != nil
          && batch.awaitsProofReadyAnnouncement
          && batch.proofReadyNotificationPendingAt == nil
          && batch.nextProofHeight == height
        return hasTransaction || hasProof
      }
      .sorted(by: { $0.batchId < $1.batchId })
      .first?
      .accountUuid
  }

  mutating func markProofReadyIfNeeded(
    remoteHeight: UInt64,
    endpoint: String,
    at date: Date
  ) -> BackgroundMigrationProofReadyMetadata? {
    guard
      let candidate = proofReadinessCandidate(
        remoteHeight: remoteHeight,
        endpoint: endpoint
      ),
      let batchIndex = batches.firstIndex(where: { $0.batchId == candidate.batchId })
    else { return nil }

    if batches[batchIndex].proofReadyNotificationPendingAt == nil {
      batches[batchIndex].proofReadyNotificationPendingAt = date
    }
    return candidate
  }

  func proofReadinessCandidate(
    remoteHeight: UInt64,
    endpoint: String
  ) -> BackgroundMigrationProofReadyMetadata? {
    batches
      .filter { batch in
        guard let nextProofHeight = batch.nextProofHeight else { return false }
        return batch.lightwalletdUrl == endpoint
          && batch.armedAt != nil
          && batch.awaitsProofReadyAnnouncement
          && nextProofHeight <= remoteHeight
      }
      .sorted {
        ($0.nextProofHeight ?? 0, $0.batchId) < ($1.nextProofHeight ?? 0, $1.batchId)
      }
      .first
      .map {
        BackgroundMigrationProofReadyMetadata(
          batchId: $0.batchId,
          observedHeight: remoteHeight
        )
      }
  }

  mutating func recordVerifiedProofReadiness(
    network: String,
    accountUuid: String,
    runId: String,
    at date: Date
  ) -> Bool {
    let candidates = batches.indices.filter { batchIndex in
      let batch = batches[batchIndex]
      return batch.network == network
        && batch.accountUuid == accountUuid
        && batch.runId == runId
        && batch.armedAt != nil
        && batch.nextProofHeight != nil
    }
    guard
      let batchIndex = candidates.sorted(by: {
        let lhs = batches[$0]
        let rhs = batches[$1]
        return (lhs.nextProofHeight ?? 0, lhs.batchId) < (rhs.nextProofHeight ?? 0, rhs.batchId)
      }).first
    else { return false }

    if batches[batchIndex].proofReadyNotifiedAt == nil,
      batches[batchIndex].proofReadyNotificationPendingAt == nil
    {
      batches[batchIndex].proofReadyNotificationPendingAt = date
    }
    return true
  }

  func pendingProofReadyNotification() -> BackgroundMigrationProofReadyMetadata? {
    batches
      .filter {
        $0.armedAt != nil
          && $0.proofReadyNotificationPendingAt != nil
          && $0.proofReadyNotifiedAt == nil
          && $0.nextProofHeight != nil
      }
      .sorted {
        ($0.nextProofHeight ?? 0, $0.batchId) < ($1.nextProofHeight ?? 0, $1.batchId)
      }
      .first
      .map {
        BackgroundMigrationProofReadyMetadata(
          batchId: $0.batchId,
          observedHeight: $0.nextProofHeight ?? 0
        )
      }
  }

  mutating func acknowledgeProofReadyNotification(batchId: String, at date: Date) throws {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      throw BackgroundMigrationOutboxError.batchNotFound
    }
    guard batches[batchIndex].proofReadyNotificationPendingAt != nil else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    batches[batchIndex].proofReadyNotificationPendingAt = nil
    batches[batchIndex].proofReadyNotifiedAt = date
  }

  /// Queues the height-only nudge for a batch whose readiness cannot be
  /// verified here.
  ///
  /// Where background preparation is unavailable the wallet never scans while
  /// the app is closed, so verified readiness cannot be observed from a wake at
  /// all. Announcing nothing leaves the user with no signal that the migration
  /// is waiting on them. This announces once per proof height, and deliberately
  /// leaves `proofReadyNotifiedAt` untouched so the verified announcement can
  /// still be delivered later.
  /// The caller has already established that the chain reached this batch's
  /// proof height; this only records that the nudge is owed.
  mutating func markUnverifiedProofReadyNoticeIfNeeded(
    batchId: String,
    at date: Date
  ) -> BackgroundMigrationProofReadyMetadata? {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      return nil
    }
    let batch = batches[batchIndex]
    guard
      batch.armedAt != nil,
      let nextProofHeight = batch.nextProofHeight,
      batch.proofReadyNotifiedAt == nil,
      batch.proofReadyNotificationPendingAt == nil,
      batch.proofReadyHeightNoticePendingAt == nil,
      batch.proofReadyHeightNoticedAt == nil
    else { return nil }

    batches[batchIndex].proofReadyHeightNoticePendingAt = date
    return BackgroundMigrationProofReadyMetadata(
      batchId: batchId,
      observedHeight: nextProofHeight,
      verified: false
    )
  }

  /// A nudge whose delivery has not been confirmed yet, so a failed post is
  /// retried on the next wake instead of being lost.
  func pendingUnverifiedProofReadyNotice() -> BackgroundMigrationProofReadyMetadata? {
    batches
      .filter {
        $0.armedAt != nil
          && $0.proofReadyHeightNoticePendingAt != nil
          && $0.proofReadyHeightNoticedAt == nil
          && $0.proofReadyNotifiedAt == nil
          && $0.nextProofHeight != nil
      }
      .sorted {
        ($0.nextProofHeight ?? 0, $0.batchId) < ($1.nextProofHeight ?? 0, $1.batchId)
      }
      .first
      .map {
        BackgroundMigrationProofReadyMetadata(
          batchId: $0.batchId,
          observedHeight: $0.nextProofHeight ?? 0,
          verified: false
        )
      }
  }

  mutating func acknowledgeUnverifiedProofReadyNotice(
    batchId: String,
    at date: Date
  ) throws {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      throw BackgroundMigrationOutboxError.batchNotFound
    }
    guard batches[batchIndex].proofReadyHeightNoticePendingAt != nil else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    batches[batchIndex].proofReadyHeightNoticePendingAt = nil
    batches[batchIndex].proofReadyHeightNoticedAt = date
  }

  func pendingBroadcastCompleteNotification()
    -> BackgroundMigrationBroadcastCompleteMetadata?
  {
    batches
      .filter {
        $0.broadcastCompleteNotificationPendingAt != nil
          && $0.broadcastCompleteNotifiedAt == nil
      }
      .sorted { $0.batchId < $1.batchId }
      .first
      .map { BackgroundMigrationBroadcastCompleteMetadata(batchId: $0.batchId) }
  }

  mutating func markBroadcastCompleteIfNeeded(
    batchId: String,
    at date: Date
  ) -> BackgroundMigrationBroadcastCompleteMetadata? {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      return nil
    }
    let batch = batches[batchIndex]
    guard batch.nextProofHeight == nil,
      batch.broadcastCompleteNotifiedAt == nil,
      !(announcedBroadcastCompleteBatchIds ?? []).contains(batchId),
      !batch.items.isEmpty,
      batch.items.allSatisfy({ $0.status == .acceptedAwaitingReconciliation })
    else {
      return nil
    }
    if batches[batchIndex].broadcastCompleteNotificationPendingAt == nil {
      batches[batchIndex].broadcastCompleteNotificationPendingAt = date
    }
    return BackgroundMigrationBroadcastCompleteMetadata(batchId: batchId)
  }

  mutating func acknowledgeBroadcastCompleteNotification(
    batchId: String,
    at date: Date
  ) throws {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId }) else {
      throw BackgroundMigrationOutboxError.batchNotFound
    }
    guard batches[batchIndex].broadcastCompleteNotificationPendingAt != nil else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    batches[batchIndex].broadcastCompleteNotificationPendingAt = nil
    batches[batchIndex].broadcastCompleteNotifiedAt = date
    var announced = announcedBroadcastCompleteBatchIds ?? []
    if !announced.contains(batchId) {
      announced.append(batchId)
      announcedBroadcastCompleteBatchIds = announced
    }
    if batches[batchIndex].items.isEmpty
      && batches[batchIndex].nextProofHeight == nil
    {
      batches.remove(at: batchIndex)
    }
  }

  mutating func expireItems(remoteHeight: UInt64, endpoint: String, at date: Date) {
    for batchIndex in batches.indices {
      guard batches[batchIndex].lightwalletdUrl == endpoint else { continue }
      var expiredAnyItem = false
      for itemIndex in batches[batchIndex].items.indices {
        let item = batches[batchIndex].items[itemIndex]
        guard item.status == .armed, remoteHeight >= item.expiryHeight else { continue }
        expiredAnyItem = true
        batches[batchIndex].items[itemIndex].status = .expiredAwaitingReconciliation
        receipts.append(
          makeReceipt(
            batch: batches[batchIndex],
            item: batches[batchIndex].items[itemIndex],
            outcome: .expired,
            remoteHeight: remoteHeight,
            responseCode: nil,
            responseMessage: nil,
            scheduleUpdates: [],
            at: date
          )
        )
      }
      if expiredAnyItem {
        batches[batchIndex].armedAt = nil
        batches[batchIndex].nextProofHeight = nil
      }
    }
  }

  mutating func markDueItemsNeedingResign(
    remoteHeight: UInt64,
    endpoint: String,
    at date: Date
  ) {
    for batchIndex in batches.indices {
      guard batches[batchIndex].lightwalletdUrl == endpoint,
        let canonicalExpiryHeight = Self.canonicalExpiryHeight(
          for: remoteHeight,
          network: batches[batchIndex].network
        )
      else { continue }
      var foundNoncanonicalItem = false
      for itemIndex in batches[batchIndex].items.indices {
        let item = batches[batchIndex].items[itemIndex]
        guard item.status == .armed,
          item.scheduledHeight <= remoteHeight,
          item.expiryHeight != canonicalExpiryHeight
        else { continue }
        foundNoncanonicalItem = true
        batches[batchIndex].items[itemIndex].status = .needsResignAwaitingReconciliation
        receipts.append(
          makeReceipt(
            batch: batches[batchIndex],
            item: batches[batchIndex].items[itemIndex],
            outcome: .needsResign,
            remoteHeight: remoteHeight,
            responseCode: nil,
            responseMessage: "Broadcast height crossed a ZIP 318 expiry boundary.",
            scheduleUpdates: [],
            at: date
          )
        )
      }
      if foundNoncanonicalItem {
        batches[batchIndex].armedAt = nil
        batches[batchIndex].nextProofHeight = nil
      }
    }
  }

  mutating func selectDue(
    remoteHeight: UInt64,
    endpoint: String? = nil,
    at date: Date
  ) -> BackgroundMigrationOutboxSelection? {
    let candidates = batches.enumerated().compactMap {
      batchIndex, batch -> (Int, BackgroundMigrationOutboxBatch)? in
      guard endpoint == nil || batch.lightwalletdUrl == endpoint,
        batch.armedAt != nil,
        batch.items.contains(where: {
          $0.status == .armed && $0.scheduledHeight <= remoteHeight
            && remoteHeight < $0.expiryHeight
            && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= date)
            && !Self.upgradeHolds($0, in: batch, remoteHeight: remoteHeight)
        })
      else { return nil }
      return (batchIndex, batch)
    }
    guard !candidates.isEmpty else { return nil }

    let orderedScopes = Array(Set(candidates.map { $0.1.scopeKey })).sorted()
    let selectedScope: String
    if let lastAttemptedScopeKey,
      let lastIndex = orderedScopes.firstIndex(of: lastAttemptedScopeKey)
    {
      selectedScope = orderedScopes[(lastIndex + 1) % orderedScopes.count]
    } else {
      selectedScope = orderedScopes[0]
    }
    guard let batch = candidates.map(\.1).first(where: { $0.scopeKey == selectedScope }),
      let item = batch.items
        .filter({
          $0.status == .armed && $0.scheduledHeight <= remoteHeight
            && remoteHeight < $0.expiryHeight
            && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= date)
            && !Self.upgradeHolds($0, in: batch, remoteHeight: remoteHeight)
        })
        .sorted(by: {
          ($0.scheduledHeight, $0.txidHex) < ($1.scheduledHeight, $1.txidHex)
        })
        .first
    else { return nil }

    lastAttemptedScopeKey = selectedScope
    return BackgroundMigrationOutboxSelection(
      batchId: batch.batchId,
      accountUuid: batch.accountUuid,
      scopeKey: batch.scopeKey,
      lightwalletdUrl: batch.lightwalletdUrl,
      item: item
    )
  }

  mutating func beginSubmission(itemId: String, attemptId: String, at date: Date) throws {
    let location = try itemLocation(itemId)
    guard batches[location.batch].items[location.item].status == .armed else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    batches[location.batch].items[location.item].status = .submitting
    batches[location.batch].items[location.item].attemptId = attemptId
    batches[location.batch].items[location.item].attemptStartedAt = date
  }

  func validateReschedulingAfterAcceptance(
    itemId: String,
    remoteHeight: UInt64
  ) throws {
    let location = try itemLocation(itemId)
    let expiryHeights = batches[location.batch].items
      .filter {
        $0.itemId != itemId && $0.status == .armed
          && $0.scheduledHeight <= remoteHeight
      }
      .map(\.expiryHeight)
      .sorted()
    let spacing = Self.redrawSpacing(
      expiryHeights: expiryHeights,
      network: batches[location.batch].network
    )
    var nextHeight = remoteHeight
    for expiryHeight in expiryHeights {
      let (candidate, overflow) = nextHeight.addingReportingOverflow(spacing)
      guard !overflow, candidate < expiryHeight else {
        throw BackgroundMigrationOutboxError.invalidSchedule
      }
      nextHeight = candidate
    }
  }

  mutating func recordUncertain(itemId: String, error: String, at date: Date) throws {
    let location = try itemLocation(itemId)
    guard batches[location.batch].items[location.item].status == .submitting else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    var item = batches[location.batch].items[location.item]
    item.status = .armed
    item.attemptCount += 1
    item.nextAttemptAt = date.addingTimeInterval(
      BackgroundMigrationOutboxCadence.retryDelay(attemptCount: item.attemptCount)
    )
    item.lastError = error
    item.attemptId = nil
    item.attemptStartedAt = nil
    batches[location.batch].items[location.item] = item
  }

  /// Restores a selected item when cancellation was observed before the
  /// transport call began. Unlike an interrupted/failed transport, this is a
  /// definite non-attempt and must not make stop reconciliation wait for
  /// transaction expiry.
  mutating func recordCancelledBeforeSubmission(itemId: String, error: String) throws {
    let location = try itemLocation(itemId)
    guard batches[location.batch].items[location.item].status == .submitting else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    var item = batches[location.batch].items[location.item]
    item.status = .armed
    item.nextAttemptAt = nil
    item.lastError = error
    item.attemptId = nil
    item.attemptStartedAt = nil
    batches[location.batch].items[location.item] = item
  }

  mutating func recordAccepted(
    itemId: String,
    equivalent: Bool,
    remoteHeight: UInt64,
    responseCode: Int32,
    responseMessage: String,
    at date: Date,
    random: inout some RandomNumberGenerator
  ) throws {
    let location = try itemLocation(itemId)
    guard batches[location.batch].items[location.item].status == .submitting else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    batches[location.batch].items[location.item].status = .acceptedAwaitingReconciliation
    batches[location.batch].items[location.item].attemptId = nil
    batches[location.batch].items[location.item].attemptStartedAt = nil
    batches[location.batch].items[location.item].nextAttemptAt = nil
    let updates = try rescheduleOverdueItems(
      batchIndex: location.batch,
      excluding: itemId,
      remoteHeight: remoteHeight,
      random: &random
    )
    let batch = batches[location.batch]
    let item = batch.items[location.item]
    receipts.append(
      makeReceipt(
        batch: batch,
        item: item,
        outcome: equivalent ? .acceptedEquivalent : .accepted,
        remoteHeight: remoteHeight,
        responseCode: responseCode,
        responseMessage: responseMessage,
        scheduleUpdates: updates,
        at: date
      )
    )
  }

  mutating func recordRejected(
    itemId: String,
    remoteHeight: UInt64,
    responseCode: Int32,
    responseMessage: String,
    at date: Date
  ) throws {
    let location = try itemLocation(itemId)
    guard batches[location.batch].items[location.item].status == .submitting else {
      throw BackgroundMigrationOutboxError.invalidTransition
    }
    batches[location.batch].items[location.item].status = .rejectedAwaitingReconciliation
    batches[location.batch].items[location.item].attemptId = nil
    batches[location.batch].items[location.item].attemptStartedAt = nil
    batches[location.batch].items[location.item].nextAttemptAt = nil
    batches[location.batch].armedAt = nil
    batches[location.batch].nextProofHeight = nil
    let batch = batches[location.batch]
    let item = batch.items[location.item]
    receipts.append(
      makeReceipt(
        batch: batch,
        item: item,
        outcome: .rejected,
        remoteHeight: remoteHeight,
        responseCode: responseCode,
        responseMessage: responseMessage,
        scheduleUpdates: [],
        at: date
      )
    )
  }

  mutating func acknowledgeReceipts(_ receiptIds: Set<String>) {
    let acknowledged = receipts.filter { receiptIds.contains($0.receiptId) }
    let acknowledgedItemIds = Set(acknowledged.map(\.itemId))
    let terminalBatchIds = Set(
      acknowledged.filter {
        $0.outcome == .rejected || $0.outcome == .expired || $0.outcome == .needsResign
      }.map(\.batchId)
    )
    receipts.removeAll { receiptIds.contains($0.receiptId) }
    let removableTerminalBatchIds = terminalBatchIds.filter { batchId in
      !receipts.contains(where: { $0.batchId == batchId })
    }
    batches.removeAll { removableTerminalBatchIds.contains($0.batchId) }
    for batchIndex in batches.indices {
      batches[batchIndex].items.removeAll { acknowledgedItemIds.contains($0.itemId) }
    }
    batches.removeAll {
      $0.items.isEmpty && $0.nextProofHeight == nil
        && $0.broadcastCompleteNotificationPendingAt == nil
    }
  }

  /// Removes one stale batch record without touching the rest of the account
  /// scope.
  ///
  /// Recovery needs this when a record cannot accept its run's scheduled
  /// transactions: revoking the whole account would also delete the run's
  /// background credential, which is what re-staging depends on. Refuses while
  /// the record still has delivery state, so nothing in flight is dropped.
  mutating func discardBatch(batchId: String) throws -> Bool {
    guard let batchIndex = batches.firstIndex(where: { $0.batchId == batchId })
    else {
      return false
    }
    guard !batches[batchIndex].items.contains(where: {
      $0.status == .submitting || $0.attemptCount > 0
    }),
      !receipts.contains(where: { $0.batchId == batchId })
    else {
      throw BackgroundMigrationOutboxError.conflictingBatch
    }
    batches.remove(at: batchIndex)
    return true
  }

  mutating func revoke(network: String, accountUuid: String) {
    let batchIds = Set(
      batches.filter { $0.network == network && $0.accountUuid == accountUuid }
        .map(\.batchId)
    )
    batches.removeAll { batchIds.contains($0.batchId) }
    receipts.removeAll { batchIds.contains($0.batchId) }
    let scopePrefix = "\(network):\(accountUuid):"
    if var announced = announcedBroadcastCompleteBatchIds {
      announced.removeAll { $0.hasPrefix(scopePrefix) }
      announcedBroadcastCompleteBatchIds = announced.isEmpty ? nil : announced
    }
    if lastAttemptedScopeKey == "\(network):\(accountUuid)" {
      lastAttemptedScopeKey = nil
    }
  }

  private func itemLocation(_ itemId: String) throws -> (batch: Int, item: Int) {
    for batchIndex in batches.indices {
      if let itemIndex = batches[batchIndex].items.firstIndex(where: { $0.itemId == itemId }) {
        return (batchIndex, itemIndex)
      }
    }
    throw BackgroundMigrationOutboxError.itemNotFound
  }

  private mutating func rescheduleOverdueItems(
    batchIndex: Int,
    excluding itemId: String,
    remoteHeight: UInt64,
    random: inout some RandomNumberGenerator
  ) throws -> [BackgroundMigrationOutboxScheduleUpdate] {
    let mean = batches[batchIndex].timingMeanBlocks
    let max = batches[batchIndex].timingMaxBlocks
    guard mean > 0, max > 0, mean <= max else {
      throw BackgroundMigrationOutboxError.invalidSchedule
    }
    var overdueIndexes = batches[batchIndex].items.indices.filter {
      let item = batches[batchIndex].items[$0]
      return item.itemId != itemId && item.status == .armed
        && item.scheduledHeight <= remoteHeight
    }
    overdueIndexes.shuffle(using: &random)
    overdueIndexes.sort {
      batches[batchIndex].items[$0].expiryHeight
        < batches[batchIndex].items[$1].expiryHeight
    }
    let network = batches[batchIndex].network
    let expiryHeights = overdueIndexes.map { batches[batchIndex].items[$0].expiryHeight }
    let spacing = Self.redrawSpacing(expiryHeights: expiryHeights, network: network)
    // The latest height each item can take while every later one still fits
    // `spacing` apart before its own expiry, the shape validation checks.
    var latestHeights = [UInt64](repeating: 0, count: expiryHeights.count)
    var laterBound = UInt64.max
    for position in expiryHeights.indices.reversed() {
      guard expiryHeights[position] > 0 else {
        throw BackgroundMigrationOutboxError.invalidSchedule
      }
      let latest = min(expiryHeights[position] - 1, laterBound)
      latestHeights[position] = latest
      laterBound = latest >= spacing ? latest - spacing : 0
    }
    var elapsed: UInt64 = 0
    var updates: [BackgroundMigrationOutboxScheduleUpdate] = []
    for (offset, itemIndex) in overdueIndexes.enumerated() {
      let latestHeight = latestHeights[offset]
      let currentHeight = remoteHeight.saturatingAdd(elapsed)
      guard latestHeight > currentHeight else {
        throw BackgroundMigrationOutboxError.invalidSchedule
      }
      // ZIP 318 delays are reference blocks; from NU7 each spans three blocks.
      let blocksPerReferenceBlock = BackgroundMigrationOutboxSchedule.blocksPerReferenceBlock(
        at: currentHeight,
        network: network
      )
      let boundedMax = min(max, (latestHeight - currentHeight) / blocksPerReferenceBlock)
      guard boundedMax > 0 else {
        throw BackgroundMigrationOutboxError.invalidSchedule
      }
      elapsed = elapsed.saturatingAdd(
        BackgroundMigrationOutboxSchedule.sampleDelay(
          meanBlocks: mean,
          maxBlocks: boundedMax,
          random: &random
        ) * blocksPerReferenceBlock
      )
      let scheduledHeight = remoteHeight.saturatingAdd(elapsed)
      batches[batchIndex].items[itemIndex] = replacingSchedule(
        batches[batchIndex].items[itemIndex],
        scheduledHeight: scheduledHeight,
        scheduleStartHeight: remoteHeight
      )
      updates.append(
        BackgroundMigrationOutboxScheduleUpdate(
          itemId: batches[batchIndex].items[itemIndex].itemId,
          scheduledHeight: scheduledHeight,
          scheduleStartHeight: remoteHeight
        )
      )
    }
    return updates
  }

  private func replacingSchedule(
    _ item: BackgroundMigrationOutboxItem,
    scheduledHeight: UInt64,
    scheduleStartHeight: UInt64
  ) -> BackgroundMigrationOutboxItem {
    var copy = item
    copy = BackgroundMigrationOutboxItem(
      itemId: item.itemId,
      partIndex: item.partIndex,
      txidHex: item.txidHex,
      rawTransaction: item.rawTransaction,
      anchorBoundaryHeight: item.anchorBoundaryHeight,
      scheduledHeight: scheduledHeight,
      scheduleStartHeight: scheduleStartHeight,
      expiryHeight: item.expiryHeight,
      targetHeight: item.targetHeight
    )
    copy.status = item.status
    copy.attemptCount = item.attemptCount
    copy.nextAttemptAt = item.nextAttemptAt
    copy.lastError = item.lastError
    return copy
  }

  private func makeReceipt(
    batch: BackgroundMigrationOutboxBatch,
    item: BackgroundMigrationOutboxItem,
    outcome: BackgroundMigrationOutboxReceiptOutcome,
    remoteHeight: UInt64,
    responseCode: Int32?,
    responseMessage: String?,
    scheduleUpdates: [BackgroundMigrationOutboxScheduleUpdate],
    at date: Date
  ) -> BackgroundMigrationOutboxReceipt {
    BackgroundMigrationOutboxReceipt(
      receiptId: "\(batch.batchId):\(item.itemId):\(outcome.rawValue)",
      batchId: batch.batchId,
      itemId: item.itemId,
      network: batch.network,
      accountUuid: batch.accountUuid,
      runId: batch.runId,
      txidHex: item.txidHex,
      outcome: outcome,
      remoteHeight: remoteHeight,
      responseCode: responseCode,
      responseMessage: responseMessage,
      recordedAt: date,
      scheduleUpdates: scheduleUpdates
    )
  }

  /// ZIP 318's canonical expiry for a part scheduled at `height`, from Rust.
  static func canonicalExpiryHeight(for height: UInt64, network: String) -> UInt64? {
    let expiryHeight = network.withCString { zcash_zip318_canonical_expiry_height($0, height) }
    return expiryHeight == 0 ? nil : expiryHeight
  }

  /// Whether the network upgrade holds `item`, as the foreground judges it.
  static func upgradeHolds(
    _ item: BackgroundMigrationOutboxItem,
    in batch: BackgroundMigrationOutboxBatch,
    remoteHeight: UInt64
  ) -> Bool {
    BackgroundMigrationOutboxCadence.holdsBroadcast(
      network: batch.network,
      targetHeight: item.targetHeight,
      remoteHeight: remoteHeight
    )
  }

  /// Blocks reserved per redrawn item: one reference block at the latest
  /// expiry, the widest spacing any draw before it can take.
  static func redrawSpacing(expiryHeights: [UInt64], network: String) -> UInt64 {
    BackgroundMigrationOutboxSchedule.blocksPerReferenceBlock(
      at: expiryHeights.max() ?? 0,
      network: network
    )
  }

  /// The upgrade, as "network:activation height", once no block before it is
  /// left for an unsent part on `endpoint` signed for the branch it ended. The
  /// foreground stops that part's run on its next sync.
  func upgradeStopKey(remoteHeight: UInt64, endpoint: String) -> String? {
    for batch in batches where batch.lightwalletdUrl == endpoint {
      guard
        let activation = BackgroundMigrationOutboxCadence.nu7ActivationHeight(
          network: batch.network
        ),
        remoteHeight + 1 >= activation,
        batch.items.contains(where: {
          ($0.status == .armed || $0.status == .needsResignAwaitingReconciliation)
            && ($0.targetHeight ?? activation) < activation
        })
      else { continue }
      return "\(batch.network):\(activation)"
    }
    return nil
  }

  /// Txids of due parts on `endpoint` that wait for the network upgrade.
  func dueTxidsHeldForUpgrade(remoteHeight: UInt64, endpoint: String) -> [String] {
    batches.filter { $0.lightwalletdUrl == endpoint }.flatMap { batch in
      batch.items.filter {
        $0.status == .armed && $0.scheduledHeight <= remoteHeight
          && Self.upgradeHolds($0, in: batch, remoteHeight: remoteHeight)
      }.map(\.txidHex)
    }.sorted()
  }
}

enum BackgroundMigrationOutboxSchedule {
  /// Blocks per ZIP 318 reference block at `height`, from Rust.
  static func blocksPerReferenceBlock(at height: UInt64, network: String) -> UInt64 {
    max(1, network.withCString { zcash_zip318_blocks_per_reference_block($0, height) })
  }

  static func sampleDelay(
    meanBlocks: UInt64,
    maxBlocks: UInt64,
    random: inout some RandomNumberGenerator
  ) -> UInt64 {
    precondition(meanBlocks > 0 && maxBlocks > 0)
    let unit = Double(random.next()) / Double(UInt64.max)
    let lowerBound = exp(-Double(maxBlocks) / Double(meanBlocks))
    let uniform = lowerBound + (1 - lowerBound) * unit
    let sampled = max(1, UInt64(ceil(-log(uniform) * Double(meanBlocks))))
    return min(sampled, maxBlocks)
  }
}

enum BackgroundMigrationOutboxCadence {
  static let preNu7SecondsPerBlock: TimeInterval = 75
  /// ZIP 218 target spacing from NU7 activation.
  static let nu7SecondsPerBlock: TimeInterval = 25
  static let rollingCheckInterval: TimeInterval = 10 * 60
  static let dueLeadTime: TimeInterval = 10 * 60

  static func nextCheckDelay(
    remoteHeight: UInt64,
    nextScheduledHeight: UInt64?,
    nu7ActivationHeight: UInt64?
  ) -> TimeInterval? {
    guard let nextScheduledHeight else { return nil }
    if nextScheduledHeight <= remoteHeight { return 60 }
    let estimated = estimatedSeconds(
      from: remoteHeight,
      to: nextScheduledHeight,
      nu7ActivationHeight: nu7ActivationHeight
    )
    return min(rollingCheckInterval, max(60, estimated - dueLeadTime))
  }

  /// Blocks up to `nu7ActivationHeight - 1` take 75 seconds, later ones 25.
  static func estimatedSeconds(
    from remoteHeight: UInt64,
    to targetHeight: UInt64,
    nu7ActivationHeight: UInt64?
  ) -> TimeInterval {
    guard targetHeight > remoteHeight else { return 0 }
    let blocks = targetHeight - remoteHeight
    var preNu7Blocks = blocks
    if let activation = nu7ActivationHeight, activation > 0 {
      let lastPreNu7 = min(activation - 1, targetHeight)
      preNu7Blocks = lastPreNu7 > remoteHeight ? lastPreNu7 - remoteHeight : 0
    }
    return TimeInterval(preNu7Blocks) * preNu7SecondsPerBlock
      + TimeInterval(blocks - preNu7Blocks) * nu7SecondsPerBlock
  }

  static func nu7ActivationHeight(network: String) -> UInt64? {
    let height = network.withCString { zcash_nu7_activation_height($0) }
    return height == 0 ? nil : height
  }

  /// Whether a part signed for `targetHeight` waits for a network upgrade at
  /// `remoteHeight`: sent then, it could miss the last old-branch block and
  /// keep its input spent until expiry. Rust owns the window.
  static func holdsBroadcast(
    network: String,
    targetHeight: UInt64?,
    remoteHeight: UInt64
  ) -> Bool {
    network.withCString {
      zcash_migration_broadcast_held($0, targetHeight ?? 0, remoteHeight)
    }
  }

  static func retryDelay(attemptCount: UInt32) -> TimeInterval {
    switch attemptCount {
    case 0, 1: return 60
    case 2: return 5 * 60
    case 3: return 15 * 60
    default: return 60 * 60
    }
  }
}

extension UInt64 {
  fileprivate func saturatingAdd(_ other: UInt64) -> UInt64 {
    let (result, overflow) = addingReportingOverflow(other)
    return overflow ? UInt64.max : result
  }
}
