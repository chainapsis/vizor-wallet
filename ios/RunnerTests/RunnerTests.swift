import Flutter
import Security
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

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

final class BackgroundMigrationRunnerTests: XCTestCase {
  func testManifestDecoderAcceptsBoundCredentialAndRejectsProvisionalOne() throws {
    let bound = try JSONEncoder().encode(makeBackgroundMigrationManifest())
    XCTAssertNotNil(IronwoodMigrationBackgroundManifest.decode(bound))

    let provisional = try JSONEncoder().encode(
      makeBackgroundMigrationManifest(expectedRunId: nil)
    )
    XCTAssertNil(IronwoodMigrationBackgroundManifest.decode(provisional))
  }

  func testManifestResolutionRebasesTheSameWalletDbIntoTheCurrentContainer() {
    let current = makeBackgroundMigrationManifest(accountUuid: "rebase")
    let support = try! resolveWalletSupportDirectory()
    let dbName = URL(fileURLWithPath: current.dbPath).lastPathComponent
    let stale = current.replacingDbPath(
      "/old/app-container/Library/Application Support/\(dbName)"
    )

    let resolved = BackgroundMigrationRunner.resolveAllowedManifest(
      stale,
      currentDbPath: current.dbPath,
      supportDirectory: support
    )

    XCTAssertEqual(resolved?.dbPath, current.dbPath)
    XCTAssertNil(
      BackgroundMigrationRunner.resolveAllowedManifest(
        stale.replacingDbPath("/old/app-container/different-wallet.db"),
        currentDbPath: current.dbPath,
        supportDirectory: support
      )
    )
  }

  func testWatchdogIdentifierIsStablePerManifestRun() {
    let first = makeBackgroundMigrationManifest(
      accountUuid: "private-account",
      expectedRunId: "private-run"
    )
    let same = makeBackgroundMigrationManifest(
      accountUuid: "private-account",
      expectedRunId: "private-run"
    )
    let nextRun = makeBackgroundMigrationManifest(
      accountUuid: "private-account",
      expectedRunId: "next-run"
    )

    let identifier = BackgroundMigrationNotificationPolicy.identifier(for: first)

    XCTAssertEqual(
      identifier,
      BackgroundMigrationNotificationPolicy.identifier(for: same)
    )
    XCTAssertNotEqual(
      identifier,
      BackgroundMigrationNotificationPolicy.identifier(for: nextRun)
    )
    XCTAssertFalse(identifier.contains("private-account"))
    XCTAssertFalse(identifier.contains("private-run"))
  }

  func testWatchdogDeadlineUsesScheduledHeightAndNinetySixBlockGrace() {
    let now = Date(timeIntervalSince1970: 1_000)

    let deadline = BackgroundMigrationNotificationPolicy.watchdogDate(
      now: now,
      nextScheduledHeight: 1_100,
      observedHeight: 1_000
    )

    XCTAssertEqual(
      deadline.timeIntervalSince(now),
      TimeInterval(100 + 96) * 75
    )
  }

  func testWatchdogDeadlineStartsGraceAtAnAlreadyReachedHeight() {
    let now = Date(timeIntervalSince1970: 1_000)

    let deadline = BackgroundMigrationNotificationPolicy.watchdogDate(
      now: now,
      nextScheduledHeight: 900,
      observedHeight: 1_000
    )

    XCTAssertEqual(deadline.timeIntervalSince(now), TimeInterval(96) * 75)
  }

  func testWatchdogDeadlineUsesConservativeFallbackWithoutNextHeight() {
    let now = Date(timeIntervalSince1970: 1_000)

    let deadline = BackgroundMigrationNotificationPolicy.watchdogDate(
      now: now,
      nextScheduledHeight: nil,
      observedHeight: 1_000
    )

    XCTAssertEqual(
      deadline.timeIntervalSince(now),
      TimeInterval(144 + 96) * 75
    )
  }

  func testRepeatedWatchdogReconciliationDoesNotPostponeTheSameTarget() {
    let identifier = "watchdog-id"
    let firstDeadline = Date(timeIntervalSince1970: 10_000)
    let first = BackgroundMigrationNotificationPolicy.resolvedWatchdogState(
      identifier: identifier,
      nextScheduledHeight: 1_100,
      proposedDeadline: firstDeadline,
      existing: nil
    )

    let repeated = BackgroundMigrationNotificationPolicy.resolvedWatchdogState(
      identifier: identifier,
      nextScheduledHeight: 1_100,
      proposedDeadline: firstDeadline.addingTimeInterval(600),
      existing: first
    )

    XCTAssertEqual(repeated.deadline, firstDeadline)
  }

  func testInspectionFailurePreservesAnExistingWatchdog() {
    let existing = BackgroundMigrationWatchdogState(
      identifier: "watchdog-id",
      nextScheduledHeight: 1_100,
      deadline: Date(timeIntervalSince1970: 10_000)
    )

    XCTAssertFalse(
      BackgroundMigrationNotificationPolicy.shouldScheduleFallbackWatchdog(
        existing: existing,
        needsActionAlreadyNotified: false
      )
    )
    XCTAssertTrue(
      BackgroundMigrationNotificationPolicy.shouldScheduleFallbackWatchdog(
        existing: nil,
        needsActionAlreadyNotified: false
      )
    )
    XCTAssertFalse(
      BackgroundMigrationNotificationPolicy.shouldScheduleFallbackWatchdog(
        existing: nil,
        needsActionAlreadyNotified: true
      )
    )
  }

  func testWatchdogReconciliationReplacesDeadlineForTheNextTarget() {
    let identifier = "watchdog-id"
    let first = BackgroundMigrationWatchdogState(
      identifier: identifier,
      nextScheduledHeight: 1_100,
      deadline: Date(timeIntervalSince1970: 10_000)
    )
    let nextDeadline = Date(timeIntervalSince1970: 20_000)

    let next = BackgroundMigrationNotificationPolicy.resolvedWatchdogState(
      identifier: identifier,
      nextScheduledHeight: 1_200,
      proposedDeadline: nextDeadline,
      existing: first
    )

    XCTAssertEqual(next.deadline, nextDeadline)
    XCTAssertEqual(next.nextScheduledHeight, 1_200)
  }

  func testNeedsUserActionNotificationIsImmediatePrivateAndDeduplicated() {
    let manifest = makeBackgroundMigrationManifest(
      accountUuid: "sensitive-account",
      expectedRunId: "sensitive-run"
    )

    let first = BackgroundMigrationNotificationPolicy.needsUserActionPlan(
      for: manifest,
      alreadyNotified: false
    )

    XCTAssertEqual(first?.delivery, .immediate)
    XCTAssertFalse(first?.title.contains("sensitive-account") ?? true)
    XCTAssertFalse(first?.body.contains("sensitive-account") ?? true)
    XCTAssertFalse(first?.body.contains("sensitive-run") ?? true)
    XCTAssertNil(
      BackgroundMigrationNotificationPolicy.needsUserActionPlan(
        for: manifest,
        alreadyNotified: true
      )
    )
  }

  func testWatchdogCopyDoesNotExposeManifestIdentity() {
    let manifest = makeBackgroundMigrationManifest(
      accountUuid: "sensitive-account",
      expectedRunId: "sensitive-run"
    )

    let plan = BackgroundMigrationNotificationPolicy.watchdogPlan(
      for: manifest,
      now: Date(timeIntervalSince1970: 1_000),
      nextScheduledHeight: 1_100,
      observedHeight: 1_000
    )

    XCTAssertFalse(plan.title.contains("sensitive-account"))
    XCTAssertFalse(plan.body.contains("sensitive-account"))
    XCTAssertFalse(plan.body.contains("sensitive-run"))
  }

  func testRunnerReturnsNoWorkWithoutManifest() {
    let harness = BackgroundMigrationRunnerHarness(manifests: [])

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .noWork
    )
    XCTAssertEqual(harness.syncCount, 0)
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerRetriesWhenManifestKeychainIsTemporarilyUnavailable() {
    let harness = BackgroundMigrationRunnerHarness(
      manifests: [makeBackgroundMigrationManifest()]
    )
    harness.manifestsAccessible = false

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .temporarilyUnavailable
    )
    XCTAssertEqual(harness.syncCount, 0)
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerRunsSyncWithoutAdvancingInTheSameWake() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [
      makeNativeResult(action: .sync, chainTipHeight: 505, nextScheduledHeight: 500),
      makeNativeResult(action: .advance, chainTipHeight: 510, nextScheduledHeight: 500),
    ]

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .synced(nextHeight: 500, observedHeight: 510)
    )
    XCTAssertEqual(harness.events, ["inspect", "sync", "inspect"])
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerSyncsAWaitingWalletBeforeSchedulingTheNextWake() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [
      makeNativeResult(action: .wait, chainTipHeight: 400, nextScheduledHeight: 500),
      makeNativeResult(action: .wait, chainTipHeight: 450, nextScheduledHeight: 500),
    ]

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .synced(nextHeight: 500, observedHeight: 450)
    )
    XCTAssertEqual(harness.events, ["inspect", "sync", "inspect"])
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerAdvancesWithoutSyncingInTheSameWake() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .advance)]
    harness.nativeResult = makeNativeResult(
      action: .wait,
      chainTipHeight: 505,
      nextScheduledHeight: 510,
      broadcastedCount: 1
    )

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .advanced(nextHeight: 510, observedHeight: 505)
    )
    XCTAssertEqual(harness.events, ["inspect", "cycle"])
    XCTAssertEqual(harness.syncCount, 0)
  }

  func testRunnerSchedulesAQuickFollowUpWhileProofsRemain() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .advance)]
    harness.nativeResult = makeNativeResult(
      action: .advance,
      chainTipHeight: 500,
      nextScheduledHeight: 600
    )

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .preparing(nextHeight: 600, observedHeight: 500)
    )
    XCTAssertEqual(harness.events, ["inspect", "cycle"])
  }

  func testRunnerDeletesCredentialOnlyAfterComplete() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .complete)]

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .complete
    )
    XCTAssertEqual(harness.deleted, [manifest])
    XCTAssertEqual(harness.unblocked, [manifest])
  }

  func testRunnerPreservesCredentialWhenUserActionIsRequired() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .needsUserAction)]

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .needsUserAction
    )
    XCTAssertTrue(harness.deleted.isEmpty)
    XCTAssertEqual(harness.blocked, [manifest])
  }

  func testRunnerDoesNotRunCycleAfterSyncFailureOrCancellation() {
    let manifest = makeBackgroundMigrationManifest()
    let failed = BackgroundMigrationRunnerHarness(manifests: [manifest])
    failed.inspectionResults = [makeNativeResult(action: .sync)]
    failed.syncResult = 1
    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: failed.dependencies()),
      .failed
    )
    XCTAssertEqual(failed.cycleCount, 0)

    let cancelled = BackgroundMigrationRunnerHarness(manifests: [manifest])
    cancelled.cancelled = true
    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: cancelled.dependencies()),
      .cancelled
    )
    XCTAssertEqual(cancelled.syncCount, 0)
  }

  func testRunnerProcessesOnlyOneManifestPerWake() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.inspectedAccounts, ["account-a"])
    XCTAssertTrue(harness.syncedAccounts.isEmpty)
    XCTAssertEqual(harness.cycledAccounts, ["account-a"])
  }

  func testRunnerRotatesToTheAccountAfterTheLastAttemptedManifest() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])
    harness.lastAttemptedKey = first.storageKey

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.inspectedAccounts, ["account-b"])
    XCTAssertEqual(harness.savedAttemptedKeys, [second.storageKey])
  }

  func testRunnerKeepsRotatingAcrossConsecutiveMultiAccountWakes() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())
    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())
    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.inspectedAccounts, ["account-a", "account-b", "account-a"])
  }

  func testRunnerSkipsBlockedManifestOnLaterWake() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])
    harness.blockedKeys = [first.storageKey]

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.inspectedAccounts, ["account-b"])
  }

  func testRunnerBlocksStaleManifestAndAdvancesValidAccountInSameWake() {
    let stale = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let valid = makeBackgroundMigrationManifest(accountUuid: "account-b")
    try? FileManager.default.removeItem(atPath: stale.dbPath)
    let harness = BackgroundMigrationRunnerHarness(manifests: [stale, valid])

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.blocked, [stale])
    XCTAssertEqual(harness.inspectedAccounts, ["account-b"])
    XCTAssertEqual(harness.savedAttemptedKeys, [valid.storageKey])
  }

  func testRunnerPassesCancellationEpochToTheSelectedOperation() {
    let manifest = makeBackgroundMigrationManifest()
    let syncHarness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    syncHarness.cancelEpoch = 42
    syncHarness.inspectionResults = [
      makeNativeResult(action: .sync),
      makeNativeResult(action: .wait),
    ]

    _ = BackgroundMigrationRunner.runOnce(dependencies: syncHarness.dependencies())

    XCTAssertEqual(syncHarness.syncEpochs, [42])
    XCTAssertTrue(syncHarness.cycleEpochs.isEmpty)

    let cycleHarness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    cycleHarness.cancelEpoch = 43
    cycleHarness.inspectionResults = [makeNativeResult(action: .advance)]

    _ = BackgroundMigrationRunner.runOnce(dependencies: cycleHarness.dependencies())

    XCTAssertTrue(cycleHarness.syncEpochs.isEmpty)
    XCTAssertEqual(cycleHarness.cycleEpochs, [43])
  }

  func testRunnerTreatsInterruptedMigrationSyncAsCancellation() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .sync)]
    harness.syncResult = 5

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .cancelled
    )
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerDoesNotEnterCycleWhenCancellationArrivesAfterSync() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .sync)]
    harness.cancelAfterSync = true

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .cancelled
    )
    XCTAssertEqual(harness.syncCount, 1)
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerRevokesManifestRejectedByNativeAccountValidation() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.inspectionResults = [makeNativeResult(action: .revokeAuthorization)]

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .needsUserAction
    )
    XCTAssertEqual(harness.deleted, [manifest])
    XCTAssertEqual(harness.unblocked, [manifest])
  }

  func testReschedulePolicyRetriesExpirationButNotExplicitCancellation() {
    XCTAssertEqual(
      BackgroundMigrationReschedulePolicy.delay(
        after: .cancelled,
        runnableManifestCount: 1,
        cancelledByExpiration: true
      ),
      10 * 60
    )
    XCTAssertNil(
      BackgroundMigrationReschedulePolicy.delay(
        after: .cancelled,
        runnableManifestCount: 1,
        cancelledByExpiration: false
      )
    )
  }

  func testReschedulePolicyRetriesTemporarilyUnavailableKeychainWithoutManifestCount() {
    XCTAssertEqual(
      BackgroundMigrationReschedulePolicy.delay(
        after: .temporarilyUnavailable,
        runnableManifestCount: 0,
        cancelledByExpiration: false
      ),
      10 * 60
    )
  }

  func testReschedulePolicyQuicklyContinuesProofPreparation() {
    XCTAssertEqual(
      BackgroundMigrationReschedulePolicy.delay(
        after: .preparing(nextHeight: 600, observedHeight: 500),
        runnableManifestCount: 1,
        cancelledByExpiration: false
      ),
      60
    )
  }

  func testReschedulePolicyCapsWaitingAccountWhenAnotherAccountCanRun() {
    XCTAssertEqual(
      BackgroundMigrationReschedulePolicy.delay(
        after: .waiting(nextHeight: 1_000, observedHeight: 500),
        runnableManifestCount: 2,
        cancelledByExpiration: false
      ),
      2 * 60
    )
  }

  func testReschedulePolicyUsesTheRefreshedHeightAfterSync() {
    XCTAssertEqual(
      BackgroundMigrationReschedulePolicy.delay(
        after: .synced(nextHeight: 500, observedHeight: 505),
        runnableManifestCount: 1,
        cancelledByExpiration: false
      ),
      75
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

private final class BackgroundMigrationRunnerHarness {
  var manifests: [IronwoodMigrationBackgroundManifest]
  var manifestsAccessible = true
  var blockedKeys: Set<String> = []
  var lastAttemptedKey: String?
  var cancelEpoch: UInt64 = 0
  var syncResult: Int32 = 0
  var inspectionResults = [makeNativeResult(action: .advance)]
  var nativeResult = makeNativeResult(action: .wait)
  var cancelled = false
  var cancelAfterSync = false
  var syncCount = 0
  var cycleCount = 0
  var events: [String] = []
  var syncedAccounts: [String] = []
  var cycledAccounts: [String] = []
  var inspectedAccounts: [String] = []
  var deleted: [IronwoodMigrationBackgroundManifest] = []
  var blocked: [IronwoodMigrationBackgroundManifest] = []
  var unblocked: [IronwoodMigrationBackgroundManifest] = []
  var syncEpochs: [UInt64] = []
  var cycleEpochs: [UInt64] = []
  var savedAttemptedKeys: [String] = []

  init(manifests: [IronwoodMigrationBackgroundManifest]) {
    self.manifests = manifests
  }

  func dependencies() -> BackgroundMigrationRunnerDependencies {
    BackgroundMigrationRunnerDependencies(
      loadManifests: {
        self.manifestsAccessible ? self.manifests : nil
      },
      resolveManifest: { manifest in
        FileManager.default.fileExists(atPath: manifest.dbPath)
          ? manifest : nil
      },
      loadBlockedKeys: { self.blockedKeys },
      loadLastAttemptedKey: { self.lastAttemptedKey },
      saveLastAttemptedKey: {
        self.lastAttemptedKey = $0
        self.savedAttemptedKeys.append($0)
      },
      currentCancelEpoch: { self.cancelEpoch },
      inspect: { manifest in
        self.events.append("inspect")
        self.inspectedAccounts.append(manifest.accountUuid)
        return self.inspectionResults.count > 1
          ? self.inspectionResults.removeFirst()
          : self.inspectionResults[0]
      },
      runSync: { manifest, epoch in
        self.syncCount += 1
        self.events.append("sync")
        self.syncedAccounts.append(manifest.accountUuid)
        self.syncEpochs.append(epoch)
        if self.cancelAfterSync {
          self.cancelled = true
        }
        return self.syncResult
      },
      runCycle: { manifest, epoch in
        self.cycleCount += 1
        self.events.append("cycle")
        self.cycledAccounts.append(manifest.accountUuid)
        self.cycleEpochs.append(epoch)
        return self.nativeResult
      },
      deleteManifest: { self.deleted.append($0) },
      markBlocked: {
        self.blocked.append($0)
        self.blockedKeys.insert($0.storageKey)
      },
      removeBlocked: {
        self.unblocked.append($0)
        self.blockedKeys.remove($0.storageKey)
      },
      isCancelled: { self.cancelled }
    )
  }
}

private func makeBackgroundMigrationManifest(
  accountUuid: String = "account-1",
  expectedRunId: String? = "run-1"
) -> IronwoodMigrationBackgroundManifest {
  let support = try! resolveWalletSupportDirectory()
  let dbPath =
    support
    .appendingPathComponent("background-migration-test-\(accountUuid).db").path
  FileManager.default.createFile(atPath: dbPath, contents: Data())
  return IronwoodMigrationBackgroundManifest(
    version: 1,
    network: "regtest",
    accountUuid: accountUuid,
    dbPath: dbPath,
    lightwalletdUrl: "http://127.0.0.1:9067",
    credentialHex: String(repeating: "ab", count: 32),
    saltBase64: "AQIDBAUGBwgJCgsMDQ4PEA==",
    expectedRunId: expectedRunId
  )
}

private func makeNativeResult(
  returnCode: Int32 = 0,
  action: BackgroundMigrationNativeAction,
  chainTipHeight: UInt64 = 500,
  nextScheduledHeight: UInt64? = nil,
  broadcastedCount: UInt32 = 0
) -> BackgroundMigrationNativeResult {
  BackgroundMigrationNativeResult(
    returnCode: returnCode,
    action: action,
    cancelled: false,
    scannedHeight: chainTipHeight,
    chainTipHeight: chainTipHeight,
    nextScheduledHeight: nextScheduledHeight,
    broadcastedCount: broadcastedCount
  )
}
