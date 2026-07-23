import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

enum BackgroundMigrationPreparationPassResult: Equatable {
  case completed
  case waitingForConfirmations
  case deferred(TimeInterval)
  case needsAction
  case cancelled
}

private enum BackgroundMigrationPreparationStepResult {
  case progress(CMigrationPreparationProgress)
  case retry(TimeInterval)
  case needsAction
  case cancelled
}

func migrationPreparationPassResult(
  states: [UInt8]
) -> BackgroundMigrationPreparationPassResult {
  if states.contains(2) { return .needsAction }
  if states.contains(3) { return .cancelled }
  if states.contains(0) {
    return .waitingForConfirmations
  }
  if states.contains(5) {
    return .deferred(
      BackgroundMigrationOutboxCadence.rollingCheckInterval
    )
  }
  if states.allSatisfy({ $0 == 1 || $0 == 4 }) {
    return .completed
  }
  return .needsAction
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
  private static let busyRetryDelay: TimeInterval = 60
  private static let transientRetryDelay: TimeInterval = 10 * 60
  private static let waitingHeartbeatInterval: TimeInterval = 15
  private static let waitingHeartbeatUnitLimit: Int64 = 949
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
  private var deferredPassRunning = false
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
      request.strategy = .fail
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
        print("[BGPreparation] submit failed: \(error)")
        let deferred = BackgroundMigrationManager.shared
          .schedulePreparationHandoff(after: 60)
        if deferred {
          self.recordSchedulingState(
            "deferred_after_submit_failure",
            error: error
          )
          self.cancelWatchdog()
          completion(true)
          return
        }
        self.recordSchedulingState("failed", error: error)
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

  func resumeAfterMutation() {
    stateLock.withPreparationLock {
      expired = false
      mutationQuiesced = false
    }
    guard hasResumablePreparation() else {
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      recordSchedulingState("idle_after_mutation")
      cancelWatchdog()
      return
    }
    start { _ in }
  }

  fileprivate func recordSyncProgress(_ progress: CSyncProgress) {
    guard progress.percentage.isFinite else { return }
    let fraction = min(max(progress.percentage, 0), 1)
    let syncUnits = Int64((25 + fraction * 25).rounded())
    updateProgress(syncUnits)
  }

  func runDeferredPass() -> BackgroundMigrationPreparationPassResult {
    let mayRun = stateLock.withPreparationLock { () -> Bool in
      guard !mutationQuiesced && !taskRunning else { return false }
      taskRunning = true
      deferredPassRunning = true
      expired = false
      foregroundHandoffRequested = false
      taskProgress = nil
      return true
    }
    guard mayRun else {
      let blockedByMutation = stateLock.withPreparationLock {
        mutationQuiesced
      }
      return blockedByMutation ? .cancelled : .deferred(60)
    }

    recordSchedulingState("processing")
    let passResult = runPreparationPass()
    let result =
      passResult == .waitingForConfirmations
      ? .deferred(Self.busyRetryDelay)
      : passResult
    stateLock.withPreparationLock {
      taskRunning = false
      deferredPassRunning = false
      foregroundHandoffRequested = false
    }
    switch result {
    case .completed:
      recordSchedulingState("processing_completed")
    case .waitingForConfirmations, .deferred:
      recordSchedulingState("processing_deferred")
    case .needsAction:
      recordSchedulingState("processing_failed")
    case .cancelled:
      recordSchedulingState("processing_cancelled")
    }
    return result
  }

  func expireDeferredPass() {
    let shouldCancel = stateLock.withPreparationLock { () -> Bool in
      guard deferredPassRunning else { return false }
      expired = true
      return true
    }
    if shouldCancel {
      _ = zcash_cancel_migration_preparation_sync()
    }
  }

  func cancelDeferredPass() {
    let shouldCancel = stateLock.withPreparationLock { () -> Bool in
      guard deferredPassRunning else { return false }
      expired = true
      return true
    }
    if shouldCancel {
      _ = zcash_cancel_migration_preparation_sync()
    }
  }

  func recordDeferredSchedulingFailure() {
    recordSchedulingState("processing_reschedule_failed")
    scheduleWatchdog()
    postNeedsActionNotification()
  }

  private func handle(_ task: BGContinuedProcessingTask) {
    let mayRun = stateLock.withPreparationLock { () -> Bool in
        submissionInFlight = false
        guard !mutationQuiesced && !taskRunning else { return false }
        taskRunning = true
        expired = false
        foregroundHandoffRequested = false
        taskProgress = task.progress
        taskProgress?.totalUnitCount = 1000
        lastCompletedUnitCount = 0
        return true
      }
    guard mayRun else {
      task.setTaskCompleted(success: true)
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
      var passResult = self.runPreparationPass()
      while passResult == .waitingForConfirmations
        && !self.isStopRequested
      {
        guard self.waitForNextSyncPass() else {
          passResult = .cancelled
          break
        }
        passResult = self.runPreparationPass()
      }
      var deferredToProcessing = false
      if case .deferred(let retryDelay) = passResult {
        deferredToProcessing = BackgroundMigrationManager.shared
          .schedulePreparationHandoff(after: retryDelay)
        if !deferredToProcessing {
          self.postNeedsActionNotification()
        }
      }
      let passCompleted = passResult == .completed
      if passCompleted || deferredToProcessing {
        self.updateProgress(1000)
      }
      let (handedOff, didExpire, quiescedForMutation) =
        self.stateLock.withPreparationLock {
          (
            self.foregroundHandoffRequested,
            self.expired,
            self.mutationQuiesced
          )
        }
      self.stateLock.withPreparationLock {
        self.taskRunning = false
        self.taskProgress = nil
        self.foregroundHandoffRequested = false
      }
      let shouldRecoverInProcessing =
        didExpire && !handedOff && !quiescedForMutation
        && self.hasResumablePreparation()
      let recoveredInProcessing =
        shouldRecoverInProcessing
        && BackgroundMigrationManager.shared
          .schedulePreparationHandoff(after: 60)
      let success =
        passCompleted || deferredToProcessing || recoveredInProcessing
        || handedOff || quiescedForMutation
      if success {
        BGTaskScheduler.shared.cancel(
          taskRequestWithIdentifier: Self.taskIdentifier
        )
      }
      if quiescedForMutation {
        self.recordSchedulingState("quiesced_for_mutation")
        self.cancelWatchdog()
      } else if handedOff {
        self.recordSchedulingState("handed_off_to_foreground")
        self.scheduleWatchdog()
      } else if deferredToProcessing {
        self.recordSchedulingState("handed_off_to_processing")
        self.cancelWatchdog()
      } else if recoveredInProcessing {
        self.recordSchedulingState("expired_handed_off_to_processing")
        self.cancelWatchdog()
      } else {
        self.recordSchedulingState(success ? "completed" : "failed")
        if success {
          self.cancelWatchdog()
        }
      }
      task.setTaskCompleted(success: success)
    }
  }

  func hasResumablePreparation() -> Bool {
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
      // An inspection error is not proof that the run is inactive. Schedule a
      // retry so a transient DB lock cannot strand a bound preparation.
      return code != 0 || preparation.state == 0 || preparation.state == 5
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

  private func runPreparationPass()
    -> BackgroundMigrationPreparationPassResult
  {
    guard zcash_begin_migration_preparation_operation() else {
      print("[BGPreparation] another preparation operation is active")
      return .deferred(60)
    }
    defer { zcash_end_migration_preparation_operation() }
    guard !isStopRequested else { return .cancelled }

    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else {
      postNeedsActionNotification()
      return .needsAction
    }
    let preparations = manifests.filter { $0.expectedRunId != nil }
    guard !preparations.isEmpty else { return .completed }

    var accountProgress = Array(repeating: 0.0, count: preparations.count)
    var states: [UInt8] = []
    var syncedContexts = Set<String>()
    for entry in preparations.enumerated() {
      let manifest = entry.element
      let syncContext = [
        manifest.dbPath,
        manifest.lightwalletdUrl,
        manifest.network,
      ].joined(separator: "|")
      let preparation: CMigrationPreparationProgress
      switch runPreparationStep(
        manifest,
        syncContext: syncContext,
        syncedContexts: &syncedContexts
      ) {
      case .progress(let progress):
        preparation = progress
      case .retry(let retryDelay):
        return .deferred(retryDelay)
      case .needsAction:
        postNeedsActionNotification()
        return .needsAction
      case .cancelled:
        return .cancelled
      }
      states.append(preparation.state)
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
        return .needsAction
      case 3:
        if !isExpired && !isForegroundHandoffRequested {
          postNeedsActionNotification()
        }
        return .cancelled
      case 0, 5:
        break
      default:
        postNeedsActionNotification()
        return .needsAction
      }
    }

    return migrationPreparationPassResult(states: states)
  }

  private func runPreparationStep(
    _ manifest: IronwoodMigrationBackgroundManifest,
    syncContext: String,
    syncedContexts: inout Set<String>
  ) -> BackgroundMigrationPreparationStepResult {
    guard let runId = manifest.expectedRunId,
      manifest.credentialHex.count == 64
    else {
      return .needsAction
    }
    guard !isStopRequested else { return .cancelled }

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
      return .retry(Self.transientRetryDelay)
    }
    let waitingForProofAnchor = preparation.state == 5
    guard preparation.state == 0 || waitingForProofAnchor else {
      return .progress(preparation)
    }

    guard UIApplication.shared.isProtectedDataAvailable else {
      print("[BGPreparation] protected data unavailable")
      return .retry(Self.transientRetryDelay)
    }

    if syncedContexts.insert(syncContext).inserted {
      guard waitForRunningSync() else {
        return isStopRequested
          ? .cancelled
          : .retry(Self.busyRetryDelay)
      }
      var syncCode = runSync(manifest)
      if syncCode == 3 {
        guard waitForRunningSync() else {
          return isStopRequested
            ? .cancelled
            : .retry(Self.busyRetryDelay)
        }
        syncCode = runSync(manifest)
      }
      if syncCode != 0 {
        print("[BGPreparation] sync failed: \(syncCode)")
        return isStopRequested
          ? .cancelled
          : .retry(Self.transientRetryDelay)
      }
    }

    guard !isStopRequested else { return .cancelled }

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
        return .retry(Self.transientRetryDelay)
      }
      return .progress(preparation)
    }

    guard UIApplication.shared.isProtectedDataAvailable else {
      print("[BGPreparation] protected data unavailable")
      return .retry(Self.transientRetryDelay)
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
      if isStopRequested { return .cancelled }
      return advanceCode == 2
        ? .needsAction
        : .retry(Self.transientRetryDelay)
    }
    return .progress(preparation)
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
    while !isStopRequested {
      if !zcash_is_sync_running() {
        return true
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return false
  }

  private func waitForNextSyncPass() -> Bool {
    let sleepInterval: TimeInterval = 0.25
    let heartbeatTicks = Int(
      Self.waitingHeartbeatInterval / sleepInterval
    )
    let syncTicks = Int(
      BackgroundMigrationOutboxCadence.secondsPerBlock / sleepInterval
    )
    for tick in 1...syncTicks where !isStopRequested {
      Thread.sleep(forTimeInterval: sleepInterval)
      if tick.isMultiple(of: heartbeatTicks) {
        advanceWaitingHeartbeat()
      }
    }
    return !isStopRequested
  }

  private func advanceWaitingHeartbeat() {
    let didAdvance = stateLock.withPreparationLock { () -> Bool in
      guard let taskProgress,
        lastCompletedUnitCount < Self.waitingHeartbeatUnitLimit
      else {
        return false
      }
      lastCompletedUnitCount += 1
      taskProgress.completedUnitCount = lastCompletedUnitCount
      return true
    }
    if didAdvance {
      scheduleWatchdog()
    }
  }

  private var isExpired: Bool {
    stateLock.withPreparationLock { expired }
  }

  private var isForegroundHandoffRequested: Bool {
    stateLock.withPreparationLock { foregroundHandoffRequested }
  }

  private var isStopRequested: Bool {
    stateLock.withPreparationLock {
      expired || foregroundHandoffRequested
    }
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
      guard let taskProgress else { return false }
      let units = min(max(requestedUnits, lastCompletedUnitCount), 1000)
      guard units > lastCompletedUnitCount else { return false }
      lastCompletedUnitCount = units
      taskProgress.completedUnitCount = units
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
