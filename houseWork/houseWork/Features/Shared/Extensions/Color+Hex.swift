//
//  Color+Hex.swift
//  houseWork
//
//  Helpers to convert SwiftUI colors to/from hex strings for persistence.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Color {
    init?(hex: String) {
        var formatted = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if formatted.hasPrefix("#") {
            formatted.removeFirst()
        }
        
        guard formatted.count == 6 || formatted.count == 8 else { return nil }
        if formatted.count == 6 {
            formatted.append("FF")
        }
        
        var value: UInt64 = 0
        guard Scanner(string: formatted).scanHexInt64(&value) else { return nil }
        
        let r = Double((value & 0xFF000000) >> 24) / 255.0
        let g = Double((value & 0x00FF0000) >> 16) / 255.0
        let b = Double((value & 0x0000FF00) >> 8) / 255.0
        let a = Double(value & 0x000000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, opacity: a)
    }
    
    var hexString: String? {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(
            format: "#%02X%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255),
            Int(a * 255)
        )
        #else
        return nil
        #endif
    }
}
