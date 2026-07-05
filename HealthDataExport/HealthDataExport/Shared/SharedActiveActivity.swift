import Foundation
import WidgetKit

/// The App Group shared between the watch app and its widget/complication.
enum AppGroup {
    static let identifier = "group.com.tengzx.HealthDataExport"

    /// Shared defaults backing the App Group container. Falls back to `.standard`
    /// if the entitlement is missing so callers never crash.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}

/// A minimal snapshot of the currently-running time-tracking activity, mirrored
/// from the watch app into the App Group container so the watch-face widget can
/// render it without touching the app's own state or the network.
struct SharedActiveActivity: Codable, Hashable {
    var name: String
    var startedAt: Date
    var colorHex: String
    var symbolName: String
}

/// Reads and writes the shared active-activity snapshot and nudges WidgetKit to
/// refresh the watch face whenever it changes.
enum SharedActivityStore {
    private static let key = "shared.activeActivity"

    /// Optional side-effect run after every write. The phone sets this to relay the
    /// change to the watch over WatchConnectivity; the watch leaves it unset (the
    /// watch is the *receiver*, so relaying back would loop).
    nonisolated(unsafe) static var onWrite: ((SharedActiveActivity?) -> Void)?

    static func read() -> SharedActiveActivity? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SharedActiveActivity.self, from: data)
    }

    /// Persist the running activity (or clear it with `nil`), reload the
    /// complication timelines, and relay the change (via `onWrite`). Use this for
    /// *local* user changes that should propagate to the other device.
    static func write(_ activity: SharedActiveActivity?) {
        writeSilently(activity)
        onWrite?(activity)
    }

    /// Persist + reload the complication WITHOUT relaying. Use this when applying a
    /// change that *arrived from* the other device, so it isn't echoed straight
    /// back (which would loop forever).
    static func writeSilently(_ activity: SharedActiveActivity?) {
        let defaults = AppGroup.defaults
        if let activity, let data = try? JSONEncoder().encode(activity) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
