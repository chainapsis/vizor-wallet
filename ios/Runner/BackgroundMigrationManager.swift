import BackgroundTasks
import Foundation
import Security

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
}

enum IronwoodMigrationManifestStore {
  static func loadAll() -> [IronwoodMigrationBackgroundManifest] {
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
      return []
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
    guard runnableManifestCount > 0 else {
      return nil
    }
    switch outcome {
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
    }
  }

  private static func estimatedDelay(
    nextHeight: UInt64?,
    observedHeight: UInt64
  ) -> TimeInterval {
    guard let nextHeight else {
      return 2 * 60
    }
    let remainingBlocks = nextHeight > observedHeight
      ? nextHeight - observedHeight : 1
    return max(60, TimeInterval(remainingBlocks) * 75)
  }
}

struct BackgroundMigrationRunnerDependencies {
  var loadManifests: () -> [IronwoodMigrationBackgroundManifest]
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
    loadManifests: IronwoodMigrationManifestStore.loadAll,
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
    let manifests = dependencies.loadManifests()
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
      if isAllowed(candidate) {
        manifest = candidate
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

  private static func isAllowed(
    _ manifest: IronwoodMigrationBackgroundManifest
  ) -> Bool {
    guard manifest.isValid,
      let endpoint = URL(string: manifest.lightwalletdUrl),
      ["http", "https"].contains(endpoint.scheme?.lowercased() ?? ""),
      FileManager.default.fileExists(atPath: manifest.dbPath),
      let support = try? resolveWalletSupportDirectory()
    else {
      return false
    }
    let dbUrl = URL(fileURLWithPath: manifest.dbPath).standardizedFileURL
    let supportUrl = support.standardizedFileURL
    return dbUrl.deletingLastPathComponent() == supportUrl
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
    do {
      try BGTaskScheduler.shared.submit(request)
      return true
    } catch {
      print("[BGMigration] schedule failed: \(error)")
      return false
    }
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
    guard hasRunnableManifest() else { return true }
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
      self?.scheduleRemainingWork()
      DispatchQueue.main.async { completion(true) }
    }
  }

  func revokeAll(completion: @escaping (Bool) -> Void) {
    stopActiveWork(quiesceForMutation: true)
    queue.async {
      IronwoodMigrationManifestStore.deleteAll()
      BackgroundMigrationBlockedStore.clear()
      BackgroundMigrationCursorStore.clear()
      DispatchQueue.main.async { completion(true) }
    }
  }

  func runOnceForTesting() -> BackgroundMigrationRunOutcome {
    guard prepareForBackgroundWake() else { return .cancelled }
    return BackgroundMigrationRunner.runOnce()
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
      self.reschedule(after: outcome)
      task.setTaskCompleted(success: outcome != .failed && outcome != .cancelled)
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

  private func reschedule(after outcome: BackgroundMigrationRunOutcome) {
    let delay = BackgroundMigrationReschedulePolicy.delay(
      after: outcome,
      runnableManifestCount: runnableManifestCount(),
      cancelledByExpiration: shouldRetryCancelledWake
    )
    guard let delay else { return }
    _ = schedule(
      earliestBeginDate: Date().addingTimeInterval(delay),
      clearsBlockedManifests: false
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
