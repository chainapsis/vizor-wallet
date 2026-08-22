import BackgroundTasks
import Foundation

/// Owns the `com.keplr.vizor.voting-shares` BGProcessingTask.
///
/// This lane is silent: it posts no notifications and — unlike the Ironwood
/// migration manager — has no notification-authorization gating. It only
/// wakes, runs one outbox pass (status polls and resubmissions of exact staged
/// bytes), and re-arms itself while armed unconfirmed work remains.
final class BackgroundVotingShareManager {
  static let shared = BackgroundVotingShareManager()
  static let taskIdentifier = "com.keplr.vizor.voting-shares"
  /// Floor between wakes so an immediately-due outbox cannot request a wake
  /// in the past or thrash the scheduler.
  static let minimumWakeDelay: TimeInterval = 60
  /// Retry spacing when the encrypted store is temporarily unreadable
  /// (keychain locked before first unlock after reboot).
  static let unavailableRetryDelay: TimeInterval = 15 * 60

  private let queue = DispatchQueue(
    label: "com.keplr.vizor.voting-shares.outbox",
    qos: .utility
  )
  private let stateLock = NSLock()
  private var expired = false
  private var activeCancellation: BackgroundVotingShareCancellation?

  private init() {}

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

  /// Submits (replacing) the pending wake request at the outbox's preferred
  /// time: `max(now + minimumWakeDelay, nextActionableDate)`.
  func schedule(completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      let submitted = self.submitRequest(earliestBeginDate: self.preferredWakeDate())
      DispatchQueue.main.async { completion(submitted) }
    }
  }

  /// Cancels any active background run so the foreground owns the network
  /// from here. The pending wake request is left in place; a wake that fires
  /// later simply runs a normal pass against the then-current store.
  func handoffToForeground() {
    stateLock.votingShareWithLock {
      activeCancellation?.cancel()
      activeCancellation = nil
    }
  }

  /// Reschedules while runnable work remains; cancels the pending request
  /// otherwise. Completes with true when the request was cancelled.
  func cancelIfNoRunnableWork(completion: @escaping (Bool) -> Void) {
    queue.async { [weak self] in
      guard let self else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      if self.hasRunnableWork() {
        _ = self.submitRequest(earliestBeginDate: self.preferredWakeDate())
        DispatchQueue.main.async { completion(false) }
      } else {
        BGTaskScheduler.shared.cancel(
          taskRequestWithIdentifier: Self.taskIdentifier
        )
        DispatchQueue.main.async { completion(true) }
      }
    }
  }

  /// Stops any active run, drops the account's rounds and receipts, and then
  /// reschedules for the remaining accounts or cancels the pending request.
  func revokeAccount(
    network: String,
    accountUuid: String,
    completion: @escaping (Bool) -> Void
  ) {
    stateLock.votingShareWithLock {
      activeCancellation?.cancel()
      activeCancellation = nil
    }
    queue.async { [weak self] in
      let revoked =
        (try? BackgroundVotingShareOutboxStore.shared.update { snapshot in
          snapshot.revoke(network: network, accountUuid: accountUuid)
        }) != nil
      self?.rescheduleOrCancel()
      DispatchQueue.main.async { completion(revoked) }
    }
  }

  /// Stops any active run, removes the whole store, and cancels the pending
  /// wake request.
  func revokeAll(completion: @escaping (Bool) -> Void) {
    stateLock.votingShareWithLock {
      activeCancellation?.cancel()
      activeCancellation = nil
    }
    queue.async {
      let removed = (try? BackgroundVotingShareOutboxStore.shared.removeAll()) != nil
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      DispatchQueue.main.async { completion(removed) }
    }
  }

  #if DEBUG || targetEnvironment(simulator)
    func runOnceForTesting() -> BackgroundVotingShareOutboxRunResult {
      let cancellation = BackgroundVotingShareCancellation()
      stateLock.votingShareWithLock { activeCancellation = cancellation }
      defer { stateLock.votingShareWithLock { activeCancellation = nil } }
      return BackgroundVotingShareOutboxRunner.runOnce(cancellation: cancellation)
    }
  #endif

  private func handle(_ task: BGProcessingTask) {
    let cancellation = BackgroundVotingShareCancellation()
    stateLock.votingShareWithLock {
      expired = false
      activeCancellation?.cancel()
      activeCancellation = cancellation
    }
    task.expirationHandler = { [weak self] in
      // Expiration interrupts one execution opportunity; it is not evidence
      // anything failed. Stop cleanly, complete successfully, and re-arm.
      self?.stateLock.votingShareWithLock {
        self?.expired = true
      }
      cancellation.cancel()
    }
    queue.async { [weak self] in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      let runResult = BackgroundVotingShareOutboxRunner.runOnce(
        cancellation: cancellation
      )
      self.stateLock.votingShareWithLock {
        if self.activeCancellation === cancellation {
          self.activeCancellation = nil
        }
      }
      let wasExpired = self.stateLock.votingShareWithLock { self.expired }
      self.rearmAfterRun(runResult)
      task.setTaskCompleted(
        success: wasExpired || Self.runCompletedSuccessfully(runResult.transport)
      )
    }
  }

  private static func runCompletedSuccessfully(
    _ transport: BackgroundVotingShareTransportOutcome
  ) -> Bool {
    switch transport {
    case .noWork, .processed, .cancelled:
      return true
    case .temporarilyUnavailable, .failed:
      return false
    }
  }

  private func rearmAfterRun(_ runResult: BackgroundVotingShareOutboxRunResult) {
    if runResult.transport == .temporarilyUnavailable {
      _ = submitRequest(
        earliestBeginDate: Date().addingTimeInterval(Self.unavailableRetryDelay)
      )
      return
    }
    guard runResult.hasArmedUnconfirmedWork else {
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
      return
    }
    let floor = Date().addingTimeInterval(Self.minimumWakeDelay)
    let earliest = runResult.nextActionableDate.map { max(floor, $0) } ?? floor
    _ = submitRequest(earliestBeginDate: earliest)
  }

  private func rescheduleOrCancel() {
    if hasRunnableWork() {
      _ = submitRequest(earliestBeginDate: preferredWakeDate())
    } else {
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: Self.taskIdentifier
      )
    }
  }

  private func preferredWakeDate() -> Date {
    let now = Date()
    let floor = now.addingTimeInterval(Self.minimumWakeDelay)
    guard
      let next = (try? BackgroundVotingShareOutboxStore.shared.read())?
        .nextActionableDate(at: now)
    else {
      return floor
    }
    return max(floor, next)
  }

  private func submitRequest(earliestBeginDate: Date) -> Bool {
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
      print("[BGVotingShares] schedule failed: \(error)")
      return false
    }
  }

  private func hasRunnableWork() -> Bool {
    // An unreadable store (keychain locked) must not retire the schedule;
    // assume work remains so a later wake can look again.
    guard let snapshot = try? BackgroundVotingShareOutboxStore.shared.read() else {
      return true
    }
    return snapshot.hasArmedUnconfirmedWork
  }
}

extension NSLock {
  fileprivate func votingShareWithLock<T>(_ body: () -> T) -> T {
    lock()
    defer { unlock() }
    return body()
  }
}
