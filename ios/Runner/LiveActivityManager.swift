import ActivityKit
import Foundation

/// Manages Live Activity (Dynamic Island) from Swift for background sync.
@available(iOS 16.1, *)
class LiveActivityManager {
    static let shared = LiveActivityManager()
    private let appGroupId = "group.com.zcash.zcashWallet"
    private var activityId: String?

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = LiveActivitiesAppAttributes()
        let state = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId)

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            activityId = activity.id

            // Set initial values in shared UserDefaults
            let defaults = UserDefaults(suiteName: appGroupId)!
            defaults.set("0.0", forKey: "\(activity.id)_percentage")
            defaults.set("0", forKey: "\(activity.id)_scannedHeight")
            defaults.set("0", forKey: "\(activity.id)_chainTipHeight")
            defaults.set("Starting sync...", forKey: "\(activity.id)_status")
        } catch {
            print("LiveActivityManager: failed to start: \(error)")
        }
    }

    func update(percentage: Double, scannedHeight: UInt64, chainTipHeight: UInt64) {
        guard let activityId = activityId else { return }

        let defaults = UserDefaults(suiteName: appGroupId)!
        defaults.set(String(percentage), forKey: "\(activityId)_percentage")
        defaults.set(String(scannedHeight), forKey: "\(activityId)_scannedHeight")
        defaults.set(String(chainTipHeight), forKey: "\(activityId)_chainTipHeight")
        defaults.set("Syncing \(Int(percentage * 100))%", forKey: "\(activityId)_status")

        // Trigger widget update by updating ContentState
        Task {
            for activity in Activity<LiveActivitiesAppAttributes>.activities {
                if activity.id == activityId {
                    let state = LiveActivitiesAppAttributes.ContentState(appGroupId: appGroupId)
                    await activity.update(.init(state: state, staleDate: nil))
                }
            }
        }
    }

    func stop() {
        Task {
            for activity in Activity<LiveActivitiesAppAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        activityId = nil
    }
}
