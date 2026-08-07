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

/// Whether a wake that declined the Tor route must leave a replacement request
/// behind before it completes.
///
/// Starting the wake consumed the pending request, and nothing else arms one
/// until the user opens the app. Without a replacement, a device that reaches a
/// charger and an unmetered link an hour later gets no execution opportunity at
/// all, and already-signed items sit past the height they were scheduled for
/// until they have to be signed again.
///
/// The chain ends with the work rather than on a counter, because the reasons
/// for declining — battery, a metered or constrained link, a Tor client that did
/// not come up — all change on their own and none of them is evidence about the
/// next wake. What is permanent is having nothing left to do: no armed item, no
/// owed announcement, no preparation run to resume. A wake that the foreground
/// has taken over, or one on a wallet whose accounts are being mutated, also
/// stops here; those have an owner already.
///
/// `hasRunnableWork` comes last and is deferred. Answering it inspects the
/// preparation run, which opens the wallet database — the one thing a wake
/// that has just found `mutationQuiesced` set must not do, because the fence
/// that set it has already told Dart the wallet is free.
func ironwoodMigrationTorDeferredWakeShouldRearm(
  disposition: IronwoodMigrationOutboxWakeDisposition,
  mutationQuiesced: Bool,
  hasRunnableWork: @autoclosure () -> Bool
) -> Bool {
  disposition.shouldReschedule && !mutationQuiesced && hasRunnableWork()
}

/// How a wake that reached no network left its replacement.
enum IronwoodMigrationRearmOutcome: Equatable {
  /// There was nothing to arm — no armed item, no owed announcement, no
  /// preparation run to resume, or the work already has an owner.
  case nothingToArm
  /// The replacement was submitted.
  case armed
  /// The hold ran out while the submission was still in flight. The
  /// submission has not answered and has not failed.
  case stillArming
  /// The submission answered, and the answer was no.
  case refused
}

/// What the scheduler is told about a wake that reached no network.
///
/// Declining the route is the policy working, not a wake that failed, and
/// every sibling completion says so: `finishTorDeferredTask` always reports
/// success, and the guard in front of this one does too. This path did not,
/// for one reason: it holds the wake open while `schedule` waits on
/// `UNUserNotificationCenter.getNotificationSettings`, and at background
/// launch that call can outlast the hold. The hold expiring used to report
/// failure — for a replacement that lands moments later and is armed. Repeated
/// on exactly the route-and-battery combination this feature exists for, that
/// teaches `BGTaskScheduler` to stop scheduling the identifier the whole
/// re-arm chain depends on.
///
/// So the hold expiring reports what it observed, which is nothing: the
/// submission is still arming. A submission that actually came back refused is
/// the one outcome that still reports failure — there the wake really did end
/// with no replacement and nothing on the way.
func ironwoodMigrationWakeWithoutNetworkWorkSucceeded(
  _ outcome: IronwoodMigrationRearmOutcome
) -> Bool {
  switch outcome {
  case .nothingToArm, .armed, .stillArming:
    return true
  case .refused:
    return false
  }
}

/// Holds a wake open while its replacement is submitted, and completes it
/// exactly once with a status that reflects what actually happened.
///
/// The hold and the submission race by design — the submission must be filed
/// before `setTaskCompleted` returns, or iOS may suspend the process with
/// nothing armed, and the task must complete even if the submission callback
/// never fires. Whichever arrives first decides, and the loser is dropped;
/// what the winner reports is the whole of `ironwoodMigrationRearmOutcome`'s
/// job.
final class IronwoodMigrationRearmHold {
  private let latch = MigrationPreparationCompletionLatch()
  private let complete: (IronwoodMigrationRearmOutcome) -> Void

  init(complete: @escaping (IronwoodMigrationRearmOutcome) -> Void) {
    self.complete = complete
  }

  /// The hold's deadline passed before the submission answered.
  func holdExpired() {
    finish(.stillArming)
  }

  /// The submission answered.
  func submissionFinished(armed: Bool) {
    finish(armed ? .armed : .refused)
  }

  private func finish(_ outcome: IronwoodMigrationRearmOutcome) {
    guard latch.claim() else { return }
    complete(outcome)
  }
}

/// What a wake is still allowed to do, from the two flags that can take it away
/// from it.
///
/// Both inputs are wake-scoped: they describe the wake that set them, and a
/// wake clears them as it starts. Reading them before that clearing answers for
/// the previous wake — most damagingly as `.finishForegroundOnly`, which says
/// the foreground has taken this work over and stops the wake from arming a
/// replacement for work nobody has taken.
func ironwoodMigrationOutboxWakeDisposition(
  foregroundHandoffRequested: Bool,
  notificationWorkDisabled: Bool
) -> IronwoodMigrationOutboxWakeDisposition {
  foregroundHandoffRequested || notificationWorkDisabled
    ? .finishForegroundOnly
    : .continueBackgroundWork
}

/// Whether a wake may still start network work after a step it could not
/// interrupt.
///
/// Bringing Tor up blocks for tens of seconds and takes no cancellation
/// handle, so a wake can outlive that call but never stop it. Every path that
/// ends a wake — the system reclaiming it, the foreground taking it over, a
/// wallet mutation, a revoked notification permission — can land inside that
/// window and reach nothing.
///
/// So the state is read again on the far side. A wake the system has already
/// reclaimed may be suspended at any moment, and it broadcasts transactions:
/// suspension between lightwalletd accepting one and the outbox recording that
/// it did leaves an item that looks unsent and is not. The wake that stops here
/// instead still holds the one thing it can act on — the ability to leave a
/// replacement request behind before it completes.
/// `routeStillAffordable` belongs here for the same reason: the bring-up
/// samples power and metering before it starts and can then block for a minute,
/// so a charger pulled or a link that turned metered during it is a condition
/// the wake was admitted under and no longer meets.
///
/// `routeStillAffordable` comes last and is deferred, because answering it
/// samples power and the current path and costs up to a second. A wake the
/// cheap flags have already ended does not spend that second; it has only
/// seconds left, and they belong to the replacement it still owes.
func ironwoodMigrationOutboxWakeMayStartNetworkWork(
  expired: Bool,
  disposition: IronwoodMigrationOutboxWakeDisposition,
  mutationQuiesced: Bool,
  routeStillAffordable: @autoclosure () -> Bool
) -> Bool {
  !expired && !mutationQuiesced && disposition == .continueBackgroundWork
    && routeStillAffordable()
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

/// Confirms migration proof readiness straight from the wallet database.
///
/// The inspection is a plain FFI call, so it does not need the preparation task
/// machinery that only exists on iOS 26. That makes it the whole verification on
/// older supported versions, where background preparation never runs and this
/// notification is the only thing that brings the user back to continue the
/// migration. The iOS 26 continued task independently tracks already-executed
/// preparation transaction confirmations with lightwalletd queries; it does
/// not sync or make this proof-readiness decision.
enum IronwoodMigrationProofReadinessCheck {
  struct Scope {
    let batch: BackgroundMigrationOutboxBatch
    let manifest: IronwoodMigrationBackgroundManifest
  }

  static func scope(batchId: String) -> Scope? {
    guard
      let batch = try? BackgroundMigrationOutboxStore.shared.read().batches.first(
        where: { $0.batchId == batchId }
      ),
      let manifest = IronwoodMigrationBackgroundCredentialStore.loadAll()?.first(
        where: {
          $0.expectedRunId == batch.runId
            && $0.accountUuid == batch.accountUuid
            && $0.network == batch.network
        }
      )
    else {
      return nil
    }
    return Scope(batch: batch, manifest: manifest)
  }

  /// Returns whether the run's proof is ready, or `nil` when the inspection
  /// itself failed and readiness stays unknown.
  static func inspect(_ scope: Scope) -> Bool? {
    var ready = false
    let code = zcash_inspect_migration_proof_readiness(
      scope.manifest.dbPath,
      scope.manifest.network,
      scope.manifest.accountUuid,
      scope.batch.runId,
      &ready
    )
    return code == 0 ? ready : nil
  }

  /// Verification for versions without background preparation: inspect only,
  /// and record the readiness so the notification is not announced twice.
  static func verifyWithoutPreparation(batchId: String) -> Bool {
    guard let scope = scope(batchId: batchId), inspect(scope) == true else {
      return false
    }
    var matched = false
    guard
      (try? BackgroundMigrationOutboxStore.shared.update { snapshot in
        matched = snapshot.recordVerifiedProofReadiness(
          network: scope.batch.network,
          accountUuid: scope.batch.accountUuid,
          runId: scope.batch.runId,
          at: Date()
        )
      }) != nil
    else {
      return false
    }
    return matched
  }
}

final class BackgroundMigrationManager {
  static let shared = BackgroundMigrationManager()
  static let taskIdentifier = "com.keplr.vizor.ironwood-migration"

  /// How long a wake may be held open for its replacement submission.
  ///
  /// The hold exists so iOS cannot suspend the process between completing the
  /// task and filing the replacement. It has to stay short: the wake is being
  /// completed because it has nothing else to do, and a task that never
  /// completes is a worse outcome than one that completes unarmed.
  private static let rearmSubmissionTimeout: TimeInterval = 10

  /// Everything a wake does that can reach the wallet, and the fence a wallet
  /// mutation drains to establish that none of it is still running.
  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-migration.outbox",
    qos: .utility
  )

  /// The Tor bring-up, and only that.
  ///
  /// It is the one step of a wake that takes no cancellation handle — it can
  /// be outlived but never stopped — and a cold bootstrap holds for tens of
  /// seconds. Run on `queue` it made `quiesce` wait out a bootstrap before it
  /// could answer, which is a wallet-mutation fence blocking the accounts UI
  /// for up to a minute. It touches no wallet database, so the fence has
  /// nothing to establish about it and it belongs off the fence's queue.
  private let torBringUpQueue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-migration.tor-bring-up",
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

  private var isWakeExpired: Bool {
    stateLock.vizorWithLock { expired }
  }

  private var shouldRetryCancelledWake: Bool {
    isWakeExpired
  }

  private var isMutationQuiesced: Bool {
    stateLock.vizorWithLock { mutationQuiesced }
  }

  private var isNotificationWorkDisabled: Bool {
    stateLock.vizorWithLock { notificationAuthorization.isDisabled }
  }

  private var wakeDisposition: IronwoodMigrationOutboxWakeDisposition {
    ironwoodMigrationOutboxWakeDisposition(
      foregroundHandoffRequested: isForegroundHandoffRequested,
      notificationWorkDisabled: isNotificationWorkDisabled
    )
  }

  private var isForegroundHandoffRequested: Bool {
    stateLock.vizorWithLock { foregroundHandoffRequested }
  }

  /// Whether this wake is still worth spending its remaining window on.
  ///
  /// The same predicate the wake applies on the far side of the bring-up, with
  /// affordability supplied as established rather than re-sampled: on this side
  /// the launch gate has just answered it, and the bring-up is the only step
  /// that can invalidate the answer. Everything else it reads — the system
  /// reclaiming the wake, the foreground taking it over, a wallet mutation, a
  /// revoked permission — can already be true before a single byte is spent.
  private var wakeMaySpendTime: Bool {
    ironwoodMigrationOutboxWakeMayStartNetworkWork(
      expired: isWakeExpired,
      disposition: wakeDisposition,
      mutationQuiesced: isMutationQuiesced,
      routeStillAffordable: true
    )
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
      // Deliberately not `requiresExternalPower`, even though a Tor pass wants
      // a charger. The route is a setting the user can change after this
      // request is submitted, and the request keeps whatever it was built with:
      // a wake that turned direct would then wait for a charger it no longer
      // needs, holding signed work past the height it was scheduled for.
      // Both halves of the gate are checked when the pass runs instead.
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

  /// Establishes that no native work is touching the wallet before Dart
  /// mutates accounts, and blocks the caller's flow until it has.
  ///
  /// Close the gate, then drain, in that order. `stopActiveWork` sets
  /// `mutationQuiesced` and cancels whatever is running, so work that has not
  /// started yet refuses at its own gate; the `queue` barrier below then waits
  /// out whatever had already started. Everything that can reach the wallet
  /// runs on `queue`, which is what makes draining it sufficient.
  ///
  /// It is a real barrier and has to stay one. The thing that must never come
  /// back into it is the Tor bring-up: that is uninterruptible, has nothing to
  /// do with the wallet database, and runs on `torBringUpQueue` for exactly
  /// that reason. A wake caught mid-bring-up finds the gate closed when it
  /// hops back here and stops.
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
    // This wake may be a cold launch where Dart never applied the saved route,
    // and it broadcasts signed transactions. Declare the route before any
    // other native call so a path that still reaches lightwalletd fails closed
    // rather than putting a transaction on clearnet. Declaring samples nothing
    // and never bootstraps, so it costs the wake nothing to do it first.
    let routeIsTor = BackgroundNetworkRoute.declareBackgroundNetworkRoute()
    // The wake's own flags come next, before anything reads a disposition out
    // of them. `expired` and `foregroundHandoffRequested` describe the wake
    // that set them and are cleared only here, so an exit taken ahead of this
    // answers for a previous wake — a wake that ends up reading "the foreground
    // has taken this over" when nothing has, and declining to arm a
    // replacement because of it.
    //
    // A refusal here is a wake with an owner: the wallet is mid-mutation, whose
    // resume path arms the next wake, or notification permission is gone, which
    // stopped background migration deliberately. Neither wants a replacement.
    guard prepareForBackgroundWake() else {
      task.setTaskCompleted(success: true)
      return
    }
    // Installed as soon as the wake owns its own flags, and before the first
    // step that can hold it. Sampling power and the current path takes up to a
    // second, and the route-declined exit below holds the wake open across an
    // asynchronous submission; an expiry landing in either window reaches
    // nothing without this, and the process is killed with no replacement
    // filed. Setting `expired` costs a declined wake nothing: the exits that
    // arm a replacement deliberately do not consult it.
    task.expirationHandler = { [weak self] in
      self?.expire()
    }
    // On a Tor route the declaration is only half the answer: the wake also has
    // to have established that this device can afford Tor right now. Asking
    // here keeps an unaffordable wake from touching the outbox at all, and
    // costs nothing — this gate never bootstraps.
    guard BackgroundNetworkRoute.backgroundPassIsAllowed(
      routeIsTor: routeIsTor,
      passIsLive: { self.wakeMaySpendTime },
      isAffordable: BackgroundNetworkRoute.torBackgroundPassIsAffordable
    ) else {
      finishTorDeferredWake(task)
      return
    }
    startAuthorizationMonitoring()
    // Published before the bring-up below, not after it. Expiration, a
    // foreground handoff, and a wallet mutation all end a wake by cancelling
    // whatever token is published; a window with none leaves them nothing to
    // reach, and the work on the far side of it starts uncancelled.
    let cancellation = BackgroundMigrationCancellation()
    stateLock.vizorWithLock {
      activeCancellation = cancellation
    }
    torBringUpQueue.async { [weak self] in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      // Tor before the first query or broadcast. A cold bootstrap blocks for
      // tens of seconds, so it runs on a queue of its own rather than on the
      // notification-gate callback — and, just as deliberately, not on
      // `queue`.
      //
      // `queue` is the fence a wallet mutation waits behind: `quiesce` cancels
      // this wake and then drains `queue` to establish that nothing native is
      // still touching the wallet database. This step touches no database.
      // Running it on the fence queue made the fence wait out a bring-up it
      // has no reason to wait for — and one that, unlike every other step
      // here, ignores the cancellation `quiesce` just delivered — so the
      // accounts, uninstall and forgot-passcode screens blocked for up to a
      // minute behind a Tor bootstrap.
      //
      // A client that does not come up ready ends the wake the same way an
      // unaffordable one does: fail-closed, no network work, the run left to
      // the foreground.
      guard BackgroundNetworkRoute.allowsBackgroundNetworkWork(
        while: { self.wakeMaySpendTime }
      ) else {
        self.clearActiveCancellation()
        self.stopAuthorizationMonitoring()
        self.finishTorDeferredWake(task)
        return
      }
      // Back onto the fence queue for everything from here on, because
      // everything from here on can reach the wallet. A mutation that landed
      // during the bring-up is already past `quiesce` by now; what stops this
      // wake is the `mutationQuiesced` read in the gate below, which was set
      // before the fence released and is what every not-yet-started piece of
      // work checks.
      self.queue.async {
        // The bring-up above cannot be cancelled, only outlived, and it is
        // long enough to be outlived. Ask again before the first byte goes
        // out: the outbox is transport for already-signed transactions, so
        // entering it on a reclaimed wake risks suspension mid-broadcast, and
        // it would consume this execution opportunity without leaving a
        // replacement.
        guard ironwoodMigrationOutboxWakeMayStartNetworkWork(
          expired: self.isWakeExpired,
          disposition: self.wakeDisposition,
          mutationQuiesced: self.isMutationQuiesced,
          routeStillAffordable: BackgroundNetworkRoute
            .torBackgroundPassRemainsAffordable
        ) else {
          self.clearActiveCancellation()
          self.stopAuthorizationMonitoring()
          self.finishWakeWithoutNetworkWork(task)
          return
        }
        // This wake has established what a confirmation tracker that stood
        // down for the route is waiting on: a device that can carry it. The
        // tracker's own request type cannot hold that wait — the scheduler
        // starts it rather than scheduling it — so this is where it gets armed
        // again. Self-gating: it submits nothing unless a run is still waiting
        // for denomination confirmations, and it runs before the outbox so the
        // submission is not racing this wake's completion.
        if #available(iOS 26.0, *) {
          BackgroundMigrationPreparationManager.shared.start { _ in }
        }
        // This wake is a silent BGProcessingTask. It queries the chain tip,
        // broadcasts transactions that are already signed, and notifies — it
        // does not scan. The separate continued-processing task owns
        // denomination confirmation tracking and hands confirmed waves back to
        // the foreground.
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
        // Readiness cannot be established here without scanning, and this wake
        // does not scan. Reaching the anchor height is a chain-tip question, so
        // the runner marks the candidate from the observed height and the
        // notification tells the user to reopen the app, which is where the
        // sync and the proof belong. The announcement is recorded apart from a
        // verified one so it does not retire the batch.
        let runResult = BackgroundMigrationOutboxRunner.runOnce(
          cancellation: cancellation,
          requiresPreparationProofVerification: true
        )
        self.clearActiveCancellation()
        let announced = runResult.proofReady.flatMap {
          self.unverifiedProofReadyNotice(for: $0)
        }
        // This silent wake still cannot scan. If no continued task owns the
        // active preparation, notify once so foreground recovery can resume it.
        if #available(iOS 26.0, *) {
          BackgroundMigrationPreparationManager.shared
            .notifyPreparationNeedsForeground()
        }
        self.finishOutboxRun(
          BackgroundMigrationOutboxRunResult(
            transport: runResult.transport,
            proofReady: announced,
            broadcastComplete: runResult.broadcastComplete,
            transportAccountUuid: runResult.transportAccountUuid
          ),
          task: task,
          preparationResult: preparationResult
        )
      }
    }
  }

  private func finishOutboxRun(
    _ runResult: BackgroundMigrationOutboxRunResult,
    task: BGProcessingTask,
    preparationResult: BackgroundMigrationPreparationPassResult
  ) {
    guard wakeDisposition == .continueBackgroundWork else {
      finishForegroundOnly(task)
      return
    }
    finishWake(
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

  /// Completes a silent wake that must not reach the network: the saved route
  /// is Tor and this device cannot carry it right now — on battery, on a
  /// metered or constrained link, or with a Tor client that did not come up.
  ///
  /// It queries no chain tip and broadcasts nothing. Declining is the policy
  /// working rather than a wake that failed, but the outbox stays
  /// background-capable across the deferral: this wake arms the next one, so
  /// signed items are transported by the first wake that lands on a charger and
  /// an unmetered link instead of waiting for the user to open the app. The
  /// foreground remains the other continuation, not the only one.
  private func finishTorDeferredWake(_ task: BGProcessingTask) {
    // Free of network work, and the one thing this wake can still report: a
    // preparation run that needs the foreground for reasons of its own. The
    // quiescence and notification fences that gate every other wake apply
    // here unchanged.
    if #available(iOS 26.0, *),
      !isMutationQuiesced,
      wakeDisposition.shouldDeliverNotifications
    {
      BackgroundMigrationPreparationManager.shared
        .notifyPreparationNeedsForeground()
    }
    finishWakeWithoutNetworkWork(task)
  }

  /// Completes a wake that reached no network at all — refused before its
  /// first query, or interrupted before it — and leaves a replacement behind
  /// whenever work remains.
  ///
  /// Every reason a wake stops short of the network is temporary: battery, a
  /// metered or constrained link, a Tor client that did not come up, the
  /// system reclaiming the execution slot. None of them is evidence about the
  /// next wake, and none of them is a reason to strand items whose signatures
  /// expire by height. What is permanent is having nothing left to do.
  ///
  /// This is not an announcement path. Anything a wake owes the user is said
  /// by the caller before it gets here, because an interrupted wake has
  /// seconds, and the replacement is what those seconds are for.
  private func finishWakeWithoutNetworkWork(_ task: BGProcessingTask) {
    let report = { (outcome: IronwoodMigrationRearmOutcome) in
      task.setTaskCompleted(
        success: ironwoodMigrationWakeWithoutNetworkWorkSucceeded(outcome)
      )
    }
    guard ironwoodMigrationTorDeferredWakeShouldRearm(
      disposition: wakeDisposition,
      mutationQuiesced: isMutationQuiesced,
      hasRunnableWork: hasRunnableOutboxWork() || hasResumablePreparationWork()
    ) else {
      report(.nothingToArm)
      return
    }
    // The replacement goes in before the completion. `schedule` runs the
    // notification-gate status callback first, and once `setTaskCompleted`
    // returns iOS may suspend the process before the submit gets to run, which
    // would leave nothing armed — the failure this path exists to prevent.
    //
    // The delay is the outbox's own rolling cadence, not a longer wait for
    // conditions to change. `earliestBeginDate` is a floor the system reads as
    // "no earlier than", and it schedules these wakes when the device is idle
    // on power and Wi-Fi anyway, which is when a Tor route is affordable. A
    // longer floor would only push the wake past the moment the device plugs
    // in, and signed items expire by height.
    let hold = IronwoodMigrationRearmHold(complete: report)
    // The task must finish even if the schedule callback never fires; never
    // completing it is worse than an unarmed replacement. It reports
    // `.stillArming` rather than a failure: at background launch the gate
    // `schedule` waits on can outlast this hold, and the replacement it is
    // still submitting usually lands. A wake that declined for policy and has
    // its replacement on the way is not a failed execution opportunity, and
    // saying it was is how the identifier stops being scheduled.
    queue.asyncAfter(deadline: .now() + Self.rearmSubmissionTimeout) {
      hold.holdExpired()
    }
    schedule(
      earliestBeginDate: Date().addingTimeInterval(
        BackgroundMigrationOutboxCadence.rollingCheckInterval
      )
    ) { rescheduled in
      if !rescheduled {
        print("[BGMigration] wake without network work could not re-arm")
      }
      hold.submissionFinished(armed: rescheduled)
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
        }) || (batch.nextProofHeight != nil && batch.awaitsProofReadyAnnouncement)
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

  /// Records that this batch owes the height-only nudge, and returns it so the
  /// wake delivers it. A retry of an already-queued nudge passes straight
  /// through; a batch that was nudged before returns nil so it is not repeated.
  private func unverifiedProofReadyNotice(
    for candidate: BackgroundMigrationProofReadyMetadata
  ) -> BackgroundMigrationProofReadyMetadata? {
    if !candidate.verified { return candidate }
    // A build that verified readiness here could leave a verified announcement
    // queued. Nothing marks one any more, so deliver and acknowledge it through
    // the path that queued it — re-marking it as a nudge is refused, which
    // would strand the notification with no way to clear it.
    if let pending = (try? BackgroundMigrationOutboxStore.shared.read())?
      .pendingProofReadyNotification(),
      pending.batchId == candidate.batchId
    {
      return pending
    }
    var notice: BackgroundMigrationProofReadyMetadata?
    guard
      (try? BackgroundMigrationOutboxStore.shared.update { snapshot in
        notice = snapshot.markUnverifiedProofReadyNoticeIfNeeded(
          batchId: candidate.batchId,
          at: Date()
        )
      }) != nil
    else {
      return nil
    }
    return notice
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
            if proofReady.verified {
              try snapshot.acknowledgeProofReadyNotification(
                batchId: proofReady.batchId,
                at: Date()
              )
            } else {
              // Leaves proofReadyNotifiedAt nil on purpose, so the verified
              // announcement is still available once readiness holds.
              try snapshot.acknowledgeUnverifiedProofReadyNotice(
                batchId: proofReady.batchId,
                at: Date()
              )
            }
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
