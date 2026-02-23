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

    static var primaryBackground: Color {
        Color(UIColor.systemBackground)
    }

    static var secondaryText: Color {
        Color(UIColor.secondaryLabel)
    }
}
