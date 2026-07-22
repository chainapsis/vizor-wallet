import BackgroundTasks
import CryptoKit
import Foundation
import Security
import UserNotifications

let ironwoodMigrationBackgroundCredentialService =
  "com.keplr.vizor.ironwood-migration-background.v1"

struct IronwoodMigrationBackgroundManifest: Decodable {
  let version: Int
  let network: String
  let accountUuid: String
  let dbPath: String
  let lightwalletdUrl: String
  let credentialHex: String
  let saltBase64: String
  let expectedRunId: String?
}

enum IronwoodMigrationBackgroundCredentialStore {
  static func loadAll() -> [IronwoodMigrationBackgroundManifest]? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: ironwoodMigrationBackgroundCredentialService,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess else {
      print("[BGMigration] keychain load failed: \(status)")
      return nil
    }
    let values: [Data]
    if let data = result as? Data {
      values = [data]
    } else {
      values = result as? [Data] ?? []
    }
    var manifests: [IronwoodMigrationBackgroundManifest] = []
    for value in values {
      guard
        let manifest = try? JSONDecoder().decode(
          IronwoodMigrationBackgroundManifest.self,
          from: value
        )
      else {
        print("[BGMigration] keychain manifest decode failed")
        return nil
      }
      manifests.append(manifest)
    }
    return manifests.sorted {
      ($0.network, $0.accountUuid) < ($1.network, $1.accountUuid)
    }
  }

  static func delete(network: String, accountUuid: String) {
    delete(account: "\(network):\(accountUuid)")
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

  private static func delete(account: String) {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: ironwoodMigrationBackgroundCredentialService,
      kSecAttrAccount: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      print("[BGMigration] keychain delete failed: \(status)")
    }
  }
}

private enum BackgroundMigrationNotification {
  static let needsActionIdentifier =
    "com.keplr.vizor.ironwood-migration.needs-action"

  static func proofReadyIdentifier(batchId: String) -> String {
    let digest = SHA256.hash(data: Data(batchId.utf8))
      .prefix(16)
      .map { String(format: "%02x", $0) }
      .joined()
    return "com.keplr.vizor.ironwood-migration.proof-ready.\(digest)"
  }

  static func remove(batchIds: [String], includeNeedsAction: Bool) {
    var identifiers = batchIds.map(proofReadyIdentifier)
    if includeNeedsAction {
      identifiers.append(needsActionIdentifier)
    }
    guard !identifiers.isEmpty else { return }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }
}

final class BackgroundMigrationManager {
  static let shared = BackgroundMigrationManager()
  static let taskIdentifier = "com.keplr.vizor.ironwood-migration"

  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-migration.outbox",
    qos: .utility
  )
  private let stateLock = NSLock()
  private var expired = false
  private var mutationQuiesced = false
  private var activeCancellation: BackgroundMigrationCancellation?

  private init() {}

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
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { granted, _ in completion(granted) }
  }

  @discardableResult
  func schedule(earliestBeginDate: Date = Date()) -> Bool {
    guard !isMutationQuiesced else { return false }
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
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

  func cancelIfNoRunnableWork() {
    if hasRunnableOutboxWork() {
      _ = schedule(earliestBeginDate: Date().addingTimeInterval(60))
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
    guard hasRunnableOutboxWork() else { return true }
    return schedule(earliestBeginDate: Date().addingTimeInterval(60))
  }

  func revokeAccount(
    network: String,
    accountUuid: String,
    completion: @escaping (Bool) -> Void
  ) {
    stopActiveWork(quiesceForMutation: true)
    queue.async { [weak self] in
      let batchIds = self?.batchIds(network: network, accountUuid: accountUuid) ?? []
      let revoked =
        (try? BackgroundMigrationOutboxChannel.revoke(
          network: network,
          accountUuid: accountUuid
        )) != nil
      if revoked {
        IronwoodMigrationBackgroundCredentialStore.delete(
          network: network,
          accountUuid: accountUuid
        )
      }
      let hasRemainingWork = self?.hasRunnableOutboxWork() ?? false
      BackgroundMigrationNotification.remove(
        batchIds: batchIds,
        includeNeedsAction: !hasRemainingWork
      )
      self?.scheduleRemainingWork()
      DispatchQueue.main.async { completion(revoked) }
    }
  }

  func revokeAll(completion: @escaping (Bool) -> Void) {
    stopActiveWork(quiesceForMutation: true)
    queue.async { [weak self] in
      let batchIds =
        (try? BackgroundMigrationOutboxStore.shared.read().batches.map(\.batchId))
        ?? []
      let removed = (try? BackgroundMigrationOutboxChannel.removeAll()) != nil
      if removed {
        IronwoodMigrationBackgroundCredentialStore.deleteAll()
      }
      BackgroundMigrationNotification.remove(
        batchIds: batchIds,
        includeNeedsAction: true
      )
      self?.endMutationQuiescence()
      DispatchQueue.main.async { completion(removed) }
    }
  }

  #if DEBUG || targetEnvironment(simulator)
    func runOnceForTesting() -> BackgroundMigrationOutboxRunResult {
      guard prepareForBackgroundWake() else {
        return BackgroundMigrationOutboxRunResult(
          transport: .cancelled,
          proofReady: nil
        )
      }
      let cancellation = BackgroundMigrationCancellation()
      stateLock.vizorWithLock { activeCancellation = cancellation }
      defer { stateLock.vizorWithLock { activeCancellation = nil } }
      return BackgroundMigrationOutboxRunner.runOnce(cancellation: cancellation)
    }

    func resumeWithoutSchedulingForTesting() -> Bool {
      endMutationQuiescence()
      return true
    }
  #endif

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
      let cancellation = BackgroundMigrationCancellation()
      self.stateLock.vizorWithLock {
        self.activeCancellation = cancellation
      }
      let runResult = BackgroundMigrationOutboxRunner.runOnce(
        cancellation: cancellation
      )
      self.stateLock.vizorWithLock {
        self.activeCancellation = nil
      }
      self.finishWake(runResult) {
        task.setTaskCompleted(
          success: runResult.transport != .temporarilyUnavailable
            && runResult.transport != .cancelled
        )
      }
    }
  }

  private func stopActiveWork(quiesceForMutation: Bool) {
    stateLock.vizorWithLock {
      expired = false
      activeCancellation?.cancel()
      activeCancellation = nil
      if quiesceForMutation {
        mutationQuiesced = true
      }
    }
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
  }

  private func prepareForBackgroundWake() -> Bool {
    stateLock.vizorWithLock {
      guard !mutationQuiesced else { return false }
      expired = false
      activeCancellation = nil
      return true
    }
  }

  private func endMutationQuiescence() {
    stateLock.vizorWithLock {
      mutationQuiesced = false
      expired = false
      activeCancellation = nil
    }
  }

  private func expire() {
    stateLock.vizorWithLock {
      expired = true
      activeCancellation?.cancel()
    }
  }

  private func finishWake(
    _ runResult: BackgroundMigrationOutboxRunResult,
    completion: @escaping () -> Void
  ) {
    guard let proofReady = runResult.proofReady else {
      reschedule(
        after: runResult.transport,
        retryProofNotification: false,
        completion: completion
      )
      return
    }

    postProofReadyNotification(batchId: proofReady.batchId) { [weak self] delivered in
      guard let self else {
        completion()
        return
      }
      var acknowledged = false
      if delivered {
        acknowledged =
          (try? BackgroundMigrationOutboxStore.shared.update { snapshot in
            try snapshot.acknowledgeProofReadyNotification(
              batchId: proofReady.batchId,
              at: Date()
            )
          }) != nil
      }
      self.reschedule(
        after: runResult.transport,
        retryProofNotification: !delivered || !acknowledged,
        completion: completion
      )
    }
  }

  private func reschedule(
    after transport: BackgroundMigrationTransportOutcome,
    retryProofNotification: Bool,
    completion: @escaping () -> Void
  ) {
    if transport == .needsUserAction {
      postNeedsUserActionNotification()
    }

    var delay: TimeInterval?
    switch transport {
    case .waiting(_, _, let requestedDelay),
      .accepted(_, _, let requestedDelay):
      delay = requestedDelay
    case .temporarilyUnavailable:
      delay = 10 * 60
    case .cancelled:
      delay = shouldRetryCancelledWake ? 10 * 60 : nil
    case .noWork, .needsUserAction:
      delay = nil
    }
    if retryProofNotification {
      delay = min(delay ?? 10 * 60, 10 * 60)
    }
    if hasRunnableOutboxWork() {
      delay = min(delay ?? 60, 10 * 60)
    }
    if let delay {
      _ = schedule(earliestBeginDate: Date().addingTimeInterval(delay))
    }
    completion()
  }

  private func hasRunnableOutboxWork() -> Bool {
    guard let snapshot = try? BackgroundMigrationOutboxStore.shared.read() else {
      return true
    }
    return snapshot.batches.contains { batch in
      (batch.armedAt != nil
        && batch.items.contains { item in
          item.status == .armed || item.status == .submitting
        }) || (batch.nextProofHeight != nil && batch.proofReadyNotifiedAt == nil)
    }
  }

  private func batchIds(network: String, accountUuid: String) -> [String] {
    guard let snapshot = try? BackgroundMigrationOutboxStore.shared.read() else {
      return []
    }
    return snapshot.batches.filter {
      $0.network == network && $0.accountUuid == accountUuid
    }.map(\.batchId)
  }

  private func scheduleRemainingWork() {
    endMutationQuiescence()
    if hasRunnableOutboxWork() {
      _ = schedule(earliestBeginDate: Date().addingTimeInterval(60))
    }
  }

  private func postNeedsUserActionNotification() {
    let content = UNMutableNotificationContent()
    content.title = "Ironwood migration needs attention"
    content.body = "Open Vizor to review and continue your migration."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: BackgroundMigrationNotification.needsActionIdentifier,
        content: content,
        trigger: nil
      )
    )
  }

  private func postProofReadyNotification(
    batchId: String,
    completion: @escaping (Bool) -> Void
  ) {
    let content = UNMutableNotificationContent()
    content.title = "Continue your Ironwood migration"
    content.body = "Open Vizor to prepare the next migration transfer."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: BackgroundMigrationNotification.proofReadyIdentifier(
          batchId: batchId
        ),
        content: content,
        trigger: nil
      )
    ) { error in completion(error == nil) }
  }
}

extension NSLock {
  fileprivate func vizorWithLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
