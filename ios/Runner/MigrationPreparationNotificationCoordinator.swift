import Foundation
import UserNotifications

enum MigrationPreparationNotificationKind: String, Codable, Equatable {
  case needsForegroundRecovery
  case terminalFailure

  fileprivate var priority: Int {
    switch self {
    case .needsForegroundRecovery:
      return 0
    case .terminalFailure:
      return 1
    }
  }
}

struct MigrationPreparationNotificationEvent: Codable, Equatable {
  let scope: String
  let kind: MigrationPreparationNotificationKind
  let fingerprint: String

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

  mutating func retain(scopes: Set<String>) {
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
      case .needsForegroundRecovery, .terminalFailure:
        title = "Migration needs attention"
        body = "Open Vizor to continue."
      }
    } else {
      title = "Migration updates"
      body =
        "\(accountCount) accounts need attention. Open Vizor to continue."
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

final class MigrationPreparationNotificationCoordinator {
  static let shared = MigrationPreparationNotificationCoordinator()

  static let summaryIdentifier =
    "com.keplr.vizor.ironwood-preparation.summary"
  private static let stateKey =
    "ironwoodMigrationPreparationNotificationBatchState"
  private static let aggregationWindow: TimeInterval = 30

  private let queue = DispatchQueue(
    label: "com.keplr.vizor.ironwood-preparation.notifications"
  )
  private let center: UNUserNotificationCenter
  private let defaults: UserDefaults
  private var state: MigrationPreparationNotificationBatchState
  private var submissionGeneration: UInt64 = 0

  private init(
    center: UNUserNotificationCenter = .current(),
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
    guard !events.isEmpty else { return }
    queue.async {
      let now = Date()
      self.state.expireBatchIfNeeded(now: now)
      var changed = false
      for event in events {
        changed = self.state.enqueue(event) || changed
      }
      guard changed else { return }
      if self.state.batchDeadline == nil {
        self.state.batchDeadline =
          now.addingTimeInterval(Self.aggregationWindow)
      }
      self.persistState()
      self.schedulePendingSummary(now: now)
    }
  }

  func resolve(scope: String) {
    queue.async {
      let now = Date()
      self.state.resolve(scope: scope)
      let expired = self.state.expireBatchIfNeeded(now: now)
      self.persistState()
      if expired || self.state.summary == nil {
        self.submissionGeneration &+= 1
        self.center.removePendingNotificationRequests(
          withIdentifiers: [Self.summaryIdentifier]
        )
        self.removeDeliveredSummary()
        return
      }
      // Keep the existing aggregate in place while another account still
      // needs attention. Replacing a delivered A+B summary with B would create
      // a second alert merely because A recovered.
    }
  }

  func retain(scopes: Set<String>) {
    queue.async {
      self.state.retain(scopes: scopes)
      self.persistState()
      guard self.state.summary == nil else { return }
      self.submissionGeneration &+= 1
      self.center.removePendingNotificationRequests(
        withIdentifiers: [Self.summaryIdentifier]
      )
      self.removeDeliveredSummary()
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

  private func schedulePendingSummary(now: Date) {
    guard let summary = state.summary else { return }
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
        guard generation == self.submissionGeneration else { return }
        if error == nil {
          self.state.markAccepted(summary.events)
          self.persistState()
        }
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
