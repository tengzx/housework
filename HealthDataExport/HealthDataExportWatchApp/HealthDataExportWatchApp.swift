import SwiftUI
import WatchKit

/// Activates WatchConnectivity at *process* launch. This is load-bearing: when
/// the phone sends a complication push (`transferCurrentComplicationUserInfo`),
/// watchOS launches this app in the BACKGROUND to deliver it — no view ever
/// appears. Activating the session only from a view's `.task` meant background
/// deliveries sat queued until the user opened the app, so the watch face
/// stayed stale after starting/stopping a time entry on the phone.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchAuthSync.shared.activate()
        }
    }
}

@main
struct HealthDataExportWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
