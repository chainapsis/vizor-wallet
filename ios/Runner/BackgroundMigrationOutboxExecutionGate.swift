import Foundation

/// One wallet-wide admission gate for both foreground and background outbox
/// runners. A mutation blocks new runs immediately, then waits for the admitted
/// run to persist its response. It never cancels an in-flight SendTransaction.
final class BackgroundMigrationOutboxExecutionGate: @unchecked Sendable {
  static let shared = BackgroundMigrationOutboxExecutionGate()

  private let condition = NSCondition()
  private var running = false
  private var mutationLeases = Set<String>()

  var isPaused: Bool {
    condition.lock()
    defer { condition.unlock() }
    return !mutationLeases.isEmpty
  }

  func tryBeginRun() -> Bool {
    condition.lock()
    defer { condition.unlock() }
    guard !running && mutationLeases.isEmpty else { return false }
    running = true
    return true
  }

  func finishRun() {
    condition.lock()
    running = false
    condition.broadcast()
    condition.unlock()
  }

  /// Register on the calling thread before dispatching the blocking wait.
  /// Reusing a lease makes retries after a lost channel response idempotent.
  func pause(leaseId: String) {
    condition.lock()
    mutationLeases.insert(leaseId)
    condition.unlock()
  }

  /// Must run off the main thread and outside the runner's execution queue.
  func waitUntilIdle() {
    condition.lock()
    defer { condition.unlock() }
    while running { condition.wait() }
  }

  /// Successful account removal/reset also retires safety holds left by a
  /// failed stop. Call while holding a separate mutation lease, after revoking
  /// the corresponding outbox records. Other live mutation leases stay intact.
  func discardStopLeases(network: String? = nil, accountUuid: String? = nil) {
    let prefix: String
    if let network, let accountUuid {
      prefix = "stop:\(network):\(accountUuid):"
    } else {
      prefix = "stop:"
    }
    condition.lock()
    mutationLeases = mutationLeases.filter { !$0.hasPrefix(prefix) }
    condition.unlock()
  }

  /// Only the caller's lease is released; duplicate replies cannot release a
  /// different mutation. Returns whether all callers have finished.
  @discardableResult
  func resume(leaseId: String) -> Bool {
    condition.lock()
    defer { condition.unlock() }
    mutationLeases.remove(leaseId)
    return mutationLeases.isEmpty
  }
}
