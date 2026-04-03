//
//  SyncWidgetLiveActivity.swift
//  SyncWidget
//

import ActivityKit
import SwiftUI
import WidgetKit

struct SyncWidgetLiveActivity: Widget {
    let appGroupId = "group.com.zcash.zcashWallet"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            // Lock Screen banner
            let sharedDefault = UserDefaults(suiteName: appGroupId)!
            let displayMode = sharedDefault.string(forKey: context.attributes.prefixedKey("displayMode")) ?? "sync"

            if displayMode == "txTrack" {
                txTrackBanner(context: context, defaults: sharedDefault)
            } else {
                syncBanner(context: context, defaults: sharedDefault)
            }

        } dynamicIsland: { context in
            let sharedDefault = UserDefaults(suiteName: appGroupId)!
            let displayMode = sharedDefault.string(forKey: context.attributes.prefixedKey("displayMode")) ?? "sync"

            if displayMode == "txTrack" {
                return txTrackIsland(context: context, defaults: sharedDefault)
            } else {
                return syncIsland(context: context, defaults: sharedDefault)
            }
        }
    }

    // MARK: - Sync UI

    private func syncBanner(context: ActivityViewContext<LiveActivitiesAppAttributes>, defaults: UserDefaults) -> some View {
        let percentage = Double(defaults.string(forKey: context.attributes.prefixedKey("percentage")) ?? "0") ?? 0
        let scannedHeight = defaults.string(forKey: context.attributes.prefixedKey("scannedHeight")) ?? "0"
        let chainTipHeight = defaults.string(forKey: context.attributes.prefixedKey("chainTipHeight")) ?? "0"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.yellow)
                Text("Zcash Sync")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.headline)
                    .foregroundColor(.yellow)
            }
            ProgressView(value: percentage)
                .tint(.yellow)
            Text("Block \(scannedHeight) / \(chainTipHeight)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.black)
    }

    private func syncIsland(context: ActivityViewContext<LiveActivitiesAppAttributes>, defaults: UserDefaults) -> DynamicIsland {
        let percentage = Double(defaults.string(forKey: context.attributes.prefixedKey("percentage")) ?? "0") ?? 0
        let status = defaults.string(forKey: context.attributes.prefixedKey("status")) ?? "Syncing..."

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.yellow)
            }
            DynamicIslandExpandedRegion(.trailing) {
                Text("\(Int(percentage * 100))%")
                    .font(.title2)
                    .foregroundColor(.yellow)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 4) {
                    ProgressView(value: percentage)
                        .tint(.yellow)
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        } compactLeading: {
            Image(systemName: "shield.checkered")
                .foregroundColor(.yellow)
        } compactTrailing: {
            Text("\(Int(percentage * 100))%")
                .font(.caption)
                .foregroundColor(.yellow)
        } minimal: {
            Image(systemName: "shield.checkered")
                .foregroundColor(.yellow)
        }
    }

    // MARK: - TX Tracking UI

    private func txTrackBanner(context: ActivityViewContext<LiveActivitiesAppAttributes>, defaults: UserDefaults) -> some View {
        let status = defaults.string(forKey: context.attributes.prefixedKey("status")) ?? "Tracking transactions"
        let txStatus = defaults.string(forKey: context.attributes.prefixedKey("txStatus")) ?? "pending"
        let isDone = txStatus == "done"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isDone ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .foregroundColor(isDone ? .green : .orange)
                Text("Zcash Transaction")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if !isDone {
                    ProgressView()
                        .tint(.orange)
                }
            }
            Text(status)
                .font(.subheadline)
                .foregroundColor(isDone ? .green : .orange)
        }
        .padding()
        .background(Color.black)
    }

    private func txTrackIsland(context: ActivityViewContext<LiveActivitiesAppAttributes>, defaults: UserDefaults) -> DynamicIsland {
        let status = defaults.string(forKey: context.attributes.prefixedKey("status")) ?? "Tracking"
        let txStatus = defaults.string(forKey: context.attributes.prefixedKey("txStatus")) ?? "pending"
        let isDone = txStatus == "done"

        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                    .foregroundColor(isDone ? .green : .orange)
            }
            DynamicIslandExpandedRegion(.trailing) {
                if !isDone {
                    ProgressView()
                        .tint(.orange)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(status)
                    .font(.caption)
                    .foregroundColor(isDone ? .green : .orange)
            }
        } compactLeading: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                .foregroundColor(isDone ? .green : .orange)
        } compactTrailing: {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                ProgressView()
                    .tint(.orange)
            }
        } minimal: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "clock.arrow.circlepath")
                .foregroundColor(isDone ? .green : .orange)
        }
    }
}
