import Flutter
import Security
import UIKit
import UserNotifications
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testMigrationNotificationAuthorizationStatusIsFailClosed() {
    XCTAssertEqual(
      IronwoodMigrationNotificationAuthorizationStatus(.notDetermined),
      .notDetermined
    )
    XCTAssertEqual(
      IronwoodMigrationNotificationAuthorizationStatus(.denied),
      .denied
    )
    XCTAssertEqual(
      IronwoodMigrationNotificationAuthorizationStatus(.authorized),
      .authorized
    )
    XCTAssertEqual(
      IronwoodMigrationNotificationAuthorizationStatus(.provisional),
      .authorized
    )
    XCTAssertEqual(
      IronwoodMigrationNotificationAuthorizationStatus(.ephemeral),
      .authorized
    )
    XCTAssertFalse(
      IronwoodMigrationNotificationAuthorizationStatus.denied
        .allowsBackgroundMigration
    )
    XCTAssertTrue(
      IronwoodMigrationNotificationAuthorizationStatus.authorized
        .allowsBackgroundMigration
    )
  }

  func testMigrationAuthorizationMonitorStopsDeniedEntryBeforeWork() {
    let denied = expectation(description: "denied entry stops background work")
    var checks = 0
    let monitor = IronwoodMigrationNotificationAuthorizationMonitor(
      pollInterval: 0.01,
      queue: DispatchQueue(label: "test.ironwood.authorization.denied"),
      statusProvider: { completion in
        checks += 1
        completion(.denied)
      }
    )

    monitor.start {
      denied.fulfill()
    }

    wait(for: [denied], timeout: 1)
    monitor.cancel()
    XCTAssertEqual(checks, 1)
  }

  func testMigrationAuthorizationMonitorStopsWorkAfterMidRunRevoke() {
    let revoked = expectation(description: "mid-run revoke stops background work")
    var checks = 0
    let monitor = IronwoodMigrationNotificationAuthorizationMonitor(
      pollInterval: 0.01,
      queue: DispatchQueue(label: "test.ironwood.authorization.revoke"),
      statusProvider: { completion in
        checks += 1
        completion(checks == 1 ? .authorized : .denied)
      }
    )

    monitor.start {
      revoked.fulfill()
    }

    wait(for: [revoked], timeout: 1)
    monitor.cancel()
    XCTAssertGreaterThanOrEqual(checks, 2)
  }

  func testMigrationAuthorizationEpochRejectsHeldAuthorizedCallbackAfterDisable() {
    var authorization = IronwoodMigrationNotificationAuthorizationEpochState()
    let heldEpoch = authorization.generation
    var heldCallbackWasAccepted: Bool?
    let heldAuthorizedCallback = {
      (status: IronwoodMigrationNotificationAuthorizationStatus) in
      guard status.allowsBackgroundMigration else { return }
      heldCallbackWasAccepted = authorization.authorize(
        ifCurrent: heldEpoch
      )
    }

    authorization.disable()
    heldAuthorizedCallback(.authorized)

    XCTAssertEqual(heldCallbackWasAccepted, false)
    XCTAssertTrue(authorization.isDisabled)
  }

  func testMigrationAuthorizationEpochsAreIndependentPerManager() {
    var outboxAuthorization =
      IronwoodMigrationNotificationAuthorizationEpochState()
    var preparationAuthorization =
      IronwoodMigrationNotificationAuthorizationEpochState()
    let outboxEpoch = outboxAuthorization.generation
    let preparationEpoch = preparationAuthorization.generation

    outboxAuthorization.disable()

    XCTAssertFalse(
      outboxAuthorization.authorize(ifCurrent: outboxEpoch)
    )
    XCTAssertTrue(
      preparationAuthorization.authorize(ifCurrent: preparationEpoch)
    )
    XCTAssertTrue(outboxAuthorization.isDisabled)
    XCTAssertFalse(preparationAuthorization.isDisabled)
  }

  func testMigrationOutboxRevocationFinishesWithoutNotificationOrReregistration() {
    let disposition =
      IronwoodMigrationOutboxWakeDisposition.finishForegroundOnly

    XCTAssertFalse(disposition.shouldDeliverNotifications)
    XCTAssertFalse(disposition.shouldReschedule)
    XCTAssertTrue(disposition.taskCompletionIsSuccessful)
  }

  func testMigrationOutboxArmSchedulePolicySupportsForegroundOnlyMode() {
    XCTAssertTrue(
      IronwoodMigrationOutboxArmSchedulePolicy.reportsSuccess(
        authorization: .denied,
        submitted: false
      )
    )
    XCTAssertTrue(
      IronwoodMigrationOutboxArmSchedulePolicy.reportsSuccess(
        authorization: .notDetermined,
        submitted: false
      )
    )
  }

  func testMigrationOutboxArmSchedulePolicySurfacesAuthorizedSubmitFailure() {
    XCTAssertFalse(
      IronwoodMigrationOutboxArmSchedulePolicy.reportsSuccess(
        authorization: .authorized,
        submitted: false
      )
    )
    XCTAssertTrue(
      IronwoodMigrationOutboxArmSchedulePolicy.reportsSuccess(
        authorization: .authorized,
        submitted: true
      )
    )
  }

  func testMigrationPreparationRuntimeStateIsScopedToMatchingRun() {
    XCTAssertEqual(
      migrationPreparationRuntimeState(
        hasMatchingManifest: false,
        notificationsDisabled: false,
        submissionInFlight: false,
        taskRunning: true,
        deferredPassRunning: false,
        foregroundHandoffRequested: false,
        foregroundContinuationPending: false,
        pendingRequest: false
      ),
      .idle
    )
  }

  func testMigrationPreparationRuntimeStateIsFailClosedWhenDisabled() {
    XCTAssertEqual(
      migrationPreparationRuntimeState(
        hasMatchingManifest: true,
        notificationsDisabled: true,
        submissionInFlight: false,
        taskRunning: true,
        deferredPassRunning: false,
        foregroundHandoffRequested: false,
        foregroundContinuationPending: true,
        pendingRequest: true
      ),
      .disabled
    )
  }

  func testMigrationPreparationRuntimeStateTracksAutomaticWork() {
    XCTAssertEqual(
      migrationPreparationRuntimeState(
        hasMatchingManifest: true,
        notificationsDisabled: false,
        submissionInFlight: false,
        taskRunning: false,
        deferredPassRunning: false,
        foregroundHandoffRequested: false,
        foregroundContinuationPending: false,
        pendingRequest: true
      ),
      .scheduled
    )
    XCTAssertEqual(
      migrationPreparationRuntimeState(
        hasMatchingManifest: true,
        notificationsDisabled: false,
        submissionInFlight: false,
        taskRunning: false,
        deferredPassRunning: true,
        foregroundHandoffRequested: false,
        foregroundContinuationPending: false,
        pendingRequest: false
      ),
      .running
    )
    XCTAssertEqual(
      migrationPreparationRuntimeState(
        hasMatchingManifest: true,
        notificationsDisabled: false,
        submissionInFlight: false,
        taskRunning: true,
        deferredPassRunning: false,
        foregroundHandoffRequested: true,
        foregroundContinuationPending: false,
        pendingRequest: false
      ),
      .handoffRequested
    )
  }

  func testMigrationPreparationRuntimeStatePrioritizesForegroundContinuation() {
    XCTAssertEqual(
      migrationPreparationRuntimeState(
        hasMatchingManifest: true,
        notificationsDisabled: false,
        submissionInFlight: false,
        taskRunning: false,
        deferredPassRunning: false,
        foregroundHandoffRequested: false,
        foregroundContinuationPending: true,
        pendingRequest: false
      ),
      .foregroundContinuationPending
    )
  }

  func testMigrationPreparationForegroundLaunchHandsPendingWorkToForeground() {
    XCTAssertTrue(
      shouldMarkMigrationPreparationForegroundContinuation(
        hasPendingRequest: true,
        hasBoundPreparation: true,
        notificationsDisabled: false
      )
    )
  }

  func testMigrationPreparationForegroundLaunchDoesNotInventContinuation() {
    XCTAssertFalse(
      shouldMarkMigrationPreparationForegroundContinuation(
        hasPendingRequest: false,
        hasBoundPreparation: true,
        notificationsDisabled: false
      )
    )
    XCTAssertFalse(
      shouldMarkMigrationPreparationForegroundContinuation(
        hasPendingRequest: true,
        hasBoundPreparation: false,
        notificationsDisabled: false
      )
    )
    XCTAssertFalse(
      shouldMarkMigrationPreparationForegroundContinuation(
        hasPendingRequest: true,
        hasBoundPreparation: true,
        notificationsDisabled: true
      )
    )
  }

  func testMigrationPreparationForegroundLaunchRedirectsChainWaits() {
    XCTAssertTrue(
      shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
        hasPendingRequest: true,
        hasBoundPreparation: false,
        notificationsDisabled: false,
        resumeTarget: .backgroundProcessing
      )
    )
    XCTAssertFalse(
      shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
        hasPendingRequest: false,
        hasBoundPreparation: false,
        notificationsDisabled: false,
        resumeTarget: .backgroundProcessing
      )
    )
    XCTAssertFalse(
      shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
        hasPendingRequest: true,
        hasBoundPreparation: false,
        notificationsDisabled: true,
        resumeTarget: .backgroundProcessing
      )
    )
    XCTAssertFalse(
      shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
        hasPendingRequest: true,
        hasBoundPreparation: true,
        notificationsDisabled: false,
        resumeTarget: .backgroundProcessing
      )
    )
    XCTAssertFalse(
      shouldHandoffMigrationPreparationToBackgroundOnForegroundLaunch(
        hasPendingRequest: true,
        hasBoundPreparation: false,
        notificationsDisabled: false,
        resumeTarget: .continuedProcessing
      )
    )
  }

  func testMigrationPreparationDefersChainWaitsToProcessingTask() {
    XCTAssertEqual(
      migrationPreparationPassResult(states: [0]),
      .waitingForConfirmations
    )
    XCTAssertEqual(
      migrationPreparationPassResult(states: [5]),
      .deferred(BackgroundMigrationOutboxCadence.rollingCheckInterval)
    )
    XCTAssertEqual(
      migrationPreparationPassResult(states: [5, 0]),
      .waitingForConfirmations
    )
  }

  func testMigrationPreparationResumesOnlyConfirmationWorkAsContinuedTask() {
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [0],
        inspectionFailed: false
      ),
      .continuedProcessing
    )
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [5],
        inspectionFailed: false
      ),
      .backgroundProcessing
    )
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [5, 0],
        inspectionFailed: false
      ),
      .continuedProcessing
    )
  }

  func testMigrationPreparationForegroundContinuationOnlyTracksConfirmationWork() {
    XCTAssertTrue(
      migrationPreparationStateNeedsForegroundContinuation(0)
    )
    for state in UInt8(1)...UInt8(5) {
      XCTAssertFalse(
        migrationPreparationStateNeedsForegroundContinuation(state)
      )
    }
  }

  func testMigrationPreparationContinuedTaskOnlyRunsConfirmationWork() {
    XCTAssertEqual(
      migrationPreparationContinuedTaskDisposition(.continuedProcessing),
      .run
    )
    XCTAssertEqual(
      migrationPreparationContinuedTaskDisposition(.backgroundProcessing),
      .handoffToBackground
    )
    XCTAssertEqual(
      migrationPreparationContinuedTaskDisposition(.idle),
      .complete
    )
    XCTAssertEqual(
      migrationPreparationContinuedTaskDisposition(.terminal),
      .complete
    )
  }

  func testMigrationPreparationRetriesInspectionFailuresInBackground() {
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [],
        inspectionFailed: true
      ),
      .backgroundProcessing
    )
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [1, 4],
        inspectionFailed: false
      ),
      .idle
    )
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [4],
        inspectionFailed: false
      ),
      .terminal
    )
  }

  func testMigrationPreparationCompletesOnlyTerminalBackgroundStates() {
    XCTAssertEqual(
      migrationPreparationPassResult(states: []),
      .completed
    )
    XCTAssertEqual(
      migrationPreparationPassResult(states: [1, 4]),
      .completed
    )
    XCTAssertEqual(
      migrationPreparationPassResult(states: [2]),
      .needsAction
    )
    XCTAssertEqual(
      migrationPreparationPassResult(states: [3]),
      .needsAction
    )
  }

  func testMigrationPreparationNeedsActionCompletesBackgroundWake() {
    XCTAssertTrue(
      migrationPreparationPassNeedsForegroundAction(.needsAction)
    )
    XCTAssertTrue(
      migrationPreparationBackgroundWakeSucceeded(.needsAction)
    )
    XCTAssertFalse(
      migrationPreparationBackgroundWakeSucceeded(.cancelled)
    )
  }

  func testUnexpectedPreparationCancellationNeedsForegroundAction() {
    XCTAssertEqual(
      migrationPreparationCancellationResult(
        taskExpired: false,
        foregroundHandoffRequested: false,
        mutationQuiesced: false,
        notificationsDisabled: false
      ),
      .needsAction
    )
    XCTAssertEqual(
      migrationPreparationCancellationResult(
        taskExpired: false,
        foregroundHandoffRequested: true,
        mutationQuiesced: false,
        notificationsDisabled: false
      ),
      .cancelled
    )
    XCTAssertEqual(
      migrationPreparationCancellationResult(
        taskExpired: true,
        foregroundHandoffRequested: false,
        mutationQuiesced: false,
        notificationsDisabled: false
      ),
      .cancelled
    )
  }

  func testExpiredPreparationRecoversInBackgroundWithoutNeedsAction() {
    XCTAssertTrue(
      migrationPreparationExpirationRequiresBackgroundRecovery(
        taskExpired: true,
        resumeTarget: .continuedProcessing
      )
    )
    XCTAssertTrue(
      migrationPreparationExpirationRequiresBackgroundRecovery(
        taskExpired: true,
        resumeTarget: .backgroundProcessing
      )
    )
    XCTAssertFalse(
      migrationPreparationExpirationRequiresBackgroundRecovery(
        taskExpired: true,
        resumeTarget: .terminal
      )
    )
    XCTAssertFalse(
      migrationPreparationExpirationRequiresBackgroundRecovery(
        taskExpired: true,
        resumeTarget: .idle
      )
    )
    XCTAssertFalse(
      migrationPreparationExpirationRequiresBackgroundRecovery(
        taskExpired: false,
        resumeTarget: .continuedProcessing
      )
    )
    XCTAssertTrue(
      migrationPreparationExpirationRequiresForegroundContinuation(
        taskExpired: true,
        resumeTarget: .idle
      )
    )
    XCTAssertFalse(
      migrationPreparationExpirationRequiresForegroundContinuation(
        taskExpired: true,
        resumeTarget: .continuedProcessing
      )
    )
    XCTAssertFalse(
      migrationPreparationExpirationRequiresForegroundContinuation(
        taskExpired: true,
        resumeTarget: .terminal
      )
    )
    XCTAssertFalse(
      migrationPreparationPassNeedsForegroundAction(.cancelled)
    )
  }

  func testFailedPreparationHandoffRequiresForegroundAction() {
    XCTAssertEqual(
      migrationPreparationPassResultAfterHandoff(
        .deferred(60),
        handoffScheduled: false,
        interruptionRequested: false
      ),
      .needsAction
    )
    XCTAssertEqual(
      migrationPreparationPassResultAfterHandoff(
        .deferred(60),
        handoffScheduled: true,
        interruptionRequested: false
      ),
      .deferred(60)
    )
    XCTAssertEqual(
      migrationPreparationPassResultAfterHandoff(
        .deferred(60),
        handoffScheduled: false,
        interruptionRequested: true
      ),
      .cancelled
    )
    XCTAssertEqual(
      migrationPreparationPassResultAfterHandoff(
        .completed,
        handoffScheduled: false,
        interruptionRequested: false
      ),
      .completed
    )
  }

  func testGlobalPreparationFailureUsesSingleNotificationScope() {
    XCTAssertEqual(
      migrationPreparationNeedsActionNotificationScope(
        manifestScope: nil
      ),
      "global"
    )
    XCTAssertEqual(
      migrationPreparationNeedsActionNotificationScope(
        manifestScope: "main:account-1:run-1"
      ),
      "main:account-1:run-1"
    )
  }

  func testTerminalPreparationCancellationCompletesExpiredTask() {
    XCTAssertTrue(
      migrationPreparationPassCompleted(
        .cancelled,
        terminalAfterExpiration: true
      )
    )
    XCTAssertFalse(
      migrationPreparationPassCompleted(
        .cancelled,
        terminalAfterExpiration: false
      )
    )
  }

  func testMigrationPreparationNeedsActionNotificationDeduplicatesFingerprint() {
    XCTAssertTrue(
      shouldPostMigrationPreparationNeedsActionNotification(
        previousFingerprint: nil,
        fingerprint: "main:account-1:run-1:sign:0"
      )
    )
    XCTAssertFalse(
      shouldPostMigrationPreparationNeedsActionNotification(
        previousFingerprint: "main:account-1:run-1:sign:0",
        fingerprint: "main:account-1:run-1:sign:0"
      )
    )
    XCTAssertTrue(
      shouldPostMigrationPreparationNeedsActionNotification(
        previousFingerprint: "main:account-1:run-1:sign:0",
        fingerprint: "main:account-1:run-1:sign:1"
      )
    )
  }

  func testMigrationPreparationNeedsActionFingerprintCommitsOnlyAfterAcceptedSubmission() {
    XCTAssertNil(
      migrationPreparationNeedsActionFingerprintAfterSubmission(
        previousFingerprint: nil,
        fingerprint: "main:account-1:run-1:foreground",
        submissionAccepted: false
      )
    )
    XCTAssertEqual(
      migrationPreparationNeedsActionFingerprintAfterSubmission(
        previousFingerprint: nil,
        fingerprint: "main:account-1:run-1:foreground",
        submissionAccepted: true
      ),
      "main:account-1:run-1:foreground"
    )
  }

  func testMigrationPreparationNeedsActionResetInvalidatesAnInFlightSubmission() throws {
    var tracker = MigrationPreparationNeedsActionSubmissionTracker()
    let token = try XCTUnwrap(
      tracker.begin(
        scope: "main:account-1:run-1",
        fingerprint: "main:account-1:run-1:foreground"
      )
    )

    XCTAssertEqual(tracker.scopes, ["main:account-1:run-1"])
    tracker.reset()
    XCTAssertEqual(
      tracker.complete(
        scope: "main:account-1:run-1",
        token: token
      ),
      .invalidated
    )
  }

  func testMigrationPreparationNeedsActionKeepsANewerSubmissionCurrent() throws {
    var tracker = MigrationPreparationNeedsActionSubmissionTracker()
    let firstToken = try XCTUnwrap(
      tracker.begin(scope: "global", fingerprint: "global:first")
    )
    let secondToken = try XCTUnwrap(
      tracker.begin(scope: "global", fingerprint: "global:second")
    )

    XCTAssertEqual(
      tracker.complete(scope: "global", token: firstToken),
      .superseded
    )
    XCTAssertEqual(
      tracker.complete(scope: "global", token: secondToken),
      .current
    )
  }

  func testFreshInstallCleanerMarksInstallWhenNoWalletKeychainExists() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .missing

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

  func testFreshInstallCleanerPreservesExistingInstallWhenWalletDbStillExists() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .found("zcash_wallet_existing.db")
    harness.walletDbExists = true

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

  func testFreshInstallCleanerClearsStaleKeychainWhenWalletDbIsGone() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerDefersSentinelWhenKeychainReadFails() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .failed(errSecInteractionNotAllowed)

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertFalse(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

  func testFreshInstallCleanerDefersSentinelWhenWalletDbNameIsInvalid() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .invalid

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertFalse(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

  func testFreshInstallCleanerDefersOnlyWhenSecureStoreDeleteFails() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false
    harness.deleteStatuses = [
      FreshInstallKeychainCleaner.servicesToClear[0]: errSecSuccess,
      FreshInstallKeychainCleaner.servicesToClear.last!: errSecAuthFailed,
    ]

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertFalse(harness.markedInstalled)
    XCTAssertTrue(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerCompletesWhenOnlyNonAnchorDeleteFails() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false
    harness.deleteStatuses = [
      FreshInstallKeychainCleaner.servicesToClear[0]: errSecAuthFailed
    ]

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerClearsPendingWhenNoWalletKeychainExists() {
    let harness = FreshInstallCleanerHarness()
    harness.cleanupPending = true
    harness.lookup = .missing

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

  func testFreshInstallCleanerClearsPendingWhenCurrentWalletDbStillExists() {
    let harness = FreshInstallCleanerHarness()
    harness.cleanupPending = true
    harness.lookup = .found("zcash_wallet_existing.db")
    harness.walletDbExists = true

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

  func testFreshInstallCleanerRetriesPendingCleanupWhenWalletDbIsGone() {
    let harness = FreshInstallCleanerHarness()
    harness.cleanupPending = true
    harness.lookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerKeepsPendingWhenSecureStoreDeleteFails() {
    let harness = FreshInstallCleanerHarness()
    harness.cleanupPending = true
    harness.lookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false
    harness.deleteStatuses = [
      FreshInstallKeychainCleaner.servicesToClear.last!: errSecAuthFailed
    ]

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertFalse(harness.markedInstalled)
    XCTAssertTrue(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerDoesNothingWhenSentinelAlreadyExists() {
    let harness = FreshInstallCleanerHarness()
    harness.hasSentinel = true
    harness.cleanupPending = true
    harness.lookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertFalse(harness.markedInstalled)
    XCTAssertTrue(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
  }

}

final class NativeLightwalletdClientTests: XCTestCase {
  func testNativeLightwalletdParserReadsHeightAfterUnknownField() throws {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x06,
      0x12, 0x01, 0xAA,
      0x08, 0xAC, 0x02,
    ])

    XCTAssertEqual(
      try NativeLightwalletdClient.parseLatestBlockResponse(response),
      300
    )
  }

  func testNativeLightwalletdParserRejectsTruncatedFrame() {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x06,
      0x08, 0xAC,
    ])

    XCTAssertThrowsError(
      try NativeLightwalletdClient.parseLatestBlockResponse(response)
    ) { error in
      XCTAssertEqual(error as? NativeLightwalletdError, .malformedResponse)
    }
  }

  func testNativeLightwalletdParserReadsRejectedSendResponse() throws {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x15,
      0x08, 0xEA, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01,
      0x12, 0x08, 0x69, 0x6F, 0x20, 0x65, 0x72, 0x72, 0x6F, 0x72,
    ])

    XCTAssertEqual(
      try NativeLightwalletdClient.parseSendTransactionResponse(response),
      NativeLightwalletdSendResponse(
        errorCode: -22,
        errorMessage: "io error"
      )
    )
  }

  func testNativeLightwalletdParserTreatsOmittedZeroCodeAsSuccess() throws {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x00,
    ])

    XCTAssertEqual(
      try NativeLightwalletdClient.parseSendTransactionResponse(response),
      NativeLightwalletdSendResponse(errorCode: 0, errorMessage: "")
    )
  }
}

private final class FreshInstallCleanerHarness {
  var hasSentinel = false
  var markedInstalled = false
  var cleanupPending = false
  var lookup: KeychainDbNameLookup = .missing
  var walletDbExists = false
  var deleteStatuses: [String: OSStatus] = [:]
  var deletedServices: [String] = []
  var logs: [String] = []

  func dependencies() -> FreshInstallKeychainCleaner.Dependencies {
    FreshInstallKeychainCleaner.Dependencies(
      hasInstallSentinel: {
        self.hasSentinel
      },
      markInstallSentinel: {
        self.markedInstalled = true
        self.hasSentinel = true
      },
      hasCleanupPending: {
        self.cleanupPending
      },
      markCleanupPending: {
        self.cleanupPending = true
      },
      clearCleanupPending: {
        self.cleanupPending = false
      },
      readWalletDbName: {
        self.lookup
      },
      walletDbExists: { _ in
        self.walletDbExists
      },
      deleteKeychainService: { service in
        self.deletedServices.append(service)
        return self.deleteStatuses[service] ?? errSecSuccess
      },
      log: { message in
        self.logs.append(message)
      }
    )
  }
}
