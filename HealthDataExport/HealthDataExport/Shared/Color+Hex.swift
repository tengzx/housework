import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }

    /// Returns the color with its brightness reduced by `amount` (0…1), keeping
    /// hue and saturation. Used to give category-tinted glyphs a bit more depth.
    func darkened(by amount: CGFloat) -> Color {
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return self }
        return Color(hue: Double(h), saturation: Double(s), brightness: Double(max(0, b - amount)), opacity: Double(a))
    }

    /// RRGGBB hex string (no leading `#`), or nil if the color can't be resolved
    /// to sRGB components. Used to persist an auto-derived shortcut color.
    func toHex() -> String? {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        let clamp = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
