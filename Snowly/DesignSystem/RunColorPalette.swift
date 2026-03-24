//
//  RunColorPalette.swift
//  Snowly
//
//  Shared run color sampling for route/map/chart consistency.
//

import SwiftUI
import UIKit

enum RunColorPalette {
    private struct RGBA {
        let r: Double, g: Double, b: Double, a: Double
    }

    private struct Stop {
        let position: Double
        let rgba: RGBA
        let color: Color
    }

    // Ordered "warm -> cool" ramp for run sequencing across map + charts.
    // Stop RGBA values are resolved once at static init to avoid repeated
    // UIColor bridging + getRed() calls inside Canvas render loops.
    private static let sequentialStops: [Stop] = {
        let raw: [(Double, Color)] = [
            (0.00, ColorTokens.brandRed),
            (0.24, ColorTokens.brandWarmAmber),
            (0.50, Color(red: 0.22, green: 0.83, blue: 0.52)),
            (0.76, ColorTokens.brandIceBlue),
            (1.00, Color(red: 0.56, green: 0.43, blue: 0.96)),
        ]
        return raw.map { Stop(position: $0.0, rgba: resolveRGBA($0.1), color: $0.1) }
    }()

    private static let whiteRGBA = RGBA(r: 1, g: 1, b: 1, a: 1)
    private static let blackRGBA = RGBA(r: 0, g: 0, b: 0, a: 1)

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
        let base = interpolatedRGBA(at: runPosition(forIndex: index, totalRuns: totalRuns))
        let top = mixRGBA(base, whiteRGBA, by: 0.22)
        let bottom = mixRGBA(base, blackRGBA, by: 0.18)
        return (top, bottom)
    }

    private static func runPosition(forIndex index: Int, totalRuns: Int) -> Double {
        guard totalRuns > 1 else { return 0 }
        let clampedIndex = max(0, min(index, totalRuns - 1))
        return Double(clampedIndex) / Double(totalRuns - 1)
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
            return mixRGBA(lower.rgba, upper.rgba, by: t)
        }

        return last.color
    }

    private static func interpolatedRGBA(at position: Double) -> RGBA {
        let clamped = max(0, min(position, 1))
        guard let first = sequentialStops.first else { return whiteRGBA }
        guard let last = sequentialStops.last else { return first.rgba }
        if clamped <= first.position { return first.rgba }
        if clamped >= last.position { return last.rgba }

        for idx in 0..<(sequentialStops.count - 1) {
            let lower = sequentialStops[idx]
            let upper = sequentialStops[idx + 1]
            guard clamped >= lower.position, clamped <= upper.position else { continue }
            let span = max(upper.position - lower.position, 1e-6)
            let t = (clamped - lower.position) / span
            return lerpRGBA(lower.rgba, upper.rgba, by: t)
        }

        return last.rgba
    }

    // MARK: - RGBA Helpers

    /// Resolve a SwiftUI Color to clamped sRGB components. Called once per stop at static init.
    private static func resolveRGBA(_ color: Color) -> RGBA {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(
            r: min(max(Double(r), 0), 1),
            g: min(max(Double(g), 0), 1),
            b: min(max(Double(b), 0), 1),
            a: min(max(Double(a), 0), 1)
        )
    }

    /// Linearly interpolate two RGBA values and return a Color. Pure arithmetic, no UIColor.
    private static func mixRGBA(_ a: RGBA, _ b: RGBA, by t: Double) -> Color {
        let f = max(0, min(t, 1))
        return Color(
            red: a.r + (b.r - a.r) * f,
            green: a.g + (b.g - a.g) * f,
            blue: a.b + (b.b - a.b) * f,
            opacity: a.a + (b.a - a.a) * f
        )
    }

    /// Linearly interpolate two RGBA values, returning RGBA (for chaining).
    private static func lerpRGBA(_ a: RGBA, _ b: RGBA, by t: Double) -> RGBA {
        let f = max(0, min(t, 1))
        return RGBA(
            r: a.r + (b.r - a.r) * f,
            g: a.g + (b.g - a.g) * f,
            b: a.b + (b.b - a.b) * f,
            a: a.a + (b.a - a.a) * f
        )
    }
}
