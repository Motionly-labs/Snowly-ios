//
//  LiveActivityTokens.swift
//  SnowlyWidgetExtension
//
//  Design tokens for the Live Activity and Control Widget.
//  This target cannot import Snowly's main DesignSystem,
//  so tokens are defined here independently.
//

import SwiftUI

enum LiveActivityTokens {

    // MARK: - Colors

    /// Tint for the play/resume action (shown when session is paused — tap to resume).
    static let playAccent = Color(hex: "34C759")
    /// Tint for the pause action / active-tracking state. Matches iOS primaryAccent (brandIceBlue).
    static let pauseAccent = Color(hex: "1E88E5")
    /// Foreground color for Dynamic Island minimal view.
    static let minimalForeground = Color.white
    /// Foreground color for compact trailing carousel text.
    static let compactForeground = Color.white
    /// Tint for control widget idle (not-tracking) state.
    static let controlIdleAccent = Color.primary

    // MARK: - Spacing

    /// Outer horizontal padding for the lock-screen container.
    static let contentPaddingH: CGFloat = 16
    /// Outer vertical padding for the lock-screen container.
    static let contentPaddingV: CGFloat = 12
    /// Spacing between major horizontal sections/groups.
    static let sectionSpacing: CGFloat = 10
    /// Spacing between a label and its value.
    static let labelSpacing: CGFloat = 2
    /// Spacing between a metric value and its unit.
    static let metricValueSpacing: CGFloat = 4
    /// Spacing between pill/chip items in a row.
    static let pillSpacing: CGFloat = 6
    /// Spacing between icon and value in the compact trailing view.
    static let compactItemSpacing: CGFloat = 3
    /// Spacing between grid cells (stat chips).
    static let gridSpacing: CGFloat = 8
    /// Minimum spacer length in the header row.
    static let minSpacerLength: CGFloat = 8

    // MARK: - Chip / Pill Geometry

    /// Horizontal padding inside a stat chip.
    static let chipPaddingH: CGFloat = 8
    /// Vertical padding inside a stat chip.
    static let chipPaddingV: CGFloat = 6
    /// Corner radius of a stat chip.
    static let chipCornerRadius: CGFloat = 8
    /// Horizontal padding inside a metric pill.
    static let pillPaddingH: CGFloat = 8
    /// Vertical padding inside a metric pill.
    static let pillPaddingV: CGFloat = 4

    // MARK: - Typography

    /// Large speed readout in the lock-screen header.
    static let speedFont: Font = .system(size: 32, weight: .bold, design: .rounded).monospacedDigit()
    /// Icon size for the pause/play button on the lock screen.
    static let pausePlayIconSize: CGFloat = 28

    // MARK: - Scale Factors

    /// Minimum scale factor for the large speed value.
    static let speedMinScale: CGFloat = 0.65
    /// Minimum scale factor for standard content text.
    static let contentMinScale: CGFloat = 0.75
    /// Minimum scale factor for pill/chip labels.
    static let pillMinScale: CGFloat = 0.8
}

// MARK: - Color hex helper (local copy; main app's is not accessible here)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
