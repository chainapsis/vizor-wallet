import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

func shouldResubmitMigrationPreparationTask(
  success: Bool,
  handedOff: Bool,
  expired: Bool,
  hasActivePreparation: Bool
) -> Bool {
  !success && !handedOff && expired && hasActivePreparation
}

@available(iOS 26.0, *)
final class BackgroundMigrationPreparationManager {
  static let shared = BackgroundMigrationPreparationManager()
  static let taskIdentifier = "com.keplr.vizor.ironwood-preparation"

  private static let watchdogIdentifier =
    "com.keplr.vizor.ironwood-preparation.watchdog"
  private static let needsActionIdentifier =
    "com.keplr.vizor.ironwood-preparation.needs-action"
  private static let proofReadyIdentifier =
    "com.keplr.vizor.ironwood-preparation.proof-ready"
  private static let watchdogDelay: TimeInterval = 15 * 60
  private static let schedulingStateKey =
    "ironwoodMigrationPreparationSchedulingState"
  private static let schedulingStateUpdatedAtKey =
    "ironwoodMigrationPreparationSchedulingStateUpdatedAt"
  private static let schedulingErrorKey =
    "ironwoodMigrationPreparationSchedulingError"

  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-preparation",
    qos: .utility
  )
  private let stateLock = NSLock()
  private var expired = false
  private var submissionInFlight = false
  private var taskRunning = false
  private var mutationQuiesced = false
  private var foregroundHandoffRequested = false
  private var taskProgress: Progress?
  private var lastCompletedUnitCount: Int64 = 0

  private init() {}

  func cancelPendingRequestForForegroundLaunch() {
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    recordSchedulingState("cancelled_on_launch")
    cancelWatchdog()
  }

  func handoffToForeground() {
    let shouldCancelPreparationSync = stateLock.withPreparationLock {
      foregroundHandoffRequested = taskRunning
      return taskRunning
    }
    guard shouldCancelPreparationSync else { return }
    recordSchedulingState("handoff_to_foreground")
    _ = zcash_cancel_migration_preparation_sync()
  }

  func registerBackgroundTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.taskIdentifier,
      using: nil
    ) { task in
      guard let continuedTask = task as? BGContinuedProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handle(continuedTask)
    }
  }

  func start(completion: @escaping (Bool) -> Void) {
    let shouldCheckScheduler = stateLock.withPreparationLock { () -> Bool in
      guard !mutationQuiesced && !submissionInFlight && !taskRunning else {
        return false
      }
      submissionInFlight = true
      return true
    }
    guard shouldCheckScheduler else {
      let blockedByMutation = stateLock.withPreparationLock {
        mutationQuiesced
      }
      completion(!blockedByMutation)
      return
    }
    recordSchedulingState("checking")
    BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
      guard let self else {
        completion(false)
        return
      }
      let maySubmit = self.stateLock.withPreparationLock { () -> Bool in
        guard !self.mutationQuiesced else {
          self.submissionInFlight = false
          return false
        }
        return true
      }
      guard maySubmit else {
        completion(false)
        return
      }
      if requests.contains(where: { $0.identifier == Self.taskIdentifier }) {
        self.stateLock.withPreparationLock { self.submissionInFlight = false }
        self.recordSchedulingState("pending")
        completion(true)
        return
      }

      self.scheduleWatchdog()
      let request = BGContinuedProcessingTaskRequest(
        identifier: Self.taskIdentifier,
        title: "Preparing migration",
        subtitle: "You can continue using your device"
      )
      do {
        try BGTaskScheduler.shared.submit(request)
        self.stateLock.withPreparationLock {
          self.submissionInFlight = false
        }
        self.recordSchedulingState("submitted")
        print("[BGPreparation] submitted")
        completion(true)
      } catch {
        self.stateLock.withPreparationLock {
          self.submissionInFlight = false
        }
        self.recordSchedulingState("failed", error: error)
        print("[BGPreparation] submit failed: \(error)")
        self.postNeedsActionNotification()
        completion(false)
      }
    }
  }

  func cancelIfNoActivePreparation() {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else { return }
    let hasPreparation = manifests.contains { manifest in
      guard let runId = manifest.expectedRunId else { return false }
      var preparation = CMigrationPreparationProgress(
        state: 0,
        confirmation_count: 0,
        confirmation_target: 0,
        completed_stage_count: 0,
        total_stage_count: 0
      )
      let code = zcash_inspect_migration_preparation(
        manifest.dbPath,
        manifest.network,
        manifest.accountUuid,
        runId,
        &preparation
      )
      return code != 0 || preparation.state == 0 || preparation.state == 5
    }
    guard !hasPreparation else { return }
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    recordSchedulingState("cancelled")
    cancelWatchdog()
  }

  func quiesce(completion: @escaping (Bool) -> Void) {
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    stateLock.withPreparationLock {
      expired = true
      submissionInFlight = false
      mutationQuiesced = true
    }
    _ = zcash_cancel_migration_preparation_sync()
    queue.async {
      DispatchQueue.main.async { completion(true) }
    }
  }

  func resumeAfterFailedMutation() {
    stateLock.withPreparationLock {
      expired = false
      mutationQuiesced = false
    }
    start { _ in }
  }

  fileprivate func recordSyncProgress(_ progress: CSyncProgress) {
    guard progress.percentage.isFinite else { return }
    let fraction = min(max(progress.percentage, 0), 1)
    let syncUnits = Int64((25 + fraction * 25).rounded())
    updateProgress(syncUnits)
    SyncProgressStreamHandler.shared.sendProgress(progress)
  }

  private func handle(_ task: BGContinuedProcessingTask) {
    let mayRun = stateLock.withPreparationLock { () -> Bool in
      guard !mutationQuiesced else { return false }
      submissionInFlight = false
      taskRunning = true
      expired = false
      foregroundHandoffRequested = false
      taskProgress = task.progress
      taskProgress?.totalUnitCount = 1000
      lastCompletedUnitCount = 0
      return true
    }
    guard mayRun else {
      task.setTaskCompleted(success: false)
      return
    }
    recordSchedulingState("running")
    updateProgress(25)

    task.expirationHandler = { [weak self] in
      guard let self else { return }
      self.stateLock.withPreparationLock { self.expired = true }
      _ = zcash_cancel_migration_preparation_sync()
      self.scheduleWatchdog()
    }

    queue.async { [weak self] in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      let success = self.runPreparation()
      let (handedOff, didExpire) = self.stateLock.withPreparationLock {
        (self.foregroundHandoffRequested, self.expired)
      }
      self.stateLock.withPreparationLock {
        self.taskRunning = false
        self.taskProgress = nil
        self.foregroundHandoffRequested = false
      }
      let shouldResubmit = shouldResubmitMigrationPreparationTask(
        success: success,
        handedOff: handedOff,
        expired: didExpire,
        hasActivePreparation: didExpire && self.hasResumablePreparation()
      )
      if success || handedOff {
        BGTaskScheduler.shared.cancel(
          taskRequestWithIdentifier: Self.taskIdentifier
        )
      }
      if handedOff {
        self.recordSchedulingState("handed_off_to_foreground")
        self.scheduleWatchdog()
      } else if shouldResubmit {
        self.recordSchedulingState("expired_resubmitting")
      } else {
        self.recordSchedulingState(success ? "completed" : "failed")
      }
      task.setTaskCompleted(success: success || handedOff)
      if shouldResubmit {
        self.start { _ in }
      }
    }
  }

  private func hasResumablePreparation() -> Bool {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else { return false }
    return manifests.contains { manifest in
      guard let runId = manifest.expectedRunId else { return false }
      var preparation = CMigrationPreparationProgress(
        state: 0,
        confirmation_count: 0,
        confirmation_target: 0,
        completed_stage_count: 0,
        total_stage_count: 0
      )
      let code = zcash_inspect_migration_preparation(
        manifest.dbPath,
        manifest.network,
        manifest.accountUuid,
        runId,
        &preparation
      )
      return code == 0 && (preparation.state == 0 || preparation.state == 5)
    }
  }

  private func recordSchedulingState(_ state: String, error: Error? = nil) {
    let defaults = UserDefaults.standard
    defaults.set(state, forKey: Self.schedulingStateKey)
    defaults.set(
      Date().timeIntervalSince1970,
      forKey: Self.schedulingStateUpdatedAtKey
    )
    if let error {
      defaults.set(String(describing: error), forKey: Self.schedulingErrorKey)
    } else {
      defaults.removeObject(forKey: Self.schedulingErrorKey)
    }
  }

  private func runPreparation() -> Bool {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else {
      postNeedsActionNotification()
      return false
    }
    let preparations = manifests.filter { $0.expectedRunId != nil }
    guard !preparations.isEmpty else {
      cancelWatchdog()
      return true
    }

    var pending = Array(preparations.enumerated())
    var accountProgress = Array(repeating: 0.0, count: preparations.count)
    while !pending.isEmpty && !isExpired {
      var syncedContexts = Set<String>()
      var remaining: [(offset: Int, element: IronwoodMigrationBackgroundManifest)] = []
      for entry in pending {
        let manifest = entry.element
        let syncContext = [
          manifest.dbPath,
          manifest.lightwalletdUrl,
          manifest.network,
        ].joined(separator: "|")
        guard
          let preparation = runPreparationStep(
            manifest,
            syncContext: syncContext,
            syncedContexts: &syncedContexts
          )
        else {
          return false
        }
        accountProgress[entry.offset] = preparationFraction(preparation)
        updateProgress(aggregatePreparationUnits(accountProgress))

        switch preparation.state {
        case 1:
          postProofReadyNotification()
          accountProgress[entry.offset] = 1
          updateProgress(aggregatePreparationUnits(accountProgress))
        case 4:
          accountProgress[entry.offset] = 1
          updateProgress(aggregatePreparationUnits(accountProgress))
        case 2:
          postNeedsActionNotification()
          return false
        case 3:
          if !isExpired && !isForegroundHandoffRequested {
            postNeedsActionNotification()
          }
          return false
        default:
          remaining.append(entry)
        }
      }
      pending = remaining
      if !pending.isEmpty && !waitForNextSyncPass() {
        return false
      }
    }
    guard pending.isEmpty else { return false }

    updateProgress(1000)
    cancelWatchdog()
    _ = BackgroundMigrationManager.shared.schedule()
    return true
  }

  private func runPreparationStep(
    _ manifest: IronwoodMigrationBackgroundManifest,
    syncContext: String,
    syncedContexts: inout Set<String>
  ) -> CMigrationPreparationProgress? {
    guard let runId = manifest.expectedRunId,
      manifest.credentialHex.count == 64
    else {
      postNeedsActionNotification()
      return nil
    }

    var preparation = CMigrationPreparationProgress(
      state: 0,
      confirmation_count: 0,
      confirmation_target: 0,
      completed_stage_count: 0,
      total_stage_count: 0
    )
    let inspectCode = zcash_inspect_migration_preparation(
      manifest.dbPath,
      manifest.network,
      manifest.accountUuid,
      runId,
      &preparation
    )
    guard inspectCode == 0 else {
      print("[BGPreparation] inspection failed: \(inspectCode)")
      postNeedsActionNotification()
      return nil
    }
    let waitingForProofAnchor = preparation.state == 5
    guard preparation.state == 0 || waitingForProofAnchor else {
      return preparation
    }

    guard UIApplication.shared.isProtectedDataAvailable else {
      print("[BGPreparation] protected data unavailable")
      postNeedsActionNotification()
      return nil
    }

    if syncedContexts.insert(syncContext).inserted {
      guard waitForRunningSync() else {
        if !isExpired {
          print("[BGPreparation] sync ownership wait failed")
          postNeedsActionNotification()
        }
        return nil
      }
      var syncCode = runSync(manifest)
      if syncCode == 3 {
        guard waitForRunningSync() else { return nil }
        syncCode = runSync(manifest)
      }
      if syncCode != 0 {
        print("[BGPreparation] sync failed: \(syncCode)")
        if !isExpired && !isForegroundHandoffRequested {
          postNeedsActionNotification()
        }
        return nil
      }
    }

    guard !isExpired && !isForegroundHandoffRequested else { return nil }

    if waitingForProofAnchor {
      let inspectCode = zcash_inspect_migration_preparation(
        manifest.dbPath,
        manifest.network,
        manifest.accountUuid,
        runId,
        &preparation
      )
      guard inspectCode == 0 else {
        print("[BGPreparation] proof readiness inspection failed: \(inspectCode)")
        postNeedsActionNotification()
        return nil
      }
      return preparation
    }

    guard UIApplication.shared.isProtectedDataAvailable else {
      print("[BGPreparation] protected data unavailable")
      postNeedsActionNotification()
      return nil
    }

    let credential = Data(manifest.credentialHex.utf8)
    let advanceCode = credential.withUnsafeBytes { bytes in
      zcash_advance_migration_preparation(
        manifest.dbPath,
        manifest.lightwalletdUrl,
        manifest.network,
        manifest.accountUuid,
        runId,
        bytes.bindMemory(to: UInt8.self).baseAddress,
        UInt(bytes.count),
        manifest.saltBase64,
        &preparation
      )
    }
    guard advanceCode == 0 else {
      print("[BGPreparation] advance failed: \(advanceCode)")
      if !isExpired && !isForegroundHandoffRequested {
        postNeedsActionNotification()
      }
      return nil
    }
    return preparation
  }

  private func runSync(_ manifest: IronwoodMigrationBackgroundManifest) -> Int32 {
    zcash_run_full_sync_for_migration_preparation(
      manifest.dbPath,
      manifest.lightwalletdUrl,
      manifest.network,
      migrationPreparationSyncProgressCallback
    )
  }

  private func waitForRunningSync() -> Bool {
    while !isExpired {
      if !zcash_is_sync_running() {
        return true
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return false
  }

  private func waitForNextSyncPass() -> Bool {
    for _ in 0..<60 where !isExpired {
      Thread.sleep(forTimeInterval: 0.25)
    }
    return !isExpired
  }

  private var isExpired: Bool {
    stateLock.withPreparationLock { expired }
  }

  private var isForegroundHandoffRequested: Bool {
    stateLock.withPreparationLock { foregroundHandoffRequested }
  }

  private func preparationFraction(
    _ progress: CMigrationPreparationProgress
  ) -> Double {
    if progress.state == 1 { return 1 }
    let stageTotal = max(1, Int(progress.total_stage_count))
    let confirmationTarget = max(1, Int(progress.confirmation_target))
    let currentConfirmation = min(
      Int(progress.confirmation_count),
      confirmationTarget
    )
    return min(
      1,
      (Double(progress.completed_stage_count)
        + Double(currentConfirmation) / Double(confirmationTarget))
        / Double(stageTotal)
    )
  }

  private func aggregatePreparationUnits(_ progress: [Double]) -> Int64 {
    let aggregate = progress.reduce(0, +) / Double(max(1, progress.count))
    return Int64((50 + aggregate * 900).rounded())
  }

  private func updateProgress(_ requestedUnits: Int64) {
    let didAdvance = stateLock.withPreparationLock { () -> Bool in
      let units = min(max(requestedUnits, lastCompletedUnitCount), 1000)
      guard units > lastCompletedUnitCount else { return false }
      lastCompletedUnitCount = units
      taskProgress?.completedUnitCount = units
      return true
    }
    if didAdvance {
      scheduleWatchdog()
    }
  }

  private func scheduleWatchdog() {
    let content = UNMutableNotificationContent()
    content.title = "Migration preparation paused"
    content.body = "Open Vizor to continue preparing your migration."
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: Self.watchdogIdentifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(
        timeInterval: Self.watchdogDelay,
        repeats: false
      )
    )
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(
      withIdentifiers: [Self.watchdogIdentifier]
    )
    center.add(request)
  }

  private func cancelWatchdog() {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(
      withIdentifiers: [Self.watchdogIdentifier]
    )
    center.removeDeliveredNotifications(
      withIdentifiers: [Self.watchdogIdentifier]
    )
  }

  private func postNeedsActionNotification() {
    let content = UNMutableNotificationContent()
    content.title = "Continue preparing your migration"
    content.body = "Open and unlock Vizor to continue."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: Self.needsActionIdentifier,
        content: content,
        trigger: nil
      )
    )
  }

  private func postProofReadyNotification() {
    let content = UNMutableNotificationContent()
    content.title = "Migration proof is ready"
    content.body = "Open Vizor to continue your migration."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: Self.proofReadyIdentifier,
        content: content,
        trigger: nil
      )
    )
  }

}

@available(iOS 26.0, *)
private func migrationPreparationSyncProgressCallback(
  _ progress: CSyncProgress
) {
  BackgroundMigrationPreparationManager.shared.recordSyncProgress(progress)
}

extension NSLock {
  fileprivate func withPreparationLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
