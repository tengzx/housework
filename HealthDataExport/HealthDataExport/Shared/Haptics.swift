import SwiftUI
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// Centralized haptic feedback so every tappable control shares one consistent
/// tactile response across iOS and watchOS.
enum Haptics {
#if os(watchOS)
    /// Standard feedback for a control tap.
    static func tap() {
        WKInterfaceDevice.current().play(.click)
    }

    /// Feedback for success / error outcomes.
    static func notify(success: Bool) {
        WKInterfaceDevice.current().play(success ? .success : .failure)
    }
#else
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    /// Standard feedback for a button / control tap.
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .medium, .heavy, .rigid:
            generator = medium
        default:
            generator = light
        }
        generator.prepare()
        generator.impactOccurred()
    }

    /// Feedback for success / error outcomes.
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.prepare()
        notification.notificationOccurred(type)
    }
#endif
}

/// A drop-in replacement for the plain button style that keeps the plain
/// appearance (no chrome, inherited foreground) while adding a subtle press
/// scale and a haptic tap on press-down.
struct HapticButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}
