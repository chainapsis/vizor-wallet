import Foundation

enum BackgroundVotingShareChannelError: Error {
  case invalidArguments(String)
}

/// Argument decoding for the `com.zcash.wallet/background_voting` method
/// channel. Pure Foundation on purpose: share payloads cross the channel as
/// UTF-8 JSON strings, so no Flutter types are needed and the decoding stays
/// unit-testable without a Flutter engine.
enum BackgroundVotingShareChannel {
  /// Stages (idempotently merges) one round and returns the natively computed
  /// `shareKey -> payloadDigestHex` map for the stage-to-arm handshake.
  static func stageShareRound(
    arguments: Any?,
    store: BackgroundVotingShareOutboxStore = .shared
  ) throws -> [String: String] {
    let decoded = try decodeRound(arguments)
    _ = try store.update { snapshot in
      try snapshot.stage(decoded.round, prune: decoded.prune)
    }
    return Dictionary(
      uniqueKeysWithValues: decoded.round.shares.map {
        ($0.shareKey, $0.payloadDigestHex)
      }
    )
  }

  static func armShareRound(
    arguments: Any?,
    store: BackgroundVotingShareOutboxStore = .shared
  ) throws {
    let arguments = try dictionary(arguments)
    let roundKey = try string(arguments, "roundKey")
    guard let rawDigests = arguments["expectedDigests"] as? [String: String] else {
      throw BackgroundVotingShareChannelError.invalidArguments("expectedDigests")
    }
    _ = try store.update { snapshot in
      try snapshot.armRound(
        roundKey: roundKey,
        expectedDigests: rawDigests,
        at: Date()
      )
    }
  }

  static func hasShareRound(
    arguments: Any?,
    store: BackgroundVotingShareOutboxStore = .shared
  ) throws -> Bool {
    let arguments = try dictionary(arguments)
    guard let expectedShareKeys = arguments["expectedShareKeys"] as? [String] else {
      throw BackgroundVotingShareChannelError.invalidArguments("expectedShareKeys")
    }
    return try store.read().hasRound(
      roundKey: try string(arguments, "roundKey"),
      expectedShareKeys: Set(expectedShareKeys)
    )
  }

  static func listShareReceipts(
    store: BackgroundVotingShareOutboxStore = .shared
  ) throws -> [[String: Any]] {
    try store.read().receipts.map { receipt in
      [
        "receiptId": receipt.receiptId,
        "roundKey": receipt.roundKey,
        "network": receipt.network,
        "accountUuid": receipt.accountUuid,
        "roundId": receipt.roundId,
        "bundleIndex": receipt.bundleIndex,
        "proposalId": receipt.proposalId,
        "shareIndex": receipt.shareIndex,
        "shareIdHex": receipt.shareIdHex,
        "outcome": receipt.outcome.rawValue,
        "url": receipt.url as Any,
        "recordedAtSeconds": Int64(receipt.recordedAt.timeIntervalSince1970),
      ]
    }
  }

  static func acknowledgeShareReceipts(
    arguments: Any?,
    store: BackgroundVotingShareOutboxStore = .shared
  ) throws {
    let arguments = try dictionary(arguments)
    guard let receiptIds = arguments["receiptIds"] as? [String] else {
      throw BackgroundVotingShareChannelError.invalidArguments("receiptIds")
    }
    _ = try store.update { snapshot in
      snapshot.acknowledgeReceipts(Set(receiptIds))
    }
  }

  static func revoke(
    network: String,
    accountUuid: String,
    store: BackgroundVotingShareOutboxStore = .shared
  ) throws {
    _ = try store.update { snapshot in
      snapshot.revoke(network: network, accountUuid: accountUuid)
    }
  }

  static func removeAll(store: BackgroundVotingShareOutboxStore = .shared) throws {
    try store.removeAll()
  }

  private static func decodeRound(
    _ raw: Any?
  ) throws -> (round: BackgroundVotingShareRound, prune: Bool) {
    let arguments = try dictionary(raw)
    guard let rawShares = arguments["shares"] as? [[String: Any]] else {
      throw BackgroundVotingShareChannelError.invalidArguments("shares")
    }
    let shares = try rawShares.map { rawShare -> BackgroundVotingShare in
      // The pre-rendered POST body crosses the channel as a UTF-8 JSON
      // string; the exact bytes staged here are the exact bytes resubmitted.
      let bodyJson = try string(rawShare, "recoveryBodyJson")
      return BackgroundVotingShare(
        bundleIndex: try uint32(rawShare, "bundleIndex"),
        proposalId: try uint32(rawShare, "proposalId"),
        shareIndex: try uint32(rawShare, "shareIndex"),
        shareIdHex: try string(rawShare, "shareIdHex"),
        submitAtSeconds: try uint64(rawShare, "submitAtSeconds"),
        createdAtSeconds: try uint64(rawShare, "createdAtSeconds"),
        recoveryBodyJson: Data(bodyJson.utf8),
        sentToUrls: try stringArray(rawShare, "sentToUrls")
      )
    }
    let round = BackgroundVotingShareRound(
      network: try string(arguments, "network"),
      accountUuid: try string(arguments, "accountUuid"),
      roundId: try string(arguments, "roundId"),
      voteEndSeconds: try uint64(arguments, "voteEndSeconds"),
      helperUrls: try stringArray(arguments, "helperUrls"),
      createdAt: Date(),
      shares: shares
    )
    return (round, try bool(arguments, "prune"))
  }

  private static func dictionary(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else {
      throw BackgroundVotingShareChannelError.invalidArguments("arguments")
    }
    return value
  }

  private static func string(_ values: [String: Any], _ key: String) throws -> String {
    guard let value = values[key] as? String, !value.isEmpty else {
      throw BackgroundVotingShareChannelError.invalidArguments(key)
    }
    return value
  }

  private static func stringArray(
    _ values: [String: Any],
    _ key: String
  ) throws -> [String] {
    guard let value = values[key] as? [String] else {
      throw BackgroundVotingShareChannelError.invalidArguments(key)
    }
    return value
  }

  private static func bool(_ values: [String: Any], _ key: String) throws -> Bool {
    guard let value = values[key] as? Bool else {
      throw BackgroundVotingShareChannelError.invalidArguments(key)
    }
    return value
  }

  private static func int64(_ values: [String: Any], _ key: String) throws -> Int64 {
    guard let number = values[key] as? NSNumber else {
      throw BackgroundVotingShareChannelError.invalidArguments(key)
    }
    return number.int64Value
  }

  private static func uint64(_ values: [String: Any], _ key: String) throws -> UInt64 {
    let value = try int64(values, key)
    guard value >= 0 else {
      throw BackgroundVotingShareChannelError.invalidArguments(key)
    }
    return UInt64(value)
  }

  private static func uint32(_ values: [String: Any], _ key: String) throws -> UInt32 {
    let value = try uint64(values, key)
    guard value <= UInt64(UInt32.max) else {
      throw BackgroundVotingShareChannelError.invalidArguments(key)
    }
    return UInt32(value)
  }
}
