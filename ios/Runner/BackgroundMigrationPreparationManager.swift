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

func migrationPreparationPassNeedsForegroundAction(
  _ result: BackgroundMigrationPreparationPassResult
) -> Bool {
  result == .needsAction
}

func migrationPreparationBackgroundWakeSucceeded(
  _ result: BackgroundMigrationPreparationPassResult
) -> Bool {
  result != .cancelled
}

func shouldPostMigrationPreparationNeedsActionNotification(
  previousFingerprint: String?,
  fingerprint: String
) -> Bool {
  previousFingerprint != fingerprint
}

private enum BackgroundMigrationPreparationStepResult {
  case progress(CMigrationPreparationProgress)
  case retry(TimeInterval)
  case needsAction
  case cancelled
}

enum BackgroundMigrationPreparationRuntimeState: String, Equatable {
  case idle
  case disabled
  case scheduled
  case running
  case handoffRequested
  case foregroundContinuationPending
}

func shouldMarkMigrationPreparationForegroundContinuation(
  hasPendingRequest: Bool,
  hasBoundPreparation: Bool,
  notificationsDisabled: Bool
) -> Bool {
  hasPendingRequest && hasBoundPreparation && !notificationsDisabled
}

func migrationPreparationRuntimeState(
  hasMatchingManifest: Bool,
  notificationsDisabled: Bool,
  submissionInFlight: Bool,
  taskRunning: Bool,
  deferredPassRunning: Bool,
  foregroundHandoffRequested: Bool,
  foregroundContinuationPending: Bool,
  pendingRequest: Bool
) -> BackgroundMigrationPreparationRuntimeState {
  guard hasMatchingManifest else { return .idle }
  if notificationsDisabled { return .disabled }
  if foregroundContinuationPending {
    return .foregroundContinuationPending
  }
  if foregroundHandoffRequested { return .handoffRequested }
  if taskRunning || deferredPassRunning { return .running }
  if submissionInFlight || pendingRequest { return .scheduled }
  return .idle
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
  private static let foregroundContinuationScopesKey =
    "ironwoodMigrationPreparationForegroundContinuationScopes"
  private static let needsActionNotificationFingerprintsKey =
    "ironwoodMigrationPreparationNeedsActionNotificationFingerprints"

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
  private var notificationAuthorization =
    IronwoodMigrationNotificationAuthorizationEpochState()
  private var foregroundHandoffRequested = false
  private var foregroundContinuationScopes: Set<String>
  private var needsActionNotificationFingerprints: [String: String]
  private var taskProgress: Progress?
  private var lastCompletedUnitCount: Int64 = 0
  private var authorizationMonitor:
    IronwoodMigrationNotificationAuthorizationMonitor?

  private init() {
    foregroundContinuationScopes = Set(
      UserDefaults.standard.stringArray(
        forKey: Self.foregroundContinuationScopesKey
      ) ?? []
    )
    needsActionNotificationFingerprints =
      UserDefaults.standard.dictionary(
        forKey: Self.needsActionNotificationFingerprintsKey
      ) as? [String: String] ?? [:]
  }

  func handoffPendingRequestForForegroundLaunch() {
    BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
      guard let self else { return }
      let hasPendingRequest = requests.contains {
        $0.identifier == Self.taskIdentifier
      }
      let notificationsDisabled = self.stateLock.withPreparationLock {
        self.notificationAuthorization.isDisabled
      }
      let hasBoundPreparation =
        hasPendingRequest && !notificationsDisabled
        && self.markForegroundContinuationsReady()
      let shouldContinue =
        shouldMarkMigrationPreparationForegroundContinuation(
          hasPendingRequest: hasPendingRequest,
          hasBoundPreparation: hasBoundPreparation,
          notificationsDisabled: notificationsDisabled
        )
      if !shouldContinue {
        BGTaskScheduler.shared.cancel(
          taskRequestWithIdentifier: Self.taskIdentifier
        )
      }
      self.recordSchedulingState(
        shouldContinue
          ? "pending_handed_off_to_foreground_launch"
          : "cancelled_on_launch"
      )
      if shouldContinue {
        self.scheduleWatchdog()
      } else {
        self.cancelWatchdog()
      }
    }
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

  func runtimeState(
    network: String,
    accountUuid: String,
    runId: String,
    completion: @escaping (BackgroundMigrationPreparationRuntimeState) -> Void
  ) {
    let scope = Self.foregroundContinuationScope(
      network: network,
      accountUuid: accountUuid,
      runId: runId
    )
    clearNeedsActionNotification(scope: scope)
    let evaluate = { [weak self] in
      guard let self else {
        completion(.idle)
        return
      }
      BGTaskScheduler.shared.getPendingTaskRequests { requests in
        let hasPendingRequest = requests.contains {
          $0.identifier == Self.taskIdentifier
        }
        let shouldClaimPendingRequest = self.stateLock.withPreparationLock {
          hasPendingRequest
            && !self.taskRunning
            && !self.deferredPassRunning
            && !self.mutationQuiesced
            && !self.notificationAuthorization.isDisabled
        }
        if shouldClaimPendingRequest {
          self.markForegroundContinuationsReady()
          BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: Self.taskIdentifier
          )
          self.recordSchedulingState("pending_handed_off_to_foreground")
        }
        let hasMatchingManifest =
          IronwoodMigrationBackgroundCredentialStore.loadAll()?.contains {
            $0.network == network
              && $0.accountUuid == accountUuid
              && $0.expectedRunId == runId
          } ?? false
        if !hasMatchingManifest {
          self.stateLock.withPreparationLock {
            self.foregroundContinuationScopes.remove(scope)
            self.persistForegroundContinuationScopesLocked()
          }
        }
        let state = self.stateLock.withPreparationLock {
          migrationPreparationRuntimeState(
            hasMatchingManifest: hasMatchingManifest,
            notificationsDisabled:
              self.notificationAuthorization.isDisabled,
            submissionInFlight: self.submissionInFlight,
            taskRunning: self.taskRunning,
            deferredPassRunning: self.deferredPassRunning,
            foregroundHandoffRequested:
              self.foregroundHandoffRequested,
            foregroundContinuationPending:
              self.foregroundContinuationScopes.contains(scope),
            pendingRequest: hasPendingRequest && !shouldClaimPendingRequest
          )
        }
        completion(state)
      }
    }
    let waitForHandoff = stateLock.withPreparationLock {
      foregroundHandoffRequested && taskRunning
    }
    if waitForHandoff {
      waitForForegroundHandoffCompletion(completion: evaluate)
    } else {
      evaluate()
    }
  }

  func acknowledgeForegroundContinuation(
    network: String,
    accountUuid: String,
    runId: String
  ) {
    let scope = Self.foregroundContinuationScope(
      network: network,
      accountUuid: accountUuid,
      runId: runId
    )
    stateLock.withPreparationLock {
      foregroundContinuationScopes.remove(scope)
      persistForegroundContinuationScopesLocked()
    }
    clearNeedsActionNotification(scope: scope)
    cancelIfNoActivePreparation()
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
      self.startAuthorized(
        authorizationEpoch: authorizationEpoch,
        completion: completion
      )
    }
  }

  private func startAuthorized(
    authorizationEpoch: UInt64,
    completion: @escaping (Bool) -> Void
  ) {
    let shouldCheckScheduler = stateLock.withPreparationLock { () -> Bool in
      guard !mutationQuiesced
        && !submissionInFlight
        && !taskRunning
        && foregroundContinuationScopes.isEmpty
      else {
        return false
      }
      guard !notificationAuthorization.isDisabled else { return false }
      submissionInFlight = true
      return true
    }
    guard shouldCheckScheduler else {
      let (
        blockedByMutation,
        disabledForNotifications,
        foregroundContinuationPending,
        workActive
      ) =
        stateLock.withPreparationLock {
          (
            mutationQuiesced,
            notificationAuthorization.isDisabled,
            !foregroundContinuationScopes.isEmpty,
            submissionInFlight || taskRunning
          )
        }
      completion(
        !blockedByMutation
          && !disabledForNotifications
          && (foregroundContinuationPending
            || workActive)
      )
      return
    }
    guard stateLock.withPreparationLock({
      notificationAuthorization.generation == authorizationEpoch
        && !notificationAuthorization.isDisabled
    }) else {
      stateLock.withPreparationLock {
        submissionInFlight = false
      }
      completion(false)
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
        IronwoodMigrationNotificationGate.shared.status { status in
          self.stateLock.withPreparationLock {
            self.submissionInFlight = false
          }
          guard status.allowsBackgroundMigration else {
            IronwoodMigrationNotificationGate.shared.hardDisable()
            completion(false)
            return
          }
          guard self.enableNotificationWork(
            ifCurrent: authorizationEpoch
          ) else {
            self.stateLock.withPreparationLock {
              self.submissionInFlight = false
            }
            completion(false)
            return
          }
          self.recordSchedulingState("pending")
          completion(true)
        }
        return
      }

      IronwoodMigrationNotificationGate.shared.status { status in
        guard status.allowsBackgroundMigration else {
          self.stateLock.withPreparationLock {
            self.submissionInFlight = false
          }
          IronwoodMigrationNotificationGate.shared.hardDisable()
          completion(false)
          return
        }
        guard self.enableNotificationWork(
          ifCurrent: authorizationEpoch
        ) else {
          self.stateLock.withPreparationLock {
            self.submissionInFlight = false
          }
          completion(false)
          return
        }
        self.scheduleWatchdog()
        let request = BGContinuedProcessingTaskRequest(
          identifier: Self.taskIdentifier,
          title: "Preparing migration",
          subtitle: "You can continue using your device"
        )
        request.strategy = .fail
        let submission = self.stateLock.withPreparationLock {
          () -> (submitted: Bool, error: Error?) in
          guard !self.mutationQuiesced,
            !self.notificationAuthorization.isDisabled,
            self.notificationAuthorization.generation == authorizationEpoch,
            self.submissionInFlight
          else {
            self.submissionInFlight = false
            return (false, nil)
          }
          do {
            try BGTaskScheduler.shared.submit(request)
            self.submissionInFlight = false
            return (true, nil)
          } catch {
            self.submissionInFlight = false
            return (false, error)
          }
        }
        if submission.submitted {
          self.recordSchedulingState("submitted")
          print("[BGPreparation] submitted")
          completion(true)
          return
        }
        guard let error = submission.error else {
          self.cancelWatchdog()
          completion(false)
          return
        }
        print("[BGPreparation] submit failed: \(error)")
        BackgroundMigrationManager.shared.schedulePreparationHandoff(
          after: 60
        ) { deferred in
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
          self.postNeedsActionNotification(reason: "submission-failed")
          completion(false)
        }
      }
    }
  }

  func disableForUnauthorizedNotifications() {
    let monitor = stateLock.withPreparationLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      expired = true
      submissionInFlight = false
      notificationAuthorization.disable()
      foregroundContinuationScopes.removeAll()
      persistForegroundContinuationScopesLocked()
      defer { authorizationMonitor = nil }
      return authorizationMonitor
    }
    monitor?.cancel()
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    _ = zcash_cancel_migration_preparation_sync()
    cancelWatchdog()
    resetNeedsActionNotifications()
  }

  private func captureNotificationAuthorizationEpoch() -> UInt64 {
    stateLock.withPreparationLock {
      notificationAuthorization.generation
    }
  }

  private func enableNotificationWork(ifCurrent epoch: UInt64) -> Bool {
    stateLock.withPreparationLock {
      notificationAuthorization.authorize(ifCurrent: epoch)
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
    stateLock.withPreparationLock {
      foregroundContinuationScopes.removeAll()
      persistForegroundContinuationScopesLocked()
    }
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    recordSchedulingState("cancelled")
    cancelWatchdog()
    resetNeedsActionNotifications()
  }

  func quiesce(completion: @escaping (Bool) -> Void) {
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
    stateLock.withPreparationLock {
      expired = true
      submissionInFlight = false
      mutationQuiesced = true
      foregroundContinuationScopes.removeAll()
      persistForegroundContinuationScopesLocked()
    }
    _ = zcash_cancel_migration_preparation_sync()
    resetNeedsActionNotifications()
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

  func runDeferredPass(
    completion: @escaping (BackgroundMigrationPreparationPassResult) -> Void
  ) {
    let authorizationEpoch = captureNotificationAuthorizationEpoch()
    IronwoodMigrationNotificationGate.shared.status { [weak self] status in
      guard let self else {
        completion(.cancelled)
        return
      }
      guard status.allowsBackgroundMigration else {
        IronwoodMigrationNotificationGate.shared.hardDisable()
        completion(.cancelled)
        return
      }
      guard self.enableNotificationWork(ifCurrent: authorizationEpoch) else {
        completion(.cancelled)
        return
      }
      self.queue.async {
        completion(self.runDeferredPassAuthorized())
      }
    }
  }

  private func runDeferredPassAuthorized()
    -> BackgroundMigrationPreparationPassResult
  {
    let foregroundContinuationPending = stateLock.withPreparationLock {
      !foregroundContinuationScopes.isEmpty
    }
    if foregroundContinuationPending {
      return .needsAction
    }
    let mayRun = stateLock.withPreparationLock { () -> Bool in
      guard !mutationQuiesced
        && !notificationAuthorization.isDisabled
        && !taskRunning
      else { return false }
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

    startAuthorizationMonitoring()
    recordSchedulingState("processing")
    let passResult = runPreparationPass()
    let result =
      passResult == .waitingForConfirmations
      ? .deferred(Self.busyRetryDelay)
      : passResult
    let handedOff = stateLock.withPreparationLock { () -> Bool in
      let handedOff = foregroundHandoffRequested
      taskRunning = false
      deferredPassRunning = false
      foregroundHandoffRequested = false
      return handedOff
    }
    stopAuthorizationMonitoring()
    if handedOff {
      markForegroundContinuationsReady()
      recordSchedulingState("processing_handed_off_to_foreground")
      return .cancelled
    }
    switch result {
    case .completed:
      recordSchedulingState("processing_completed")
    case .waitingForConfirmations, .deferred:
      recordSchedulingState("processing_deferred")
    case .needsAction:
      markForegroundContinuationsReady()
      recordSchedulingState("processing_needs_action")
      cancelWatchdog()
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
    postNeedsActionNotification(reason: "processing-reschedule-failed")
  }

  private func handle(_ task: BGContinuedProcessingTask) {
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

  private func handleAuthorized(_ task: BGContinuedProcessingTask) {
    let mayRun = stateLock.withPreparationLock { () -> Bool in
        submissionInFlight = false
        guard !mutationQuiesced
          && !notificationAuthorization.isDisabled
          && !taskRunning
        else { return false }
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
    startAuthorizationMonitoring()
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
      if case .deferred(let retryDelay) = passResult {
        BackgroundMigrationManager.shared.schedulePreparationHandoff(
          after: retryDelay
        ) { deferredToProcessing in
          if !deferredToProcessing {
            self.postNeedsActionNotification(
              reason: "processing-handoff-failed"
            )
          }
          self.finishAuthorizedTask(
            task,
            passResult: passResult,
            deferredToProcessing: deferredToProcessing
          )
        }
        return
      }
      self.finishAuthorizedTask(
        task,
        passResult: passResult,
        deferredToProcessing: false
      )
    }
  }

  private func finishAuthorizedTask(
    _ task: BGContinuedProcessingTask,
    passResult: BackgroundMigrationPreparationPassResult,
    deferredToProcessing: Bool
  ) {
    stopAuthorizationMonitoring()
    let passCompleted = passResult == .completed
    let needsForegroundAction =
      migrationPreparationPassNeedsForegroundAction(passResult)
    if passCompleted || needsForegroundAction || deferredToProcessing {
      updateProgress(1000)
    }
    let (
      handedOff,
      didExpire,
      quiescedForMutation,
      disabledForNotifications
    ) =
      stateLock.withPreparationLock {
        (
          foregroundHandoffRequested,
          expired,
          mutationQuiesced,
          notificationAuthorization.isDisabled
        )
      }
    if handedOff {
      // Publish the continuation before clearing the running flag so a
      // foreground state read cannot observe an idle gap between the two.
      markForegroundContinuationsReady()
    } else if needsForegroundAction {
      markForegroundContinuationsReady()
    }
    stateLock.withPreparationLock {
      taskRunning = false
      taskProgress = nil
      foregroundHandoffRequested = false
    }
    let shouldRecoverInProcessing =
      didExpire && !handedOff && !quiescedForMutation
      && !disabledForNotifications
      && hasResumablePreparation()
    if shouldRecoverInProcessing {
      BackgroundMigrationManager.shared.schedulePreparationHandoff(after: 60) {
        recoveredInProcessing in
        self.completeAuthorizedTask(
          task,
          passCompleted: passCompleted,
          needsForegroundAction: needsForegroundAction,
          deferredToProcessing: deferredToProcessing,
          recoveredInProcessing: recoveredInProcessing,
          handedOff: handedOff,
          quiescedForMutation: quiescedForMutation,
          disabledForNotifications: disabledForNotifications
        )
      }
      return
    }
    completeAuthorizedTask(
      task,
      passCompleted: passCompleted,
      needsForegroundAction: needsForegroundAction,
      deferredToProcessing: deferredToProcessing,
      recoveredInProcessing: false,
      handedOff: handedOff,
      quiescedForMutation: quiescedForMutation,
      disabledForNotifications: disabledForNotifications
    )
  }

  private func completeAuthorizedTask(
    _ task: BGContinuedProcessingTask,
    passCompleted: Bool,
    needsForegroundAction: Bool,
    deferredToProcessing: Bool,
    recoveredInProcessing: Bool,
    handedOff: Bool,
    quiescedForMutation: Bool,
    disabledForNotifications: Bool
  ) {
    if passCompleted {
      stateLock.withPreparationLock {
        foregroundContinuationScopes.removeAll()
        persistForegroundContinuationScopesLocked()
      }
      resetNeedsActionNotifications()
    }
    let success =
      passCompleted || needsForegroundAction
      || deferredToProcessing || recoveredInProcessing
      || handedOff || quiescedForMutation || disabledForNotifications
    if success {
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
    }
    if disabledForNotifications {
      recordSchedulingState("disabled_for_notifications")
      cancelWatchdog()
    } else if quiescedForMutation {
      recordSchedulingState("quiesced_for_mutation")
      cancelWatchdog()
    } else if handedOff {
      recordSchedulingState("handed_off_to_foreground")
      scheduleWatchdog()
    } else if needsForegroundAction {
      recordSchedulingState("needs_action")
      cancelWatchdog()
    } else if deferredToProcessing {
      recordSchedulingState("handed_off_to_processing")
      cancelWatchdog()
    } else if recoveredInProcessing {
      recordSchedulingState("expired_handed_off_to_processing")
      cancelWatchdog()
    } else {
      recordSchedulingState(success ? "completed" : "failed")
      if success {
        cancelWatchdog()
      }
    }
    task.setTaskCompleted(success: success)
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

  private static func foregroundContinuationScope(
    network: String,
    accountUuid: String,
    runId: String
  ) -> String {
    "\(network):\(accountUuid):\(runId)"
  }

  private func waitForForegroundHandoffCompletion(
    remainingAttempts: Int = 200,
    completion: @escaping () -> Void
  ) {
    let stillHandingOff = stateLock.withPreparationLock {
      foregroundHandoffRequested && taskRunning
    }
    guard stillHandingOff && remainingAttempts > 0 else {
      completion()
      return
    }
    queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
      guard let self else {
        completion()
        return
      }
      self.waitForForegroundHandoffCompletion(
        remainingAttempts: remainingAttempts - 1,
        completion: completion
      )
    }
  }

  @discardableResult
  private func markForegroundContinuationsReady() -> Bool {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else { return false }
    let scopes = manifests.compactMap { manifest -> String? in
      guard let runId = manifest.expectedRunId else { return nil }
      return Self.foregroundContinuationScope(
        network: manifest.network,
        accountUuid: manifest.accountUuid,
        runId: runId
      )
    }
    stateLock.withPreparationLock {
      foregroundContinuationScopes.formUnion(scopes)
      persistForegroundContinuationScopesLocked()
    }
    return !scopes.isEmpty
  }

  private func persistForegroundContinuationScopesLocked() {
    UserDefaults.standard.set(
      foregroundContinuationScopes.sorted(),
      forKey: Self.foregroundContinuationScopesKey
    )
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
      postNeedsActionNotification(reason: "credential-store-unavailable")
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
        postNeedsActionNotification(
          reason: "advance-needs-action",
          manifest: manifest
        )
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
        postNeedsActionNotification(
          reason: "signing-required",
          manifest: manifest,
          progress: preparation
        )
        return .needsAction
      case 3:
        if !isExpired && !isForegroundHandoffRequested {
          postNeedsActionNotification(
            reason: "preparation-cancelled",
            manifest: manifest,
            progress: preparation
          )
        }
        return .cancelled
      case 0, 5:
        break
      default:
        postNeedsActionNotification(
          reason: "unknown-state",
          manifest: manifest,
          progress: preparation
        )
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
      guard !isStopRequested else { return .cancelled }
      var syncCode = runSync(manifest)
      if syncCode == 3 {
        guard waitForRunningSync() else {
          return isStopRequested
            ? .cancelled
            : .retry(Self.busyRetryDelay)
        }
        guard !isStopRequested else { return .cancelled }
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
    guard !isStopRequested else { return .cancelled }

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

  private func startAuthorizationMonitoring() {
    let monitor = IronwoodMigrationNotificationAuthorizationMonitor()
    let previous = stateLock.withPreparationLock {
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
    let monitor = stateLock.withPreparationLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      defer { authorizationMonitor = nil }
      return authorizationMonitor
    }
    monitor?.cancel()
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
        || notificationAuthorization.isDisabled
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
    guard !stateLock.withPreparationLock({
      notificationAuthorization.isDisabled
    }) else {
      return
    }
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
    addNotificationIfEnabled(request)
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

  private func postNeedsActionNotification(
    reason: String,
    manifest: IronwoodMigrationBackgroundManifest? = nil,
    progress: CMigrationPreparationProgress? = nil
  ) {
    guard !stateLock.withPreparationLock({
      notificationAuthorization.isDisabled
    }) else {
      return
    }
    if let manifest {
      guard let scope = Self.preparationScope(for: manifest) else { return }
      postNeedsActionNotification(
        scope: scope,
        fingerprint: needsActionFingerprint(
          scope: scope,
          reason: reason,
          progress: progress
        )
      )
      return
    }

    let manifests =
      IronwoodMigrationBackgroundCredentialStore.loadAll()?.filter {
        $0.expectedRunId != nil
      } ?? []
    if manifests.isEmpty {
      postNeedsActionNotification(
        scope: "global",
        fingerprint: "global:\(reason)"
      )
      return
    }
    for manifest in manifests {
      guard let scope = Self.preparationScope(for: manifest) else { continue }
      postNeedsActionNotification(
        scope: scope,
        fingerprint: needsActionFingerprint(
          scope: scope,
          reason: reason,
          progress: nil
        )
      )
    }
  }

  private func postNeedsActionNotification(
    scope: String,
    fingerprint: String
  ) {
    let shouldPost = stateLock.withPreparationLock { () -> Bool in
      guard shouldPostMigrationPreparationNeedsActionNotification(
        previousFingerprint: needsActionNotificationFingerprints[scope],
        fingerprint: fingerprint
      ) else {
        return false
      }
      needsActionNotificationFingerprints[scope] = fingerprint
      persistNeedsActionNotificationFingerprintsLocked()
      return true
    }
    guard shouldPost else { return }

    let content = UNMutableNotificationContent()
    content.title = "Continue preparing your migration"
    content.body = "Open and unlock Vizor to continue."
    content.sound = .default
    addNotificationIfEnabled(
      UNNotificationRequest(
        identifier: Self.needsActionNotificationIdentifier(scope: scope),
        content: content,
        trigger: nil
      )
    )
  }

  private func needsActionFingerprint(
    scope: String,
    reason: String,
    progress: CMigrationPreparationProgress?
  ) -> String {
    guard let progress else { return "\(scope):\(reason)" }
    return [
      scope,
      reason,
      String(progress.state),
      String(progress.confirmation_count),
      String(progress.confirmation_target),
      String(progress.completed_stage_count),
      String(progress.total_stage_count),
    ].joined(separator: ":")
  }

  private func clearNeedsActionNotification(scope: String) {
    let identifier = Self.needsActionNotificationIdentifier(scope: scope)
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(
      withIdentifiers: [identifier, Self.needsActionIdentifier]
    )
    center.removeDeliveredNotifications(
      withIdentifiers: [identifier, Self.needsActionIdentifier]
    )
  }

  private func resetNeedsActionNotifications() {
    let identifiers = stateLock.withPreparationLock { () -> [String] in
      let identifiers = needsActionNotificationFingerprints.keys.map {
        Self.needsActionNotificationIdentifier(scope: $0)
      }
      needsActionNotificationFingerprints.removeAll()
      persistNeedsActionNotificationFingerprintsLocked()
      return identifiers
    }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(
      withIdentifiers: identifiers + [Self.needsActionIdentifier]
    )
    center.removeDeliveredNotifications(
      withIdentifiers: identifiers + [Self.needsActionIdentifier]
    )
  }

  private func persistNeedsActionNotificationFingerprintsLocked() {
    UserDefaults.standard.set(
      needsActionNotificationFingerprints,
      forKey: Self.needsActionNotificationFingerprintsKey
    )
  }

  private func postProofReadyNotification() {
    guard !stateLock.withPreparationLock({
      notificationAuthorization.isDisabled
    }) else {
      return
    }
    let content = UNMutableNotificationContent()
    content.title = "Continue your Ironwood migration"
    content.body = "Open Vizor to continue your migration."
    content.sound = .default
    addNotificationIfEnabled(
      UNNotificationRequest(
        identifier: Self.proofReadyIdentifier,
        content: content,
        trigger: nil
      )
    )
  }

  private func addNotificationIfEnabled(_ request: UNNotificationRequest) {
    guard !stateLock.withPreparationLock({
      notificationAuthorization.isDisabled
    }) else {
      return
    }
    let center = UNUserNotificationCenter.current()
    center.add(request) { _ in
      let disabled = self.stateLock.withPreparationLock {
        self.notificationAuthorization.isDisabled
      }
      guard disabled else { return }
      center.removePendingNotificationRequests(
        withIdentifiers: [request.identifier]
      )
      center.removeDeliveredNotifications(
        withIdentifiers: [request.identifier]
      )
    }
  }

  private static func preparationScope(
    for manifest: IronwoodMigrationBackgroundManifest
  ) -> String? {
    guard let runId = manifest.expectedRunId else { return nil }
    return foregroundContinuationScope(
      network: manifest.network,
      accountUuid: manifest.accountUuid,
      runId: runId
    )
  }

  private static func needsActionNotificationIdentifier(
    scope: String
  ) -> String {
    "\(needsActionIdentifier).\(scope)"
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
