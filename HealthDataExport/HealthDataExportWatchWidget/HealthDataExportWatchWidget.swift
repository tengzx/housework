import WidgetKit
import SwiftUI

private enum WidgetStrings {
    private static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let value: String = switch key {
        case "watch.widget.placeholder_name":
            isChinese ? "写代码" : "Coding"
        case "watch.widget.running":
            isChinese ? "进行中" : "Running"
        case "watch.widget.started_at":
            isChinese ? "开始于 %@" : "Started at %@"
        case "watch.widget.title":
            isChinese ? "时间记录" : "Time Tracking"
        case "watch.widget.empty_hint":
            isChinese ? "点按开始记录" : "Tap to start tracking"
        case "watch.widget.description":
            isChinese ? "在表盘上显示正在进行的时间记录" : "Show the current active time entry on the watch face"
        default:
            key
        }
        guard !args.isEmpty else { return value }
        return String(format: value, locale: Locale.current, arguments: args)
    }
}

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
                name: WidgetStrings.tr("watch.widget.placeholder_name"),
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

/// Formats the session start time as `HH:mm` for the "开始于" subtitle.
private let startedAtFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
}()

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

    // Wide rectangular slot: a status header, the icon beside the name + a live
    // counting-up timer, the start time, and an elapsed progress bar.
    @ViewBuilder
    private var rectangular: some View {
        if let activity = entry.activity {
            VStack(alignment: .leading, spacing: 2) {
                // Header: status dot + label, with a chevron hinting it's tappable.
                HStack(spacing: 5) {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                        .widgetAccentable()
                    Text(WidgetStrings.tr("watch.widget.running"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                // Main: activity glyph beside the name and the live timer.
                HStack(spacing: 7) {
                    Image(systemName: activity.symbolName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(tint)
                        .widgetAccentable()
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(activity.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(activity.startedAt, style: .timer)
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .widgetAccentable()
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                Text(WidgetStrings.tr("watch.widget.started_at", startedAtFormatter.string(from: activity.startedAt)))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                // Elapsed bar: fills toward a 2-hour reference window. It refreshes
                // with the timeline rather than live, so it's a coarse indicator.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * elapsedFraction(for: activity))
                            .widgetAccentable()
                    }
                }
                .frame(height: 4)
                .padding(.top, 1)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(WidgetStrings.tr("watch.widget.title"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(WidgetStrings.tr("watch.widget.empty_hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// How full the elapsed bar is: 0 → just started, 1 → running ≥ 2 hours.
    private func elapsedFraction(for activity: SharedActiveActivity) -> Double {
        let window: TimeInterval = 2 * 60 * 60
        let elapsed = Date().timeIntervalSince(activity.startedAt)
        return min(max(elapsed / window, 0.04), 1)
    }
}

// MARK: - Widget

struct ActiveActivityWidget: Widget {
    let kind = "ActiveActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveActivityProvider()) { entry in
            ActiveActivityWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.tr("watch.widget.running"))
        .description(WidgetStrings.tr("watch.widget.description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

@main
struct HealthDataExportWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ActiveActivityWidget()
    }
}
