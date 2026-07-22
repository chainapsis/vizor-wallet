import BackgroundTasks
import CryptoKit
import Foundation
import Security
import UserNotifications

let ironwoodMigrationBackgroundCredentialService =
  "com.keplr.vizor.ironwood-migration-background.v1"

struct IronwoodMigrationBackgroundManifest: Codable, Equatable {
  let version: Int
  let network: String
  let accountUuid: String
  let dbPath: String
  let lightwalletdUrl: String
  let credentialHex: String
  let saltBase64: String
  let expectedRunId: String?

  var storageKey: String { "\(network):\(accountUuid)" }

  var isValid: Bool {
    guard version == 1,
      ["main", "test", "regtest"].contains(network),
      !accountUuid.isEmpty,
      !dbPath.isEmpty,
      !lightwalletdUrl.isEmpty,
      let expectedRunId,
      !expectedRunId.isEmpty,
      credentialHex.count == 64,
      credentialHex.utf8.allSatisfy({
        (48...57).contains($0) || (97...102).contains($0)
      }),
      let salt = Data(base64Encoded: saltBase64),
      salt.count == 16
    else {
      return false
    }
    return true
  }

  static func decode(_ data: Data) -> IronwoodMigrationBackgroundManifest? {
    guard let manifest = try? JSONDecoder().decode(Self.self, from: data),
      manifest.isValid
    else {
      return nil
    }
    return manifest
  }

  func replacingDbPath(_ resolvedDbPath: String)
    -> IronwoodMigrationBackgroundManifest
  {
    IronwoodMigrationBackgroundManifest(
      version: version,
      network: network,
      accountUuid: accountUuid,
      dbPath: resolvedDbPath,
      lightwalletdUrl: lightwalletdUrl,
      credentialHex: credentialHex,
      saltBase64: saltBase64,
      expectedRunId: expectedRunId
    )
  }
}

enum IronwoodMigrationManifestStore {
  static func loadAll() -> [IronwoodMigrationBackgroundManifest] {
    loadAllIfAccessible() ?? []
  }

  fileprivate static func loadAllIfAccessible()
    -> [IronwoodMigrationBackgroundManifest]?
  {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: ironwoodMigrationBackgroundCredentialService,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return []
    }
    guard status == errSecSuccess else {
      print("[BGMigration] keychain read failed: \(status)")
      return nil
    }
    let values: [Data]
    if let data = result as? Data {
      values = [data]
    } else {
      values = result as? [Data] ?? []
    }
    return values.compactMap(IronwoodMigrationBackgroundManifest.decode).sorted {
      if $0.network == $1.network {
        return $0.accountUuid < $1.accountUuid
      }
      return $0.network < $1.network
    }
  }

  static func delete(_ manifest: IronwoodMigrationBackgroundManifest) {
    delete(storageKey: manifest.storageKey)
  }

  static func delete(network: String, accountUuid: String) {
    delete(storageKey: "\(network):\(accountUuid)")
  }

  static func deleteAll() {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: ironwoodMigrationBackgroundCredentialService,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      print("[BGMigration] keychain delete failed: \(status)")
    }
  }

  private static func delete(storageKey: String) {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: ironwoodMigrationBackgroundCredentialService,
      kSecAttrAccount: storageKey,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      print("[BGMigration] keychain delete failed: \(status)")
    }
  }
}

enum BackgroundMigrationBlockedStore {
  private static let defaultsKey =
    "ironwoodMigrationBackgroundBlockedManifestKeys"

  static func load() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
  }

  static func mark(_ manifest: IronwoodMigrationBackgroundManifest) {
    var keys = load()
    keys.insert(manifest.storageKey)
    UserDefaults.standard.set(Array(keys).sorted(), forKey: defaultsKey)
  }

  static func remove(_ manifest: IronwoodMigrationBackgroundManifest) {
    remove(storageKey: manifest.storageKey)
  }

  static func remove(storageKey: String) {
    var keys = load()
    keys.remove(storageKey)
    UserDefaults.standard.set(Array(keys).sorted(), forKey: defaultsKey)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: defaultsKey)
  }
}

enum BackgroundMigrationCursorStore {
  private static let defaultsKey =
    "ironwoodMigrationBackgroundLastAttemptedManifestKey"

  static func load() -> String? {
    UserDefaults.standard.string(forKey: defaultsKey)
  }

  static func save(_ storageKey: String) {
    UserDefaults.standard.set(storageKey, forKey: defaultsKey)
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: defaultsKey)
  }
}

enum BackgroundMigrationNativeAction: UInt8 {
  case complete = 0
  case wait = 1
  case sync = 2
  case advance = 3
  case needsUserAction = 4
  case revokeAuthorization = 5
}

struct BackgroundMigrationNativeResult: Equatable {
  let returnCode: Int32
  let action: BackgroundMigrationNativeAction
  let cancelled: Bool
  let scannedHeight: UInt64
  let chainTipHeight: UInt64
  let nextScheduledHeight: UInt64?
  let broadcastedCount: UInt32
}

enum BackgroundMigrationRunOutcome: Equatable {
  case noWork
  case temporarilyUnavailable
  case preparing(nextHeight: UInt64?, observedHeight: UInt64)
  case waiting(nextHeight: UInt64?, observedHeight: UInt64)
  case synced(nextHeight: UInt64?, observedHeight: UInt64)
  case advanced(nextHeight: UInt64?, observedHeight: UInt64)
  case complete
  case needsUserAction
  case failed
  case cancelled
}

enum BackgroundMigrationReschedulePolicy {
  static func delay(
    after outcome: BackgroundMigrationRunOutcome,
    runnableManifestCount: Int,
    cancelledByExpiration: Bool
  ) -> TimeInterval? {
    if outcome == .temporarilyUnavailable {
      return 10 * 60
    }
    guard runnableManifestCount > 0 else {
      return nil
    }
    switch outcome {
    case .preparing:
      return 60
    case .synced(let nextHeight, let observedHeight),
      .waiting(let nextHeight, let observedHeight),
      .advanced(let nextHeight, let observedHeight):
      let delay = estimatedDelay(
        nextHeight: nextHeight,
        observedHeight: observedHeight
      )
      return runnableManifestCount > 1 ? min(delay, 2 * 60) : delay
    case .failed:
      return 10 * 60
    case .complete, .needsUserAction:
      return 60
    case .cancelled:
      return cancelledByExpiration ? 10 * 60 : nil
    case .noWork:
      return nil
    case .temporarilyUnavailable:
      return 10 * 60
    }
  }

  private static func estimatedDelay(
    nextHeight: UInt64?,
    observedHeight: UInt64
  ) -> TimeInterval {
    guard let nextHeight else {
      return 2 * 60
    }
    let remainingBlocks =
      nextHeight > observedHeight
      ? nextHeight - observedHeight : 1
    return max(60, TimeInterval(remainingBlocks) * 75)
  }
}

enum BackgroundMigrationNotificationDelivery: Equatable {
  case immediate
  case at(Date)
}

struct BackgroundMigrationNotificationPlan: Equatable {
  let identifier: String
  let delivery: BackgroundMigrationNotificationDelivery
  let title: String
  let body: String
}

struct BackgroundMigrationWatchdogState: Codable, Equatable {
  let identifier: String
  let nextScheduledHeight: UInt64?
  let deadline: Date
}

enum BackgroundMigrationNotificationPolicy {
  static let secondsPerBlock: TimeInterval = 75
  static let graceBlockCount: UInt64 = 96
  static let fallbackSchedulingBlockCount: UInt64 = 144

  static func shouldScheduleFallbackWatchdog(
    existing: BackgroundMigrationWatchdogState?,
    needsActionAlreadyNotified: Bool
  ) -> Bool {
    existing == nil && !needsActionAlreadyNotified
  }

  static func identifier(
    for manifest: IronwoodMigrationBackgroundManifest
  ) -> String {
    let identity = [
      manifest.network,
      manifest.accountUuid,
      manifest.expectedRunId ?? "unbound",
    ].joined(separator: "|")
    let digest = SHA256.hash(data: Data(identity.utf8))
      .prefix(16)
      .map { String(format: "%02x", $0) }
      .joined()
    return "com.keplr.vizor.ironwood-migration.watchdog.\(digest)"
  }

  static func watchdogDate(
    now: Date,
    nextScheduledHeight: UInt64?,
    observedHeight: UInt64
  ) -> Date {
    let blocksUntilScheduled: UInt64
    if let nextScheduledHeight {
      blocksUntilScheduled =
        nextScheduledHeight > observedHeight
        ? nextScheduledHeight - observedHeight : 0
    } else {
      // With no usable height, wait one normal scheduling interval in
      // addition to the late grace instead of warning prematurely.
      blocksUntilScheduled = fallbackSchedulingBlockCount
    }
    let delay =
      TimeInterval(blocksUntilScheduled) * secondsPerBlock
      + TimeInterval(graceBlockCount) * secondsPerBlock
    return now.addingTimeInterval(delay)
  }

  static func watchdogPlan(
    for manifest: IronwoodMigrationBackgroundManifest,
    now: Date,
    nextScheduledHeight: UInt64?,
    observedHeight: UInt64
  ) -> BackgroundMigrationNotificationPlan {
    watchdogPlan(
      for: manifest,
      deadline: watchdogDate(
        now: now,
        nextScheduledHeight: nextScheduledHeight,
        observedHeight: observedHeight
      )
    )
  }

  static func watchdogPlan(
    for manifest: IronwoodMigrationBackgroundManifest,
    deadline: Date
  ) -> BackgroundMigrationNotificationPlan {
    BackgroundMigrationNotificationPlan(
      identifier: identifier(for: manifest),
      delivery: .at(deadline),
      title: "Check your Ironwood migration",
      body: "A scheduled transfer may still be waiting. Open Vizor to review."
    )
  }

  static func resolvedWatchdogState(
    identifier: String,
    nextScheduledHeight: UInt64?,
    proposedDeadline: Date,
    existing: BackgroundMigrationWatchdogState?
  ) -> BackgroundMigrationWatchdogState {
    let deadline: Date
    if let existing,
      existing.identifier == identifier,
      existing.nextScheduledHeight == nextScheduledHeight
    {
      deadline = min(existing.deadline, proposedDeadline)
    } else {
      deadline = proposedDeadline
    }
    return BackgroundMigrationWatchdogState(
      identifier: identifier,
      nextScheduledHeight: nextScheduledHeight,
      deadline: deadline
    )
  }

  static func needsUserActionPlan(
    for manifest: IronwoodMigrationBackgroundManifest,
    alreadyNotified: Bool
  ) -> BackgroundMigrationNotificationPlan? {
    guard !alreadyNotified else { return nil }
    return BackgroundMigrationNotificationPlan(
      identifier: identifier(for: manifest),
      delivery: .immediate,
      title: "Ironwood migration needs attention",
      body: "Open Vizor to review and continue your migration."
    )
  }
}

private enum BackgroundMigrationNotificationStore {
  private static let identifiersKey =
    "ironwoodMigrationNotificationIdentifiersByManifest"
  private static let needsActionKey =
    "ironwoodMigrationNeedsActionNotificationIdentifiers"
  private static let watchdogStatesKey =
    "ironwoodMigrationWatchdogStatesByManifest"

  static func identifiersByStorageKey() -> [String: String] {
    UserDefaults.standard.dictionary(forKey: identifiersKey) as? [String: String]
      ?? [:]
  }

  static func identifier(for storageKey: String) -> String? {
    identifiersByStorageKey()[storageKey]
  }

  static func save(identifier: String, for storageKey: String) {
    var identifiers = identifiersByStorageKey()
    identifiers[storageKey] = identifier
    UserDefaults.standard.set(identifiers, forKey: identifiersKey)
  }

  @discardableResult
  static func removeIdentifier(for storageKey: String) -> String? {
    var identifiers = identifiersByStorageKey()
    let removed = identifiers.removeValue(forKey: storageKey)
    UserDefaults.standard.set(identifiers, forKey: identifiersKey)
    return removed
  }

  static func clearIdentifiers() -> [String] {
    let identifiers = Array(identifiersByStorageKey().values)
    UserDefaults.standard.removeObject(forKey: identifiersKey)
    return identifiers
  }

  static func needsActionIdentifiers() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: needsActionKey) ?? [])
  }

  static func markNeedsActionNotified(_ identifier: String) {
    var identifiers = needsActionIdentifiers()
    identifiers.insert(identifier)
    UserDefaults.standard.set(Array(identifiers).sorted(), forKey: needsActionKey)
  }

  static func clearNeedsActionNotified(_ identifier: String) {
    var identifiers = needsActionIdentifiers()
    identifiers.remove(identifier)
    UserDefaults.standard.set(Array(identifiers).sorted(), forKey: needsActionKey)
  }

  static func clearAllNeedsActionNotifications() {
    UserDefaults.standard.removeObject(forKey: needsActionKey)
  }

  static func watchdogState(
    for storageKey: String
  ) -> BackgroundMigrationWatchdogState? {
    watchdogStates()[storageKey]
  }

  static func saveWatchdogState(
    _ state: BackgroundMigrationWatchdogState,
    for storageKey: String
  ) {
    var states = watchdogStates()
    states[storageKey] = state
    saveWatchdogStates(states)
  }

  static func removeWatchdogState(for storageKey: String) {
    var states = watchdogStates()
    states.removeValue(forKey: storageKey)
    saveWatchdogStates(states)
  }

  static func clearWatchdogStates() {
    UserDefaults.standard.removeObject(forKey: watchdogStatesKey)
  }

  private static func watchdogStates()
    -> [String: BackgroundMigrationWatchdogState]
  {
    guard let data = UserDefaults.standard.data(forKey: watchdogStatesKey),
      let states = try? JSONDecoder().decode(
        [String: BackgroundMigrationWatchdogState].self,
        from: data
      )
    else {
      return [:]
    }
    return states
  }

  private static func saveWatchdogStates(
    _ states: [String: BackgroundMigrationWatchdogState]
  ) {
    guard !states.isEmpty else {
      UserDefaults.standard.removeObject(forKey: watchdogStatesKey)
      return
    }
    guard let data = try? JSONEncoder().encode(states) else {
      return
    }
    UserDefaults.standard.set(data, forKey: watchdogStatesKey)
  }
}

struct BackgroundMigrationRunnerDependencies {
  var loadManifests: () -> [IronwoodMigrationBackgroundManifest]?
  var resolveManifest: (IronwoodMigrationBackgroundManifest) -> IronwoodMigrationBackgroundManifest?
  var loadBlockedKeys: () -> Set<String>
  var loadLastAttemptedKey: () -> String?
  var saveLastAttemptedKey: (String) -> Void
  var currentCancelEpoch: () -> UInt64
  var inspect: (IronwoodMigrationBackgroundManifest) -> BackgroundMigrationNativeResult
  var runSync: (IronwoodMigrationBackgroundManifest, UInt64) -> Int32
  var runCycle: (IronwoodMigrationBackgroundManifest, UInt64) -> BackgroundMigrationNativeResult
  var deleteManifest: (IronwoodMigrationBackgroundManifest) -> Void
  var markBlocked: (IronwoodMigrationBackgroundManifest) -> Void
  var removeBlocked: (IronwoodMigrationBackgroundManifest) -> Void
  var isCancelled: () -> Bool

  static let live = BackgroundMigrationRunnerDependencies(
    loadManifests: IronwoodMigrationManifestStore.loadAllIfAccessible,
    resolveManifest: BackgroundMigrationRunner.resolveAllowedManifest,
    loadBlockedKeys: BackgroundMigrationBlockedStore.load,
    loadLastAttemptedKey: BackgroundMigrationCursorStore.load,
    saveLastAttemptedKey: BackgroundMigrationCursorStore.save,
    currentCancelEpoch: zcash_background_migration_cancellation_epoch,
    inspect: BackgroundMigrationRunner.runNativeInspection,
    runSync: BackgroundMigrationRunner.runNativeSync,
    runCycle: BackgroundMigrationRunner.runNativeCycle,
    deleteManifest: IronwoodMigrationManifestStore.delete,
    markBlocked: BackgroundMigrationBlockedStore.mark,
    removeBlocked: BackgroundMigrationBlockedStore.remove,
    isCancelled: { BackgroundMigrationManager.shared.isCancelled }
  )
}

enum BackgroundMigrationRunner {
  static func runOnce(
    dependencies: BackgroundMigrationRunnerDependencies = .live
  ) -> BackgroundMigrationRunOutcome {
    guard let manifests = dependencies.loadManifests() else {
      return .temporarilyUnavailable
    }
    guard !manifests.isEmpty else {
      return .noWork
    }
    let blockedKeys = dependencies.loadBlockedKeys()
    let runnable = manifests.filter { !blockedKeys.contains($0.storageKey) }
    guard !runnable.isEmpty else {
      return .needsUserAction
    }
    let ordered: [IronwoodMigrationBackgroundManifest]
    if let lastKey = dependencies.loadLastAttemptedKey(),
      let lastIndex = runnable.firstIndex(where: { $0.storageKey == lastKey })
    {
      let nextIndex = (lastIndex + 1) % runnable.count
      ordered = Array(runnable[nextIndex...]) + Array(runnable[..<nextIndex])
    } else {
      ordered = runnable
    }
    var manifest: IronwoodMigrationBackgroundManifest?
    for candidate in ordered {
      if let resolved = dependencies.resolveManifest(candidate) {
        manifest = resolved
        break
      }
      dependencies.markBlocked(candidate)
    }
    guard let manifest else {
      return .needsUserAction
    }
    dependencies.saveLastAttemptedKey(manifest.storageKey)
    guard !dependencies.isCancelled() else {
      return .cancelled
    }
    let cancelEpoch = dependencies.currentCancelEpoch()
    let inspection = dependencies.inspect(manifest)
    guard inspection.returnCode == 0 else {
      return .failed
    }
    switch inspection.action {
    case .complete:
      dependencies.deleteManifest(manifest)
      dependencies.removeBlocked(manifest)
      return .complete
    case .needsUserAction:
      dependencies.markBlocked(manifest)
      return .needsUserAction
    case .revokeAuthorization:
      dependencies.deleteManifest(manifest)
      dependencies.removeBlocked(manifest)
      return .needsUserAction
    case .wait, .sync:
      let syncResult = dependencies.runSync(manifest, cancelEpoch)
      guard syncResult == 0 else {
        return syncResult == 5 || dependencies.isCancelled() ? .cancelled : .failed
      }
      guard !dependencies.isCancelled() else {
        return .cancelled
      }
      let refreshed = dependencies.inspect(manifest)
      guard refreshed.returnCode == 0 else {
        return .failed
      }
      switch refreshed.action {
      case .complete:
        dependencies.deleteManifest(manifest)
        dependencies.removeBlocked(manifest)
        return .complete
      case .needsUserAction:
        dependencies.markBlocked(manifest)
        return .needsUserAction
      case .revokeAuthorization:
        dependencies.deleteManifest(manifest)
        dependencies.removeBlocked(manifest)
        return .needsUserAction
      case .wait, .sync, .advance:
        break
      }
      return .synced(
        nextHeight: refreshed.nextScheduledHeight,
        observedHeight: refreshed.chainTipHeight
      )
    case .advance:
      break
    }

    let result = dependencies.runCycle(manifest, cancelEpoch)
    guard result.returnCode == 0 else {
      return .failed
    }
    if result.cancelled || dependencies.isCancelled() {
      return .cancelled
    }
    if result.broadcastedCount > 0 {
      return .advanced(
        nextHeight: result.nextScheduledHeight,
        observedHeight: result.chainTipHeight
      )
    }
    if result.action == .advance,
      let nextHeight = result.nextScheduledHeight,
      result.chainTipHeight < nextHeight
    {
      return .preparing(
        nextHeight: nextHeight,
        observedHeight: result.chainTipHeight
      )
    }
    switch result.action {
    case .complete:
      dependencies.deleteManifest(manifest)
      dependencies.removeBlocked(manifest)
      return .complete
    case .needsUserAction:
      dependencies.markBlocked(manifest)
      return .needsUserAction
    case .revokeAuthorization:
      dependencies.deleteManifest(manifest)
      dependencies.removeBlocked(manifest)
      return .needsUserAction
    case .wait, .sync, .advance:
      return .waiting(
        nextHeight: result.nextScheduledHeight,
        observedHeight: result.chainTipHeight
      )
    }
  }

  fileprivate static func resolveAllowedManifest(
    _ manifest: IronwoodMigrationBackgroundManifest
  ) -> IronwoodMigrationBackgroundManifest? {
    guard let support = try? resolveWalletSupportDirectory()
    else {
      return nil
    }
    let dbName = URL(fileURLWithPath: manifest.dbPath).lastPathComponent
    let currentDbPath = support.appendingPathComponent(dbName).path
    return resolveAllowedManifest(
      manifest,
      currentDbPath: currentDbPath,
      supportDirectory: support
    )
  }

  static func resolveAllowedManifest(
    _ manifest: IronwoodMigrationBackgroundManifest,
    currentDbPath: String,
    supportDirectory: URL
  ) -> IronwoodMigrationBackgroundManifest? {
    guard manifest.isValid,
      let endpoint = URL(string: manifest.lightwalletdUrl),
      ["http", "https"].contains(endpoint.scheme?.lowercased() ?? ""),
      FileManager.default.fileExists(atPath: currentDbPath)
    else {
      return nil
    }
    let storedDbUrl = URL(fileURLWithPath: manifest.dbPath).standardizedFileURL
    let currentDbUrl = URL(fileURLWithPath: currentDbPath).standardizedFileURL
    let supportUrl = supportDirectory.standardizedFileURL
    guard storedDbUrl.lastPathComponent == currentDbUrl.lastPathComponent,
      currentDbUrl.deletingLastPathComponent() == supportUrl
    else {
      return nil
    }
    return manifest.replacingDbPath(currentDbUrl.path)
  }

  fileprivate static func runNativeSync(
    manifest: IronwoodMigrationBackgroundManifest,
    cancelEpoch: UInt64
  ) -> Int32 {
    zcash_run_full_sync_for_migration(
      manifest.dbPath,
      manifest.lightwalletdUrl,
      manifest.network,
      cancelEpoch,
      { _ in }
    )
  }

  fileprivate static func runNativeInspection(
    manifest: IronwoodMigrationBackgroundManifest
  ) -> BackgroundMigrationNativeResult {
    guard let expectedRunId = manifest.expectedRunId else {
      return failedNativeResult()
    }
    var output = CBackgroundMigrationResult()
    let returnCode = zcash_inspect_background_migration(
      manifest.dbPath,
      manifest.network,
      manifest.accountUuid,
      expectedRunId,
      &output
    )
    guard let action = BackgroundMigrationNativeAction(rawValue: output.action) else {
      return failedNativeResult(returnCode: returnCode)
    }
    return BackgroundMigrationNativeResult(
      returnCode: returnCode,
      action: action,
      cancelled: output.cancelled,
      scannedHeight: output.scanned_height,
      chainTipHeight: output.chain_tip_height,
      nextScheduledHeight: output.next_scheduled_height == 0
        ? nil : output.next_scheduled_height,
      broadcastedCount: output.broadcasted_count
    )
  }

  fileprivate static func runNativeCycle(
    manifest: IronwoodMigrationBackgroundManifest,
    cancelEpoch: UInt64
  ) -> BackgroundMigrationNativeResult {
    guard let expectedRunId = manifest.expectedRunId else {
      return failedNativeResult()
    }
    var output = CBackgroundMigrationResult()
    let credential = Array(manifest.credentialHex.utf8)
    let returnCode = credential.withUnsafeBufferPointer { bytes in
      zcash_run_background_migration_cycle(
        manifest.dbPath,
        manifest.lightwalletdUrl,
        manifest.network,
        manifest.accountUuid,
        expectedRunId,
        bytes.baseAddress,
        UInt(bytes.count),
        manifest.saltBase64,
        cancelEpoch,
        &output
      )
    }
    guard let action = BackgroundMigrationNativeAction(rawValue: output.action) else {
      return failedNativeResult(returnCode: returnCode)
    }
    return BackgroundMigrationNativeResult(
      returnCode: returnCode,
      action: action,
      cancelled: output.cancelled,
      scannedHeight: output.scanned_height,
      chainTipHeight: output.chain_tip_height,
      nextScheduledHeight: output.next_scheduled_height == 0
        ? nil : output.next_scheduled_height,
      broadcastedCount: output.broadcasted_count
    )
  }

  private static func failedNativeResult(
    returnCode: Int32 = 1
  ) -> BackgroundMigrationNativeResult {
    BackgroundMigrationNativeResult(
      returnCode: returnCode,
      action: .needsUserAction,
      cancelled: false,
      scannedHeight: 0,
      chainTipHeight: 0,
      nextScheduledHeight: nil,
      broadcastedCount: 0
    )
  }
}

private final class BackgroundMigrationNotificationCoordinator {
  static let shared = BackgroundMigrationNotificationCoordinator()

  private let center: UNUserNotificationCenter
  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-migration.notifications",
    qos: .utility
  )
  private var addGenerationByStorageKey: [String: UInt64] = [:]
  private var inFlightAddCountByStorageKey: [String: Int] = [:]
  private var cancellationWaitersByStorageKey: [String: [() -> Void]] = [:]
  private var cancelAllWaiters: [() -> Void] = []

  private init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
      if let error {
        print("[BGMigration] notification authorization failed: \(error)")
      }
      if granted {
        guard let self else {
          DispatchQueue.main.async { completion(false) }
          return
        }
        self.reconcile(completion: { completion(true) })
        return
      }
      DispatchQueue.main.async { completion(false) }
    }
  }

  func reconcile(
    after outcome: BackgroundMigrationRunOutcome? = nil,
    attemptedStorageKey: String? = nil,
    now: Date = Date(),
    completion: (() -> Void)? = nil
  ) {
    queue.async { [weak self] in
      guard let self else {
        if let completion {
          DispatchQueue.main.async(execute: completion)
        }
        return
      }
      let pendingAdds = DispatchGroup()
      self.reconcileOnQueue(
        after: outcome,
        attemptedStorageKey: attemptedStorageKey,
        now: now,
        pendingAdds: pendingAdds
      )
      pendingAdds.notify(queue: self.queue) {
        if let completion {
          DispatchQueue.main.async(execute: completion)
        }
      }
    }
  }

  func cancel(
    storageKey: String,
    completion: (() -> Void)? = nil
  ) {
    queue.async { [weak self] in
      guard let self else {
        if let completion {
          DispatchQueue.main.async(execute: completion)
        }
        return
      }
      self.invalidateAdds(for: storageKey)
      let identifier = BackgroundMigrationNotificationStore.removeIdentifier(
        for: storageKey
      )
      BackgroundMigrationNotificationStore.removeWatchdogState(
        for: storageKey
      )
      if let identifier {
        self.cancelNotification(identifier)
      }
      self.afterInFlightAddsFinish(for: storageKey) {
        if let identifier {
          self.cancelNotification(identifier)
        }
        if let completion {
          DispatchQueue.main.async(execute: completion)
        }
      }
    }
  }

  func cancelAll(completion: (() -> Void)? = nil) {
    queue.async { [weak self] in
      guard let self else {
        if let completion {
          DispatchQueue.main.async(execute: completion)
        }
        return
      }
      for storageKey in self.inFlightAddCountByStorageKey.keys {
        self.invalidateAdds(for: storageKey)
      }
      let identifiers = BackgroundMigrationNotificationStore.clearIdentifiers()
      BackgroundMigrationNotificationStore.clearAllNeedsActionNotifications()
      BackgroundMigrationNotificationStore.clearWatchdogStates()
      self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
      self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
      self.afterAllInFlightAddsFinish {
        self.center.removePendingNotificationRequests(withIdentifiers: identifiers)
        self.center.removeDeliveredNotifications(withIdentifiers: identifiers)
        if let completion {
          DispatchQueue.main.async(execute: completion)
        }
      }
    }
  }

  private func reconcileOnQueue(
    after outcome: BackgroundMigrationRunOutcome?,
    attemptedStorageKey: String?,
    now: Date,
    pendingAdds: DispatchGroup
  ) {
    guard let manifests = IronwoodMigrationManifestStore.loadAllIfAccessible()
    else {
      return
    }
    let blockedKeys = BackgroundMigrationBlockedStore.load()
    let activeStorageKeys = Set(manifests.map(\.storageKey))

    for manifest in manifests {
      let identifier = registerIdentifier(for: manifest)
      if blockedKeys.contains(manifest.storageKey) {
        scheduleNeedsUserAction(
          for: manifest,
          identifier: identifier,
          pendingAdds: pendingAdds
        )
        continue
      }
      if manifest.storageKey == attemptedStorageKey,
        let outcome,
        apply(
          outcome: outcome,
          to: manifest,
          identifier: identifier,
          now: now,
          pendingAdds: pendingAdds
        )
      {
        continue
      }
      reconcileInspection(
        for: manifest,
        identifier: identifier,
        now: now,
        pendingAdds: pendingAdds
      )
    }

    for storageKey
      in BackgroundMigrationNotificationStore
      .identifiersByStorageKey().keys where !activeStorageKeys.contains(storageKey)
    {
      cancel(
        storageKey: storageKey,
        identifier: BackgroundMigrationNotificationStore.identifier(
          for: storageKey
        ),
        pendingAdds: pendingAdds
      )
    }
  }

  private func registerIdentifier(
    for manifest: IronwoodMigrationBackgroundManifest
  ) -> String {
    let identifier = BackgroundMigrationNotificationPolicy.identifier(for: manifest)
    if let previous = BackgroundMigrationNotificationStore.identifier(
      for: manifest.storageKey
    ), previous != identifier {
      BackgroundMigrationNotificationStore.removeWatchdogState(
        for: manifest.storageKey
      )
      cancelNotification(previous)
    }
    BackgroundMigrationNotificationStore.save(
      identifier: identifier,
      for: manifest.storageKey
    )
    return identifier
  }

  private func apply(
    outcome: BackgroundMigrationRunOutcome,
    to manifest: IronwoodMigrationBackgroundManifest,
    identifier: String,
    now: Date,
    pendingAdds: DispatchGroup
  ) -> Bool {
    switch outcome {
    case .preparing(let nextHeight, let observedHeight),
      .waiting(let nextHeight, let observedHeight),
      .synced(let nextHeight, let observedHeight),
      .advanced(let nextHeight, let observedHeight):
      scheduleWatchdog(
        for: manifest,
        identifier: identifier,
        now: now,
        nextScheduledHeight: nextHeight,
        observedHeight: observedHeight,
        pendingAdds: pendingAdds
      )
      return true
    case .needsUserAction:
      scheduleNeedsUserAction(
        for: manifest,
        identifier: identifier,
        pendingAdds: pendingAdds
      )
      return true
    case .complete:
      cancel(
        manifest: manifest,
        identifier: identifier,
        pendingAdds: pendingAdds
      )
      return true
    case .noWork, .temporarilyUnavailable, .failed, .cancelled:
      return false
    }
  }

  private func reconcileInspection(
    for manifest: IronwoodMigrationBackgroundManifest,
    identifier: String,
    now: Date,
    pendingAdds: DispatchGroup
  ) {
    guard
      let resolvedManifest =
        BackgroundMigrationRunner
        .resolveAllowedManifest(manifest)
    else {
      scheduleNeedsUserAction(
        for: manifest,
        identifier: identifier,
        pendingAdds: pendingAdds
      )
      return
    }
    let inspection = BackgroundMigrationRunner.runNativeInspection(
      manifest: resolvedManifest
    )
    guard inspection.returnCode == 0 else {
      let existing = BackgroundMigrationNotificationStore.watchdogState(
        for: manifest.storageKey
      )
      let needsActionAlreadyNotified =
        BackgroundMigrationNotificationStore
        .needsActionIdentifiers().contains(identifier)
      guard
        BackgroundMigrationNotificationPolicy.shouldScheduleFallbackWatchdog(
          existing: existing,
          needsActionAlreadyNotified: needsActionAlreadyNotified
        )
      else {
        return
      }
      scheduleWatchdog(
        for: manifest,
        identifier: identifier,
        now: now,
        nextScheduledHeight: nil,
        observedHeight: 0,
        pendingAdds: pendingAdds
      )
      return
    }
    switch inspection.action {
    case .complete, .revokeAuthorization:
      cancel(
        manifest: manifest,
        identifier: identifier,
        pendingAdds: pendingAdds
      )
    case .needsUserAction:
      scheduleNeedsUserAction(
        for: manifest,
        identifier: identifier,
        pendingAdds: pendingAdds
      )
    case .wait, .sync, .advance:
      scheduleWatchdog(
        for: manifest,
        identifier: identifier,
        now: now,
        nextScheduledHeight: inspection.nextScheduledHeight,
        observedHeight: inspection.chainTipHeight,
        pendingAdds: pendingAdds
      )
    }
  }

  private func scheduleWatchdog(
    for manifest: IronwoodMigrationBackgroundManifest,
    identifier: String,
    now: Date,
    nextScheduledHeight: UInt64?,
    observedHeight: UInt64,
    pendingAdds: DispatchGroup
  ) {
    BackgroundMigrationNotificationStore.clearNeedsActionNotified(identifier)
    let existingState = BackgroundMigrationNotificationStore.watchdogState(
      for: manifest.storageKey
    )
    let proposedDeadline = BackgroundMigrationNotificationPolicy.watchdogDate(
      now: now,
      nextScheduledHeight: nextScheduledHeight,
      observedHeight: observedHeight
    )
    let state = BackgroundMigrationNotificationPolicy.resolvedWatchdogState(
      identifier: identifier,
      nextScheduledHeight: nextScheduledHeight,
      proposedDeadline: proposedDeadline,
      existing: existingState
    )
    guard state != existingState else { return }
    if let existingState,
      existingState.identifier != state.identifier
        || existingState.nextScheduledHeight != state.nextScheduledHeight
    {
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    BackgroundMigrationNotificationStore.removeWatchdogState(
      for: manifest.storageKey
    )
    add(
      BackgroundMigrationNotificationPolicy.watchdogPlan(
        for: manifest,
        deadline: state.deadline
      ),
      storageKey: manifest.storageKey,
      pendingAdds: pendingAdds
    ) {
      BackgroundMigrationNotificationStore.saveWatchdogState(
        state,
        for: manifest.storageKey
      )
    }
  }

  private func scheduleNeedsUserAction(
    for manifest: IronwoodMigrationBackgroundManifest,
    identifier: String,
    pendingAdds: DispatchGroup
  ) {
    let alreadyNotified =
      BackgroundMigrationNotificationStore
      .needsActionIdentifiers().contains(identifier)
    guard !alreadyNotified else { return }

    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    if BackgroundMigrationNotificationStore.watchdogState(
      for: manifest.storageKey
    ) != nil {
      center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    BackgroundMigrationNotificationStore.removeWatchdogState(
      for: manifest.storageKey
    )
    guard
      let plan = BackgroundMigrationNotificationPolicy.needsUserActionPlan(
        for: manifest,
        alreadyNotified: false
      )
    else {
      return
    }
    add(
      plan,
      storageKey: manifest.storageKey,
      pendingAdds: pendingAdds
    ) {
      BackgroundMigrationNotificationStore.markNeedsActionNotified(identifier)
    }
  }

  private func add(
    _ plan: BackgroundMigrationNotificationPlan,
    storageKey: String,
    pendingAdds: DispatchGroup,
    onSuccess: @escaping () -> Void
  ) {
    let generation = nextAddGeneration(for: storageKey)
    inFlightAddCountByStorageKey[storageKey, default: 0] += 1
    pendingAdds.enter()
    center.removePendingNotificationRequests(withIdentifiers: [plan.identifier])
    let content = UNMutableNotificationContent()
    content.title = plan.title
    content.body = plan.body
    content.sound = .default

    let trigger: UNNotificationTrigger?
    switch plan.delivery {
    case .immediate:
      trigger = nil
    case .at(let date):
      trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: max(1, date.timeIntervalSinceNow),
        repeats: false
      )
    }
    let request = UNNotificationRequest(
      identifier: plan.identifier,
      content: content,
      trigger: trigger
    )
    center.add(request) { [self] error in
      queue.async {
        defer {
          self.finishInFlightAdd(for: storageKey)
          pendingAdds.leave()
        }
        if let error {
          print("[BGMigration] notification scheduling failed: \(error)")
          return
        }
        guard self.addGenerationByStorageKey[storageKey] == generation else {
          if BackgroundMigrationNotificationStore.identifier(for: storageKey)
            != plan.identifier
          {
            self.cancelNotification(plan.identifier)
          }
          return
        }
        onSuccess()
      }
    }
  }

  private func cancel(
    manifest: IronwoodMigrationBackgroundManifest,
    identifier: String,
    pendingAdds: DispatchGroup
  ) {
    cancel(
      storageKey: manifest.storageKey,
      identifier: identifier,
      pendingAdds: pendingAdds
    )
  }

  private func cancel(
    storageKey: String,
    identifier: String?,
    pendingAdds: DispatchGroup
  ) {
    invalidateAdds(for: storageKey)
    _ = BackgroundMigrationNotificationStore.removeIdentifier(
      for: storageKey
    )
    BackgroundMigrationNotificationStore.removeWatchdogState(
      for: storageKey
    )
    if let identifier {
      cancelNotification(identifier)
    }
    guard inFlightAddCountByStorageKey[storageKey, default: 0] > 0
    else {
      return
    }
    pendingAdds.enter()
    afterInFlightAddsFinish(for: storageKey) { [self] in
      if let identifier {
        cancelNotification(identifier)
      }
      pendingAdds.leave()
    }
  }

  private func cancelNotification(_ identifier: String) {
    BackgroundMigrationNotificationStore.clearNeedsActionNotified(identifier)
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }

  private func nextAddGeneration(for storageKey: String) -> UInt64 {
    let generation = addGenerationByStorageKey[storageKey, default: 0] &+ 1
    addGenerationByStorageKey[storageKey] = generation
    return generation
  }

  private func invalidateAdds(for storageKey: String) {
    _ = nextAddGeneration(for: storageKey)
  }

  private func afterInFlightAddsFinish(
    for storageKey: String,
    _ completion: @escaping () -> Void
  ) {
    guard inFlightAddCountByStorageKey[storageKey, default: 0] > 0 else {
      completion()
      return
    }
    cancellationWaitersByStorageKey[storageKey, default: []].append(completion)
  }

  private func afterAllInFlightAddsFinish(_ completion: @escaping () -> Void) {
    guard !inFlightAddCountByStorageKey.isEmpty else {
      completion()
      return
    }
    cancelAllWaiters.append(completion)
  }

  private func finishInFlightAdd(for storageKey: String) {
    let remaining = inFlightAddCountByStorageKey[storageKey, default: 0] - 1
    if remaining > 0 {
      inFlightAddCountByStorageKey[storageKey] = remaining
      return
    }
    inFlightAddCountByStorageKey.removeValue(forKey: storageKey)
    let storageKeyWaiters =
      cancellationWaitersByStorageKey.removeValue(
        forKey: storageKey
      ) ?? []
    for waiter in storageKeyWaiters {
      waiter()
    }
    guard inFlightAddCountByStorageKey.isEmpty else { return }
    let allWaiters = cancelAllWaiters
    cancelAllWaiters.removeAll()
    for waiter in allWaiters {
      waiter()
    }
  }
}

final class BackgroundMigrationManager {
  static let shared = BackgroundMigrationManager()
  static let taskIdentifier = "com.keplr.vizor.ironwood-migration"

  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-migration",
    qos: .utility
  )
  private let stateLock = NSLock()
  private var cancelled = false
  private var expired = false
  private var mutationQuiesced = false

  private init() {}

  var isCancelled: Bool {
    stateLock.vizorWithLock { cancelled }
  }

  private var shouldRetryCancelledWake: Bool {
    stateLock.vizorWithLock { expired }
  }

  private var isMutationQuiesced: Bool {
    stateLock.vizorWithLock { mutationQuiesced }
  }

  func registerBackgroundTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.taskIdentifier,
      using: nil
    ) { task in
      guard let processingTask = task as? BGProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handle(processingTask)
    }
  }

  func requestNotificationAuthorization(
    completion: @escaping (Bool) -> Void
  ) {
    BackgroundMigrationNotificationCoordinator.shared.requestAuthorization(
      completion: completion
    )
  }

  @discardableResult
  func schedule(
    earliestBeginDate: Date = Date(),
    clearsBlockedManifests: Bool = true
  ) -> Bool {
    guard !isMutationQuiesced else { return false }
    if clearsBlockedManifests {
      BackgroundMigrationBlockedStore.clear()
    }
    let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
    request.requiresNetworkConnectivity = true
    request.requiresExternalPower = false
    request.earliestBeginDate = earliestBeginDate
    let submitted: Bool
    do {
      try BGTaskScheduler.shared.submit(request)
      submitted = true
    } catch {
      print("[BGMigration] schedule failed: \(error)")
      submitted = false
    }
    BackgroundMigrationNotificationCoordinator.shared.reconcile()
    return submitted
  }

  func cancel() {
    stopActiveWork(quiesceForMutation: false)
  }

  private func stopActiveWork(quiesceForMutation: Bool) {
    stateLock.vizorWithLock {
      cancelled = true
      expired = false
      if quiesceForMutation {
        mutationQuiesced = true
      }
    }
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    zcash_cancel_background_migration()
    zcash_cancel_sync()
  }

  func cancelIfNoRunnableWork() {
    if hasRunnableManifest() {
      _ = schedule(
        earliestBeginDate: Date().addingTimeInterval(60),
        clearsBlockedManifests: false
      )
    } else {
      BackgroundMigrationNotificationCoordinator.shared.reconcile()
      cancel()
    }
  }

  func quiesce(completion: @escaping (Bool) -> Void) {
    stopActiveWork(quiesceForMutation: true)
    queue.async {
      DispatchQueue.main.async { completion(true) }
    }
  }

  func resumeAfterFailedMutation() -> Bool {
    endMutationQuiescence()
    guard hasRunnableManifest() else {
      BackgroundMigrationNotificationCoordinator.shared.reconcile()
      return true
    }
    return schedule(
      earliestBeginDate: Date().addingTimeInterval(60),
      clearsBlockedManifests: false
    )
  }

  func revokeAccount(
    network: String,
    accountUuid: String,
    completion: @escaping (Bool) -> Void
  ) {
    stopActiveWork(quiesceForMutation: true)
    queue.async { [weak self] in
      let storageKey = "\(network):\(accountUuid)"
      IronwoodMigrationManifestStore.delete(
        network: network,
        accountUuid: accountUuid
      )
      BackgroundMigrationBlockedStore.remove(storageKey: storageKey)
      if BackgroundMigrationCursorStore.load() == storageKey {
        BackgroundMigrationCursorStore.clear()
      }
      BackgroundMigrationNotificationCoordinator.shared.cancel(
        storageKey: storageKey,
        completion: {
          self?.scheduleRemainingWork()
          completion(true)
        }
      )
    }
  }

  func revokeAll(completion: @escaping (Bool) -> Void) {
    stopActiveWork(quiesceForMutation: true)
    queue.async {
      IronwoodMigrationManifestStore.deleteAll()
      BackgroundMigrationBlockedStore.clear()
      BackgroundMigrationCursorStore.clear()
      BackgroundMigrationNotificationCoordinator.shared.cancelAll {
        completion(true)
      }
    }
  }

  func runOnceForTesting() -> BackgroundMigrationRunOutcome {
    guard prepareForBackgroundWake() else { return .cancelled }
    return BackgroundMigrationRunner.runOnce()
  }

  func resumeWithoutSchedulingForTesting() -> Bool {
    endMutationQuiescence()
    return true
  }

  private func handle(_ task: BGProcessingTask) {
    guard prepareForBackgroundWake() else {
      task.setTaskCompleted(success: true)
      return
    }
    task.expirationHandler = { [weak self] in
      self?.expire()
    }
    queue.async { [weak self] in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      let outcome = BackgroundMigrationRunner.runOnce()
      self.reschedule(after: outcome) {
        task.setTaskCompleted(
          success: outcome != .failed && outcome != .cancelled
        )
      }
    }
  }

  private func prepareForBackgroundWake() -> Bool {
    stateLock.vizorWithLock {
      guard !mutationQuiesced else { return false }
      cancelled = false
      expired = false
      return true
    }
  }

  private func endMutationQuiescence() {
    stateLock.vizorWithLock {
      mutationQuiesced = false
      cancelled = false
      expired = false
    }
  }

  private func expire() {
    stateLock.vizorWithLock {
      cancelled = true
      expired = true
    }
    zcash_cancel_background_migration()
    zcash_cancel_sync()
  }

  private func reschedule(
    after outcome: BackgroundMigrationRunOutcome,
    completion: @escaping () -> Void
  ) {
    BackgroundMigrationNotificationCoordinator.shared.reconcile(
      after: outcome,
      attemptedStorageKey: BackgroundMigrationCursorStore.load(),
      completion: { [weak self] in
        guard let self else {
          completion()
          return
        }
        let delay = BackgroundMigrationReschedulePolicy.delay(
          after: outcome,
          runnableManifestCount: self.runnableManifestCount(),
          cancelledByExpiration: self.shouldRetryCancelledWake
        )
        if let delay {
          _ = self.schedule(
            earliestBeginDate: Date().addingTimeInterval(delay),
            clearsBlockedManifests: false
          )
        }
        completion()
      }
    )
  }

  private func hasRunnableManifest() -> Bool {
    runnableManifestCount() > 0
  }

  private func runnableManifestCount() -> Int {
    let blocked = BackgroundMigrationBlockedStore.load()
    return IronwoodMigrationManifestStore.loadAll().filter {
      !blocked.contains($0.storageKey)
    }.count
  }

  private func scheduleRemainingWork() {
    endMutationQuiescence()
    if hasRunnableManifest() {
      _ = schedule(
        earliestBeginDate: Date().addingTimeInterval(60),
        clearsBlockedManifests: false
      )
    }
  }

}

extension NSLock {
  fileprivate func vizorWithLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
