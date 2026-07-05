import WidgetKit
import SwiftUI

// MARK: - Timeline

struct ActiveActivityEntry: TimelineEntry {
    let date: Date
    let activity: SharedActiveActivity?
}

struct ActiveActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveActivityEntry {
        ActiveActivityEntry(
            date: .now,
            activity: SharedActiveActivity(
                name: "写代码",
                startedAt: .now,
                colorHex: "FF7847",
                symbolName: "chevron.left.forwardslash.chevron.right"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveActivityEntry) -> Void) {
        completion(ActiveActivityEntry(date: .now, activity: SharedActivityStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveActivityEntry>) -> Void) {
        // The elapsed time renders itself via `Text(_, style: .timer)`, so a single
        // entry is enough. The app calls `WidgetCenter.reloadAllTimelines()` when the
        // activity changes for an immediate update — but watchOS budget-throttles
        // complication reloads, so relying on that alone can leave the face frozen on
        // a stale snapshot while the App Group already holds the truth. Ask WidgetKit
        // to refresh periodically as a safety net: each refresh re-reads the App Group
        // and self-heals a missed reload.
        let entry = ActiveActivityEntry(date: .now, activity: SharedActivityStore.read())
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Views

/// Deep link opened when the complication is tapped — routes the watch app to the
/// time-tracker (the in-progress screen).
private let openTimeTrackerURL = URL(string: "zhixing://time")

struct ActiveActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActiveActivityEntry

    var body: some View {
        content
            .widgetURL(openTimeTrackerURL)
            .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            circular
        default:
            rectangular
        }
    }

    private var tint: Color {
        Color(hex: entry.activity?.colorHex ?? "8A8F9C")
    }

    // Small round face slot: an accentable ring with the activity's glyph.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.activity?.symbolName ?? "clock.badge.questionmark")
                .font(.system(size: 17, weight: .semibold))
                .widgetAccentable()
        }
    }

    // Wide rectangular slot: status + name + a live counting-up timer.
    @ViewBuilder
    private var rectangular: some View {
        if let activity = entry.activity {
            HStack(spacing: 8) {
                Image(systemName: activity.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text("进行中")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(activity.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(activity.startedAt, style: .timer)
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .widgetAccentable()
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("时间记录")
                        .font(.system(size: 15, weight: .semibold))
                    Text("点按开始记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Widget

struct ActiveActivityWidget: Widget {
    let kind = "ActiveActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveActivityProvider()) { entry in
            ActiveActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("进行中")
        .description("在表盘上显示正在进行的时间记录")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct HealthDataExportWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ActiveActivityWidget()
    }
}
