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

enum IronwoodMigrationNotificationAuthorizationStatus: String, Equatable {
  case notDetermined
  case denied
  case authorized

  init(_ status: UNAuthorizationStatus) {
    switch status {
    case .notDetermined:
      self = .notDetermined
    case .denied:
      self = .denied
    case .authorized, .provisional, .ephemeral:
      self = .authorized
    @unknown default:
      self = .denied
    }
  }

  var allowsBackgroundMigration: Bool {
    self == .authorized
  }
}

enum IronwoodMigrationOutboxArmSchedulePolicy {
  static func reportsSuccess(
    authorization: IronwoodMigrationNotificationAuthorizationStatus,
    submitted: Bool
  ) -> Bool {
    !authorization.allowsBackgroundMigration || submitted
  }
}

struct IronwoodMigrationNotificationAuthorizationEpochState {
  private(set) var generation: UInt64 = 0
  private(set) var isDisabled = false

  mutating func disable() {
    generation &+= 1
    isDisabled = true
  }

  mutating func authorize(ifCurrent expectedGeneration: UInt64) -> Bool {
    guard generation == expectedGeneration else { return false }
    isDisabled = false
    return true
  }
}

enum IronwoodMigrationOutboxWakeDisposition: Equatable {
  case continueBackgroundWork
  case finishForegroundOnly

  var shouldDeliverNotifications: Bool {
    self == .continueBackgroundWork
  }

  var shouldReschedule: Bool {
    self == .continueBackgroundWork
  }

  var taskCompletionIsSuccessful: Bool {
    self == .finishForegroundOnly
  }
}

final class IronwoodMigrationNotificationAuthorizationMonitor {
  typealias StatusProvider =
    (@escaping (IronwoodMigrationNotificationAuthorizationStatus) -> Void) -> Void

  private let pollInterval: TimeInterval
  private let queue: DispatchQueue
  private let statusProvider: StatusProvider
  private let lock = NSLock()
  private var timer: DispatchSourceTimer?
  private var checkInFlight = false
  private var isStopped = true
  private var unauthorizedHandler: (() -> Void)?

  init(
    pollInterval: TimeInterval = 1,
    queue: DispatchQueue = DispatchQueue(
      label: "com.keplr.vizor.ironwood-notification-authorization",
      qos: .utility
    ),
    statusProvider: @escaping StatusProvider =
      IronwoodMigrationNotificationGate.shared.status
  ) {
    self.pollInterval = pollInterval
    self.queue = queue
    self.statusProvider = statusProvider
  }

  func start(onUnauthorized: @escaping () -> Void) {
    let source = DispatchSource.makeTimerSource(queue: queue)
    let shouldStart = lock.vizorWithLock { () -> Bool in
      guard timer == nil else { return false }
      isStopped = false
      unauthorizedHandler = onUnauthorized
      timer = source
      return true
    }
    guard shouldStart else { return }
    source.schedule(deadline: .now(), repeating: pollInterval)
    source.setEventHandler { [weak self] in
      self?.checkAuthorization()
    }
    source.resume()
  }

  func cancel() {
    let source = lock.vizorWithLock { () -> DispatchSourceTimer? in
      guard !isStopped || timer != nil else { return nil }
      isStopped = true
      checkInFlight = false
      unauthorizedHandler = nil
      defer { timer = nil }
      return timer
    }
    source?.setEventHandler {}
    source?.cancel()
  }

  private func checkAuthorization() {
    let shouldCheck = lock.vizorWithLock { () -> Bool in
      guard !isStopped && !checkInFlight else { return false }
      checkInFlight = true
      return true
    }
    guard shouldCheck else { return }

    statusProvider { [weak self] status in
      guard let self else { return }
      guard !status.allowsBackgroundMigration else {
        self.lock.vizorWithLock {
          self.checkInFlight = false
        }
        return
      }

      let stopped = self.lock.vizorWithLock {
        () -> (DispatchSourceTimer?, (() -> Void)?) in
        guard !self.isStopped else {
          self.checkInFlight = false
          return (nil, nil)
        }
        self.isStopped = true
        self.checkInFlight = false
        let source = self.timer
        let handler = self.unauthorizedHandler
        self.timer = nil
        self.unauthorizedHandler = nil
        return (source, handler)
      }
      stopped.0?.setEventHandler {}
      stopped.0?.cancel()
      stopped.1?()
    }
  }
}

final class IronwoodMigrationNotificationGate {
  static let shared = IronwoodMigrationNotificationGate()

  private init() {}

  func status(
    completion: @escaping (IronwoodMigrationNotificationAuthorizationStatus) -> Void
  ) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      completion(
        IronwoodMigrationNotificationAuthorizationStatus(
          settings.authorizationStatus
        )
      )
    }
  }

  func requestAuthorization(
    completion: @escaping (IronwoodMigrationNotificationAuthorizationStatus) -> Void
  ) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    ) { _, _ in
      self.status(completion: completion)
    }
  }

  func openSettings(completion: @escaping (Bool) -> Void) {
    DispatchQueue.main.async {
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        completion(false)
        return
      }
      UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
  }

  func enforceOnForeground() {
    status { status in
      guard !status.allowsBackgroundMigration else { return }
      self.hardDisable()
    }
  }

  func hardDisable() {
    BackgroundMigrationManager.shared.disableForUnauthorizedNotifications()
    if #available(iOS 26.0, *) {
      BackgroundMigrationPreparationManager.shared
        .disableForUnauthorizedNotifications()
    }
    BackgroundMigrationNotification.removeAll()
  }
}

private enum BackgroundMigrationNotification {
  private static let identifierPrefix =
    "com.keplr.vizor.ironwood-"
  static let needsActionIdentifier =
    "com.keplr.vizor.ironwood-migration.needs-action"

  static func proofReadyIdentifier(batchId: String) -> String {
    let digest = SHA256.hash(data: Data(batchId.utf8))
      .prefix(16)
      .map { String(format: "%02x", $0) }
      .joined()
    return "com.keplr.vizor.ironwood-migration.proof-ready.\(digest)"
  }

  static func broadcastCompleteIdentifier(batchId: String) -> String {
    let digest = SHA256.hash(data: Data(batchId.utf8))
      .prefix(16)
      .map { String(format: "%02x", $0) }
      .joined()
    return "com.keplr.vizor.ironwood-migration.sent.\(digest)"
  }

  static func remove(batchIds: [String], includeNeedsAction: Bool) {
    var identifiers = batchIds.flatMap {
      [proofReadyIdentifier(batchId: $0), broadcastCompleteIdentifier(batchId: $0)]
    }
    if includeNeedsAction {
      identifiers.append(needsActionIdentifier)
    }
    guard !identifiers.isEmpty else { return }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  static func removeAll() {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      center.removePendingNotificationRequests(
        withIdentifiers: requests
          .map(\.identifier)
          .filter { $0.hasPrefix(identifierPrefix) }
      )
    }
    center.getDeliveredNotifications { notifications in
      center.removeDeliveredNotifications(
        withIdentifiers: notifications
          .map(\.request.identifier)
          .filter { $0.hasPrefix(identifierPrefix) }
      )
    }
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
  private var foregroundHandoffRequested = false
  private var notificationAuthorization =
    IronwoodMigrationNotificationAuthorizationEpochState()
  private var activeCancellation: BackgroundMigrationCancellation?
  private var authorizationMonitor:
    IronwoodMigrationNotificationAuthorizationMonitor?

  private init() {}

  private var shouldRetryCancelledWake: Bool {
    stateLock.vizorWithLock { expired }
  }

  private var isMutationQuiesced: Bool {
    stateLock.vizorWithLock { mutationQuiesced }
  }

  private var isNotificationWorkDisabled: Bool {
    stateLock.vizorWithLock { notificationAuthorization.isDisabled }
  }

  private var wakeDisposition: IronwoodMigrationOutboxWakeDisposition {
    isNotificationWorkDisabled || isForegroundHandoffRequested
      ? .finishForegroundOnly
      : .continueBackgroundWork
  }

  private var isForegroundHandoffRequested: Bool {
    stateLock.vizorWithLock { foregroundHandoffRequested }
  }

  func handoffToForeground() {
    stateLock.vizorWithLock {
      foregroundHandoffRequested = true
      activeCancellation?.cancel()
    }
    if #available(iOS 26.0, *) {
      BackgroundMigrationPreparationManager.shared.handoffToForeground()
    }
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

  func schedule(
    earliestBeginDate: Date = Date(),
    completion: @escaping (Bool) -> Void
  ) {
    guard !isMutationQuiesced else {
      completion(false)
      return
    }
    let authorizationEpoch = captureNotificationAuthorizationEpoch()
    IronwoodMigrationNotificationGate.shared.status { [weak self] status in
      guard let self else {
        completion(false)
        return
      }
      guard status.allowsBackgroundMigration else {
        IronwoodMigrationNotificationGate.shared.hardDisable()
        completion(false)
        return
      }
      guard self.enableNotificationWork(ifCurrent: authorizationEpoch) else {
        completion(false)
        return
      }
      completion(self.submitAuthorized(earliestBeginDate: earliestBeginDate))
    }
  }

  private func submitAuthorized(earliestBeginDate: Date) -> Bool {
    stateLock.vizorWithLock {
      guard !mutationQuiesced && !notificationAuthorization.isDisabled else {
        return false
      }
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
  }

  func schedulePreparationHandoff(
    after delay: TimeInterval,
    completion: @escaping (Bool) -> Void
  ) {
    let effectiveDelay = hasRunnableOutboxWork() ? min(delay, 60) : delay
    schedule(
      earliestBeginDate: Date().addingTimeInterval(effectiveDelay),
      completion: completion
    )
  }

  func cancel() {
    stopActiveWork(quiesceForMutation: false)
  }

  func cancelIfNoRunnableWork() {
    if hasRunnableOutboxWork() || hasResumablePreparationWork() {
      schedule(earliestBeginDate: Date().addingTimeInterval(60)) { _ in }
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

  func resumeAfterFailedMutation(completion: @escaping (Bool) -> Void) {
    endMutationQuiescence()
    guard hasRunnableOutboxWork() else {
      completion(true)
      return
    }
    schedule(
      earliestBeginDate: Date().addingTimeInterval(60),
      completion: completion
    )
  }

  func disableForUnauthorizedNotifications() {
    let monitor = stateLock.vizorWithLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      notificationAuthorization.disable()
      expired = false
      activeCancellation?.cancel()
      activeCancellation = nil
      defer { authorizationMonitor = nil }
      return authorizationMonitor
    }
    monitor?.cancel()
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
  }

  private func captureNotificationAuthorizationEpoch() -> UInt64 {
    stateLock.vizorWithLock {
      notificationAuthorization.generation
    }
  }

  private func enableNotificationWork(ifCurrent epoch: UInt64) -> Bool {
    stateLock.vizorWithLock {
      notificationAuthorization.authorize(ifCurrent: epoch)
    }
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
    let authorizationEpoch = captureNotificationAuthorizationEpoch()
    IronwoodMigrationNotificationGate.shared.status { [weak self] status in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      guard status.allowsBackgroundMigration else {
        IronwoodMigrationNotificationGate.shared.hardDisable()
        task.setTaskCompleted(success: true)
        return
      }
      guard self.enableNotificationWork(ifCurrent: authorizationEpoch) else {
        task.setTaskCompleted(success: true)
        return
      }
      self.handleAuthorized(task)
    }
  }

  private func handleAuthorized(_ task: BGProcessingTask) {
    guard prepareForBackgroundWake() else {
      task.setTaskCompleted(success: true)
      return
    }
    startAuthorizationMonitoring()
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
      if #available(iOS 26.0, *) {
        BackgroundMigrationPreparationManager.shared.runDeferredPass {
          preparationResult in
          self.runOutbox(
            task: task,
            cancellation: cancellation,
            preparationResult: preparationResult
          )
        }
      } else {
        self.runOutbox(
          task: task,
          cancellation: cancellation,
          preparationResult: .completed
        )
      }
    }
  }

  private func runOutbox(
    task: BGProcessingTask,
    cancellation: BackgroundMigrationCancellation,
    preparationResult: BackgroundMigrationPreparationPassResult
  ) {
    let authorizationEpoch = captureNotificationAuthorizationEpoch()
    IronwoodMigrationNotificationGate.shared.status { [weak self] status in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      guard status.allowsBackgroundMigration else {
        IronwoodMigrationNotificationGate.shared.hardDisable()
        task.setTaskCompleted(success: true)
        return
      }
      guard self.enableNotificationWork(ifCurrent: authorizationEpoch) else {
        self.finishForegroundOnly(task)
        return
      }
      self.queue.async {
        guard self.wakeDisposition == .continueBackgroundWork else {
          self.finishForegroundOnly(task)
          return
        }
        let runResult = BackgroundMigrationOutboxRunner.runOnce(
          cancellation: cancellation
        )
        self.clearActiveCancellation()
        guard self.wakeDisposition == .continueBackgroundWork else {
          self.finishForegroundOnly(task)
          return
        }
        self.finishWake(
          runResult,
          preparationResult: preparationResult
        ) { rescheduled in
          let preparationSucceeded =
            migrationPreparationBackgroundWakeSucceeded(preparationResult)
          self.stopAuthorizationMonitoring()
          if self.wakeDisposition == .finishForegroundOnly {
            task.setTaskCompleted(
              success: self.wakeDisposition.taskCompletionIsSuccessful
            )
            return
          }
          task.setTaskCompleted(
            success: runResult.transport != .temporarilyUnavailable
              && runResult.transport != .cancelled
              && preparationSucceeded
              && rescheduled
          )
        }
      }
    }
  }

  private func clearActiveCancellation() {
    stateLock.vizorWithLock {
      activeCancellation = nil
    }
  }

  private func finishForegroundOnly(_ task: BGProcessingTask) {
    let disposition = wakeDisposition
    clearActiveCancellation()
    stopAuthorizationMonitoring()
    task.setTaskCompleted(
      success: disposition.taskCompletionIsSuccessful
    )
  }

  private func startAuthorizationMonitoring() {
    let monitor = IronwoodMigrationNotificationAuthorizationMonitor()
    let previous = stateLock.vizorWithLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      defer { authorizationMonitor = monitor }
      return authorizationMonitor
    }
    previous?.cancel()
    monitor.start {
      IronwoodMigrationNotificationGate.shared.hardDisable()
    }
  }

  private func stopAuthorizationMonitoring() {
    let monitor = stateLock.vizorWithLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      defer { authorizationMonitor = nil }
      return authorizationMonitor
    }
    monitor?.cancel()
  }

  private func stopActiveWork(quiesceForMutation: Bool) {
    let monitor = stateLock.vizorWithLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      expired = false
      activeCancellation?.cancel()
      activeCancellation = nil
      defer { authorizationMonitor = nil }
      if quiesceForMutation {
        mutationQuiesced = true
      }
      return authorizationMonitor
    }
    monitor?.cancel()
    if #available(iOS 26.0, *), quiesceForMutation {
      BackgroundMigrationPreparationManager.shared
        .cancelDeferredPass()
    }
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
  }

  private func prepareForBackgroundWake() -> Bool {
    stateLock.vizorWithLock {
      guard !mutationQuiesced && !notificationAuthorization.isDisabled else {
        return false
      }
      expired = false
      foregroundHandoffRequested = false
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
    if #available(iOS 26.0, *) {
      BackgroundMigrationPreparationManager.shared.expireDeferredPass()
    }
  }

  private func finishWake(
    _ runResult: BackgroundMigrationOutboxRunResult,
    preparationResult: BackgroundMigrationPreparationPassResult,
    completion: @escaping (Bool) -> Void
  ) {
    guard wakeDisposition.shouldDeliverNotifications else {
      completion(true)
      return
    }
    deliverBroadcastCompleteNotification(
      runResult.broadcastComplete
    ) { [weak self] broadcastCompleteAcknowledged in
      guard let self else {
        completion(false)
        return
      }
      guard self.wakeDisposition.shouldDeliverNotifications else {
        completion(true)
        return
      }
      self.deliverProofReadyNotification(
        runResult.proofReady
      ) { proofReadyAcknowledged in
        guard self.wakeDisposition.shouldReschedule else {
          completion(true)
          return
        }
        self.reschedule(
          after: runResult.transport,
          retryProofNotification: !proofReadyAcknowledged,
          retryBroadcastCompleteNotification: !broadcastCompleteAcknowledged,
          preparationResult: preparationResult,
          completion: completion
        )
      }
    }
  }

  private func reschedule(
    after transport: BackgroundMigrationTransportOutcome,
    retryProofNotification: Bool,
    retryBroadcastCompleteNotification: Bool,
    preparationResult: BackgroundMigrationPreparationPassResult,
    completion: @escaping (Bool) -> Void
  ) {
    guard wakeDisposition.shouldReschedule else {
      completion(true)
      return
    }
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
    if retryProofNotification || retryBroadcastCompleteNotification {
      delay = min(delay ?? 10 * 60, 10 * 60)
    }
    if preparationResult == .waitingForConfirmations {
      delay = min(delay ?? 60, 60)
    } else if case .deferred(let preparationDelay) = preparationResult {
      delay = min(delay ?? preparationDelay, preparationDelay)
    }
    if hasRunnableOutboxWork() {
      delay = min(delay ?? 60, 10 * 60)
    }
    let rescheduled: Bool
    if let delay {
      schedule(
        earliestBeginDate: Date().addingTimeInterval(delay)
      ) { rescheduled in
        guard self.wakeDisposition.shouldReschedule else {
          completion(true)
          return
        }
        self.finishReschedule(
          rescheduled,
          preparationResult: preparationResult,
          completion: completion
        )
      }
      return
    } else {
      rescheduled = true
    }
    finishReschedule(
      rescheduled,
      preparationResult: preparationResult,
      completion: completion
    )
  }

  private func finishReschedule(
    _ rescheduled: Bool,
    preparationResult: BackgroundMigrationPreparationPassResult,
    completion: @escaping (Bool) -> Void
  ) {
    guard wakeDisposition.shouldReschedule else {
      completion(true)
      return
    }
    if !rescheduled {
      let preparationWasDeferred: Bool
      switch preparationResult {
      case .waitingForConfirmations, .deferred:
        preparationWasDeferred = true
      case .completed, .needsAction, .cancelled:
        preparationWasDeferred = false
      }
      if #available(iOS 26.0, *), preparationWasDeferred {
        BackgroundMigrationPreparationManager.shared
          .recordDeferredSchedulingFailure()
      }
    }
    completion(rescheduled)
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
        || (batch.broadcastCompleteNotificationPendingAt != nil
          && batch.broadcastCompleteNotifiedAt == nil)
    }
  }

  private func hasResumablePreparationWork() -> Bool {
    guard #available(iOS 26.0, *) else { return false }
    return BackgroundMigrationPreparationManager.shared
      .hasResumablePreparation()
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
    if hasRunnableOutboxWork() || hasResumablePreparationWork() {
      schedule(earliestBeginDate: Date().addingTimeInterval(60)) { _ in }
    }
  }

  private func postNeedsUserActionNotification() {
    guard !isNotificationWorkDisabled else { return }
    let content = UNMutableNotificationContent()
    content.title = "Ironwood migration needs attention"
    content.body = "Open Vizor to review and continue your migration."
    content.sound = .default
    addNotificationIfEnabled(
      UNNotificationRequest(
        identifier: BackgroundMigrationNotification.needsActionIdentifier,
        content: content,
        trigger: nil
      ),
      completion: nil
    )
  }

  private func deliverBroadcastCompleteNotification(
    _ broadcastComplete: BackgroundMigrationBroadcastCompleteMetadata?,
    completion: @escaping (Bool) -> Void
  ) {
    guard !isNotificationWorkDisabled else {
      completion(true)
      return
    }
    guard let broadcastComplete else {
      completion(true)
      return
    }
    postBroadcastCompleteNotification(
      batchId: broadcastComplete.batchId
    ) { delivered in
      var acknowledged = false
      if delivered {
        acknowledged =
          (try? BackgroundMigrationOutboxStore.shared.update { snapshot in
            try snapshot.acknowledgeBroadcastCompleteNotification(
              batchId: broadcastComplete.batchId,
              at: Date()
            )
          }) != nil
      }
      completion(delivered && acknowledged)
    }
  }

  private func deliverProofReadyNotification(
    _ proofReady: BackgroundMigrationProofReadyMetadata?,
    completion: @escaping (Bool) -> Void
  ) {
    guard !isNotificationWorkDisabled else {
      completion(true)
      return
    }
    guard let proofReady else {
      completion(true)
      return
    }
    postProofReadyNotification(batchId: proofReady.batchId) { delivered in
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
      completion(delivered && acknowledged)
    }
  }

  private func postBroadcastCompleteNotification(
    batchId: String,
    completion: @escaping (Bool) -> Void
  ) {
    let content = UNMutableNotificationContent()
    content.title = "Migration transfers sent"
    content.body =
      "All scheduled transfers were submitted. Open Vizor to check the status."
    content.sound = .default
    addNotificationIfEnabled(
      UNNotificationRequest(
        identifier: BackgroundMigrationNotification.broadcastCompleteIdentifier(
          batchId: batchId
        ),
        content: content,
        trigger: nil
      ),
      completion: completion
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
    addNotificationIfEnabled(
      UNNotificationRequest(
        identifier: BackgroundMigrationNotification.proofReadyIdentifier(
          batchId: batchId
        ),
        content: content,
        trigger: nil
      ),
      completion: completion
    )
  }

  private func addNotificationIfEnabled(
    _ request: UNNotificationRequest,
    completion: ((Bool) -> Void)?
  ) {
    guard !isNotificationWorkDisabled else {
      completion?(true)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.add(request) { error in
      if self.isNotificationWorkDisabled {
        center.removePendingNotificationRequests(
          withIdentifiers: [request.identifier]
        )
        center.removeDeliveredNotifications(
          withIdentifiers: [request.identifier]
        )
        completion?(true)
        return
      }
      completion?(error == nil)
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
