import Flutter
import Foundation

enum BackgroundMigrationOutboxChannelError: Error {
  case invalidArguments(String)
  case receiptNotFound
}

enum BackgroundMigrationOutboxChannel {
  static func stageBatch(
    arguments: Any?,
    store: BackgroundMigrationOutboxStore = .shared
  ) throws -> [String: String] {
    let batch = try decodeBatch(arguments)
    _ = try store.update { snapshot in try snapshot.stage(batch) }
    return Dictionary(
      uniqueKeysWithValues: batch.items.map { ($0.itemId, $0.payloadDigestHex) }
    )
  }

  static func armBatch(
    arguments: Any?,
    store: BackgroundMigrationOutboxStore = .shared
  ) throws {
    let arguments = try dictionary(arguments)
    let batchId = try string(arguments, "batchId")
    guard let rawDigests = arguments["expectedDigests"] as? [String: String] else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments("expectedDigests")
    }
    _ = try store.update { snapshot in
      try snapshot.armBatch(
        batchId: batchId,
        expectedDigests: rawDigests,
        at: Date()
      )
    }
  }

  static func recoverBatch(
    arguments: Any?,
    store: BackgroundMigrationOutboxStore = .shared
  ) throws -> Bool {
    let arguments = try dictionary(arguments)
    guard let expectedTxids = arguments["expectedTxids"] as? [String] else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments("expectedTxids")
    }
    var recovered = false
    _ = try store.update { snapshot in
      recovered = try snapshot.recoverBatch(
        batchId: string(arguments, "batchId"),
        network: string(arguments, "network"),
        accountUuid: string(arguments, "accountUuid"),
        runId: string(arguments, "runId"),
        expectedTxids: Set(expectedTxids),
        lightwalletdUrl: string(arguments, "lightwalletdUrl"),
        at: Date()
      )
    }
    return recovered
  }

  static func listReceipts(
    store: BackgroundMigrationOutboxStore = .shared
  ) throws -> [[String: Any]] {
    let snapshot = try store.read()
    return snapshot.receipts.map { receipt in
      let rawTransaction = snapshot.batches
        .first(where: { $0.batchId == receipt.batchId })?.items
        .first(where: { $0.itemId == receipt.itemId })?.rawTransaction
      let encodedRawTransaction: Any = rawTransaction.map {
        FlutterStandardTypedData(bytes: $0) as Any
      } ?? NSNull()
      return [
        "receiptId": receipt.receiptId,
        "batchId": receipt.batchId,
        "itemId": receipt.itemId,
        "network": receipt.network,
        "accountUuid": receipt.accountUuid,
        "runId": receipt.runId,
        "txidHex": receipt.txidHex,
        "outcome": receipt.outcome.rawValue,
        "remoteHeight": receipt.remoteHeight,
        "responseCode": receipt.responseCode as Any,
        "responseMessage": receipt.responseMessage as Any,
        "rawTransaction": encodedRawTransaction,
        "recordedAtMs": Int64(receipt.recordedAt.timeIntervalSince1970 * 1000),
        "scheduleUpdates": receipt.scheduleUpdates.map { update in
          [
            "itemId": update.itemId,
            "scheduledHeight": update.scheduledHeight,
            "scheduleStartHeight": update.scheduleStartHeight,
          ]
        },
      ]
    }
  }

  static func acknowledgeReceipts(
    arguments: Any?,
    store: BackgroundMigrationOutboxStore = .shared
  ) throws {
    let arguments = try dictionary(arguments)
    guard let receiptIds = arguments["receiptIds"] as? [String] else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments("receiptIds")
    }
    _ = try store.update { snapshot in
      snapshot.acknowledgeReceipts(Set(receiptIds))
    }
  }

  static func revoke(
    network: String,
    accountUuid: String,
    store: BackgroundMigrationOutboxStore = .shared
  ) throws {
    _ = try store.update { snapshot in
      snapshot.revoke(network: network, accountUuid: accountUuid)
    }
  }

  static func removeAll(store: BackgroundMigrationOutboxStore = .shared) throws {
    try store.removeAll()
  }

  static func runOnceNow(
    store: BackgroundMigrationOutboxStore = .shared
  ) -> BackgroundMigrationOutboxRunResult {
    BackgroundMigrationOutboxRunner.runOnce(
      store: store,
      cancellation: BackgroundMigrationCancellation()
    )
  }

  private static func decodeBatch(_ raw: Any?) throws -> BackgroundMigrationOutboxBatch {
    let arguments = try dictionary(raw)
    guard let rawItems = arguments["items"] as? [[String: Any]] else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments("items")
    }
    let items = try rawItems.map { rawItem -> BackgroundMigrationOutboxItem in
      guard let typedData = rawItem["rawTransaction"] as? FlutterStandardTypedData else {
        throw BackgroundMigrationOutboxChannelError.invalidArguments("rawTransaction")
      }
      return BackgroundMigrationOutboxItem(
        itemId: try string(rawItem, "itemId"),
        partIndex: try uint32(rawItem, "partIndex"),
        txidHex: try string(rawItem, "txidHex"),
        rawTransaction: typedData.data,
        anchorBoundaryHeight: try uint64(rawItem, "anchorBoundaryHeight"),
        scheduledHeight: try uint64(rawItem, "scheduledHeight"),
        scheduleStartHeight: try uint64(rawItem, "scheduleStartHeight"),
        expiryHeight: try uint64(rawItem, "expiryHeight")
      )
    }
    return BackgroundMigrationOutboxBatch(
      batchId: try string(arguments, "batchId"),
      network: try string(arguments, "network"),
      accountUuid: try string(arguments, "accountUuid"),
      runId: try string(arguments, "runId"),
      lightwalletdUrl: try string(arguments, "lightwalletdUrl"),
      timingMeanBlocks: try uint64(arguments, "timingMeanBlocks"),
      timingMaxBlocks: try uint64(arguments, "timingMaxBlocks"),
      createdAt: Date(
        timeIntervalSince1970: TimeInterval(try int64(arguments, "createdAtMs")) / 1000
      ),
      armedAt: nil,
      nextProofHeight: try optionalUInt64(arguments, "nextProofHeight"),
      proofReadyNotificationPendingAt: nil,
      proofReadyNotifiedAt: nil,
      items: items
    )
  }

  private static func dictionary(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments("arguments")
    }
    return value
  }

  private static func string(_ values: [String: Any], _ key: String) throws -> String {
    guard let value = values[key] as? String, !value.isEmpty else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments(key)
    }
    return value
  }

  private static func int64(_ values: [String: Any], _ key: String) throws -> Int64 {
    guard let number = values[key] as? NSNumber else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments(key)
    }
    return number.int64Value
  }

  private static func uint64(_ values: [String: Any], _ key: String) throws -> UInt64 {
    let value = try int64(values, key)
    guard value >= 0 else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments(key)
    }
    return UInt64(value)
  }

  private static func optionalUInt64(
    _ values: [String: Any],
    _ key: String
  ) throws -> UInt64? {
    guard let rawValue = values[key], !(rawValue is NSNull) else { return nil }
    guard let number = rawValue as? NSNumber, number.int64Value >= 0 else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments(key)
    }
    return UInt64(number.int64Value)
  }

  private static func uint32(_ values: [String: Any], _ key: String) throws -> UInt32 {
    let value = try uint64(values, key)
    guard value <= UInt64(UInt32.max) else {
      throw BackgroundMigrationOutboxChannelError.invalidArguments(key)
    }
    return UInt32(value)
  }
}
