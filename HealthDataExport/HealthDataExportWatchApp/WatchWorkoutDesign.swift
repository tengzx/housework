import SwiftUI

/// Shared visual language for the watch workout flow. Mirrors the dark, rounded
/// look of the existing time-tracker screens.
enum WK {
    static let bg = Color(hex: "0B0B0C")
    static let surface = Color(hex: "1C1C1E")
    static let line = Color(hex: "2C2C2E")
    static let muted = Color(hex: "8A8F9C")
    static let accent = Color(hex: "4B8CFF")
    static let green = Color(hex: "34C982")
    static let orange = Color(hex: "FF7847")
    static let red = Color(hex: "FF453A")
    static let heart = Color(hex: "FF3B30")

    /// Format a weight for display, dropping a trailing ".0".
    static func weightText(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        if kg == kg.rounded() { return "\(Int(kg)) kg" }
        return String(format: "%.1f kg", kg)
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
