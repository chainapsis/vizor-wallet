//
//  SyncWidget.swift
//  SyncWidget
//
//  Created by JungHwan Yun on 3/31/26.
//

import WidgetKit
import SwiftUI

private let familiarAppGroupId = "group.com.keplr.vizor"
private let familiarProfilePictureIdKey = "familiar_widget_profile_picture_id"
private let familiarAccountNameKey = "familiar_widget_account_name"
private let familiarRevisionKey = "familiar_widget_revision"

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now, snapshot: .current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = SimpleEntry(date: .now, snapshot: .current())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshot: FamiliarSnapshot
}

struct FamiliarSnapshot {
    let profilePictureId: String
    let accountName: String
    let revision: Double

    var identity: String {
        "\(profilePictureId)-\(accountName)-\(revision)"
    }

    static let placeholder = FamiliarSnapshot(
        profilePictureId: "pfp-01",
        accountName: "Vizor",
        revision: 0
    )

    static func current() -> FamiliarSnapshot {
        let defaults = UserDefaults(suiteName: familiarAppGroupId)
        defaults?.synchronize()
        return FamiliarSnapshot(
            profilePictureId: defaults?.string(forKey: familiarProfilePictureIdKey) ?? "pfp-01",
            accountName: defaults?.string(forKey: familiarAccountNameKey) ?? "Vizor",
            revision: defaults?.double(forKey: familiarRevisionKey) ?? 0
        )
    }
}

struct SyncWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    var entry: Provider.Entry

    var body: some View {
        GeometryReader { proxy in
            FamiliarScene(
                snapshot: entry.snapshot,
                family: family,
                size: proxy.size
            )
        }
        .id(entry.snapshot.identity)
    }
}

private struct FamiliarScene: View {
    let snapshot: FamiliarSnapshot
    let family: WidgetFamily
    let size: CGSize

    private var accent: Color {
        FamiliarProfileAccent.color(for: snapshot.profilePictureId)
    }

    private var profileTitle: String {
        FamiliarProfileAccent.title(for: snapshot.profilePictureId)
    }

    var body: some View {
        ZStack {
            FamiliarBackdrop(accent: accent, family: family)
                .frame(width: size.width, height: size.height)

            RadialGradient(
                colors: [accent.opacity(0.34), Color.clear],
                center: .center,
                startRadius: 4,
                endRadius: avatarGlowRadius
            )
            .blendMode(.screen)

            FamiliarAvatar(
                profilePictureId: snapshot.profilePictureId,
                accent: accent,
                family: family
            )
            .position(x: avatarX, y: avatarY)

            VStack(spacing: 0) {
                Spacer()

                if family == .systemLarge {
                    FamiliarQuestStrip(title: profileTitle, accent: accent)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }

                FamiliarNameplate(
                    accountName: snapshot.accountName,
                    title: profileTitle,
                    accent: accent,
                    family: family
                )
                .padding(.horizontal, chromeInset)
                .padding(.bottom, chromeInset)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: family == .systemLarge ? 5 : 4)
                .opacity(0.92)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.88), Color(red: 0.90, green: 0.72, blue: 0.42).opacity(0.50)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: family == .systemLarge ? 3 : 2
                )
                .padding(1)
        }
        .clipped()
    }

    private var chromeInset: CGFloat {
        switch family {
        case .systemLarge:
            return 16
        case .systemMedium:
            return 12
        default:
            return 9
        }
    }

    private var avatarX: CGFloat {
        switch family {
        case .systemMedium:
            return size.width * 0.50
        case .systemLarge:
            return size.width * 0.50
        default:
            return size.width * 0.52
        }
    }

    private var avatarY: CGFloat {
        switch family {
        case .systemSmall:
            return size.height * 0.48
        case .systemMedium:
            return size.height * 0.45
        case .systemLarge:
            return size.height * 0.44
        default:
            return size.height * 0.60
        }
    }

    private var avatarGlowRadius: CGFloat {
        switch family {
        case .systemLarge:
            return 170
        case .systemMedium:
            return 118
        default:
            return 86
        }
    }
}

private struct FamiliarBackdrop: View {
    let accent: Color
    let family: WidgetFamily

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.09),
                    Color(red: 0.15, green: 0.13, blue: 0.10),
                    Color(red: 0.04, green: 0.05, blue: 0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(accent.opacity(0.13))
                .frame(width: bandWidth)
                .rotationEffect(.degrees(-22))
                .offset(x: bandOffset)

            Circle()
                .fill(Color(red: 0.88, green: 0.68, blue: 0.38).opacity(0.09))
                .frame(width: haloSize, height: haloSize)
                .blur(radius: 10)

            RoundedRectangle(cornerRadius: family == .systemSmall ? 18 : 24, style: .continuous)
                .stroke(Color(red: 0.84, green: 0.68, blue: 0.42).opacity(0.18), lineWidth: 1)
                .padding(family == .systemLarge ? 14 : 10)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.36),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    FamiliarCornerMark(accent: accent)
                    Spacer()
                    FamiliarCornerMark(accent: accent)
                }
                Spacer()
            }
            .padding(family == .systemLarge ? 18 : 12)
        }
        .clipped()
    }

    private var bandWidth: CGFloat {
        family == .systemLarge ? 92 : 58
    }

    private var bandOffset: CGFloat {
        family == .systemMedium ? 108 : 54
    }

    private var haloSize: CGFloat {
        family == .systemLarge ? 230 : 156
    }
}

private struct FamiliarCornerMark: View {
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(accent.opacity(0.70))
            .frame(width: 7, height: 7)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color(red: 0.88, green: 0.70, blue: 0.42).opacity(0.55), lineWidth: 1)
            }
            .rotationEffect(.degrees(45))
    }
}

private struct FamiliarAvatar: View {
    let profilePictureId: String
    let accent: Color
    let family: WidgetFamily

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.13),
                            Color(red: 0.04, green: 0.05, blue: 0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color(red: 0.91, green: 0.72, blue: 0.43).opacity(0.58), lineWidth: ringWidth + 2)
            Circle()
                .stroke(accent.opacity(0.88), lineWidth: ringWidth)
                .padding(ringWidth + 3)
            Image(FamiliarProfileAccent.assetName(for: profilePictureId))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .padding(imagePadding)
        }
        .frame(width: side, height: side)
        .shadow(color: Color.black.opacity(0.42), radius: 8, x: 0, y: 5)
        .shadow(color: accent.opacity(0.30), radius: 12, x: 0, y: 0)
    }

    private var side: CGFloat {
        switch family {
        case .systemLarge:
            return 196
        case .systemMedium:
            return 136
        default:
            return 104
        }
    }

    private var ringWidth: CGFloat {
        family == .systemSmall ? 2 : 3
    }

    private var imagePadding: CGFloat {
        switch family {
        case .systemLarge:
            return 18
        case .systemMedium:
            return 12
        default:
            return 10
        }
    }
}

private struct FamiliarProfileGem: View {
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.10).opacity(0.82))
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(45))
        }
        .frame(width: 18, height: 18)
    }
}

private struct FamiliarNameplate: View {
    let accountName: String
    let title: String
    let accent: Color
    let family: WidgetFamily

    var body: some View {
        HStack(spacing: family == .systemSmall ? 7 : 9) {
            FamiliarProfileGem(accent: accent)
                .frame(width: gemSize, height: gemSize)

            VStack(alignment: .leading, spacing: family == .systemSmall ? 0 : 1) {
                Text(accountName)
                    .font(.system(size: accountFontSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.94, green: 0.86, blue: 0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
                if family != .systemSmall {
                    Text(title.uppercased())
                        .font(.system(size: 8.5, weight: .black, design: .monospaced))
                        .foregroundStyle(accent.opacity(0.92))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, family == .systemLarge ? 12 : 9)
        .padding(.vertical, family == .systemSmall ? 6 : 7)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.86))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(red: 0.86, green: 0.68, blue: 0.42).opacity(0.42), lineWidth: 1.2)
                Rectangle()
                    .fill(accent.opacity(0.78))
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: Color.black.opacity(0.32), radius: 6, x: 0, y: 3)
    }

    private var gemSize: CGFloat {
        family == .systemSmall ? 16 : 18
    }

    private var accountFontSize: CGFloat {
        switch family {
        case .systemLarge:
            return 17
        case .systemMedium:
            return 14
        default:
            return 12
        }
    }
}

private struct FamiliarRune: View {
    let accent: Color
    let family: WidgetFamily

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.04, green: 0.05, blue: 0.06).opacity(0.58))
            Circle()
                .stroke(accent.opacity(0.82), lineWidth: family == .systemSmall ? 2 : 3)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.95))
                .frame(width: side * 0.24, height: side * 0.24)
                .rotationEffect(.degrees(45))
            Rectangle()
                .fill(Color(red: 0.88, green: 0.72, blue: 0.42).opacity(0.86))
                .frame(width: side * 0.08, height: side * 0.44)
        }
        .frame(width: side, height: side)
        .shadow(color: accent.opacity(0.34), radius: 7, x: 0, y: 0)
    }

    private var side: CGFloat {
        switch family {
        case .systemLarge:
            return 54
        case .systemMedium:
            return 42
        default:
            return 31
        }
    }
}

private struct FamiliarQuestStrip: View {
    let title: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text("FAMILIAR")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.91, green: 0.78, blue: 0.52))
            Rectangle()
                .fill(accent.opacity(0.78))
                .frame(height: 2)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(red: 0.04, green: 0.05, blue: 0.06).opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private enum FamiliarProfileAccent {
    private static func suffix(for profilePictureId: String) -> Int {
        let rawSuffix = Int(profilePictureId.split(separator: "-").last ?? "1") ?? 1
        return max(1, min(15, rawSuffix))
    }

    static func assetName(for profilePictureId: String) -> String {
        let suffix = suffix(for: profilePictureId)
        return suffix < 10 ? "profile_picture_0\(suffix)" : "profile_picture_\(suffix)"
    }

    static func color(for profilePictureId: String) -> Color {
        let suffix = suffix(for: profilePictureId)
        switch (suffix - 1) % 6 {
        case 0:
            return Color(red: 0.18, green: 0.86, blue: 0.76)
        case 1:
            return Color(red: 0.93, green: 0.63, blue: 0.28)
        case 2:
            return Color(red: 0.73, green: 0.55, blue: 0.96)
        case 3:
            return Color(red: 0.87, green: 0.38, blue: 0.34)
        case 4:
            return Color(red: 0.45, green: 0.76, blue: 0.96)
        default:
            return Color(red: 0.63, green: 0.84, blue: 0.42)
        }
    }

    static func title(for profilePictureId: String) -> String {
        let suffix = suffix(for: profilePictureId)
        let titles = [
            "Knight",
            "Viking",
            "Samurai",
            "Monarch",
            "Iron Helm",
            "Ronin",
            "Skull Knight",
            "Seer",
            "Berserker",
            "Rogue",
            "Mage",
            "Masked Cat",
            "Warden",
            "Bronze Helm",
            "Fish Knight",
        ]
        return titles[max(0, min(titles.count - 1, suffix - 1))]
    }
}

struct SyncWidget: Widget {
    let kind: String = "SyncWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                SyncWidgetEntryView(entry: entry)
                    .containerBackground(Color.black, for: .widget)
            } else {
                SyncWidgetEntryView(entry: entry)
                    .background(Color.black)
            }
        }
        .configurationDisplayName("Vizor Familiar")
        .description("A pocket familiar for your Vizor wallet.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    SyncWidget()
} timeline: {
    SimpleEntry(date: .now, snapshot: .placeholder)
}
