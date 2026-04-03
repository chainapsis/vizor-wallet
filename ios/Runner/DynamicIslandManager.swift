import ActivityKit
import Foundation

/// Central manager for Live Activity / Dynamic Island.
/// Handles priority switching between sync progress and TX tracking.
@available(iOS 26.0, *)
class DynamicIslandManager {
    static let shared = DynamicIslandManager()

    enum DisplayMode: String {
        case idle
        case sync
        case txTrack
    }

    private(set) var displayMode: DisplayMode = .idle
    private var currentActivity: Activity<LiveActivitiesAppAttributes>?
    private let defaults = UserDefaults(suiteName: "group.com.zcash.zcashWallet")
    private var activityId: UUID?

    // Cache last sync progress for restoration after TX tracking
    private var lastSyncPercentage: Double = 0

    private init() {}

    // MARK: - Sync Progress

    func showSyncProgress(percentage: Double) {
        lastSyncPercentage = percentage

        // Always update UserDefaults so widget has latest data
        updateDefaults(
            displayMode: .sync,
            status: "Syncing...",
            percentage: percentage,
            txStatus: nil
        )

        // Only update Live Activity if TX tracking isn't active
        if displayMode == .txTrack { return }

        displayMode = .sync
        ensureActivityStarted()
        refreshActivity()
    }

    // MARK: - TX Tracking

    func showTxTracking(pendingCount: Int) {
        displayMode = .txTrack
        updateDefaults(
            displayMode: .txTrack,
            status: "Tracking \(pendingCount) transaction\(pendingCount == 1 ? "" : "s")",
            percentage: 0,
            txStatus: "pending"
        )
        ensureActivityStarted()
        refreshActivity()
    }

    func updateTxStatus(confirmed: Int, expired: Int, remaining: Int) {
        let parts: [String] = [
            confirmed > 0 ? "\(confirmed) confirmed" : nil,
            expired > 0 ? "\(expired) expired" : nil,
            remaining > 0 ? "\(remaining) pending" : nil,
        ].compactMap { $0 }

        let status = parts.joined(separator: ", ")
        updateDefaults(
            displayMode: .txTrack,
            status: status,
            percentage: nil,
            txStatus: remaining > 0 ? "pending" : "done"
        )
        refreshActivity()
    }

    func restoreSyncDisplay() {
        displayMode = .sync
        updateDefaults(
            displayMode: .sync,
            status: "Syncing...",
            percentage: lastSyncPercentage,
            txStatus: nil
        )
        refreshActivity()
    }

    func endActivity() {
        displayMode = .idle
        guard let activity = currentActivity else { return }
        let state = LiveActivitiesAppAttributes.ContentState(
            appGroupId: "group.com.zcash.zcashWallet"
        )
        Task {
            await activity.end(state, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        activityId = nil
    }

    // MARK: - Private

    private func ensureActivityStarted() {
        guard currentActivity == nil else { return }
        let id = UUID()
        activityId = id
        let attributes = LiveActivitiesAppAttributes(id: id)
        let state = LiveActivitiesAppAttributes.ContentState(
            appGroupId: "group.com.zcash.zcashWallet"
        )
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            print("[DI] Activity started: \(id)")
        } catch {
            print("[DI] Failed to start activity: \(error)")
        }
    }

    private func refreshActivity() {
        guard let activity = currentActivity else { return }
        let state = LiveActivitiesAppAttributes.ContentState(
            appGroupId: "group.com.zcash.zcashWallet"
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func updateDefaults(
        displayMode: DisplayMode,
        status: String?,
        percentage: Double?,
        txStatus: String?
    ) {
        guard let id = activityId ?? self.activityId else { return }
        let prefix = "\(id)_"
        defaults?.set(displayMode.rawValue, forKey: prefix + "displayMode")
        if let status { defaults?.set(status, forKey: prefix + "status") }
        if let percentage { defaults?.set(String(percentage), forKey: prefix + "percentage") }
        if let txStatus { defaults?.set(txStatus, forKey: prefix + "txStatus") }
    }
}
