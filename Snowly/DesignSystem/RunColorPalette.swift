//
//  RunColorPalette.swift
//  Snowly
//
//  Shared run color sampling for route/map/chart consistency.
//

import SwiftUI
import UIKit

enum RunColorPalette {
    // Bright, clean, low-mud Apple-like rainbow stops.
    static let rainbow: [Color] = [
        Color(red: 1.00, green: 0.23, blue: 0.30), // vivid red
        Color(red: 1.00, green: 0.50, blue: 0.12), // punchy orange
        Color(red: 1.00, green: 0.82, blue: 0.16), // bright yellow
        Color(red: 0.33, green: 0.89, blue: 0.31), // fresh green
        Color(red: 0.00, green: 0.84, blue: 0.95), // electric cyan
        Color(red: 0.15, green: 0.47, blue: 1.00), // clean blue
        Color(red: 0.45, green: 0.34, blue: 0.98), // vivid indigo
        Color(red: 0.94, green: 0.24, blue: 0.74), // bright magenta
    ]

    /// Evenly samples the palette based on run count.
    static func color(forRunIndex index: Int, totalRuns: Int) -> Color {
        guard totalRuns > 1 else { return rainbow[0] }
        let clampedIndex = max(0, min(index, totalRuns - 1))
        let position = Double(clampedIndex) / Double(totalRuns - 1)
        return interpolatedColor(at: position)
    }

    private static func interpolatedColor(at position: Double) -> Color {
        let clamped = max(0, min(position, 1))
        let scaled = clamped * Double(rainbow.count - 1)
        let lower = Int(floor(scaled))
        let upper = min(lower + 1, rainbow.count - 1)
        let t = scaled - Double(lower)
        return mix(rainbow[lower], rainbow[upper], by: t)
    }

    private static func mix(_ a: Color, _ b: Color, by t: Double) -> Color {
        let clampedT = max(0, min(t, 1))
        let c1 = UIColor(a)
        let c2 = UIColor(b)
        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0

        guard c1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              c2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return a
        }

        return Color(
            red: Double(r1 + (r2 - r1) * CGFloat(clampedT)),
            green: Double(g1 + (g2 - g1) * CGFloat(clampedT)),
            blue: Double(b1 + (b2 - b1) * CGFloat(clampedT)),
            opacity: Double(a1 + (a2 - a1) * CGFloat(clampedT))
        )
    }
}
