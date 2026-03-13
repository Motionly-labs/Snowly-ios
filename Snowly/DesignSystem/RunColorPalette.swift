//
//  RunColorPalette.swift
//  Snowly
//
//  Shared run color sampling for route/map/chart consistency.
//

import SwiftUI
import UIKit

enum RunColorPalette {
    private struct Stop {
        let position: Double
        let color: Color
    }

    // Ordered "warm -> cool" ramp for run sequencing across map + charts.
    // This keeps ordering intuitive while preserving contrast on satellite imagery.
    private static let sequentialStops: [Stop] = [
        Stop(position: 0.00, color: ColorTokens.brandRed),
        Stop(position: 0.24, color: ColorTokens.brandWarmAmber),
        Stop(position: 0.50, color: Color(red: 0.22, green: 0.83, blue: 0.52)),
        Stop(position: 0.76, color: ColorTokens.brandIceBlue),
        Stop(position: 1.00, color: Color(red: 0.56, green: 0.43, blue: 0.96)),
    ]

    /// Returns the base color for a run index.
    /// Colors are sampled from a continuous, directional ramp to emphasize run order.
    static func color(forRunIndex index: Int, totalRuns: Int) -> Color {
        guard totalRuns > 1 else { return sequentialStops[0].color }
        let clampedIndex = max(0, min(index, totalRuns - 1))
        let position = Double(clampedIndex) / Double(totalRuns - 1)
        return interpolatedColor(at: position)
    }

    /// Gradient pair used by chart fills (top highlight + bottom depth) while
    /// keeping the same base hue as `color(forRunIndex:totalRuns:)`.
    static func chartGradientColors(forRunIndex index: Int, totalRuns: Int) -> (top: Color, bottom: Color) {
        let base = color(forRunIndex: index, totalRuns: totalRuns)
        let top = mix(base, .white, by: 0.22)
        let bottom = mix(base, .black, by: 0.18)
        return (top, bottom)
    }

    private static func interpolatedColor(at position: Double) -> Color {
        let clamped = max(0, min(position, 1))
        guard let first = sequentialStops.first else { return .red }
        guard let last = sequentialStops.last else { return first.color }
        if clamped <= first.position { return first.color }
        if clamped >= last.position { return last.color }

        for idx in 0..<(sequentialStops.count - 1) {
            let lower = sequentialStops[idx]
            let upper = sequentialStops[idx + 1]
            guard clamped >= lower.position, clamped <= upper.position else { continue }
            let span = max(upper.position - lower.position, 1e-6)
            let t = (clamped - lower.position) / span
            return mix(lower.color, upper.color, by: t)
        }

        return last.color
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
