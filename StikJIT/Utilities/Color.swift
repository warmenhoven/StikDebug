//
//  Color.swift
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

import SwiftUI

extension Color {
    func toHex() -> String? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02lX%02lX%02lX",
                      lroundf(Float(r) * 255),
                      lroundf(Float(g) * 255),
                      lroundf(Float(b) * 255))
    }

    init?(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard raw.count == 6, let hexNumber = Int(raw, radix: 16) else { return nil }
        self.init(
            red:   CGFloat((hexNumber & 0xff0000) >> 16) / 255.0,
            green: CGFloat((hexNumber & 0x00ff00) >> 8)  / 255.0,
            blue:  CGFloat( hexNumber & 0x0000ff)         / 255.0
        )
    }

    // MARK: - Adaptive accent

    static func dynamicAccentColor(opacity: Double = 0.8) -> Color {
        let hex = UserDefaults.standard.string(forKey: "customAccentColor") ?? ""
        return (hex.isEmpty ? .blue : (Color(hex: hex) ?? .blue)).opacity(opacity)
    }

    // MARK: - Contrast helpers

    /// True when the colour's perceived luminance is below 50 %.
    func isDark() -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
    }

    /// Black or white, whichever reads better on top of `self`.
    func contrastText() -> Color { isDark() ? .white : .black }
    
    static var primaryBackground: Color {
        Color(UIColor.systemBackground)
    }
    
    static var secondaryText: Color {
        Color(UIColor.secondaryLabel)
    }
}

// MARK: - Array<Color> helpers (shared across the app)

extension Array where Element == Color {
    /// Guarantees at least two stops so `Gradient` is always valid.
    func ensureMinimumCount() -> [Color] {
        if isEmpty { return [.blue, .purple] }
        if count == 1 { return [self[0], self[0].opacity(0.6)] }
        return self
    }
}
