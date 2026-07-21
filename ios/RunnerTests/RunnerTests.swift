import Flutter
@testable import Runner
import Security
import UIKit
import XCTest

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
      FreshInstallKeychainCleaner.servicesToClear[0]: errSecAuthFailed,
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

  func testRunnerReturnsNoWorkWithoutManifest() {
    let harness = BackgroundMigrationRunnerHarness(manifests: [])

    XCTAssertEqual(
      BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies()),
      .noWork
    )
    XCTAssertEqual(harness.syncCount, 0)
    XCTAssertEqual(harness.cycleCount, 0)
  }

  func testRunnerSyncsBeforeAdvancingOneCycle() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
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
    XCTAssertEqual(harness.events, ["sync", "cycle"])
  }

  func testRunnerDeletesCredentialOnlyAfterComplete() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.nativeResult = makeNativeResult(action: .complete)

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
    harness.nativeResult = makeNativeResult(action: .needsUserAction)

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

    XCTAssertEqual(harness.syncedAccounts, ["account-a"])
    XCTAssertEqual(harness.cycledAccounts, ["account-a"])
  }

  func testRunnerRotatesToTheAccountAfterTheLastAttemptedManifest() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])
    harness.lastAttemptedKey = first.storageKey

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.syncedAccounts, ["account-b"])
    XCTAssertEqual(harness.savedAttemptedKeys, [second.storageKey])
  }

  func testRunnerKeepsRotatingAcrossConsecutiveMultiAccountWakes() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())
    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())
    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.syncedAccounts, ["account-a", "account-b", "account-a"])
    XCTAssertEqual(harness.cycledAccounts, ["account-a", "account-b", "account-a"])
  }

  func testRunnerSkipsBlockedManifestOnLaterWake() {
    let first = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let second = makeBackgroundMigrationManifest(accountUuid: "account-b")
    let harness = BackgroundMigrationRunnerHarness(manifests: [first, second])
    harness.blockedKeys = [first.storageKey]

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.syncedAccounts, ["account-b"])
    XCTAssertEqual(harness.cycledAccounts, ["account-b"])
  }

  func testRunnerBlocksStaleManifestAndAdvancesValidAccountInSameWake() {
    let stale = makeBackgroundMigrationManifest(accountUuid: "account-a")
    let valid = makeBackgroundMigrationManifest(accountUuid: "account-b")
    try? FileManager.default.removeItem(atPath: stale.dbPath)
    let harness = BackgroundMigrationRunnerHarness(manifests: [stale, valid])

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.blocked, [stale])
    XCTAssertEqual(harness.syncedAccounts, ["account-b"])
    XCTAssertEqual(harness.cycledAccounts, ["account-b"])
    XCTAssertEqual(harness.savedAttemptedKeys, [valid.storageKey])
  }

  func testRunnerPassesOneCancellationEpochThroughSyncAndCycle() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
    harness.cancelEpoch = 42

    _ = BackgroundMigrationRunner.runOnce(dependencies: harness.dependencies())

    XCTAssertEqual(harness.syncEpochs, [42])
    XCTAssertEqual(harness.cycleEpochs, [42])
  }

  func testRunnerTreatsInterruptedMigrationSyncAsCancellation() {
    let manifest = makeBackgroundMigrationManifest()
    let harness = BackgroundMigrationRunnerHarness(manifests: [manifest])
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
    harness.nativeResult = makeNativeResult(action: .revokeAuthorization)

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
  var blockedKeys: Set<String> = []
  var lastAttemptedKey: String?
  var cancelEpoch: UInt64 = 0
  var syncResult: Int32 = 0
  var nativeResult = makeNativeResult(action: .wait)
  var cancelled = false
  var cancelAfterSync = false
  var syncCount = 0
  var cycleCount = 0
  var events: [String] = []
  var syncedAccounts: [String] = []
  var cycledAccounts: [String] = []
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
      loadManifests: { self.manifests },
      loadBlockedKeys: { self.blockedKeys },
      loadLastAttemptedKey: { self.lastAttemptedKey },
      saveLastAttemptedKey: {
        self.lastAttemptedKey = $0
        self.savedAttemptedKeys.append($0)
      },
      currentCancelEpoch: { self.cancelEpoch },
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
  let dbPath = support
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
