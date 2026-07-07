import Foundation
import UserNotifications

/// The backend decides, when the app reports phone usage, whether the user is
/// interrupting a focus task. Its response carries a `focusReminder` payload; when
/// present we surface it as an immediate local notification. This mirrors the
/// `RestReminderNotifier` pattern used by the fitness feature — the app has no
/// remote-push (APNs) setup, so all reminders are delivered locally.
struct FocusReminderPayload: Decodable {
    /// `first` / `rest` (`none` is never sent, but we guard anyway).
    let level: String
    /// `focus` / `sleep` — what the user is interrupting.
    let kind: String?
    let title: String?
    let body: String?
    let focusTaskName: String?
    /// Position in the cadence, e.g. 2 of `maxCount` (3).
    let sequence: Int?
    let maxCount: Int?

    var isActionable: Bool {
        !level.isEmpty && level.lowercased() != "none"
    }
}

enum FocusReminderNotifier {
    private static let identifier = "focus.interruption.reminder"

    /// Ask for alert + sound permission. Safe to call repeatedly; the system only
    /// prompts once and returns the stored decision afterwards.
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Post the reminder immediately. Skips silently when the payload is `none`,
    /// when notifications are not authorized, or when there is nothing to show.
    static func present(_ payload: FocusReminderPayload) async {
        guard payload.isActionable else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            await requestAuthorization()
            let refreshed = await center.notificationSettings()
            guard refreshed.authorizationStatus == .authorized
                || refreshed.authorizationStatus == .provisional
                || refreshed.authorizationStatus == .ephemeral else { return }
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title?.isEmpty == false ? payload.title! : "专注提醒"
        if let body = payload.body, !body.isEmpty {
            content.body = body
        }
        content.sound = .default

        // Stable identifier so a newer reminder replaces the previous one rather
        // than stacking up during a heavily-interrupted focus session.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        try? await center.add(request)
    }
}
