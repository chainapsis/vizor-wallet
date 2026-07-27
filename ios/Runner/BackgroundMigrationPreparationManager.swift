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

func migrationPreparationCancellationResult(
  taskExpired: Bool,
  foregroundHandoffRequested: Bool,
  mutationQuiesced: Bool,
  notificationsDisabled: Bool
) -> BackgroundMigrationPreparationPassResult {
  if taskExpired || foregroundHandoffRequested || mutationQuiesced
    || notificationsDisabled
  {
    return .cancelled
  }
  return .needsAction
}

func migrationPreparationExpirationRequiresBackgroundRecovery(
  taskExpired: Bool,
  resumeTarget: BackgroundMigrationPreparationResumeTarget
) -> Bool {
  guard taskExpired else { return false }
  return resumeTarget == .continuedProcessing
    || resumeTarget == .backgroundProcessing
}

func migrationPreparationExpirationRequiresForegroundContinuation(
  taskExpired: Bool,
  resumeTarget: BackgroundMigrationPreparationResumeTarget
) -> Bool {
  taskExpired && resumeTarget == .idle
}

func migrationPreparationPassCompleted(
  _ result: BackgroundMigrationPreparationPassResult,
  terminalAfterExpiration: Bool
) -> Bool {
  result == .completed || terminalAfterExpiration
}

func migrationPreparationPassResultAfterHandoff(
  _ result: BackgroundMigrationPreparationPassResult,
  handoffScheduled: Bool,
  interruptionRequested: Bool
) -> BackgroundMigrationPreparationPassResult {
  guard case .deferred = result, !handoffScheduled else { return result }
  if interruptionRequested { return .cancelled }
  return .needsAction
}

enum MigrationPreparationScopeTrackingDisposition: Equatable {
  case progress(MigrationPreparationConfirmationProgress)
  case completed(MigrationPreparationConfirmationProgress)
  case retry
  case needsForegroundRecovery(fingerprint: String, taskFailed: Bool)
  case terminalFailure(fingerprint: String)
  case inactive
}

func migrationPreparationTxidInspectionFailureDisposition()
  -> MigrationPreparationScopeTrackingDisposition
{
  .needsForegroundRecovery(
    fingerprint: "txid-inspection-failed",
    taskFailed: true
  )
}

func migrationPreparationStatusInspectionFailureDisposition()
  -> MigrationPreparationScopeTrackingDisposition
{
  .needsForegroundRecovery(
    fingerprint: "status-inspection-failed",
    taskFailed: true
  )
}

struct MigrationPreparationScopeTrackingResult: Equatable {
  let scope: String
  let disposition: MigrationPreparationScopeTrackingDisposition
}

struct MigrationPreparationTrackingBatch: Equatable {
  let progress: MigrationPreparationConfirmationProgress?
  let continuationReadyScopes: Set<String>
  let confirmedWaveScopes: Set<String>
  let notificationEvents: [MigrationPreparationNotificationEvent]
  let shouldContinue: Bool
  let hasTaskFailure: Bool
}

struct MigrationPreparationTrackingCompletionPresentation: Equatable {
  let title: String
  let subtitle: String
}

func migrationPreparationTrackingCompletionPresentation(
  _ batch: MigrationPreparationTrackingBatch
) -> MigrationPreparationTrackingCompletionPresentation? {
  guard !batch.hasTaskFailure,
    !batch.confirmedWaveScopes.isEmpty,
    !batch.shouldContinue
  else {
    return nil
  }
  return MigrationPreparationTrackingCompletionPresentation(
    title: "Open Vizor to continue preparation",
    subtitle: "Confirmed transactions are ready"
  )
}

func migrationPreparationTrackingBatch(
  results: [MigrationPreparationScopeTrackingResult],
  progressByScope: inout [
    String: MigrationPreparationConfirmationProgress
  ]
) -> MigrationPreparationTrackingBatch {
  var continuationReadyScopes = Set<String>()
  var confirmedWaveScopes = Set<String>()
  var notificationEvents: [MigrationPreparationNotificationEvent] = []
  var shouldContinue = false
  var hasTaskFailure = false
  var retryScopesWithoutProgress = 0

  for result in results {
    switch result.disposition {
    case .progress(let progress):
      progressByScope[result.scope] = progress
      shouldContinue = true
    case .retry:
      shouldContinue = true
      if progressByScope[result.scope] == nil {
        retryScopesWithoutProgress += 1
      }
    case .completed(let progress):
      progressByScope[result.scope] = progress
      continuationReadyScopes.insert(result.scope)
      confirmedWaveScopes.insert(result.scope)
      notificationEvents.append(
        MigrationPreparationNotificationEvent(
          scope: result.scope,
          kind: .needsForegroundRecovery,
          fingerprint:
            "confirmed-wave-\(progress.completedTransactionCount)-\(progress.confirmedUnitCount)"
        )
      )
    case .needsForegroundRecovery(let fingerprint, let taskFailed):
      continuationReadyScopes.insert(result.scope)
      hasTaskFailure = hasTaskFailure || taskFailed
      notificationEvents.append(
        MigrationPreparationNotificationEvent(
          scope: result.scope,
          kind: .needsForegroundRecovery,
          fingerprint: fingerprint
        )
      )
    case .terminalFailure(let fingerprint):
      continuationReadyScopes.insert(result.scope)
      hasTaskFailure = true
      notificationEvents.append(
        MigrationPreparationNotificationEvent(
          scope: result.scope,
          kind: .terminalFailure,
          fingerprint: fingerprint
        )
      )
    case .inactive:
      break
    }
  }

  let progressValues = progressByScope.values
  let confirmedUnits = progressValues.reduce(Int64(0)) {
    $0 + $1.confirmedUnitCount
  }
  let representedTotalUnits = progressValues.reduce(Int64(0)) {
    $0 + $1.totalUnitCount
  }
  let retryUnits = Int64(retryScopesWithoutProgress)
  let (totalUnits, totalOverflow) =
    representedTotalUnits.addingReportingOverflow(retryUnits)
  let boundedTotalUnits = totalOverflow ? Int64.max : totalUnits
  let completedTransactions = progressValues.reduce(0) {
    $0 + $1.completedTransactionCount
  }
  let totalTransactions = progressValues.reduce(0) {
    $0 + $1.totalTransactionCount
  }
  let progress =
    boundedTotalUnits > 0
    ? MigrationPreparationConfirmationProgress(
      confirmedUnitCount: confirmedUnits,
      totalUnitCount: boundedTotalUnits,
      completedTransactionCount: completedTransactions,
      totalTransactionCount: totalTransactions,
      isComplete:
        !shouldContinue && progressValues.allSatisfy(\.isComplete)
    )
    : nil
  return MigrationPreparationTrackingBatch(
    progress: progress,
    continuationReadyScopes: continuationReadyScopes,
    confirmedWaveScopes: confirmedWaveScopes,
    notificationEvents: notificationEvents,
    shouldContinue: shouldContinue,
    hasTaskFailure: hasTaskFailure
  )
}

func migrationPreparationTrackingBatch(
  results: [MigrationPreparationScopeTrackingResult]
) -> MigrationPreparationTrackingBatch {
  var progressByScope:
    [String: MigrationPreparationConfirmationProgress] = [:]
  return migrationPreparationTrackingBatch(
    results: results,
    progressByScope: &progressByScope
  )
}

private enum BackgroundMigrationPreparationTrackingPass {
  case batch(MigrationPreparationTrackingBatch)
  case cancelled
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

enum BackgroundMigrationPreparationResumeTarget: Equatable {
  case idle
  case terminal
  case continuedProcessing
  case backgroundProcessing
}

enum BackgroundMigrationPreparationContinuedTaskDisposition: Equatable {
  case trackConfirmations
  case foregroundOnly
  case complete
}

struct MigrationPreparationConfirmationProgress: Equatable {
  let confirmedUnitCount: Int64
  let totalUnitCount: Int64
  let completedTransactionCount: Int
  let totalTransactionCount: Int
  // This means every transaction currently materialized in the observed wave
  // reached the confirmation target. It does not mean every preparation stage
  // has been materialized or that the whole preparation is complete.
  let isComplete: Bool
}

func migrationPreparationConfirmationProgress(
  observations: [NativeLightwalletdTransactionObservation],
  chainTipHeight: UInt64,
  confirmationTarget: UInt64,
  totalStageCount: UInt32 = 0
) -> MigrationPreparationConfirmationProgress {
  let target = max(1, confirmationTarget)
  let confirmations = observations.map { observation -> UInt64 in
    guard case .mined(let minedHeight) = observation,
      chainTipHeight >= minedHeight
    else {
      return 0
    }
    return min(target, chainTipHeight - minedHeight + 1)
  }
  let completed = confirmations.filter { $0 >= target }.count
  // `observations` contains every materialized stage, including stages already
  // confirmed in an earlier wave. Stages still waiting for inputs have no txid
  // to query, so the read-only snapshot's fixed stage count supplies the full
  // denominator without double-counting prior waves.
  let totalTransactions = max(observations.count, Int(totalStageCount))
  let totalUnits = UInt64(totalTransactions) * target
  return MigrationPreparationConfirmationProgress(
    confirmedUnitCount: Int64(confirmations.reduce(0, +)),
    totalUnitCount: Int64(totalUnits),
    completedTransactionCount: completed,
    totalTransactionCount: totalTransactions,
    isComplete: !observations.isEmpty && completed == observations.count
  )
}

func migrationPreparationConfirmationDisposition(
  observations: [NativeLightwalletdTransactionObservation],
  chainTipHeight: UInt64,
  confirmationTarget: UInt64,
  totalStageCount: UInt32 = 0
) -> MigrationPreparationScopeTrackingDisposition {
  if observations.contains(where: {
    if case .forked = $0 { return true }
    return false
  }) {
    return .needsForegroundRecovery(
      fingerprint: "forked-transaction",
      taskFailed: true
    )
  }
  let progress = migrationPreparationConfirmationProgress(
    observations: observations,
    chainTipHeight: chainTipHeight,
    confirmationTarget: confirmationTarget,
    totalStageCount: totalStageCount
  )
  return progress.isComplete ? .completed(progress) : .progress(progress)
}

func migrationPreparationScopeTrackingDisposition(
  state: UInt8,
  completedStageCount: UInt32 = 0,
  totalStageCount: UInt32 = 0,
  confirmationTarget: UInt32 = 0
) -> MigrationPreparationScopeTrackingDisposition? {
  switch state {
  case 0:
    return nil
  case 1:
    // A local proof-ready snapshot is not network confirmation evidence.
    // The iOS background task may only complete from lightwalletd observations
    // collected in this process; any state-1 value is handed to foreground.
    return .needsForegroundRecovery(
      fingerprint: "state-1-unverified",
      taskFailed: true
    )
  case 2, 3:
    return .needsForegroundRecovery(
      fingerprint: "state-\(state)",
      taskFailed: true
    )
  case 4:
    return .inactive
  case 5:
    return .needsForegroundRecovery(
      fingerprint: "state-5",
      taskFailed: false
    )
  default:
    return .terminalFailure(
      fingerprint: "unexpected-state-\(state)"
    )
  }
}

func migrationPreparationDisplayedProgressUnits(
  previousUnits: Int64,
  progress: MigrationPreparationConfirmationProgress,
  displayUnitCount: Int64
) -> Int64 {
  let boundedTotal = max(1, displayUnitCount)
  let aggregateTotal = max(1, progress.totalUnitCount)
  let fraction = min(
    1,
    max(
      0,
      Double(progress.confirmedUnitCount) / Double(aggregateTotal)
    )
  )
  let requestedUnits = Int64(
    (fraction * Double(boundedTotal)).rounded()
  )
  let completionBound =
    progress.isComplete ? boundedTotal : max(0, boundedTotal - 1)
  let boundedPrevious = min(completionBound, max(0, previousUnits))
  let boundedRequested = min(completionBound, max(0, requestedUnits))
  guard !progress.isComplete else {
    return max(boundedPrevious, boundedRequested)
  }

  // Keep the system Progress moving while the chain is between blocks, but
  // never cross the display boundary for the next real confirmation.
  let boundedConfirmed = min(
    aggregateTotal,
    max(0, progress.confirmedUnitCount)
  )
  let nextConfirmedUnit =
    boundedConfirmed < aggregateTotal
    ? boundedConfirmed + 1
    : aggregateTotal
  let nextConfirmationBoundary = Int64(
    (
      Double(nextConfirmedUnit) / Double(aggregateTotal)
        * Double(boundedTotal)
    ).rounded(.down)
  )
  let heartbeatBound = min(
    completionBound,
    max(boundedRequested, nextConfirmationBoundary - 1)
  )
  return max(
    boundedPrevious,
    max(
      boundedRequested,
      min(heartbeatBound, boundedPrevious + 1)
    )
  )
}

func migrationPreparationResumeTarget(
  states: [UInt8],
  inspectionFailed: Bool
) -> BackgroundMigrationPreparationResumeTarget {
  if states.contains(0) {
    return .continuedProcessing
  }
  if inspectionFailed || states.contains(2) || states.contains(3)
    || states.contains(5)
  {
    return .backgroundProcessing
  }
  if states.isEmpty || states.allSatisfy({ $0 == 4 }) {
    return .terminal
  }
  return .idle
}

func migrationPreparationContinuedTaskDisposition(
  _ resumeTarget: BackgroundMigrationPreparationResumeTarget
) -> BackgroundMigrationPreparationContinuedTaskDisposition {
  switch resumeTarget {
  case .continuedProcessing:
    return .trackConfirmations
  case .backgroundProcessing:
    return .foregroundOnly
  case .idle, .terminal:
    return .complete
  }
}

/// Whether the foreground app should take over a pending continued-processing
/// request instead of leaving it for the system to start.
///
/// A request stays pending between submission and the moment the system starts
/// it. Claiming it in that window cancels the task the foreground just armed,
/// so the Dynamic Island activity never appears and the confirmations are
/// never tracked. Only take a request over when background tracking cannot
/// make progress on it anyway.
func shouldClaimPendingMigrationPreparationRequest(
  hasPendingRequest: Bool,
  canTrackInBackground: Bool,
  foregroundContinuationPending: Bool = false,
  taskRunning: Bool,
  deferredPassRunning: Bool,
  mutationQuiesced: Bool,
  notificationsDisabled: Bool
) -> Bool {
  hasPendingRequest
    && (foregroundContinuationPending || !canTrackInBackground) && !taskRunning
    && !deferredPassRunning && !mutationQuiesced && !notificationsDisabled
}

/// The runs a new tracking task would actually do work for: those still
/// waiting for denomination confirmations whose foreground continuation has
/// not been acknowledged yet.
///
/// The subtraction runs in this direction on purpose. The continued task is a
/// single app-wide request that sweeps every account's manifest, skipping any
/// run that is not waiting for confirmations. So a run that needs the
/// foreground app (state `5`, needs-action, unreadable) never contributes work
/// — and must never veto a *different* account's tracking either. Asking
/// "which recorded scopes are not trackable" gave exactly that veto: one
/// account parked in state `5` blocked confirmation tracking for every other
/// account, permanently, because its scope is only cleared by the migration
/// status screen.
///
/// Subtracting the other way keeps the property that guard was there for. Once
/// a run's tracking has completed and marked its continuation ready, it drops
/// out of this set, so the task is not re-armed to re-observe the same
/// confirmed transactions and re-post the same notification while the DB waits
/// for a foreground reconcile.
func migrationPreparationPendingTrackableScopes(
  continuationScopes: Set<String>,
  confirmationTrackableScopes: Set<String>
) -> Set<String> {
  confirmationTrackableScopes.subtracting(continuationScopes)
}

/// Report whether the continued-processing task ended without an observed
/// migration failure.
///
/// Expiration interrupts this one execution opportunity; it does not prove
/// that the migration failed and BGContinuedProcessingTask does not retry work
/// after `success: false`.
func migrationPreparationTrackingTaskSucceeded(
  taskFailed: Bool,
  quiesced: Bool,
  expired: Bool,
  handedOff: Bool,
  notificationsDisabled: Bool
) -> Bool {
  !taskFailed && !quiesced
    && (!expired || handedOff || notificationsDisabled)
}

func shouldMarkMigrationPreparationForegroundContinuation(
  hasPendingRequest: Bool,
  hasBoundPreparation: Bool,
  notificationsDisabled: Bool
) -> Bool {
  hasPendingRequest && hasBoundPreparation && !notificationsDisabled
}

func shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
  hasPendingRequest: Bool,
  hasBoundPreparation: Bool,
  notificationsDisabled: Bool,
  resumeTarget: BackgroundMigrationPreparationResumeTarget
) -> Bool {
  hasPendingRequest && !hasBoundPreparation && !notificationsDisabled
    && resumeTarget == .backgroundProcessing
}

func migrationPreparationStateNeedsForegroundContinuation(
  _ state: UInt8
) -> Bool {
  state == 0 || state == 2 || state == 3 || state == 5
}

func migrationPreparationStateNeedsForegroundNotification(
  _ state: UInt8
) -> Bool {
  state == 2 || state == 3 || state == 5
}

func shouldTryStoredTransactionIdByteOrder(
  after result: Result<
    NativeLightwalletdTransactionObservation,
    NativeLightwalletdError
  >
) -> Bool {
  switch result {
  case .success(.notFound), .failure(.grpcStatusUnavailable):
    return true
  default:
    return false
  }
}

func transactionObservationAfterStoredByteOrderFallback(
  first: Result<
    NativeLightwalletdTransactionObservation,
    NativeLightwalletdError
  >,
  second: Result<
    NativeLightwalletdTransactionObservation,
    NativeLightwalletdError
  >
) -> Result<
  NativeLightwalletdTransactionObservation,
  NativeLightwalletdError
> {
  if case .failure(.grpcStatusUnavailable) = first,
    case .failure(.grpcStatusUnavailable) = second
  {
    // A successful unary GetTransaction always has a framed body. Foundation
    // hides the non-OK trailers, so two empty responses for both byte orders
    // are the observable equivalent of NotFound. NotFound remains an
    // unconfirmed observation and is polled again; it is never success.
    return .success(.notFound)
  }
  return second
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
  // A persisted cancellation is not, by itself, an expected cancellation of
  // the iOS task. The user must reopen the app to recover the preparation.
  // Task-originated cancellations (foreground handoff, mutation quiescence,
  // and notification revocation) are classified at the point where the
  // manager's runtime state is available.
  if states.contains(3) { return .needsAction }
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

  /// How many consecutive passes may observe a confirmation-waiting run with
  /// no listable transaction before it is treated as stalled rather than as a
  /// foreground commit still in flight.
  private static let emptyObservationPassLimit = 2
  private var emptyObservationPassesByScope: [String: Int] = [:]

  private static let schedulingTraceFileName =
    "ironwood-preparation-scheduling-trace.jsonl"
  private static let schedulingTraceMaxBytes: UInt64 = 256 * 1024
  private let traceLock = NSLock()

  private static let watchdogIdentifier =
    "com.keplr.vizor.ironwood-preparation.watchdog"
  private static let watchdogDelay: TimeInterval = 15 * 60
  private static let confirmationQueryInterval: TimeInterval = 60
  private static let progressHeartbeatInterval: TimeInterval = 15
  private static let busyRetryDelay: TimeInterval = 60
  private static let transientRetryDelay: TimeInterval = 60
  private static let confirmationTarget: UInt64 = 3
  private static let progressDisplayUnitCount: Int64 = 1000
  private static let preparationProgressUnitLimit: Int64 = 949
  private static let schedulingStateKey =
    "ironwoodMigrationPreparationSchedulingState"
  private static let schedulingStateUpdatedAtKey =
    "ironwoodMigrationPreparationSchedulingStateUpdatedAt"
  private static let schedulingErrorKey =
    "ironwoodMigrationPreparationSchedulingError"
  private static let foregroundContinuationScopesKey =
    "ironwoodMigrationPreparationForegroundContinuationScopes"

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
  private let notificationCoordinator =
    MigrationPreparationNotificationCoordinator.shared
  private var taskProgress: Progress?
  private var trackingCancellation: BackgroundMigrationCancellation?
  private var trackingProgressByScope:
    [String: MigrationPreparationConfirmationProgress] = [:]
  private var latestTrackingProgress:
    MigrationPreparationConfirmationProgress?
  private var displayedProgressUnits: Int64 = 0
  private var authorizationMonitor:
    IronwoodMigrationNotificationAuthorizationMonitor?
  private init() {
    foregroundContinuationScopes = Set(
      UserDefaults.standard.stringArray(
        forKey: Self.foregroundContinuationScopesKey
      ) ?? []
    )
  }

  func handoffPendingRequestForForegroundLaunch() {
    notificationCoordinator.clearDeliveredSummary()
    pruneForegroundContinuationScopes()
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
      let resumeTarget =
        hasPendingRequest && !hasBoundPreparation && !notificationsDisabled
        ? self.preparationResumeTarget()
        : .idle
      let shouldHandoffToBackground =
        shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
          hasPendingRequest: hasPendingRequest,
          hasBoundPreparation: hasBoundPreparation,
          notificationsDisabled: notificationsDisabled,
          resumeTarget: resumeTarget
        )
      if shouldHandoffToBackground {
        self.recordSchedulingState(
          "processing_redirected_on_foreground_launch"
        )
        BackgroundMigrationManager.shared.schedulePreparationHandoff(
          after: 60
        ) { scheduled in
          if scheduled {
            BGTaskScheduler.shared.cancel(
              taskRequestWithIdentifier: Self.taskIdentifier
            )
            self.cancelWatchdog()
          } else {
            self.recordDeferredSchedulingFailure()
          }
        }
        return
      }
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
    let cancellation = stateLock.withPreparationLock {
      foregroundHandoffRequested = taskRunning
      return trackingCancellation
    }
    guard let cancellation else { return }
    recordSchedulingState("handoff_to_foreground")
    cancellation.cancel()
  }

  func runtimeState(
    network: String,
    accountUuid: String,
    runId: String,
    completion: @escaping (BackgroundMigrationPreparationRuntimeState) -> Void
  ) {
    pruneForegroundContinuationScopes()
    let scope = Self.foregroundContinuationScope(
      network: network,
      accountUuid: accountUuid,
      runId: runId
    )
    let evaluate = { [weak self] in
      guard let self else {
        completion(.idle)
        return
      }
      // A submitted continued-processing request is pending until the system
      // starts it. Claiming it in that window cancels the very task the
      // foreground just armed, so the Dynamic Island activity never appears.
      // Only take over a pending request when background tracking cannot make
      // progress on it anyway.
      let canTrackInBackground = migrationPreparationContinuedTaskDisposition(
        self.preparationResumeTarget()
      ) == .trackConfirmations
      BGTaskScheduler.shared.getPendingTaskRequests { requests in
        let hasPendingRequest = requests.contains {
          $0.identifier == Self.taskIdentifier
        }
        let shouldClaimPendingRequest = self.stateLock.withPreparationLock {
          let continuationPending =
            self.foregroundContinuationScopes.contains(scope)
          return shouldClaimPendingMigrationPreparationRequest(
            hasPendingRequest: hasPendingRequest,
            canTrackInBackground: canTrackInBackground,
            foregroundContinuationPending: continuationPending,
            taskRunning: self.taskRunning,
            deferredPassRunning: self.deferredPassRunning,
            mutationQuiesced: self.mutationQuiesced,
            notificationsDisabled: self.notificationAuthorization.isDisabled
          )
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
    pruneForegroundContinuationScopes()
    switch migrationPreparationContinuedTaskDisposition(
      preparationResumeTarget()
    ) {
    case .trackConfirmations:
      break
    case .foregroundOnly:
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      recordSchedulingState("foreground_only")
      cancelWatchdog()
      completion(false)
      return
    case .complete:
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      recordSchedulingState("not_needed_before_submit")
      cancelWatchdog()
      completion(false)
      return
    }
    // Arm whenever some run still needs confirmation tracking. The old
    // `foregroundContinuationScopes.isEmpty` guard vetoed submission whenever
    // ANY account had a recorded continuation, so one account parked in state
    // `5` silently stopped confirmation tracking for every other account.
    let pendingScopes = pendingTrackableScopes()
    // Record which guard refused the submission. Without this the "did not
    // submit" paths leave the previous breadcrumb in place, which reads as a
    // successful submission that never ran.
    let submissionBlockedReason = stateLock.withPreparationLock {
      () -> String? in
      if mutationQuiesced { return "blocked_mutation_quiesced" }
      if submissionInFlight { return "blocked_submission_in_flight" }
      if taskRunning { return "blocked_task_running" }
      if pendingScopes.isEmpty {
        // Not "blocked": nothing is waiting for denomination confirmations
        // that has not already been handed to the foreground.
        return "no_trackable_run"
      }
      if notificationAuthorization.isDisabled {
        return "blocked_notifications_disabled"
      }
      submissionInFlight = true
      return nil
    }
    if let submissionBlockedReason {
      recordSchedulingState(submissionBlockedReason)
      let canContinue = stateLock.withPreparationLock {
        !mutationQuiesced
          && !notificationAuthorization.isDisabled
          && (submissionInFlight || taskRunning
            || !foregroundContinuationScopes.isEmpty)
      }
      completion(canContinue)
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
      if requests.contains(where: { $0.identifier == Self.taskIdentifier }) {
        self.stateLock.withPreparationLock {
          self.submissionInFlight = false
        }
        self.recordSchedulingState("pending")
        completion(true)
        return
      }

      self.scheduleWatchdog()
      let request = BGContinuedProcessingTaskRequest(
        identifier: Self.taskIdentifier,
        title: "Checking preparation transactions",
        subtitle: "Waiting for confirmations"
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
        print("[BGPreparation] confirmation tracker submitted")
        completion(true)
        return
      }
      self.cancelWatchdog()
      if let error = submission.error {
        self.recordSchedulingState("failed", error: error)
        self.postNeedsActionNotification(reason: "submission-failed")
        print("[BGPreparation] submit failed: \(error)")
      }
      completion(false)
    }
  }

  func disableForUnauthorizedNotifications() {
    let monitor = stateLock.withPreparationLock {
      () -> IronwoodMigrationNotificationAuthorizationMonitor? in
      expired = true
      submissionInFlight = false
      notificationAuthorization.disable()
      trackingCancellation?.cancel()
      foregroundContinuationScopes.removeAll()
      persistForegroundContinuationScopesLocked()
      defer { authorizationMonitor = nil }
      return authorizationMonitor
    }
    monitor?.cancel()
    BGTaskScheduler.shared.cancel(
      taskRequestWithIdentifier: Self.taskIdentifier
    )
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
      trackingCancellation?.cancel()
      foregroundContinuationScopes.removeAll()
      persistForegroundContinuationScopesLocked()
    }
    queue.async {
      DispatchQueue.main.async { completion(true) }
    }
  }

  func resumeAfterMutation() {
    stateLock.withPreparationLock {
      expired = false
      mutationQuiesced = false
    }
    pruneForegroundContinuationScopes()
    if let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll() {
      var retainedScopes = Set(["global"])
      retainedScopes.formUnion(
        manifests.compactMap { Self.preparationScope(for: $0) }
      )
      notificationCoordinator.retain(scopes: retainedScopes)
    }
    switch preparationResumeTarget() {
    case .idle, .terminal:
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      recordSchedulingState("idle_after_mutation")
      cancelWatchdog()
    case .continuedProcessing:
      start { _ in }
    case .backgroundProcessing:
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      markForegroundContinuationsReady()
      recordSchedulingState("waiting_for_foreground_after_mutation")
      cancelWatchdog()
      notifyPreparationNeedsForeground()
    }
  }

  func expireDeferredPass() {
    stateLock.withPreparationLock {
      if deferredPassRunning {
        expired = true
      }
    }
  }

  func cancelDeferredPass() {
    stateLock.withPreparationLock {
      if deferredPassRunning {
        expired = true
      }
    }
  }

  func recordDeferredSchedulingFailure() {
    recordSchedulingState("processing_reschedule_failed")
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
    stateLock.withPreparationLock {
      submissionInFlight = false
    }
    switch migrationPreparationContinuedTaskDisposition(
      preparationResumeTarget()
    ) {
    case .trackConfirmations:
      break
    case .foregroundOnly:
      markForegroundContinuationsReady()
      notifyPreparationNeedsForeground()
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      recordSchedulingState("waiting_for_foreground")
      cancelWatchdog()
      task.setTaskCompleted(success: true)
      return
    case .complete:
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      recordSchedulingState("not_needed_on_launch")
      cancelWatchdog()
      task.setTaskCompleted(success: true)
      return
    }
    let cancellation = BackgroundMigrationCancellation()
    let mayRun = stateLock.withPreparationLock { () -> Bool in
      guard !mutationQuiesced
        && !notificationAuthorization.isDisabled
        && !taskRunning
      else {
        return false
      }
      taskRunning = true
      expired = false
      emptyObservationPassesByScope.removeAll()
      trackingProgressByScope.removeAll()
      latestTrackingProgress = nil
      displayedProgressUnits = 0
      foregroundHandoffRequested = false
      taskProgress = task.progress
      taskProgress?.totalUnitCount = Self.progressDisplayUnitCount
      taskProgress?.completedUnitCount = 0
      trackingCancellation = cancellation
      return true
    }
    guard mayRun else {
      task.setTaskCompleted(success: true)
      return
    }

    cancelWatchdog()
    startAuthorizationMonitoring()
    recordSchedulingState("tracking_confirmations")
    task.expirationHandler = { [weak self] in
      guard let self else { return }
      self.stateLock.withPreparationLock {
        self.expired = true
        self.trackingCancellation?.cancel()
      }
    }

    queue.async { [weak self] in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      var pass = self.runConfirmationTrackingPass(
        cancellation: cancellation
      )
      var taskFailureObserved = false
      while true {
        switch pass {
        case .batch(let batch):
          taskFailureObserved =
            taskFailureObserved || batch.hasTaskFailure
          self.applyTrackingBatch(batch)
          if let handoffPresentation =
            migrationPreparationTrackingCompletionPresentation(batch),
            !taskFailureObserved
          {
            self.finishConfirmationTrackingTask(
              task,
              taskFailed: false,
              completionPresentation: handoffPresentation
            )
            return
          }
          guard batch.shouldContinue, !self.isTrackingStopRequested else {
            self.finishConfirmationTrackingTask(
              task,
              taskFailed: taskFailureObserved,
              completionPresentation:
                migrationPreparationTrackingCompletionPresentation(batch)
            )
            return
          }
          guard self.waitForNextConfirmationQuery(
            cancellation: cancellation
          ) else {
            self.finishConfirmationTrackingTask(
              task,
              taskFailed: taskFailureObserved,
              completionPresentation: nil
            )
            return
          }
          pass = self.runConfirmationTrackingPass(
            cancellation: cancellation
          )
        case .cancelled:
          self.finishConfirmationTrackingTask(
            task,
            taskFailed: taskFailureObserved,
            completionPresentation: nil
          )
          return
        }
      }
    }
  }

  private func runConfirmationTrackingPass(
    cancellation: BackgroundMigrationCancellation
  ) -> BackgroundMigrationPreparationTrackingPass {
    if cancellation.isCancelled { return .cancelled }
    guard UIApplication.shared.isProtectedDataAvailable else {
      return .batch(
        migrationPreparationTrackingBatch(
          results: [
            MigrationPreparationScopeTrackingResult(
              scope: "global",
              disposition: .retry
            )
          ],
          progressByScope: &trackingProgressByScope
        )
      )
    }
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else {
      return .batch(
        migrationPreparationTrackingBatch(
          results: [
            MigrationPreparationScopeTrackingResult(
              scope: "global",
              disposition: .retry
            )
          ],
          progressByScope: &trackingProgressByScope
        )
      )
    }
    if manifests.isEmpty {
      return .batch(
        migrationPreparationTrackingBatch(
          results: [],
          progressByScope: &trackingProgressByScope
        )
      )
    }

    var results: [MigrationPreparationScopeTrackingResult] = []
    for manifest in manifests {
      guard let runId = manifest.expectedRunId else { continue }
      let scope = Self.foregroundContinuationScope(
        network: manifest.network,
        accountUuid: manifest.accountUuid,
        runId: runId
      )
      let alreadyHandedOff = stateLock.withPreparationLock {
        foregroundContinuationScopes.contains(scope)
      }
      if alreadyHandedOff {
        continue
      }
      print(
        "[BGPreparation] tracking \(manifest.network):\(manifest.accountUuid) run=\(runId)"
      )
      var preparation = CMigrationPreparationProgress(
        state: 0,
        confirmation_count: 0,
        confirmation_target: 0,
        completed_stage_count: 0,
        total_stage_count: 0
      )
      let inspectionCode = zcash_inspect_migration_preparation(
        manifest.dbPath,
        manifest.network,
        manifest.accountUuid,
        runId,
        &preparation
      )
      if inspectionCode != 0 {
        print(
          "[BGPreparation] inspect failed code=\(inspectionCode) account=\(manifest.accountUuid)"
        )
        results.append(
          MigrationPreparationScopeTrackingResult(
            scope: scope,
            disposition:
              migrationPreparationStatusInspectionFailureDisposition()
          )
        )
        continue
      }
      print(
        "[BGPreparation] inspect state=\(preparation.state) account=\(manifest.accountUuid)"
      )
      if let disposition = migrationPreparationScopeTrackingDisposition(
        state: preparation.state,
        completedStageCount: preparation.completed_stage_count,
        totalStageCount: preparation.total_stage_count,
        confirmationTarget: preparation.confirmation_target
      ) {
        results.append(
          MigrationPreparationScopeTrackingResult(
            scope: scope,
            disposition: disposition
          )
        )
        continue
      }

      guard let transactionIds = observableTransactionIds(
        manifest: manifest,
        runId: runId
      ) else {
        print(
          "[BGPreparation] txid listing failed account=\(manifest.accountUuid)"
        )
        results.append(
          MigrationPreparationScopeTrackingResult(
            scope: scope,
            disposition: migrationPreparationTxidInspectionFailureDisposition()
          )
        )
        continue
      }
      guard !transactionIds.isEmpty else {
        // A run waiting for confirmations with nothing listable is stalled: a
        // reorg reset its stages to `awaiting_inputs` and cleared the signed
        // transactions, so there is nothing to observe until the foreground
        // rebuilds and rebroadcasts them. Never report completion without a
        // txid — but do not sit on `.retry` until the system expires the task
        // either. The foreground may still be committing its first stage, so
        // allow a couple of passes for that race and then stall out with the
        // notification instead of a silent spin.
        print(
          "[BGPreparation] no observable txids account=\(manifest.accountUuid)"
        )
        let passCount = (emptyObservationPassesByScope[scope] ?? 0) + 1
        emptyObservationPassesByScope[scope] = passCount
        results.append(
          MigrationPreparationScopeTrackingResult(
            scope: scope,
            disposition:
              passCount >= Self.emptyObservationPassLimit
              ? .needsForegroundRecovery(
                fingerprint: "missing-transactions",
                taskFailed: true
              )
              : .retry
          )
        )
        continue
      }
      emptyObservationPassesByScope.removeValue(forKey: scope)
      print(
        "[BGPreparation] observing \(transactionIds.count) tx(s) account=\(manifest.accountUuid)"
      )
      let tip: UInt64
      switch NativeLightwalletdClient.latestBlockHeight(
        endpoint: manifest.lightwalletdUrl,
        cancellation: cancellation
      ) {
      case .success(let height):
        tip = height
      case .failure(.cancelled):
        return .cancelled
      case .failure(let error):
        print(
          "[BGPreparation] latest block failed account=\(manifest.accountUuid) error=\(error)"
        )
        results.append(
          MigrationPreparationScopeTrackingResult(
            scope: scope,
            disposition: .retry
          )
        )
        continue
      }

      var observations: [NativeLightwalletdTransactionObservation] = []
      var queryFailed = false
      for transactionId in transactionIds {
        switch transactionObservation(
          endpoint: manifest.lightwalletdUrl,
          transactionIdHex: transactionId,
          cancellation: cancellation
        ) {
        case .success(let observation):
          observations.append(observation)
        case .failure(.cancelled):
          return .cancelled
        case .failure(let error):
          print(
            "[BGPreparation] tx query failed txid=\(transactionId) error=\(error)"
          )
          queryFailed = true
        }
        if queryFailed { break }
      }
      if queryFailed {
        results.append(
          MigrationPreparationScopeTrackingResult(
            scope: scope,
            disposition: .retry
          )
        )
        continue
      }
      let disposition = migrationPreparationConfirmationDisposition(
        observations: observations,
        chainTipHeight: tip,
        confirmationTarget: Self.confirmationTarget,
        totalStageCount: preparation.total_stage_count
      )
      results.append(
        MigrationPreparationScopeTrackingResult(
          scope: scope,
          disposition: disposition
        )
      )
    }

    return .batch(
      migrationPreparationTrackingBatch(
        results: results,
        progressByScope: &trackingProgressByScope
      )
    )
  }

  private func observableTransactionIds(
    manifest: IronwoodMigrationBackgroundManifest,
    runId: String
  ) -> [String]? {
    var requiredLength: UInt = 0
    guard
      zcash_list_migration_preparation_txids(
        manifest.dbPath,
        manifest.network,
        manifest.accountUuid,
        runId,
        nil,
        0,
        &requiredLength
      ) == 0,
      requiredLength > 0
    else {
      return nil
    }
    var buffer = [CChar](
      repeating: 0,
      count: Int(requiredLength)
    )
    let code = buffer.withUnsafeMutableBufferPointer { pointer in
      zcash_list_migration_preparation_txids(
        manifest.dbPath,
        manifest.network,
        manifest.accountUuid,
        runId,
        pointer.baseAddress,
        requiredLength,
        &requiredLength
      )
    }
    guard code == 0 else { return nil }
    let payload = buffer.withUnsafeBufferPointer { pointer in
      String(cString: pointer.baseAddress!)
    }
    if payload.isEmpty { return [] }
    return payload.split(separator: "\n").map(String.init)
  }

  private func transactionObservation(
    endpoint: String,
    transactionIdHex: String,
    cancellation: BackgroundMigrationCancellation
  ) -> Result<
    NativeLightwalletdTransactionObservation,
    NativeLightwalletdError
  > {
    guard let storedOrder = Self.transactionIdData(transactionIdHex) else {
      return .failure(.malformedResponse)
    }
    let protocolOrder = Data(storedOrder.reversed())
    let first = NativeLightwalletdClient.transaction(
      endpoint: endpoint,
      transactionId: protocolOrder,
      cancellation: cancellation
    )
    guard protocolOrder != storedOrder,
      shouldTryStoredTransactionIdByteOrder(after: first)
    else {
      return first
    }
    let second = NativeLightwalletdClient.transaction(
      endpoint: endpoint,
      transactionId: storedOrder,
      cancellation: cancellation
    )
    return transactionObservationAfterStoredByteOrderFallback(
      first: first,
      second: second
    )
  }

  private static func transactionIdData(_ hex: String) -> Data? {
    guard hex.count == 64 else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(32)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else {
        return nil
      }
      bytes.append(byte)
      index = next
    }
    return Data(bytes)
  }

  private func waitForNextConfirmationQuery(
    cancellation: BackgroundMigrationCancellation
  ) -> Bool {
    var remaining = Self.confirmationQueryInterval
    while remaining > 0 {
      if isTrackingStopRequested || cancellation.isCancelled {
        return false
      }
      let interval = min(Self.progressHeartbeatInterval, remaining)
      if cancellation.waitUntilCancelled(timeout: interval) {
        return false
      }
      remaining -= interval
      advanceTrackingHeartbeat()
    }
    return !isTrackingStopRequested && !cancellation.isCancelled
  }

  private func applyTrackingBatch(
    _ batch: MigrationPreparationTrackingBatch
  ) {
    guard !stateLock.withPreparationLock({ mutationQuiesced }) else {
      return
    }
    if !batch.continuationReadyScopes.isEmpty {
      stateLock.withPreparationLock {
        foregroundContinuationScopes.formUnion(
          batch.continuationReadyScopes
        )
        persistForegroundContinuationScopesLocked()
      }
    }
    if let progress = batch.progress {
      updateTrackingProgress(progress)
    }
    if !batch.notificationEvents.isEmpty,
      !stateLock.withPreparationLock({
        notificationAuthorization.isDisabled
      })
    {
      notificationCoordinator.enqueue(batch.notificationEvents)
    }
  }

  private func updateTrackingProgress(
    _ progress: MigrationPreparationConfirmationProgress
  ) {
    stateLock.withPreparationLock {
      guard let taskProgress else { return }
      latestTrackingProgress = progress
      displayedProgressUnits = migrationPreparationDisplayedProgressUnits(
        previousUnits: displayedProgressUnits,
        progress: progress,
        displayUnitCount: Self.preparationProgressUnitLimit
      )
      taskProgress.totalUnitCount = Self.progressDisplayUnitCount
      taskProgress.completedUnitCount = displayedProgressUnits
    }
  }

  private func advanceTrackingHeartbeat() {
    stateLock.withPreparationLock {
      guard let taskProgress else { return }
      if let latestTrackingProgress {
        displayedProgressUnits = migrationPreparationDisplayedProgressUnits(
          previousUnits: displayedProgressUnits,
          progress: latestTrackingProgress,
          displayUnitCount: Self.preparationProgressUnitLimit
        )
      } else {
        // A transient first-query failure still reports liveness without
        // implying meaningful migration completion.
        displayedProgressUnits = min(50, displayedProgressUnits + 1)
      }
      taskProgress.totalUnitCount = Self.progressDisplayUnitCount
      taskProgress.completedUnitCount = displayedProgressUnits
    }
  }

  private func finishConfirmationTrackingTask(
    _ task: BGContinuedProcessingTask,
    taskFailed: Bool,
    completionPresentation: MigrationPreparationTrackingCompletionPresentation?
  ) {
    stopAuthorizationMonitoring()
    let runtime = stateLock.withPreparationLock {
      (
        handedOff: foregroundHandoffRequested,
        expired: expired,
        quiesced: mutationQuiesced,
        disabled: notificationAuthorization.isDisabled
      )
    }
    if (runtime.handedOff || runtime.expired) && !runtime.quiesced {
      markForegroundContinuationsReady()
    }

    let visibleCompletionPresentation =
      !runtime.handedOff && !runtime.expired && !runtime.quiesced
        && !runtime.disabled && !taskFailed
      ? completionPresentation
      : nil
    if let visibleCompletionPresentation {
      task.updateTitle(
        visibleCompletionPresentation.title,
        subtitle: visibleCompletionPresentation.subtitle
      )
    } else if runtime.quiesced {
      // The activity is still captioned "Checking transaction confirmations".
      // Leaving that text on a wallet the user just changed reads as a verdict
      // on their migration; say what actually happened instead.
      task.updateTitle(
        "Migration preparation stopped",
        subtitle: "Wallet accounts changed"
      )
    }

    stateLock.withPreparationLock {
      taskRunning = false
      taskProgress = nil
      trackingCancellation = nil
      latestTrackingProgress = nil
      foregroundHandoffRequested = false
    }

    let success = migrationPreparationTrackingTaskSucceeded(
      taskFailed: taskFailed,
      quiesced: runtime.quiesced,
      expired: runtime.expired,
      handedOff: runtime.handedOff,
      notificationsDisabled: runtime.disabled
    )
    if success {
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
    }
    if runtime.handedOff {
      recordSchedulingState("handed_off_to_foreground")
    } else if runtime.quiesced {
      recordSchedulingState("quiesced_for_mutation")
    } else if runtime.disabled {
      recordSchedulingState("disabled_for_notifications")
    } else if runtime.expired {
      recordSchedulingState("confirmation_tracking_expired")
    } else if taskFailed {
      recordSchedulingState("confirmation_tracking_failed")
    } else if visibleCompletionPresentation != nil {
      recordSchedulingState("confirmation_step_ready_for_foreground")
    } else {
      recordSchedulingState("confirmation_tracking_finished")
    }
    cancelWatchdog()
    task.setTaskCompleted(success: success)
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

  private var isTrackingStopRequested: Bool {
    stateLock.withPreparationLock {
      expired || foregroundHandoffRequested || mutationQuiesced
        || notificationAuthorization.isDisabled
    }
  }

  func hasResumablePreparation() -> Bool {
    let target = preparationResumeTarget()
    return target == .continuedProcessing || target == .backgroundProcessing
  }

  /// Tells the user a bound preparation can only continue in the foreground.
  ///
  /// The silent wake cannot recover cancelled, stalled, or explicitly
  /// foreground-only preparation states. Normal state-0 confirmation tracking
  /// is deliberately excluded: the continued task and Dynamic Island already
  /// represent that work, so a later wake must not produce a second alert.
  ///
  /// Frequency is governed by the existing needs-action fingerprint: it carries
  /// the inspected preparation state, and that state cannot move while nothing
  /// is scanning, so a stalled run is announced once and only speaks again when
  /// its progress actually changes.
  func notifyPreparationNeedsForeground() {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else { return }
    for manifest in manifests {
      guard let runId = manifest.expectedRunId else { continue }
      var preparation = CMigrationPreparationProgress(
        state: 0,
        confirmation_count: 0,
        confirmation_target: 0,
        completed_stage_count: 0,
        total_stage_count: 0
      )
      guard
        zcash_inspect_migration_preparation(
          manifest.dbPath,
          manifest.network,
          manifest.accountUuid,
          runId,
          &preparation
        ) == 0
      else { continue }
      // Recovery states are surfaced when read-only confirmation tracking
      // cannot make progress without foreground wallet work.
      guard migrationPreparationStateNeedsForegroundNotification(
        preparation.state
      ) else { continue }
      postNeedsActionNotification(
        reason: "foreground-preparation-required",
        manifest: manifest,
        progress: preparation
      )
    }
  }

  private func preparationResumeTarget()
    -> BackgroundMigrationPreparationResumeTarget
  {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else {
      // A transient protected-data or Keychain failure is not proof that no
      // preparation exists. Retry instead of silently completing the task.
      return migrationPreparationResumeTarget(
        states: [],
        inspectionFailed: true
      )
    }
    var states: [UInt8] = []
    var inspectionFailed = false
    for manifest in manifests {
      guard let runId = manifest.expectedRunId else { continue }
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
      // An inspection error is not proof that the run is inactive. A later
      // foreground read or read-only background wake may inspect it again.
      if code != 0 {
        inspectionFailed = true
      } else {
        states.append(preparation.state)
      }
    }
    return migrationPreparationResumeTarget(
      states: states,
      inspectionFailed: inspectionFailed
    )
  }

  /// Read-only snapshot of the scheduling breadcrumb, for on-device
  /// diagnosis. `flutter run` cannot attach to a release build on device and
  /// `os_log` is not reachable through `devicectl --console` here, so the
  /// submission outcome has to be readable from Dart to be visible at all.
  func schedulingDiagnostics() -> [String: Any] {
    let defaults = UserDefaults.standard
    var snapshot: [String: Any] = [
      "state": defaults.string(forKey: Self.schedulingStateKey) ?? "none",
      "updatedAt": defaults.double(forKey: Self.schedulingStateUpdatedAtKey),
    ]
    if let error = defaults.string(forKey: Self.schedulingErrorKey) {
      snapshot["error"] = error
    }
    let runtime = stateLock.withPreparationLock {
      (
        scopes: foregroundContinuationScopes.count,
        running: taskRunning,
        inFlight: submissionInFlight,
        quiesced: mutationQuiesced,
        disabled: notificationAuthorization.isDisabled
      )
    }
    snapshot["continuationScopes"] = runtime.scopes
    snapshot["taskRunning"] = runtime.running
    snapshot["submissionInFlight"] = runtime.inFlight
    snapshot["mutationQuiesced"] = runtime.quiesced
    snapshot["notificationsDisabled"] = runtime.disabled
    return snapshot
  }

  /// Append-only companion to the single-slot breadcrumb below.
  ///
  /// `UserDefaults` keeps only the latest value, so any pass that runs after
  /// the one being diagnosed erases it — repeatedly the case here, where a
  /// failure is followed by a `start()` that overwrites the reason. This keeps
  /// the ordered history that actually answers "what did the task do".
  private func appendSchedulingTrace(_ state: String, error: Error?) {
    guard
      let directory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else { return }
    let url = directory.appendingPathComponent(Self.schedulingTraceFileName)
    var line = "{\"at\":\(Date().timeIntervalSince1970),\"state\":\"\(state)\""
    if let error {
      let escaped = String(describing: error)
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: " ")
      line += ",\"error\":\"\(escaped)\""
    }
    line += "}\n"
    guard let payload = line.data(using: .utf8) else { return }
    traceLock.lock()
    defer { traceLock.unlock() }
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      // Bound the file so a long-running wallet cannot grow it without limit.
      if let size = try? handle.seekToEnd(), size > Self.schedulingTraceMaxBytes {
        try? handle.truncate(atOffset: 0)
      }
      try? handle.write(contentsOf: payload)
    } else {
      try? payload.write(to: url, options: .atomic)
    }
  }

  private func recordSchedulingState(_ state: String, error: Error? = nil) {
    appendSchedulingTrace(state, error: error)
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
    guard let scopes = foregroundContinuationEligibleScopes() else {
      return false
    }
    stateLock.withPreparationLock {
      foregroundContinuationScopes = scopes
      persistForegroundContinuationScopesLocked()
    }
    return !scopes.isEmpty
  }

  private func pruneForegroundContinuationScopes() {
    guard let eligibleScopes = foregroundContinuationEligibleScopes() else {
      return
    }
    stateLock.withPreparationLock {
      foregroundContinuationScopes.formIntersection(eligibleScopes)
      persistForegroundContinuationScopesLocked()
    }
  }

  /// Scopes whose run is still waiting for denomination confirmations
  /// (state `0`). These are exactly the runs the continued task can advance
  /// with read-only lightwalletd queries, which makes them different from the
  /// other continuation-eligible states: states `2`, `3`, `5`, and an
  /// unreadable inspection genuinely need the foreground app.
  private func confirmationTrackableScopes() -> Set<String>? {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else { return nil }
    var scopes = Set<String>()
    for manifest in manifests {
      guard let runId = manifest.expectedRunId else { continue }
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
      // An unreadable run is deliberately not trackable: it keeps whatever
      // continuation was recorded for it rather than being released here.
      guard code == 0, preparation.state == 0 else { continue }
      scopes.insert(
        Self.foregroundContinuationScope(
          network: manifest.network,
          accountUuid: manifest.accountUuid,
          runId: runId
        )
      )
    }
    return scopes
  }

  /// Whether a recorded foreground continuation should stop a new submission.
  ///
  /// Deliberately non-destructive. Clearing the scope here would submit the
  /// task but also swallow the "come back to the app" signal: the migration
  /// status screen reads that same scope through `runtimeState` to decide
  /// whether to run its foreground `retry()`, and `startPreparation` can reach
  /// this code before the screen ever reads it. So a run that is merely
  /// waiting for confirmations stops blocking submission while its scope stays
  /// recorded, and only the screen's explicit acknowledgement removes it.
  ///
  /// Account-scoped by construction: only the `network:account:run` keys that
  /// inspect as state `0` right now are treated as non-blocking. States `2`,
  /// `3`, `5`, and unreadable runs keep blocking, because those genuinely need
  /// the foreground app rather than a read-only query pass.
  private func pendingTrackableScopes() -> Set<String> {
    let trackable = confirmationTrackableScopes() ?? []
    return stateLock.withPreparationLock {
      migrationPreparationPendingTrackableScopes(
        continuationScopes: foregroundContinuationScopes,
        confirmationTrackableScopes: trackable
      )
    }
  }

  private func foregroundContinuationEligibleScopes() -> Set<String>? {
    guard let manifests = IronwoodMigrationBackgroundCredentialStore.loadAll()
    else { return nil }
    var scopes = Set<String>()
    for manifest in manifests {
      guard let runId = manifest.expectedRunId else { continue }
      let scope = Self.foregroundContinuationScope(
        network: manifest.network,
        accountUuid: manifest.accountUuid,
        runId: runId
      )
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
      if code != 0
        || migrationPreparationStateNeedsForegroundContinuation(
          preparation.state
        )
      {
        scopes.insert(scope)
      }
    }
    return scopes
  }

  private func persistForegroundContinuationScopesLocked() {
    UserDefaults.standard.set(
      foregroundContinuationScopes.sorted(),
      forKey: Self.foregroundContinuationScopesKey
    )
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
    let scope: String
    if let manifest, let manifestScope = Self.preparationScope(for: manifest) {
      scope = manifestScope
    } else {
      scope = "global"
    }
    let stateSuffix = progress.map { ":state-\($0.state)" } ?? ""
    notificationCoordinator.enqueue(
      MigrationPreparationNotificationEvent(
        scope: scope,
        kind: .needsForegroundRecovery,
        fingerprint: "\(reason)\(stateSuffix)"
      )
    )
  }

  private func clearNeedsActionNotification(scope: String) {
    notificationCoordinator.resolve(scope: scope)
  }

  private func resetNeedsActionNotifications() {
    notificationCoordinator.clearAll()
  }

  private func addNotificationIfEnabled(
    _ request: UNNotificationRequest,
    completion: ((Bool) -> Void)? = nil
  ) {
    guard !stateLock.withPreparationLock({
      notificationAuthorization.isDisabled
    }) else {
      completion?(false)
      return
    }
    let center = UNUserNotificationCenter.current()
    center.add(request) { error in
      let disabled = self.stateLock.withPreparationLock {
        self.notificationAuthorization.isDisabled
      }
      if disabled {
        center.removePendingNotificationRequests(
          withIdentifiers: [request.identifier]
        )
        center.removeDeliveredNotifications(
          withIdentifiers: [request.identifier]
        )
      }
      completion?(error == nil && !disabled)
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

}

extension NSLock {
  fileprivate func withPreparationLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
