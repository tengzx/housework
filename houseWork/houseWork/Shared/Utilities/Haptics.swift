//
//  Haptics.swift
//  houseWork
//
//  Lightweight haptic feedback helpers shared across buttons.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum Haptics {
#if os(iOS)
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
#else
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {}
#endif
}
