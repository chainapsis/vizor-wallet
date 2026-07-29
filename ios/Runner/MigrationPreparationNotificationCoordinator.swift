import Foundation
import UserNotifications

protocol MigrationPreparationNotificationCenter: AnyObject {
  func add(
    _ request: UNNotificationRequest,
    withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?
  )
  func removePendingNotificationRequests(withIdentifiers identifiers: [String])
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
  func getPendingNotificationRequests(
    completionHandler: @escaping @Sendable ([UNNotificationRequest]) -> Void
  )
}

extension UNUserNotificationCenter: MigrationPreparationNotificationCenter {}

enum MigrationPreparationNotificationKind: String, Codable, Equatable {
  /// A confirmation wave finished on a healthy run. Nothing is wrong; the
  /// foreground app just has to reopen to sync and advance the next wave.
  case confirmedWaveReady
  case needsForegroundRecovery
  case terminalFailure

  fileprivate var priority: Int {
    switch self {
    case .confirmedWaveReady:
      return 0
    case .needsForegroundRecovery:
      return 1
    case .terminalFailure:
      return 2
    }
  }
}

struct MigrationPreparationNotificationEvent: Codable, Equatable {
  let scope: String
  let kind: MigrationPreparationNotificationKind
  let fingerprint: String

  /// Dedupe identity is per scope *and* kind on purpose. A healthy
  /// `confirmedWaveReady` fingerprint that was already accepted therefore
  /// cannot suppress a later `needsForegroundRecovery` or `terminalFailure`
  /// alert for the same run — the two carry different keys.
  fileprivate var key: String {
    "\(scope)|\(kind.rawValue)"
  }
}

struct MigrationPreparationNotificationSummary: Equatable {
  let events: [MigrationPreparationNotificationEvent]
  let accountCount: Int
  let highestPriority: MigrationPreparationNotificationKind
  let title: String
  let body: String
}

struct MigrationPreparationNotificationBatchState: Codable, Equatable {
  private(set) var pendingEvents: [String: MigrationPreparationNotificationEvent] = [:]
  private(set) var acceptedFingerprints: [String: String] = [:]
  var batchDeadline: Date?

  @discardableResult
  mutating func enqueue(
    _ event: MigrationPreparationNotificationEvent
  ) -> Bool {
    if acceptedFingerprints[event.key] == event.fingerprint {
      return false
    }
    if pendingEvents[event.key] == event {
      return false
    }
    pendingEvents[event.key] = event
    return true
  }

  mutating func markAccepted(
    _ events: [MigrationPreparationNotificationEvent]
  ) {
    for event in events {
      acceptedFingerprints[event.key] = event.fingerprint
    }
  }

  mutating func resolve(scope: String) {
    pendingEvents = pendingEvents.filter { $0.value.scope != scope }
    acceptedFingerprints = acceptedFingerprints.filter {
      $0.key != scope && !$0.key.hasPrefix("\(scope)|")
    }
    // Resolving one scope starts a new boundary for any scopes that remain.
    // Do not let an expired aggregation deadline clear those other accounts
    // when the coordinator immediately checks for batch expiry.
    batchDeadline = nil
  }

  /// Drops every scope outside `scopes`.
  ///
  /// Returns whether the pending set actually changed, so the coordinator can
  /// tell "nothing to do" from "the scheduled alert now overstates what is
  /// wrong" and only reschedule in the second case.
  @discardableResult
  mutating func retain(scopes: Set<String>) -> Bool {
    let previousPendingEvents = pendingEvents
    pendingEvents = pendingEvents.filter {
      scopes.contains($0.value.scope)
    }
    acceptedFingerprints = acceptedFingerprints.filter { entry in
      scopes.contains(where: {
        entry.key == $0 || entry.key.hasPrefix("\($0)|")
      })
    }
    if pendingEvents.isEmpty {
      batchDeadline = nil
    }
    return pendingEvents != previousPendingEvents
  }

  @discardableResult
  mutating func expireBatchIfNeeded(now: Date) -> Bool {
    guard let batchDeadline, batchDeadline <= now else { return false }
    beginNewBatch()
    return true
  }

  mutating func beginNewBatch() {
    pendingEvents.removeAll()
    batchDeadline = nil
  }

  mutating func reset() {
    pendingEvents.removeAll()
    acceptedFingerprints.removeAll()
    batchDeadline = nil
  }

  var summary: MigrationPreparationNotificationSummary? {
    let events = pendingEvents.values.sorted {
      if $0.scope == $1.scope {
        return $0.kind.rawValue < $1.kind.rawValue
      }
      return $0.scope < $1.scope
    }
    guard
      let highestPriority = events.map(\.kind).max(by: {
        $0.priority < $1.priority
      })
    else {
      return nil
    }
    let accountCount = Set(events.map(\.scope)).count
    let title: String
    let body: String
    if accountCount == 1 {
      switch highestPriority {
      case .confirmedWaveReady:
        title = "Preparation transactions confirmed"
        body = "Open Vizor to start the next step."
      case .needsForegroundRecovery, .terminalFailure:
        title = "Migration needs attention"
        body = "Open Vizor to continue."
      }
    } else {
      switch highestPriority {
      case .confirmedWaveReady:
        title = "Migration preparation updates"
        body =
          "\(accountCount) accounts are ready for the next step. Open Vizor to continue."
      case .needsForegroundRecovery, .terminalFailure:
        title = "Migration updates"
        body =
          "\(accountCount) accounts need attention. Open Vizor to continue."
      }
    }
    return MigrationPreparationNotificationSummary(
      events: events,
      accountCount: accountCount,
      highestPriority: highestPriority,
      title: title,
      body: body
    )
  }
}

final class MigrationPreparationNotificationCoordinator: @unchecked Sendable {
  static let shared = MigrationPreparationNotificationCoordinator()

  static let summaryIdentifier =
    "com.keplr.vizor.ironwood-preparation.summary"
  private static let stateKey =
    "ironwoodMigrationPreparationNotificationBatchState"
  private static let aggregationWindow: TimeInterval = 30

  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-preparation.notifications"
  )
  private let center: MigrationPreparationNotificationCenter
  private let defaults: UserDefaults
  private var state: MigrationPreparationNotificationBatchState
  private var submissionGeneration: UInt64 = 0

  init(
    center: MigrationPreparationNotificationCenter =
      UNUserNotificationCenter.current(),
    defaults: UserDefaults = .standard
  ) {
    self.center = center
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.stateKey),
      let decoded = try? JSONDecoder().decode(
        MigrationPreparationNotificationBatchState.self,
        from: data
      )
    {
      state = decoded
    } else {
      state = MigrationPreparationNotificationBatchState()
    }
  }

  func enqueue(
    _ event: MigrationPreparationNotificationEvent
  ) {
    enqueue([event])
  }

  func enqueue(
    _ events: [MigrationPreparationNotificationEvent]
  ) {
    enqueue(events) { _ in }
  }

  func enqueue(
    _ events: [MigrationPreparationNotificationEvent],
    completion: @escaping (Bool) -> Void
  ) {
    guard !events.isEmpty else {
      completion(true)
      return
    }
    queue.async {
      let now = Date()
      self.state.expireBatchIfNeeded(now: now)
      var changed = false
      for event in events {
        changed = self.state.enqueue(event) || changed
      }
      guard changed else {
        let alreadySubmitted = events.allSatisfy {
          self.state.acceptedFingerprints[$0.key] == $0.fingerprint
        }
        if alreadySubmitted {
          completion(true)
        } else {
          // A previous submission may have failed or been superseded before
          // its callback persisted acceptance. Register the pending summary
          // again and make this caller wait for the new result.
          self.schedulePendingSummary(now: now, completion: completion)
        }
        return
      }
      if self.state.batchDeadline == nil {
        self.state.batchDeadline =
          now.addingTimeInterval(Self.aggregationWindow)
      }
      self.persistState()
      self.schedulePendingSummary(now: now, completion: completion)
    }
  }

  func resolve(scope: String) {
    queue.async {
      let now = Date()
      let existingDeadline = self.state.batchDeadline
      self.state.resolve(scope: scope)
      if self.state.summary != nil {
        self.state.batchDeadline = existingDeadline
      }
      self.persistState()
      if self.state.summary == nil {
        self.submissionGeneration &+= 1
        self.center.removePendingNotificationRequests(
          withIdentifiers: [Self.summaryIdentifier]
        )
        self.removeDeliveredSummary()
        return
      }
      self.center.getPendingNotificationRequests { requests in
        let pendingIdentifiers = requests.map(\.identifier)
        self.queue.async {
          guard self.state.summary != nil else { return }
          let summaryIsPending = pendingIdentifiers.contains(
            Self.summaryIdentifier
          )
          guard summaryIsPending else {
            // Preserve an already delivered aggregate. Reset the stale
            // aggregation deadline so another event cannot expire the scopes
            // that still need attention.
            self.state.batchDeadline = nil
            self.persistState()
            return
          }
          // The alert has not fired yet, so replace its stale A+B content with
          // the current unresolved summary while keeping the original deadline.
          self.schedulePendingSummary(now: now) { _ in }
        }
      }
    }
  }

  func retain(scopes: Set<String>) {
    queue.async {
      let now = Date()
      let existingDeadline = self.state.batchDeadline
      let changed = self.state.retain(scopes: scopes)
      if self.state.summary != nil {
        self.state.batchDeadline = existingDeadline
      }
      self.persistState()
      guard self.state.summary != nil else {
        self.submissionGeneration &+= 1
        self.center.removePendingNotificationRequests(
          withIdentifiers: [Self.summaryIdentifier]
        )
        self.removeDeliveredSummary()
        return
      }
      // Retention shrank the batch but left scopes behind. The request already
      // queued still carries the dropped account, so it would announce
      // "2 accounts need attention" after one of them is gone.
      guard changed else { return }
      self.center.getPendingNotificationRequests { requests in
        let pendingIdentifiers = requests.map(\.identifier)
        self.queue.async {
          guard self.state.summary != nil else { return }
          let summaryIsPending = pendingIdentifiers.contains(
            Self.summaryIdentifier
          )
          guard summaryIsPending else {
            // Preserve an already delivered aggregate. Reset the stale
            // aggregation deadline so another event cannot expire the scopes
            // that still need attention.
            self.state.batchDeadline = nil
            self.persistState()
            return
          }
          // The alert has not fired yet, so replace its stale content with the
          // retained summary while keeping the original deadline.
          self.schedulePendingSummary(now: now) { _ in }
        }
      }
    }
  }

  func clearDeliveredSummary() {
    queue.async {
      self.removeDeliveredSummary()
    }
  }

  func suppressCurrentBatch() {
    queue.async {
      if let summary = self.state.summary {
        self.state.markAccepted(summary.events)
      }
      self.state.beginNewBatch()
      self.submissionGeneration &+= 1
      self.persistState()
      self.center.removePendingNotificationRequests(
        withIdentifiers: [Self.summaryIdentifier]
      )
      self.removeDeliveredSummary()
    }
  }

  func clearAll() {
    queue.async {
      self.submissionGeneration &+= 1
      self.state.reset()
      self.persistState()
      self.center.removePendingNotificationRequests(
        withIdentifiers: [Self.summaryIdentifier]
      )
      self.removeDeliveredSummary()
    }
  }

  private func schedulePendingSummary(
    now: Date,
    completion: @escaping (Bool) -> Void
  ) {
    guard let summary = state.summary else {
      completion(true)
      return
    }
    let deadline =
      state.batchDeadline
      ?? now.addingTimeInterval(Self.aggregationWindow)
    state.batchDeadline = deadline
    submissionGeneration &+= 1
    let generation = submissionGeneration
    let content = UNMutableNotificationContent()
    content.title = summary.title
    content.body = summary.body
    content.sound = .default
    content.threadIdentifier = Self.summaryIdentifier
    let request = UNNotificationRequest(
      identifier: Self.summaryIdentifier,
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(
        timeInterval: max(1, deadline.timeIntervalSince(now)),
        repeats: false
      )
    )
    center.removePendingNotificationRequests(
      withIdentifiers: [Self.summaryIdentifier]
    )
    center.add(request) { error in
      self.queue.async {
        guard generation == self.submissionGeneration else {
          completion(false)
          return
        }
        if error == nil {
          self.state.markAccepted(summary.events)
          self.persistState()
        }
        completion(error == nil)
      }
    }
  }

  private func removeDeliveredSummary() {
    center.removeDeliveredNotifications(
      withIdentifiers: [Self.summaryIdentifier]
    )
  }

  private func persistState() {
    guard let data = try? JSONEncoder().encode(state) else { return }
    defaults.set(data, forKey: Self.stateKey)
  }
}
