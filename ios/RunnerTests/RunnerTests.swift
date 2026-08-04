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

  func testPendingPreparationRequestIsNotClaimedWhileBackgroundCanTrack() {
    // Regression: the status screen polls `runtimeState` while the app is
    // still in the foreground. Claiming the request it just submitted
    // cancelled the continued task before the system started it, so the
    // Dynamic Island activity never appeared and no confirmation was tracked.
    XCTAssertFalse(
      shouldClaimPendingMigrationPreparationRequest(
        hasPendingRequest: true,
        canTrackInBackground: true,
        taskRunning: false,
        deferredPassRunning: false,
        mutationQuiesced: false,
        notificationsDisabled: false
      )
    )
  }

  func testPendingPreparationRequestIsClaimedWhenBackgroundCannotTrack() {
    // State 5 and needs-action runs cannot progress from a read-only query
    // pass, so handing the pending request to the foreground is still right.
    XCTAssertTrue(
      shouldClaimPendingMigrationPreparationRequest(
        hasPendingRequest: true,
        canTrackInBackground: false,
        taskRunning: false,
        deferredPassRunning: false,
        mutationQuiesced: false,
        notificationsDisabled: false
      )
    )
  }

  func testForegroundContinuationClaimsTrackablePendingRequest() {
    XCTAssertTrue(
      shouldClaimPendingMigrationPreparationRequest(
        hasPendingRequest: true,
        canTrackInBackground: true,
        foregroundContinuationPending: true,
        taskRunning: false,
        deferredPassRunning: false,
        mutationQuiesced: false,
        notificationsDisabled: false
      )
    )
  }

  func testUnacknowledgedConfirmationRunArmsTheTrackingTask() {
    let scope = "test:account-a:run-1"
    XCTAssertEqual(
      migrationPreparationPendingTrackableScopes(
        continuationScopes: [],
        confirmationTrackableScopes: [scope]
      ),
      [scope]
    )
  }

  func testAcknowledgedConfirmationRunDoesNotRearmTheTrackingTask() {
    // Once tracking has completed and marked its continuation ready, the run
    // must stop arming the task or it would re-observe the same confirmed
    // transactions and re-post the same notification until the foreground
    // reconciles the DB.
    let scope = "test:account-a:run-1"
    XCTAssertTrue(
      migrationPreparationPendingTrackableScopes(
        continuationScopes: [scope],
        confirmationTrackableScopes: [scope]
      ).isEmpty
    )
  }

  func testForegroundOnlyAccountDoesNotVetoAnotherAccountsTracking() {
    // Observed on device: account 4ddd0343 sat in state 5 with a recorded
    // continuation while account 660176b0 was waiting for its preparation
    // confirmations. The old predicate let the state-5 scope block submission
    // app-wide, so `blocked_foreground_continuation` was recorded and the
    // continued task stopped registering entirely.
    let foregroundOnly = "test:account-4ddd:run-4ddd"
    let waitingForConfirmations = "test:account-6601:run-6601"
    XCTAssertEqual(
      migrationPreparationPendingTrackableScopes(
        continuationScopes: [foregroundOnly],
        confirmationTrackableScopes: [waitingForConfirmations]
      ),
      [waitingForConfirmations]
    )
  }

  func testPendingTrackableScopesAreAccountScoped() {
    // Acknowledging one account must not silence another account's tracking.
    let acknowledged = "test:account-a:run-1"
    let stillPending = "test:account-b:run-2"
    XCTAssertEqual(
      migrationPreparationPendingTrackableScopes(
        continuationScopes: [acknowledged],
        confirmationTrackableScopes: [acknowledged, stillPending]
      ),
      [stillPending]
    )
  }

  func testFailedNotificationSubmissionDoesNotRecordContinuationScope() {
    let existing = "test:account-existing:run-0"
    let newlyReady = "test:account-a:run-1"

    XCTAssertEqual(
      migrationPreparationContinuationScopesAfterNotificationSubmission(
        existingScopes: [existing],
        continuationReadyScopes: [newlyReady],
        notificationSubmissionRequired: true,
        notificationSubmitted: false
      ),
      [existing]
    )
  }

  func testSuccessfulNotificationSubmissionRecordsContinuationScope() {
    let existing = "test:account-existing:run-0"
    let newlyReady = "test:account-a:run-1"

    XCTAssertEqual(
      migrationPreparationContinuationScopesAfterNotificationSubmission(
        existingScopes: [existing],
        continuationReadyScopes: [newlyReady],
        notificationSubmissionRequired: true,
        notificationSubmitted: true
      ),
      [existing, newlyReady]
    )
  }

  func testFailedTrackingTaskAttemptsToRearm() {
    XCTAssertTrue(
      migrationPreparationTrackingShouldAttemptRearm(
        completionFailed: true,
        quiesced: false,
        expired: false,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testExpiredMidWaveTrackingRearmsInsteadOfStopping() {
    // Expiration only interrupts one execution opportunity. The wave still has
    // confirmations left to observe, so the manager submits a replacement.
    XCTAssertTrue(
      migrationPreparationTrackingShouldAttemptRearm(
        completionFailed: false,
        quiesced: false,
        expired: true,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testExpiredTrackingDoesNotRearmAfterHandoffOrRevocation() {
    XCTAssertFalse(
      migrationPreparationTrackingShouldAttemptRearm(
        completionFailed: false,
        quiesced: false,
        expired: true,
        handedOff: true,
        notificationsDisabled: false
      )
    )
    XCTAssertFalse(
      migrationPreparationTrackingShouldAttemptRearm(
        completionFailed: false,
        quiesced: false,
        expired: true,
        handedOff: false,
        notificationsDisabled: true
      )
    )
    XCTAssertFalse(
      migrationPreparationTrackingShouldAttemptRearm(
        completionFailed: false,
        quiesced: true,
        expired: true,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testConfirmedWaveSuccessDoesNotRearmTracking() {
    // Nothing is left for a read-only task to watch. The foreground app arms
    // the next wave's task after it syncs and advances the run.
    XCTAssertFalse(
      migrationPreparationTrackingShouldAttemptRearm(
        completionFailed: false,
        quiesced: false,
        expired: false,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testHandoffDoesNotParkAnUnconfirmedTrackableRun() {
    // Observed shape: accounts A and B share one task. A's wave confirms and
    // is recorded, the user opens the app, and B is still counting. Parking B
    // as handed-off stops every re-arm for it, so it only resumes when the
    // user switches to B and opens its migration screen.
    let confirmedA = "test:account-a:run-1"
    let stillCountingB = "test:account-b:run-2"

    XCTAssertEqual(
      migrationPreparationHandoffContinuationScopes(
        existingScopes: [confirmedA],
        eligibleScopes: [confirmedA, stillCountingB],
        confirmationTrackableScopes: [stillCountingB]
      ),
      [confirmedA]
    )
  }

  func testHandoffKeepsAlreadyRecordedConfirmedScopes() {
    // `applyTrackingBatch` records a confirmed wave as soon as its
    // notification is submitted. A handoff must not drop that.
    let confirmed = "test:account-a:run-1"

    XCTAssertEqual(
      migrationPreparationHandoffContinuationScopes(
        existingScopes: [confirmed],
        eligibleScopes: [],
        confirmationTrackableScopes: []
      ),
      [confirmed]
    )
  }

  func testHandoffRecordsRunsThatGenuinelyNeedTheForeground() {
    // States 2, 3, 5 and unreadable inspections are eligible but not
    // confirmation-trackable: no read-only query pass can advance them.
    let needsForeground = "test:account-c:run-3"

    XCTAssertEqual(
      migrationPreparationHandoffContinuationScopes(
        existingScopes: [],
        eligibleScopes: [needsForeground],
        confirmationTrackableScopes: []
      ),
      [needsForeground]
    )
  }

  func testClaimingAPendingRequestKeepsOtherAccountsTrackable() {
    // The runtime-state claim branch: account A's wave confirmed and was
    // recorded, so opening A's migration screen claims and cancels the pending
    // request. A's run row still reads state `0` until the foreground
    // advances it, so A is *both* recorded and trackable here — and account B
    // is mid-wave. A must survive, B must not be parked, or B is left with no
    // task, no queued request, and a continuation only its own screen clears.
    let confirmedA = "test:account-a:run-1"
    let stillCountingB = "test:account-b:run-2"

    XCTAssertEqual(
      migrationPreparationHandoffContinuationScopes(
        existingScopes: [confirmedA],
        eligibleScopes: [confirmedA, stillCountingB],
        confirmationTrackableScopes: [confirmedA, stillCountingB]
      ),
      [confirmedA]
    )
  }

  func testTrackableOnlyLaunchIsBoundButRecordsNothing() {
    // The regression this guards: a wallet whose only run is a healthy
    // mid-wave state `0` account records nothing, because the read-only task
    // can still finish it. If the "bound preparation" boolean were derived
    // from that empty recorded set it would go false, `shouldContinue` would
    // go false, and the pending request would be cancelled on every cold
    // launch. Its resume target is `.continuedProcessing`, so the
    // background-redirect branch would not rescue it either.
    let stillCounting = "test:account-a:run-1"

    XCTAssertTrue(
      migrationPreparationHandoffHasBoundPreparation(
        eligibleScopes: [stillCounting]
      )
    )
    XCTAssertTrue(
      migrationPreparationHandoffContinuationScopes(
        existingScopes: [],
        eligibleScopes: [stillCounting],
        confirmationTrackableScopes: [stillCounting]
      ).isEmpty
    )
  }

  func testLaunchWithNoEligibleRunIsNotBound() {
    XCTAssertFalse(
      migrationPreparationHandoffHasBoundPreparation(eligibleScopes: [])
    )
  }

  func testTaskCompletionLatchFiresExactlyOnce() {
    // The re-arm path races a submission callback against a timeout fallback.
    // `setTaskCompleted` twice is undefined behavior, so exactly one wins.
    let latch = MigrationPreparationCompletionLatch()

    XCTAssertTrue(latch.claim())
    XCTAssertFalse(latch.claim())
    XCTAssertFalse(latch.claim())
  }

  func testTaskCompletionLatchIsClaimedOnceUnderConcurrency() {
    let latch = MigrationPreparationCompletionLatch()
    let claims = NSCounter()
    let group = DispatchGroup()

    for _ in 0..<64 {
      DispatchQueue.global().async(group: group) {
        if latch.claim() { claims.increment() }
      }
    }
    group.wait()

    XCTAssertEqual(claims.value, 1)
  }

  func testForegroundPausesConfirmationQueriesAfterTheSeedingPass() {
    // Backgrounded: the task owns wave detection, so it always queries.
    XCTAssertTrue(
      migrationPreparationConfirmationQueryMayRun(
        appIsActive: false,
        hasCompletedInitialQuery: false
      )
    )
    XCTAssertTrue(
      migrationPreparationConfirmationQueryMayRun(
        appIsActive: false,
        hasCompletedInitialQuery: true
      )
    )
    // Foreground, nothing observed yet: the seeding pass is exempt so the
    // activity's progress bar shows real counts, not heartbeat creep.
    XCTAssertTrue(
      migrationPreparationConfirmationQueryMayRun(
        appIsActive: true,
        hasCompletedInitialQuery: false
      )
    )
    // Foreground with progress already seeded: the foreground status poll and
    // foreground sync own wave detection, so the task stops querying.
    XCTAssertFalse(
      migrationPreparationConfirmationQueryMayRun(
        appIsActive: true,
        hasCompletedInitialQuery: true
      )
    )
  }

  func testLaunchWithoutATrackableRunDoesNotStartTracking() {
    // The request armed for the previous wave is still queued once that wave
    // confirms. Starting tracking again would re-observe the same
    // transactions and re-post the same notification on every wake.
    XCTAssertFalse(
      migrationPreparationShouldTrackOnLaunch(
        disposition: .trackConfirmations,
        pendingTrackableScopes: [],
        recordedContinuationScopes: ["test:account-a:run-1"]
      )
    )
    XCTAssertTrue(
      migrationPreparationShouldTrackOnLaunch(
        disposition: .trackConfirmations,
        pendingTrackableScopes: ["test:account-a:run-1"],
        recordedContinuationScopes: []
      )
    )
    XCTAssertFalse(
      migrationPreparationShouldTrackOnLaunch(
        disposition: .foregroundOnly,
        pendingTrackableScopes: ["test:account-a:run-1"],
        recordedContinuationScopes: []
      )
    )
    XCTAssertFalse(
      migrationPreparationShouldTrackOnLaunch(
        disposition: .complete,
        pendingTrackableScopes: ["test:account-a:run-1"],
        recordedContinuationScopes: []
      )
    )
  }

  func testLaunchInspectionDisagreementStillTracks() {
    // The disposition saw a state-0 run but the trackable-scope re-inspection
    // came back empty with no recorded continuation to explain it. That is a
    // transient read failure, not a handed-off wave; dropping the queued
    // request here would kill background tracking until the next foreground
    // launch. Track instead — the pass-level retry disposition absorbs it.
    XCTAssertTrue(
      migrationPreparationShouldTrackOnLaunch(
        disposition: .trackConfirmations,
        pendingTrackableScopes: [],
        recordedContinuationScopes: []
      )
    )
  }

  func testTrackingBatchKeepsAccountResultsIndependent() {
    let completedProgress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 3,
      totalUnitCount: 3,
      completedTransactionCount: 1,
      totalTransactionCount: 1,
      isComplete: true
    )
    let waitingProgress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 1,
      totalUnitCount: 3,
      completedTransactionCount: 0,
      totalTransactionCount: 1,
      isComplete: false
    )
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .completed(completedProgress)
        ),
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-b:run-2",
          disposition: .needsForegroundRecovery(
            fingerprint: "missing-transactions",
            taskFailed: true
          )
        ),
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-c:run-3",
          disposition: .progress(waitingProgress)
        ),
      ]
    )

    XCTAssertTrue(batch.shouldContinue)
    XCTAssertTrue(batch.hasTaskFailure)
    XCTAssertEqual(
      batch.continuationReadyScopes,
      ["test:account-a:run-1", "test:account-b:run-2"]
    )
    XCTAssertEqual(
      batch.confirmedWaveScopes,
      ["test:account-a:run-1"]
    )
    XCTAssertEqual(
      batch.progress,
      MigrationPreparationConfirmationProgress(
        confirmedUnitCount: 4,
        totalUnitCount: 6,
        completedTransactionCount: 1,
        totalTransactionCount: 2,
        isComplete: false
      )
    )
    XCTAssertEqual(
      batch.notificationEvents.map(\.scope),
      ["test:account-a:run-1", "test:account-b:run-2"]
    )
    XCTAssertEqual(
      batch.notificationEvents.map(\.kind),
      [.confirmedWaveReady, .needsForegroundRecovery]
    )
    XCTAssertNil(
      migrationPreparationTrackingCompletionPresentation(batch)
    )
  }

  func testCompletedTrackingScopeFinishesWithoutBackgroundWalletWork() {
    let completedProgress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 6,
      totalUnitCount: 6,
      completedTransactionCount: 2,
      totalTransactionCount: 4,
      isComplete: true
    )
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .completed(completedProgress)
        )
      ]
    )

    XCTAssertEqual(
      batch.continuationReadyScopes,
      ["test:account-a:run-1"]
    )
    XCTAssertEqual(
      batch.confirmedWaveScopes,
      ["test:account-a:run-1"]
    )
    XCTAssertEqual(
      migrationPreparationTrackingCompletionPresentation(batch),
      MigrationPreparationTrackingCompletionPresentation(
        title: "2 of 4 preparation transactions confirmed",
        subtitle: "Open Vizor to start the next step"
      )
    )
    // The task owns one wave. It reports that wave successfully instead of
    // idling until the OS expires it and the expiry reads as "Failed".
    XCTAssertEqual(
      migrationPreparationTrackingPostBatchAction(
        batch,
        taskFailureObserved: false,
        stopRequested: false
      ),
      .finishConfirmed(
        MigrationPreparationTrackingCompletionPresentation(
          title: "2 of 4 preparation transactions confirmed",
          subtitle: "Open Vizor to start the next step"
        )
      )
    )
    XCTAssertEqual(
      batch.notificationEvents,
      [
        MigrationPreparationNotificationEvent(
          scope: "test:account-a:run-1",
          kind: .confirmedWaveReady,
          fingerprint: "confirmed-wave-2-6"
        )
      ]
    )
  }

  func testObservedFailureOrStopRequestOverridesConfirmedWaveCompletion() {
    let completedProgress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 3,
      totalUnitCount: 3,
      completedTransactionCount: 1,
      totalTransactionCount: 1,
      isComplete: true
    )
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .completed(completedProgress)
        )
      ]
    )

    XCTAssertEqual(
      migrationPreparationTrackingPostBatchAction(
        batch,
        taskFailureObserved: true,
        stopRequested: false
      ),
      .finish
    )
    XCTAssertEqual(
      migrationPreparationTrackingPostBatchAction(
        batch,
        taskFailureObserved: false,
        stopRequested: true
      ),
      .finish
    )
  }

  func testStillCountingBatchKeepsTracking() {
    let waitingProgress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 1,
      totalUnitCount: 3,
      completedTransactionCount: 0,
      totalTransactionCount: 1,
      isComplete: false
    )
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .progress(waitingProgress)
        )
      ]
    )

    XCTAssertTrue(batch.shouldContinue)
    XCTAssertNil(
      migrationPreparationTrackingCompletionPresentation(batch)
    )
    XCTAssertEqual(
      migrationPreparationTrackingPostBatchAction(
        batch,
        taskFailureObserved: false,
        stopRequested: false
      ),
      .continueTracking
    )
  }

  func testConfirmedWavePresentationFallsBackWithoutProgress() {
    // `progress` is nil when no scope reported any unit total, so the caption
    // cannot name a step. It must still say the wave landed.
    let batch = MigrationPreparationTrackingBatch(
      progress: nil,
      continuationReadyScopes: ["test:account-a:run-1"],
      confirmedWaveScopes: ["test:account-a:run-1"],
      notificationEvents: [],
      shouldContinue: false,
      hasTaskFailure: false
    )

    XCTAssertEqual(
      migrationPreparationTrackingCompletionPresentation(batch),
      MigrationPreparationTrackingCompletionPresentation(
        title: "Preparation transactions confirmed",
        subtitle: "Open Vizor to start the next step"
      )
    )
  }

  func testRecoveryAndTerminalDispositionsKeepTheirNotificationKinds() {
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .needsForegroundRecovery(
            fingerprint: "missing-transactions",
            taskFailed: true
          )
        ),
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-b:run-2",
          disposition: .terminalFailure(fingerprint: "invalid-state")
        ),
      ]
    )

    XCTAssertEqual(
      batch.notificationEvents,
      [
        MigrationPreparationNotificationEvent(
          scope: "test:account-a:run-1",
          kind: .needsForegroundRecovery,
          fingerprint: "missing-transactions"
        ),
        MigrationPreparationNotificationEvent(
          scope: "test:account-b:run-2",
          kind: .terminalFailure,
          fingerprint: "invalid-state"
        ),
      ]
    )
  }

  func testCompletedAndRetryScopesKeepTheirProgressAcrossPasses() {
    var progressByScope: [String: MigrationPreparationConfirmationProgress] =
      [:]
    let accountAComplete = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 3,
      totalUnitCount: 3,
      completedTransactionCount: 1,
      totalTransactionCount: 1,
      isComplete: true
    )
    let accountBFirstPass = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 1,
      totalUnitCount: 3,
      completedTransactionCount: 0,
      totalTransactionCount: 1,
      isComplete: false
    )
    let firstBatch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .completed(accountAComplete)
        ),
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-b:run-2",
          disposition: .progress(accountBFirstPass)
        ),
      ],
      progressByScope: &progressByScope
    )
    XCTAssertEqual(firstBatch.progress?.confirmedUnitCount, 4)
    XCTAssertEqual(firstBatch.progress?.totalUnitCount, 6)

    let retryBatch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-b:run-2",
          disposition: .retry
        )
      ],
      progressByScope: &progressByScope
    )
    XCTAssertEqual(retryBatch.progress?.confirmedUnitCount, 4)
    XCTAssertEqual(retryBatch.progress?.totalUnitCount, 6)
  }

  func testFirstRetryScopeKeepsCompletedAccountBelowOneHundredPercent() throws {
    var progressByScope: [String: MigrationPreparationConfirmationProgress] =
      [:]
    let completed = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 3,
      totalUnitCount: 3,
      completedTransactionCount: 1,
      totalTransactionCount: 1,
      isComplete: true
    )
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .completed(completed)
        ),
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-b:run-2",
          disposition: .retry
        ),
      ],
      progressByScope: &progressByScope
    )

    XCTAssertEqual(batch.progress?.confirmedUnitCount, 3)
    XCTAssertEqual(batch.progress?.totalUnitCount, 4)
    XCTAssertFalse(try XCTUnwrap(batch.progress).isComplete)
    XCTAssertLessThan(
      migrationPreparationDisplayedProgressUnits(
        previousUnits: 0,
        progress: try XCTUnwrap(batch.progress),
        displayUnitCount: 1000
      ),
      1000
    )
  }

  func testDisplayedProgressDoesNotMoveBackward() {
    let regressedAggregate = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 1,
      totalUnitCount: 9,
      completedTransactionCount: 0,
      totalTransactionCount: 3,
      isComplete: false
    )

    XCTAssertEqual(
      migrationPreparationDisplayedProgressUnits(
        previousUnits: 560,
        progress: regressedAggregate,
        displayUnitCount: 1000
      ),
      560
    )
  }

  func testDisplayedProgressTicksForwardWhileConfirmationCountIsUnchanged() {
    let waiting = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 4,
      totalUnitCount: 12,
      completedTransactionCount: 0,
      totalTransactionCount: 4,
      isComplete: false
    )

    XCTAssertEqual(
      migrationPreparationDisplayedProgressUnits(
        previousUnits: 333,
        progress: waiting,
        displayUnitCount: 1000
      ),
      334
    )
    XCTAssertEqual(
      migrationPreparationDisplayedProgressUnits(
        previousUnits: 415,
        progress: waiting,
        displayUnitCount: 1000
      ),
      415
    )
  }

  func testForkedTransactionRequiresForegroundRecoveryAndFailsTheTask() {
    let disposition = migrationPreparationConfirmationDisposition(
      observations: [.forked, .mined(height: 100)],
      chainTipHeight: 102,
      confirmationTarget: 3
    )

    XCTAssertEqual(
      disposition,
      .needsForegroundRecovery(
        fingerprint: "forked-transaction",
        taskFailed: true
      )
    )
  }

  func testTxidInspectionFailureRequiresForegroundRecoveryAndFailsTheTask() {
    XCTAssertEqual(
      migrationPreparationTxidInspectionFailureDisposition(),
      .needsForegroundRecovery(
        fingerprint: "txid-inspection-failed",
        taskFailed: true
      )
    )
  }

  func testStatusInspectionFailureRequiresForegroundRecoveryAndFailsTheTask() {
    XCTAssertEqual(
      migrationPreparationStatusInspectionFailureDisposition(),
      .needsForegroundRecovery(
        fingerprint: "status-inspection-failed",
        taskFailed: true
      )
    )
  }

  func testPreparationStateOutcomesSeparateRecoveryFromTaskFailure() {
    XCTAssertEqual(
      migrationPreparationScopeTrackingDisposition(
        state: 1,
        completedStageCount: 2,
        totalStageCount: 2,
        confirmationTarget: 3
      ),
      .needsForegroundRecovery(
        fingerprint: "state-1-unverified",
        taskFailed: true
      )
    )
    XCTAssertEqual(
      migrationPreparationScopeTrackingDisposition(state: 2),
      .needsForegroundRecovery(
        fingerprint: "state-2",
        taskFailed: true
      )
    )
    XCTAssertEqual(
      migrationPreparationScopeTrackingDisposition(state: 3),
      .needsForegroundRecovery(
        fingerprint: "state-3",
        taskFailed: true
      )
    )
    XCTAssertEqual(
      migrationPreparationScopeTrackingDisposition(state: 5),
      .needsForegroundRecovery(
        fingerprint: "state-5",
        taskFailed: false
      )
    )
  }

  func testStalledRunNeedingRebroadcastFailsTheBackgroundTask() {
    XCTAssertFalse(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: true,
        quiesced: false,
        expired: false,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testNeedsActionFailsTheBackgroundTask() {
    XCTAssertFalse(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: true,
        quiesced: false,
        expired: false,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testRunningOutOfTimeWhileCountingIsNotAMigrationFailure() {
    // Expiration interrupts one execution opportunity on a healthy run. It
    // used to complete with `success: false`, which painted "Failed" over a
    // migration that was fine and re-armed itself moments later.
    XCTAssertTrue(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: false,
        quiesced: false,
        expired: true,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testConfirmedWaveCompletionReportsSuccess() {
    XCTAssertTrue(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: false,
        quiesced: false,
        expired: false,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testForegroundHandoffAndRevokedNotificationsAreNotFailures() {
    XCTAssertTrue(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: false,
        quiesced: false,
        expired: true,
        handedOff: true,
        notificationsDisabled: false
      )
    )
    XCTAssertTrue(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: false,
        quiesced: false,
        expired: true,
        handedOff: false,
        notificationsDisabled: true
      )
    )
  }

  func testForegroundHandoffDoesNotMaskAnObservedFailure() {
    XCTAssertFalse(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: true,
        quiesced: false,
        expired: true,
        handedOff: true,
        notificationsDisabled: false
      )
    )
  }

  func testDeletingAnAccountStopsTheTaskWithoutShowingSuccess() {
    XCTAssertFalse(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: false,
        quiesced: true,
        expired: true,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testWalletMutationAfterObservedConfirmationsIsNotSuccess() {
    XCTAssertFalse(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: false,
        quiesced: true,
        expired: true,
        handedOff: false,
        notificationsDisabled: false
      )
    )
  }

  func testTerminalMigrationFailureReportsTaskFailure() {
    XCTAssertFalse(
      migrationPreparationTrackingTaskSucceeded(
        taskFailed: true,
        quiesced: false,
        expired: false,
        handedOff: false,
        notificationsDisabled: false
      )
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
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [2],
        inspectionFailed: false
      ),
      .backgroundProcessing
    )
    XCTAssertEqual(
      migrationPreparationResumeTarget(
        states: [0, 2],
        inspectionFailed: false
      ),
      .continuedProcessing
    )
  }

  func testMigrationPreparationForegroundContinuationTracksEverySyncWait() {
    for state in [UInt8(0), 2, 3, 5] {
      XCTAssertTrue(
        migrationPreparationStateNeedsForegroundContinuation(state)
      )
    }
    XCTAssertFalse(migrationPreparationStateNeedsForegroundContinuation(1))
    XCTAssertFalse(migrationPreparationStateNeedsForegroundContinuation(4))
  }

  func testCompletedConfirmationWaitDoesNotCreateForegroundNotification() {
    XCTAssertFalse(migrationPreparationStateNeedsForegroundNotification(0))
    for state in [UInt8(2), 3, 5] {
      XCTAssertTrue(migrationPreparationStateNeedsForegroundNotification(state))
    }
    XCTAssertFalse(migrationPreparationStateNeedsForegroundNotification(1))
    XCTAssertFalse(migrationPreparationStateNeedsForegroundNotification(4))
  }

  func testForegroundRecoveryNotificationFallsBackWhenInspectionFails() {
    let scope = "test:account-a:run-1"

    XCTAssertEqual(
      migrationPreparationForegroundRecoveryNotificationEvent(
        scope: scope,
        preparationState: nil
      ),
      MigrationPreparationNotificationEvent(
        scope: scope,
        kind: .needsForegroundRecovery,
        fingerprint: "foreground-preparation-inspection-failed"
      )
    )
  }

  func testForegroundRecoveryNotificationUsesTheInspectedState() {
    let scope = "test:account-a:run-1"

    XCTAssertEqual(
      migrationPreparationForegroundRecoveryNotificationEvent(
        scope: scope,
        preparationState: 5
      ),
      MigrationPreparationNotificationEvent(
        scope: scope,
        kind: .needsForegroundRecovery,
        fingerprint: "foreground-preparation-required:state-5"
      )
    )
    XCTAssertNil(
      migrationPreparationForegroundRecoveryNotificationEvent(
        scope: scope,
        preparationState: 0
      )
    )
    XCTAssertNil(
      migrationPreparationForegroundRecoveryNotificationEvent(
        scope: scope,
        preparationState: 4
      )
    )
  }

  func testMigrationPreparationContinuedTaskTracksOnlyDenominationConfirmations() {
    XCTAssertEqual(
      migrationPreparationContinuedTaskDisposition(.continuedProcessing),
      .trackConfirmations
    )
    XCTAssertEqual(
      migrationPreparationContinuedTaskDisposition(.backgroundProcessing),
      .foregroundOnly
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

  func testMigrationPreparationConfirmationProgressRequiresEveryTransactionAtThreeConfirmations() {
    let progress = migrationPreparationConfirmationProgress(
      observations: [
        .notFound,
        .mempool,
        .mined(height: 100),
      ],
      chainTipHeight: 101,
      confirmationTarget: 3
    )

    XCTAssertEqual(progress.confirmedUnitCount, 2)
    XCTAssertEqual(progress.totalUnitCount, 9)
    XCTAssertEqual(progress.completedTransactionCount, 0)
    XCTAssertEqual(progress.totalTransactionCount, 3)
    XCTAssertFalse(progress.isComplete)
  }

  func testMigrationPreparationConfirmationProgressCompletesOnlyWhenAllReachTarget() {
    let progress = migrationPreparationConfirmationProgress(
      observations: [
        .mined(height: 100),
        .mined(height: 99),
      ],
      chainTipHeight: 102,
      confirmationTarget: 3
    )

    XCTAssertEqual(progress.confirmedUnitCount, 6)
    XCTAssertEqual(progress.totalUnitCount, 6)
    XCTAssertEqual(progress.completedTransactionCount, 2)
    XCTAssertEqual(progress.totalTransactionCount, 2)
    XCTAssertTrue(progress.isComplete)
  }

  func testConfirmedWaveUsesTheWholePreparationAsItsProgressDenominator() {
    let progress = migrationPreparationConfirmationProgress(
      observations: [
        .mined(height: 100),
        .mined(height: 100),
        .mined(height: 100),
        .mined(height: 100),
      ],
      chainTipHeight: 102,
      confirmationTarget: 3,
      totalStageCount: 8
    )

    XCTAssertEqual(progress.confirmedUnitCount, 12)
    XCTAssertEqual(progress.totalUnitCount, 24)
    XCTAssertEqual(progress.completedTransactionCount, 4)
    XCTAssertEqual(progress.totalTransactionCount, 8)
    XCTAssertTrue(progress.isComplete)
    XCTAssertEqual(
      migrationPreparationDisplayedProgressUnits(
        previousUnits: 0,
        progress: progress,
        displayUnitCount: 949
      ),
      475
    )
  }

  func testTrackingProgressPresentationExplainsTheConfirmationCount() {
    let progress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 7,
      totalUnitCount: 12,
      completedTransactionCount: 2,
      totalTransactionCount: 4,
      isComplete: false
    )

    XCTAssertEqual(
      migrationPreparationTrackingProgressPresentation(progress),
      MigrationPreparationTrackingCompletionPresentation(
        title: "Preparing your migration",
        subtitle: "2 of 4 preparation transactions confirmed"
      )
    )
  }

  func testTrackingProgressPresentationAvoidsAnUnknownZeroOfZeroCount() {
    let progress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 0,
      totalUnitCount: 1,
      completedTransactionCount: 0,
      totalTransactionCount: 0,
      isComplete: false
    )

    XCTAssertEqual(
      migrationPreparationTrackingProgressPresentation(progress),
      MigrationPreparationTrackingCompletionPresentation(
        title: "Preparing your migration",
        subtitle: "Checking transaction confirmations"
      )
    )
  }

  func testFinalPreparationWaveUsesCompletionCopy() {
    let completedProgress = MigrationPreparationConfirmationProgress(
      confirmedUnitCount: 12,
      totalUnitCount: 12,
      completedTransactionCount: 4,
      totalTransactionCount: 4,
      isComplete: true
    )
    let batch = migrationPreparationTrackingBatch(
      results: [
        MigrationPreparationScopeTrackingResult(
          scope: "test:account-a:run-1",
          disposition: .completed(completedProgress)
        )
      ]
    )

    XCTAssertEqual(
      migrationPreparationTrackingCompletionPresentation(batch),
      MigrationPreparationTrackingCompletionPresentation(
        title: "Migration preparation complete",
        subtitle: "Open Vizor to continue your migration"
      )
    )
  }

  func testMigrationPreparationConfirmationProgressDoesNotCountForkedTransaction() {
    let progress = migrationPreparationConfirmationProgress(
      observations: [
        .forked,
        .mined(height: 100),
      ],
      chainTipHeight: 102,
      confirmationTarget: 3
    )

    XCTAssertEqual(progress.confirmedUnitCount, 3)
    XCTAssertEqual(progress.completedTransactionCount, 1)
    XCTAssertFalse(progress.isComplete)
  }

  func testMigrationNotificationBatchAggregatesAccountsAndPrioritizesRecovery() {
    var state = MigrationPreparationNotificationBatchState()
    let recovery = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "reorg-recovery"
    )
    let terminalFailure = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )

    XCTAssertTrue(state.enqueue(recovery))
    XCTAssertTrue(state.enqueue(terminalFailure))

    let summary = state.summary
    XCTAssertEqual(summary?.accountCount, 2)
    XCTAssertEqual(summary?.highestPriority, .terminalFailure)
    XCTAssertEqual(summary?.title, "Migration updates")
    XCTAssertEqual(
      summary?.body,
      "2 accounts need attention. Open Vizor to continue."
    )
  }

  func testConfirmedWaveNotificationUsesHealthyCopy() {
    var state = MigrationPreparationNotificationBatchState()
    let confirmed = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .confirmedWaveReady,
      fingerprint: "confirmed-wave-1-3"
    )

    XCTAssertTrue(state.enqueue(confirmed))

    let summary = state.summary
    XCTAssertEqual(summary?.accountCount, 1)
    XCTAssertEqual(summary?.highestPriority, .confirmedWaveReady)
    XCTAssertEqual(summary?.title, "Preparation transactions confirmed")
    XCTAssertEqual(summary?.body, "Open Vizor to start the next step.")
  }

  func testSingleAccountFailureKeepsTheAttentionCopy() {
    var state = MigrationPreparationNotificationBatchState()
    let failure = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )

    XCTAssertTrue(state.enqueue(failure))

    XCTAssertEqual(state.summary?.title, "Migration needs attention")
    XCTAssertEqual(state.summary?.body, "Open Vizor to continue.")
  }

  func testFailureOutranksAConfirmedWaveInTheSameBatch() {
    // A healthy wave for one account must never soften the alert for another
    // account whose run actually needs help.
    var state = MigrationPreparationNotificationBatchState()
    let confirmed = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .confirmedWaveReady,
      fingerprint: "confirmed-wave-1-3"
    )
    let recovery = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .needsForegroundRecovery,
      fingerprint: "missing-transactions"
    )

    XCTAssertTrue(state.enqueue(confirmed))
    XCTAssertTrue(state.enqueue(recovery))

    XCTAssertEqual(state.summary?.highestPriority, .needsForegroundRecovery)
    XCTAssertEqual(state.summary?.title, "Migration updates")
    XCTAssertEqual(
      state.summary?.body,
      "2 accounts need attention. Open Vizor to continue."
    )
  }

  func testMultipleConfirmedWavesUseTheHealthyAggregateCopy() {
    var state = MigrationPreparationNotificationBatchState()
    XCTAssertTrue(
      state.enqueue(
        MigrationPreparationNotificationEvent(
          scope: "test:account-a:run-1",
          kind: .confirmedWaveReady,
          fingerprint: "confirmed-wave-1-3"
        )
      )
    )
    XCTAssertTrue(
      state.enqueue(
        MigrationPreparationNotificationEvent(
          scope: "test:account-b:run-2",
          kind: .confirmedWaveReady,
          fingerprint: "confirmed-wave-2-6"
        )
      )
    )

    XCTAssertEqual(state.summary?.highestPriority, .confirmedWaveReady)
    XCTAssertEqual(state.summary?.title, "Migration preparation updates")
    XCTAssertEqual(
      state.summary?.body,
      "2 accounts are ready for the next step. Open Vizor to continue."
    )
  }

  func testAcceptedConfirmedWaveDoesNotSuppressALaterFailure() {
    // The dedupe key is `scope|kind`, so the healthy fingerprint accepted for
    // a run cannot swallow a genuine failure alert for that same run.
    var state = MigrationPreparationNotificationBatchState()
    let confirmed = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .confirmedWaveReady,
      fingerprint: "confirmed-wave-1-3"
    )
    _ = state.enqueue(confirmed)
    state.markAccepted([confirmed])
    state.beginNewBatch()

    XCTAssertFalse(state.enqueue(confirmed))
    XCTAssertTrue(
      state.enqueue(
        MigrationPreparationNotificationEvent(
          scope: "test:account-a:run-1",
          kind: .terminalFailure,
          fingerprint: "invalid-state"
        )
      )
    )
    XCTAssertEqual(state.summary?.title, "Migration needs attention")
  }

  func testMigrationNotificationBatchDeduplicatesAcceptedFingerprint() {
    var state = MigrationPreparationNotificationBatchState()
    let event = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "reorg-recovery"
    )

    XCTAssertTrue(state.enqueue(event))
    state.markAccepted([event])
    state.beginNewBatch()

    XCTAssertFalse(state.enqueue(event))
    XCTAssertNil(state.summary)
  }

  func testResolvingOneMigrationNotificationScopePreservesAnotherAccount() {
    var state = MigrationPreparationNotificationBatchState()
    let accountA = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )
    let accountB = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .needsForegroundRecovery,
      fingerprint: "reorg-recovery"
    )
    _ = state.enqueue(accountA)
    _ = state.enqueue(accountB)
    state.markAccepted([accountA, accountB])
    state.batchDeadline = Date(timeIntervalSince1970: 1)

    state.resolve(scope: accountA.scope)

    XCTAssertFalse(
      state.expireBatchIfNeeded(
        now: Date(timeIntervalSince1970: 2)
      )
    )
    XCTAssertEqual(state.summary?.accountCount, 1)
    XCTAssertEqual(state.summary?.events, [accountB])
    XCTAssertFalse(state.enqueue(accountB))
  }

  func testResolvingMigrationNotificationScopeAllowsARealRecurrence() {
    var state = MigrationPreparationNotificationBatchState()
    let event = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "reorg-recovery"
    )
    _ = state.enqueue(event)
    state.markAccepted([event])

    state.resolve(scope: event.scope)

    XCTAssertTrue(state.enqueue(event))
  }

  func testRetainingMigrationNotificationScopesDoesNotSilenceAnotherAccount() {
    var state = MigrationPreparationNotificationBatchState()
    let accountA = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )
    let accountB = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .needsForegroundRecovery,
      fingerprint: "reorg-recovery"
    )
    _ = state.enqueue(accountA)
    _ = state.enqueue(accountB)
    state.markAccepted([accountA, accountB])

    state.retain(scopes: [accountB.scope])

    XCTAssertEqual(state.summary?.events, [accountB])
    XCTAssertFalse(state.enqueue(accountB))
    XCTAssertTrue(state.enqueue(accountA))
  }

  func testExpiredMigrationNotificationBatchDoesNotRearmOldEvents() {
    var state = MigrationPreparationNotificationBatchState()
    let event = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "reorg-recovery"
    )
    _ = state.enqueue(event)
    state.batchDeadline = Date(timeIntervalSince1970: 1)

    XCTAssertTrue(
      state.expireBatchIfNeeded(
        now: Date(timeIntervalSince1970: 2)
      )
    )
    XCTAssertNil(state.summary)
    XCTAssertNil(state.batchDeadline)
  }

  func testMigrationNotificationEnqueueWaitsForRequestSubmission() {
    let center = MigrationPreparationNotificationCenterHarness()
    let suiteName = "MigrationNotificationCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let coordinator = MigrationPreparationNotificationCoordinator(
      center: center,
      defaults: defaults
    )
    let requestAdded = expectation(description: "notification request added")
    let enqueueCompleted = expectation(description: "enqueue completed")
    center.onAdd = { _ in
      requestAdded.fulfill()
    }
    let event = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "confirmed-wave-1-3"
    )
    var submissionResult: Bool?

    coordinator.enqueue([event]) { success in
      submissionResult = success
      enqueueCompleted.fulfill()
    }

    wait(for: [requestAdded], timeout: 1)
    XCTAssertNil(submissionResult)
    center.completeAdd(error: nil)
    wait(for: [enqueueCompleted], timeout: 1)
    XCTAssertEqual(submissionResult, true)
  }

  func testResolvingScopeRefreshesAnUndeliveredNotificationSummary() {
    let center = MigrationPreparationNotificationCenterHarness()
    let suiteName = "MigrationNotificationCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let coordinator = MigrationPreparationNotificationCoordinator(
      center: center,
      defaults: defaults
    )
    let initialRequestAdded = expectation(description: "initial request added")
    let refreshedRequestAdded = expectation(
      description: "pending request refreshed"
    )
    center.onAdd = { request in
      if request.content.body.hasPrefix("2 accounts") {
        initialRequestAdded.fulfill()
      } else {
        refreshedRequestAdded.fulfill()
      }
    }
    let accountA = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "confirmed-wave-1-3"
    )
    let accountB = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .needsForegroundRecovery,
      fingerprint: "confirmed-wave-1-3"
    )
    let initialSubmissionCompleted = expectation(
      description: "initial submission completed"
    )
    coordinator.enqueue([accountA, accountB]) { success in
      XCTAssertTrue(success)
      initialSubmissionCompleted.fulfill()
    }
    wait(for: [initialRequestAdded], timeout: 1)
    center.completeAdd(error: nil)
    wait(for: [initialSubmissionCompleted], timeout: 1)

    coordinator.resolve(scope: accountA.scope)

    wait(for: [refreshedRequestAdded], timeout: 1)
    XCTAssertEqual(
      center.addedRequests.last?.content.body,
      "Open Vizor to continue."
    )
    center.completeAdd(error: nil)
  }

  func testRetainingASubsetRefreshesTheStalePendingSummary() {
    // Account A is deleted while B still needs attention. The queued request
    // was written for A+B, so without a reschedule the alert would still
    // announce "2 accounts need attention" for a wallet that has one.
    let center = MigrationPreparationNotificationCenterHarness()
    let suiteName = "MigrationNotificationCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let coordinator = MigrationPreparationNotificationCoordinator(
      center: center,
      defaults: defaults
    )
    let initialRequestAdded = expectation(description: "initial request added")
    let refreshedRequestAdded = expectation(
      description: "pending request refreshed"
    )
    center.onAdd = { request in
      if request.content.body.hasPrefix("2 accounts") {
        initialRequestAdded.fulfill()
      } else {
        refreshedRequestAdded.fulfill()
      }
    }
    let accountA = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "missing-transactions"
    )
    let accountB = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )
    let initialSubmissionCompleted = expectation(
      description: "initial submission completed"
    )
    coordinator.enqueue([accountA, accountB]) { success in
      XCTAssertTrue(success)
      initialSubmissionCompleted.fulfill()
    }
    wait(for: [initialRequestAdded], timeout: 1)
    center.completeAdd(error: nil)
    wait(for: [initialSubmissionCompleted], timeout: 1)

    coordinator.retain(scopes: [accountB.scope])

    wait(for: [refreshedRequestAdded], timeout: 1)
    XCTAssertEqual(
      center.addedRequests.last?.content.body,
      "Open Vizor to continue."
    )
    center.completeAdd(error: nil)
  }

  func testRetainingEverythingDoesNotRescheduleTheSummary() {
    let center = MigrationPreparationNotificationCenterHarness()
    let suiteName = "MigrationNotificationCoordinator.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let coordinator = MigrationPreparationNotificationCoordinator(
      center: center,
      defaults: defaults
    )
    let initialRequestAdded = expectation(description: "initial request added")
    center.onAdd = { _ in initialRequestAdded.fulfill() }
    let accountA = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "missing-transactions"
    )
    let accountB = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )
    let initialSubmissionCompleted = expectation(
      description: "initial submission completed"
    )
    coordinator.enqueue([accountA, accountB]) { success in
      XCTAssertTrue(success)
      initialSubmissionCompleted.fulfill()
    }
    wait(for: [initialRequestAdded], timeout: 1)
    center.completeAdd(error: nil)
    wait(for: [initialSubmissionCompleted], timeout: 1)
    let requestCountBeforeRetain = center.addedRequests.count

    let noReschedule = expectation(description: "no reschedule")
    noReschedule.isInverted = true
    center.onAdd = { _ in noReschedule.fulfill() }

    coordinator.retain(scopes: [accountA.scope, accountB.scope])

    wait(for: [noReschedule], timeout: 0.5)
    XCTAssertEqual(center.addedRequests.count, requestCountBeforeRetain)
  }

  func testRetainingASubsetReportsTheChangeToTheCoordinator() {
    var state = MigrationPreparationNotificationBatchState()
    let accountA = MigrationPreparationNotificationEvent(
      scope: "test:account-a:run-1",
      kind: .needsForegroundRecovery,
      fingerprint: "missing-transactions"
    )
    let accountB = MigrationPreparationNotificationEvent(
      scope: "test:account-b:run-2",
      kind: .terminalFailure,
      fingerprint: "invalid-state"
    )
    _ = state.enqueue(accountA)
    _ = state.enqueue(accountB)

    XCTAssertTrue(state.retain(scopes: [accountB.scope]))
    XCTAssertFalse(state.retain(scopes: [accountB.scope]))
    XCTAssertEqual(state.summary?.accountCount, 1)
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

  func testFreshInstallCleanerPreservesStagingOnlyInterruptedMigration() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .missing
    harness.stagedLookup = .found("zcash_wallet_existing.db")
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

  func testFreshInstallCleanerClearsStagingOnlyStateAfterReinstall() {
    let harness = FreshInstallCleanerHarness()
    harness.lookup = .missing
    harness.stagedLookup = .found("zcash_wallet_deleted.db")
    harness.walletDbExists = false

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerClearsNonMainStagingOnlyStateAfterReinstall() {
    let harness = FreshInstallCleanerHarness()
    harness.lookups = [
      .missing,
      .missing,
      .missing,
      .found("zcash_wallet_deleted.db"),
    ]
    harness.walletDbExists = false

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertEqual(
      harness.deletedServices,
      FreshInstallKeychainCleaner.servicesToClear
    )
  }

  func testFreshInstallCleanerPreservesAnyExistingNetworkDatabase() {
    let harness = FreshInstallCleanerHarness()
    harness.lookups = [
      .found("zcash_wallet_deleted.db"),
      .found("zcash_wallet_existing.db"),
    ]
    harness.existingDbNames = ["zcash_wallet_existing.db"]

    FreshInstallKeychainCleaner.runIfNeeded(dependencies: harness.dependencies())

    XCTAssertTrue(harness.markedInstalled)
    XCTAssertFalse(harness.cleanupPending)
    XCTAssertTrue(harness.deletedServices.isEmpty)
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

  func testKeychainAccessibilityMigrationMovesLegacyItemThroughStaging() throws {
    let service = "com.keplr.vizor.secure_store"
    let store = KeychainAccessibilityMigrationStoreHarness()
    store.put(
      service: service,
      account: "zcash_account_mnemonic_test",
      data: Data("ciphertext".utf8),
      accessibility: kSecAttrAccessibleAfterFirstUnlock as String
    )

    let migrated = try KeychainAccessibilityMigrator(store: store)
      .ensureFirstUnlockThisDeviceOnly(service: service)

    XCTAssertEqual(migrated, 1)
    XCTAssertEqual(store.itemsByService[service]?.count, 1)
    XCTAssertEqual(
      store.itemsByService[service]?.first?.accessibility,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
    XCTAssertEqual(
      store.itemsByService[service]?.first?.data,
      Data("ciphertext".utf8)
    )
    XCTAssertNil(
      store.itemsByService[
        service + keychainAccessibilityMigrationStagingSuffix
      ]
    )
  }

  func testKeychainAccessibilityMigrationRecoversFromStagingOnly() throws {
    let service = "com.keplr.vizor.secure_store"
    let staging = service + keychainAccessibilityMigrationStagingSuffix
    let store = KeychainAccessibilityMigrationStoreHarness()
    store.put(
      service: staging,
      account: "zcash_wallet_db_name",
      data: Data("wallet.db".utf8),
      accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )

    let migrated = try KeychainAccessibilityMigrator(store: store)
      .ensureFirstUnlockThisDeviceOnly(service: service)

    XCTAssertEqual(migrated, 1)
    XCTAssertEqual(
      store.itemsByService[service]?.first?.data,
      Data("wallet.db".utf8)
    )
    XCTAssertNil(store.itemsByService[staging])
  }

  func testKeychainAccessibilityMigrationPreservesConflictingCopies() {
    let service = "com.keplr.vizor.secure_store"
    let staging = service + keychainAccessibilityMigrationStagingSuffix
    let store = KeychainAccessibilityMigrationStoreHarness()
    store.put(
      service: service,
      account: "zcash_accounts",
      data: Data("canonical".utf8),
      accessibility: kSecAttrAccessibleAfterFirstUnlock as String
    )
    store.put(
      service: staging,
      account: "zcash_accounts",
      data: Data("staged".utf8),
      accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )

    XCTAssertThrowsError(
      try KeychainAccessibilityMigrator(store: store)
        .ensureFirstUnlockThisDeviceOnly(service: service)
    ) { error in
      XCTAssertEqual(
        error as? KeychainAccessibilityMigrationError,
        .conflictingCopies("zcash_accounts")
      )
    }
    XCTAssertEqual(
      store.itemsByService[service]?.first?.data,
      Data("canonical".utf8)
    )
    XCTAssertEqual(
      store.itemsByService[staging]?.first?.data,
      Data("staged".utf8)
    )
  }

  func testFreshInstallCleanerIncludesAccessibilityMigrationStagingService() {
    XCTAssertTrue(
      FreshInstallKeychainCleaner.servicesToClear.contains(
        "com.keplr.vizor.secure_store"
          + keychainAccessibilityMigrationStagingSuffix
      )
    )
  }

  func testSecurityKeychainMigrationStoreWritesPluginCompatibleTargetClass() throws {
    let service = "com.zcash.wallet.tests.keychain-migration.\(UUID().uuidString)"
    let staging = service + keychainAccessibilityMigrationStagingSuffix
    let account = "test-item"
    defer {
      for candidate in [service, staging] {
        SecItemDelete(
          [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: candidate,
          ] as CFDictionary
        )
      }
    }

    var accessControlError: Unmanaged<CFError>?
    let legacyAccessControl = try XCTUnwrap(
      SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleAfterFirstUnlock,
        [],
        &accessControlError
      )
    )
    XCTAssertNil(accessControlError)
    XCTAssertEqual(
      SecItemAdd(
        [
          kSecClass: kSecClassGenericPassword,
          kSecAttrService: service,
          kSecAttrAccount: account,
          kSecAttrAccessControl: legacyAccessControl,
          kSecValueData: Data("secret".utf8),
        ] as CFDictionary,
        nil
      ),
      errSecSuccess
    )

    let store = SecurityKeychainMigrationStore()
    let legacy = try XCTUnwrap(store.items(service: service).first)
    XCTAssertEqual(
      legacy.accessibility,
      kSecAttrAccessibleAfterFirstUnlock as String
    )

    try store.add(legacy, service: staging)
    let target = try XCTUnwrap(store.items(service: staging).first)
    XCTAssertEqual(target.data, Data("secret".utf8))
    XCTAssertEqual(
      target.accessibility,
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
  }

}

final class NativeLightwalletdClientTests: XCTestCase {
  func testBackgroundMigrationCancellationSignalsWaitingWork() {
    let cancellation = BackgroundMigrationCancellation()
    let cancelled = expectation(description: "cancelled")
    DispatchQueue.global(qos: .utility).async {
      if cancellation.waitUntilCancelled(timeout: 1) {
        cancelled.fulfill()
      }
    }

    cancellation.cancel()

    wait(for: [cancelled], timeout: 1)
    XCTAssertTrue(cancellation.isCancelled)
  }

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

  func testNativeLightwalletdParserReadsMinedTransactionHeight() throws {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x07,
      0x0A, 0x02, 0xAA, 0xBB,
      0x10, 0xAC, 0x02,
    ])

    XCTAssertEqual(
      try NativeLightwalletdClient.parseTransactionResponse(response),
      .mined(height: 300)
    )
  }

  func testNativeLightwalletdParserReadsMempoolTransaction() throws {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x02,
      0x0A, 0x00,
    ])

    XCTAssertEqual(
      try NativeLightwalletdClient.parseTransactionResponse(response),
      .mempool
    )
  }

  func testNativeLightwalletdParserReadsForkedTransactionSentinel() throws {
    let response = Data([
      0x00, 0x00, 0x00, 0x00, 0x0B,
      0x10, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF, 0x01,
    ])

    XCTAssertEqual(
      try NativeLightwalletdClient.parseTransactionResponse(response),
      .forked
    )
  }

  func testUnavailableGrpcTrailerRetriesStoredTransactionByteOrder() {
    XCTAssertTrue(
      shouldTryStoredTransactionIdByteOrder(
        after: .failure(.grpcStatusUnavailable)
      )
    )
    XCTAssertTrue(
      shouldTryStoredTransactionIdByteOrder(after: .success(.notFound))
    )
    XCTAssertFalse(
      shouldTryStoredTransactionIdByteOrder(
        after: .failure(.timedOut)
      )
    )
    let resolved = transactionObservationAfterStoredByteOrderFallback(
      first: .failure(.grpcStatusUnavailable),
      second: .failure(.grpcStatusUnavailable)
    )
    guard case .success(.notFound) = resolved else {
      XCTFail("Expected unavailable trailers in both byte orders to be NotFound")
      return
    }
  }
}

/// A lock-guarded counter for asserting on concurrent callers.
private final class NSCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  func increment() {
    lock.lock()
    count += 1
    lock.unlock()
  }
}

private final class MigrationPreparationNotificationCenterHarness:
  MigrationPreparationNotificationCenter
{
  var onAdd: ((UNNotificationRequest) -> Void)?
  private(set) var addedRequests: [UNNotificationRequest] = []
  private var pendingRequests: [UNNotificationRequest] = []
  private var addCompletion: (@Sendable (Error?) -> Void)?

  func add(
    _ request: UNNotificationRequest,
    withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
  ) {
    addedRequests.append(request)
    pendingRequests.removeAll { $0.identifier == request.identifier }
    pendingRequests.append(request)
    addCompletion = completionHandler
    onAdd?(request)
  }

  func removePendingNotificationRequests(withIdentifiers _: [String]) {}

  func removeDeliveredNotifications(withIdentifiers _: [String]) {}

  func getPendingNotificationRequests(
    completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void
  ) {
    completionHandler(pendingRequests)
  }

  func completeAdd(error: Error?) {
    let completion = addCompletion
    addCompletion = nil
    completion?(error)
  }
}

private final class FreshInstallCleanerHarness {
  var hasSentinel = false
  var markedInstalled = false
  var cleanupPending = false
  var lookup: KeychainDbNameLookup = .missing
  var stagedLookup: KeychainDbNameLookup = .missing
  var lookups: [KeychainDbNameLookup]?
  var walletDbExists = false
  var existingDbNames: Set<String>?
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
      readWalletDbNames: {
        self.lookups ?? [self.lookup, self.stagedLookup]
      },
      walletDbExists: { dbName in
        self.existingDbNames?.contains(dbName) ?? self.walletDbExists
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

private final class KeychainAccessibilityMigrationStoreHarness:
  KeychainAccessibilityMigrationStore
{
  var itemsByService: [String: [KeychainAccessibilityMigrationItem]] = [:]

  func put(
    service: String,
    account: String,
    data: Data,
    accessibility: String
  ) {
    itemsByService[service, default: []].append(
      KeychainAccessibilityMigrationItem(
        account: account,
        data: data,
        accessibility: accessibility,
        attributes: [:]
      )
    )
  }

  func items(service: String) throws -> [KeychainAccessibilityMigrationItem] {
    itemsByService[service] ?? []
  }

  func add(
    _ item: KeychainAccessibilityMigrationItem,
    service: String
  ) throws {
    if itemsByService[service]?.contains(where: { $0.account == item.account }) == true {
      throw KeychainAccessibilityMigrationError.keychain(
        operation: "add",
        status: errSecDuplicateItem
      )
    }
    put(
      service: service,
      account: item.account,
      data: item.data,
      accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
  }

  func delete(service: String, account: String) throws {
    itemsByService[service]?.removeAll { $0.account == account }
    if itemsByService[service]?.isEmpty == true {
      itemsByService.removeValue(forKey: service)
    }
  }
}
