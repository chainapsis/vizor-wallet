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
            let status = sharedDefault.string(forKey: context.attributes.prefixedKey("status")) ?? "Syncing..."
            let percentage = Double(sharedDefault.string(forKey: context.attributes.prefixedKey("percentage")) ?? "0") ?? 0
            let scannedHeight = sharedDefault.string(forKey: context.attributes.prefixedKey("scannedHeight")) ?? "0"
            let chainTipHeight = sharedDefault.string(forKey: context.attributes.prefixedKey("chainTipHeight")) ?? "0"

            VStack(alignment: .leading, spacing: 8) {
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

        } dynamicIsland: { context in
            let sharedDefault = UserDefaults(suiteName: appGroupId)!
            let percentage = Double(sharedDefault.string(forKey: context.attributes.prefixedKey("percentage")) ?? "0") ?? 0
            let status = sharedDefault.string(forKey: context.attributes.prefixedKey("status")) ?? "Syncing..."

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
    }
}
