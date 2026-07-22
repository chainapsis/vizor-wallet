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
}

enum BackgroundMigrationOutboxReceiptOutcome: String, Codable, Equatable {
  case accepted
  case acceptedEquivalent
  case rejected
  case expired
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
    expiryHeight: UInt64
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
  let lightwalletdUrl: String
  let timingMeanBlocks: UInt64
  let timingMaxBlocks: UInt64
  let createdAt: Date
  var armedAt: Date?
  var nextProofHeight: UInt64?
  var proofReadyNotificationPendingAt: Date?
  var proofReadyNotifiedAt: Date?
  var items: [BackgroundMigrationOutboxItem]

  var scopeKey: String { "\(network):\(accountUuid)" }
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
  let scopeKey: String
  let lightwalletdUrl: String
  let item: BackgroundMigrationOutboxItem
}

struct BackgroundMigrationProofReadyMetadata: Equatable {
  let batchId: String
  let observedHeight: UInt64
}

enum BackgroundMigrationTransportOutcome: Equatable {
  case noWork
  case waiting(nextHeight: UInt64?, observedHeight: UInt64, delay: TimeInterval?)
  case accepted(nextHeight: UInt64?, observedHeight: UInt64, delay: TimeInterval?)
  case needsUserAction
  case temporarilyUnavailable
  case cancelled
}

struct BackgroundMigrationOutboxRunResult: Equatable {
  let transport: BackgroundMigrationTransportOutcome
  let proofReady: BackgroundMigrationProofReadyMetadata?
}

struct BackgroundMigrationOutboxSnapshot: Codable, Equatable {
  static let currentVersion = 1

  var version = currentVersion
  var batches: [BackgroundMigrationOutboxBatch] = []
  var receipts: [BackgroundMigrationOutboxReceipt] = []
  var lastAttemptedScopeKey: String?
  var lastInspectedEndpoint: String?

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
        existing.runId == batch.runId,
        existing.lightwalletdUrl == batch.lightwalletdUrl,
        existing.timingMeanBlocks == batch.timingMeanBlocks,
        existing.timingMaxBlocks == batch.timingMaxBlocks
      else {
        throw BackgroundMigrationOutboxError.conflictingBatch
      }
      for incoming in batch.items {
        if let existingItem = existing.items.first(where: { $0.itemId == incoming.itemId }) {
          guard existingItem.partIndex == incoming.partIndex,
            existingItem.txidHex == incoming.txidHex,
            existingItem.payloadDigestHex == incoming.payloadDigestHex,
            existingItem.anchorBoundaryHeight == incoming.anchorBoundaryHeight,
            existingItem.expiryHeight == incoming.expiryHeight
          else {
            throw BackgroundMigrationOutboxError.conflictingBatch
          }
          continue
        }
        if existing.items.contains(where: {
          $0.txidHex == incoming.txidHex || $0.partIndex == incoming.partIndex
        }) {
          throw BackgroundMigrationOutboxError.conflictingBatch
        }
        batches[batchIndex].items.append(incoming)
      }
      if existing.nextProofHeight != batch.nextProofHeight {
        batches[batchIndex].nextProofHeight = batch.nextProofHeight
        batches[batchIndex].proofReadyNotificationPendingAt = nil
        batches[batchIndex].proofReadyNotifiedAt = nil
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
            || (batch.nextProofHeight != nil && batch.proofReadyNotifiedAt == nil))
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

  func nextActionHeight(endpoint: String) -> UInt64? {
    let transactionHeight = batches.filter { $0.lightwalletdUrl == endpoint }.flatMap(\.items)
      .filter { $0.status == .armed }
      .map(\.scheduledHeight)
      .min()
    let proofHeight = batches.filter {
      $0.lightwalletdUrl == endpoint
        && $0.armedAt != nil
        && $0.proofReadyNotifiedAt == nil
        && $0.proofReadyNotificationPendingAt == nil
    }.compactMap(\.nextProofHeight).min()
    return [transactionHeight, proofHeight].compactMap { $0 }.min()
  }

  mutating func markProofReadyIfNeeded(
    remoteHeight: UInt64,
    endpoint: String,
    at date: Date
  ) -> BackgroundMigrationProofReadyMetadata? {
    let candidates = batches.indices.filter { batchIndex in
      let batch = batches[batchIndex]
      guard batch.lightwalletdUrl == endpoint,
        batch.armedAt != nil,
        batch.proofReadyNotifiedAt == nil,
        let nextProofHeight = batch.nextProofHeight
      else { return false }
      return nextProofHeight <= remoteHeight
    }
    guard
      let batchIndex = candidates.sorted(by: {
        let lhs = batches[$0]
        let rhs = batches[$1]
        return (lhs.nextProofHeight ?? 0, lhs.batchId) < (rhs.nextProofHeight ?? 0, rhs.batchId)
      }).first
    else { return nil }

    if batches[batchIndex].proofReadyNotificationPendingAt == nil {
      batches[batchIndex].proofReadyNotificationPendingAt = date
    }
    return BackgroundMigrationProofReadyMetadata(
      batchId: batches[batchIndex].batchId,
      observedHeight: remoteHeight
    )
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
        })
        .sorted(by: {
          ($0.scheduledHeight, $0.txidHex) < ($1.scheduledHeight, $1.txidHex)
        })
        .first
    else { return nil }

    lastAttemptedScopeKey = selectedScope
    return BackgroundMigrationOutboxSelection(
      batchId: batch.batchId,
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
        $0.outcome == .rejected || $0.outcome == .expired
      }.map(\.batchId)
    )
    receipts.removeAll { receiptIds.contains($0.receiptId) }
    if !terminalBatchIds.isEmpty {
      batches.removeAll { terminalBatchIds.contains($0.batchId) }
      receipts.removeAll { terminalBatchIds.contains($0.batchId) }
    }
    for batchIndex in batches.indices {
      batches[batchIndex].items.removeAll { acknowledgedItemIds.contains($0.itemId) }
    }
    batches.removeAll { $0.items.isEmpty && $0.nextProofHeight == nil }
  }

  mutating func revoke(network: String, accountUuid: String) {
    let batchIds = Set(
      batches.filter { $0.network == network && $0.accountUuid == accountUuid }
        .map(\.batchId)
    )
    batches.removeAll { batchIds.contains($0.batchId) }
    receipts.removeAll { batchIds.contains($0.batchId) }
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
    var elapsed: UInt64 = 0
    var updates: [BackgroundMigrationOutboxScheduleUpdate] = []
    for itemIndex in overdueIndexes {
      elapsed = elapsed.saturatingAdd(
        BackgroundMigrationOutboxSchedule.sampleDelay(
          meanBlocks: mean,
          maxBlocks: max,
          random: &random
        )
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
      expiryHeight: item.expiryHeight
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
}

enum BackgroundMigrationOutboxSchedule {
  static func sampleDelay(
    meanBlocks: UInt64,
    maxBlocks: UInt64,
    random: inout some RandomNumberGenerator
  ) -> UInt64 {
    precondition(meanBlocks > 0 && maxBlocks > 0)
    while true {
      let raw = random.next()
      let uniform = max(Double.leastNonzeroMagnitude, Double(raw) / Double(UInt64.max))
      let sampled = max(1, UInt64(ceil(-log(uniform) * Double(meanBlocks))))
      if sampled <= maxBlocks { return sampled }
    }
  }
}

enum BackgroundMigrationOutboxCadence {
  static let secondsPerBlock: TimeInterval = 75
  static let rollingCheckInterval: TimeInterval = 10 * 60
  static let dueLeadTime: TimeInterval = 10 * 60

  static func nextCheckDelay(remoteHeight: UInt64, nextScheduledHeight: UInt64?) -> TimeInterval? {
    guard let nextScheduledHeight else { return nil }
    if nextScheduledHeight <= remoteHeight { return 60 }
    let estimated = TimeInterval(nextScheduledHeight - remoteHeight) * secondsPerBlock
    return min(rollingCheckInterval, max(60, estimated - dueLeadTime))
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
